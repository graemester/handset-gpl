#!/bin/sh
# build-shellphone-code.sh — the "ShellPhone Code" image (proposal §10.1).
#
# A slim Alpine base that boots straight into the ShellPhone TUI (full profile):
# apk, git/curl/nano, and the shellphone-tui binary built from ../tui. Claude Code is
# NOT baked (the first-run wizard installs it, ~235 MB, keeping the image small and
# avoiding redistributing a proprietary binary); opencode and language toolchains are
# offered by the portal's Install-packs, so nothing extra is baked here either.
#
# Output: shellphone-code.qcow2[.gz] in $OUTPUT (default: this script's dir).
#   OUTPUT=/path sh build-shellphone-code.sh
#   APK_REPO=http://dl-cdn.alpinelinux.org/alpine/v3.22   # override mirror (e.g. http)
set -e

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$BASEDIR/.." && pwd)"
OUTPUT="${OUTPUT:-$BASEDIR}"
TARGET=aarch64-unknown-linux-musl
APK_REPO="${APK_REPO:-https://dl-cdn.alpinelinux.org/alpine/v3.22}"
mkdir -p "$OUTPUT"

echo "=== Building shellphone-tui ($TARGET) ==="
(cd "$REPO/tui" && cargo build --release --target "$TARGET")
TUI_BIN="$REPO/tui/target/$TARGET/release/shellphone-tui"
[ -x "$TUI_BIN" ] || { echo "TUI binary not found at $TUI_BIN" >&2; exit 1; }
cp "$TUI_BIN" "$OUTPUT/shellphone-tui"

echo "=== Assembling ShellPhone Code (Alpine arm64) ==="
docker run --rm --privileged \
  -e "APK_REPO=$APK_REPO" \
  -v "$OUTPUT":/output \
  -v "$REPO/tui/overlay":/overlay:ro \
  -v "$REPO/tui/content":/content:ro \
  alpine:3.22 sh -c '
    set -e
    MAIN="$APK_REPO/main"
    COMM="$APK_REPO/community"

    apk add --no-cache --repository "$MAIN" e2fsprogs qemu-img >/dev/null

    # 4 GB sparse ext4 (grows on demand; compresses to nothing while empty).
    dd if=/dev/zero of=/tmp/sp.raw bs=1M count=4096 status=none
    mkfs.ext4 -q -F -L shellphone-code /tmp/sp.raw
    mkdir -p /mnt/rootfs
    mount -o loop /tmp/sp.raw /mnt/rootfs

    echo "--- Base packages ---"
    apk add --root /mnt/rootfs --initdb -U --allow-untrusted \
      --repository "$MAIN" --repository "$COMM" \
      alpine-base busybox bash git curl ca-certificates nano less openssh-client tzdata

    cd /mnt/rootfs

    echo "--- Portal binary ---"
    install -D -m 0755 /output/shellphone-tui usr/local/bin/shellphone-tui

    echo "--- Overlay: full profile + relaunch loop + content ---"
    mkdir -p etc/shellphone-tui etc/profile.d usr/share/shellphone-tui/lessons root
    # Full profile (ShellPhone Code): the wizard + the complete action set.
    printf "profile = \"full\"\nimage_name = \"ShellPhone Code\"\n" > etc/shellphone-tui/profile.toml
    cp /overlay/etc/shellphone-tui/config.toml etc/shellphone-tui/config.toml
    cp /overlay/etc/profile.d/shellphone-tui.sh etc/profile.d/shellphone-tui.sh
    # BusyBox login sources /etc/profile then ~/.profile; the relaunch loop is POSIX.
    cp /overlay/root/.bash_profile root/.profile
    cp /content/PREPARING.md /content/cheatsheet.md usr/share/shellphone-tui/
    cp /content/lessons/*.md usr/share/shellphone-tui/lessons/

    echo "--- Console: bash login shell on ttyAMA0 ---"
    cat > etc/inittab << INITTAB
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
ttyAMA0::respawn:/bin/bash -l
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
INITTAB

    echo "--- Networking (DHCP on eth0 via openrc) ---"
    cat > etc/network/interfaces << NET
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
NET
    chroot /mnt/rootfs rc-update add networking default >/dev/null 2>&1 || true

    echo "--- Identity + login niceties ---"
    echo "shellphone" > etc/hostname
    echo "127.0.0.1 localhost shellphone" > etc/hosts
    # Empty root password; hushlogin so the MOTD does not fight the portal.
    sed -i "s|^root:[^:]*:|root::|" etc/shadow
    touch root/.hushlogin
    cat > etc/fstab << FSTAB
/dev/vda / ext4 rw,noatime,errors=continue 0 0
FSTAB

    echo "--- Strip for size ---"
    rm -rf usr/share/man/* usr/share/doc/* var/cache/apk/*

    cd / && sync && umount /mnt/rootfs

    echo "--- Convert + compress ---"
    qemu-img convert -f raw -O qcow2 /tmp/sp.raw /output/shellphone-code.qcow2
    gzip -9 -c /output/shellphone-code.qcow2 > /output/shellphone-code.qcow2.gz
    ls -lh /output/shellphone-code.qcow2 /output/shellphone-code.qcow2.gz
    echo "SHA-256 (compressed asset, for DistroCatalog.swift):"
    sha256sum /output/shellphone-code.qcow2.gz
    echo "=== Done ==="
  ' 2>&1
