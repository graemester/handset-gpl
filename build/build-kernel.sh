#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 The ShellPhone Authors
#
# build-kernel.sh — build the arm64 Linux kernel Image that ShellPhone boots.
#
# This is the script GPLv2 §3 asks for: "the scripts used to control compilation and
# installation of the executable" for the kernel ShellPhone distributes. It is published
# in the GPL source bundle alongside the configuration it consumes, so a recipient can
# reproduce the exact binary in the shipped app and verify it byte for byte.
#
# Usage:
#   /bin/sh ios-build/build-kernel.sh
#
# Env:
#   VERSION=6.19.8       Kernel version to build.
#   CONFIG=<path>        Kernel .config. Defaults to kernel-output/config in a checkout,
#                        or ./config / ./kernel/config when run from the source bundle.
#   OUT=<dir>            Where Image and the normalised config are written.
#                        Defaults to kernel-output/ next to this script's repo root.
#   INSTALL=1            Also copy the built Image over ShellPhone/Resources/kernel.
#                        Ignored (with a note) when that path does not exist.
#   JOBS=<n>             Parallelism. Defaults to the container's CPU count.
#
# WHY IT RUNS IN DOCKER — three dead ends, each of which cost real time:
#
#   1. Never cross-compile on macOS. The kernel builds host tools (fixdep, genksyms,
#      modpost) that need Linux headers, and macOS's case-insensitive filesystem collides
#      Documentation/Kbuild with documentation/kbuild, which breaks `make mrproper`.
#   2. Never bind-mount the kernel source tree into the container. Through virtiofs it is
#      catastrophically slow and it triggers fixdep race conditions that fail the build
#      non-deterministically. Download the tarball *inside* the container, every time.
#      Only the small output directory is mounted.
#   3. Give the VM real resources. On macOS with Colima the default 2 CPU / 2 GB is not
#      enough to finish: `colima start --cpu 8 --memory 8`.
#
# The build is native, not cross: an arm64 host runs an arm64 Linux container and produces
# an arm64 Image. On an x86_64 host, Docker emulation will work but will be very slow.
set -eu

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-6.19.8}"
SERIES="v$(printf '%s' "$VERSION" | cut -d. -f1).x"
JOBS="${JOBS:-}"

G='\033[0;32m'; Y='\033[0;33m'; R='\033[0;31m'; N='\033[0m'
say()  { printf "%b\n" "$*"; }
warn() { printf "%b\n" "${Y}warning:${N} $*" >&2; }
die()  { printf "%b\n" "${R}error:${N} $*" >&2; exit 1; }

# ---- Locate the config ----------------------------------------------------
# Works both in a full checkout and standalone inside the published source bundle,
# where the layout is kernel/config rather than kernel-output/config.
if [ -n "${CONFIG:-}" ]; then
    :
elif [ -f "$BASEDIR/kernel-output/config" ]; then
    CONFIG="$BASEDIR/kernel-output/config"
elif [ -f "$BASEDIR/kernel/config" ]; then
    CONFIG="$BASEDIR/kernel/config"
elif [ -f "./config" ]; then
    CONFIG="./config"
else
    die "no kernel config found. Pass CONFIG=<path>.
       Expected kernel-output/config (checkout) or kernel/config (source bundle)."
fi
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"

OUT="${OUT:-$BASEDIR/kernel-output}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

command -v docker >/dev/null 2>&1 || die "docker not found.
       On macOS: brew install colima docker && colima start --cpu 8 --memory 8"

say "${G}=== Building Linux $VERSION (arm64) for ShellPhone ===${N}"
say "  config: $CONFIG"
say "  output: $OUT"
say ""

# The config is copied in rather than mounted, so the container cannot write to the
# repository except through $OUT.
cp "$CONFIG" "$OUT/.config-input"

# Verify the mount actually reaches the container BEFORE spending 30 minutes finding out
# it didn't. Colima only shares $HOME by default, so an $OUT under /tmp or /var silently
# appears empty inside the container and the build fails at the `cp .config` step with a
# baffling "No such file or directory".
if ! docker run --rm -v "$OUT:/output" alpine:3.21 test -f /output/.config-input; then
    rm -f "$OUT/.config-input"
    die "the output directory is not visible inside the container:
         $OUT
       Colima shares only \$HOME by default. Either choose an OUT= under \$HOME (the
       default, kernel-output/ in the repo, is fine), or add the path to Colima's mounts:
         colima stop && colima start --cpu 8 --memory 8 --mount '$OUT:w'"
fi

# ---- Build ----------------------------------------------------------------
docker run --rm -v "$OUT:/output" alpine:3.21 sh -euc '
    VERSION="'"$VERSION"'"
    SERIES="'"$SERIES"'"
    JOBS="'"$JOBS"'"
    [ -n "$JOBS" ] || JOBS=$(nproc)

    echo "--- Installing build dependencies ---"
    apk add --no-progress -q build-base linux-headers bc flex bison perl \
        elfutils-dev openssl-dev wget cpio xz

    echo "--- Downloading linux-$VERSION (fresh, inside the container) ---"
    cd /tmp
    wget -q "https://cdn.kernel.org/pub/linux/kernel/$SERIES/linux-$VERSION.tar.xz"
    tar xf "linux-$VERSION.tar.xz"
    rm -f "linux-$VERSION.tar.xz"
    cd "linux-$VERSION"

    echo "--- Configuring (olddefconfig) ---"
    cp /output/.config-input .config
    make olddefconfig >/dev/null

    echo "--- Building Image with -j$JOBS (15-40 min) ---"
    make -j"$JOBS" Image

    echo "--- Publishing artifacts ---"
    cp arch/arm64/boot/Image /output/Image
    cp .config /output/config
    ls -l /output/Image
'
rm -f "$OUT/.config-input"

# ---- Verify ---------------------------------------------------------------
say ""
say "${G}--- Verifying the Image ---${N}"
[ -f "$OUT/Image" ] || die "no Image produced."

# arm64 Image magic is "ARM\x64" at offset 56.
if command -v xxd >/dev/null 2>&1; then
    magic="$(xxd -p -s 56 -l 4 "$OUT/Image" 2>/dev/null || true)"
    [ "$magic" = "41524d64" ] \
        && say "  ${G}OK${N} arm64 Image magic present" \
        || warn "arm64 magic not found at offset 56 (got '$magic') — is this really an Image?"
fi

bytes=$(wc -c < "$OUT/Image" | tr -d ' ')
mib=$((bytes / 1048576))
say "  size: ${bytes} bytes (~${mib} MiB)"
[ "$mib" -gt 30 ] && warn "over the 30 MiB target — check the config did not pick up
         defaults for hardware a VM does not have."

# The options without which ShellPhone cannot boot: virtio disk and net, the PL011 serial
# console the VM exposes, ext4 for the rootfs, and 9p for host file sharing.
say "  critical options:"
miss=0
for opt in CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET CONFIG_SERIAL_AMBA_PL011 \
           CONFIG_EXT4_FS CONFIG_9P_FS CONFIG_NET_9P_VIRTIO; do
    if grep -q "^${opt}=y" "$OUT/config"; then
        say "    ${G}y${N} $opt"
    else
        say "    ${R}MISSING${N} $opt"; miss=1
    fi
done
[ "$miss" -eq 1 ] && die "the built config lacks options ShellPhone requires to boot.
       Do not ship this Image."

sha="$(shasum -a 256 "$OUT/Image" | cut -d' ' -f1)"
say "  sha256: $sha"

# ---- Install / compare ----------------------------------------------------
SHIPPED="$BASEDIR/ShellPhone/Resources/kernel"
say ""
if [ "${INSTALL:-0}" = "1" ]; then
    if [ -d "$(dirname "$SHIPPED")" ]; then
        cp "$OUT/Image" "$SHIPPED"
        say "${G}Installed${N} -> ShellPhone/Resources/kernel (uncompressed; VMManager"
        say "         passes this path straight to QEMU's -kernel and does NOT decompress it)"
    else
        warn "INSTALL=1 but ShellPhone/Resources/ does not exist — nothing installed.
         That is expected when running from the published source bundle."
    fi
elif [ -f "$SHIPPED" ]; then
    have="$(shasum -a 256 "$SHIPPED" | cut -d' ' -f1)"
    if [ "$have" = "$sha" ]; then
        say "${G}Reproduced exactly.${N} This Image is byte-identical to the shipped kernel."
    else
        warn "differs from the currently shipped ShellPhone/Resources/kernel:
           built:   $sha
           shipped: $have
         Expected if the config or version changed. Re-run with INSTALL=1 to adopt it,
         then re-check COMPLIANCE.md §4 provenance before publishing a source bundle."
    fi
else
    say "Built Image is at $OUT/Image (sha256 above). Compare it with kernel/Image.sha256"
    say "in the source bundle to confirm you have reproduced the shipped kernel."
fi

say ""
say "${G}=== Done ===${N}"
