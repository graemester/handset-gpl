#!/bin/sh
# build-void.sh — Void Linux aarch64 (glibc) rootfs for ShellPhone.
#
# Void uses runit (not systemd), so boot tuning differs from the Arch/Debian
# builders: a single runit service auto-logs root in on the serial console
# (ttyAMA0) via agetty. Produces void-arm64.qcow2 + void-arm64.qcow2.gz.
#
# Usage: /bin/sh build-void.sh
# Prereqs: Docker (Colima on macOS: `colima start --cpu 4 --memory 4`).
# After rebuilding: upload void-arm64.qcow2.gz to the GitHub Release, then update the
# DistroCatalog Void entry's downloadURL/sha256 — the entry already ships .available.
# SHA-256:  shasum -a 256 void-arm64.qcow2.gz
# Verify the result with:  /bin/sh scripts/boot-test.sh void
set -e

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building Void Linux aarch64 (glibc) rootfs ==="

docker run --rm --privileged \
  -v "$BASEDIR:/output" \
  ubuntu:24.04 bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq wget xz-utils e2fsprogs qemu-utils ca-certificates >/dev/null

    echo "--- Resolving latest Void aarch64 ROOTFS ---"
    BASE="https://repo-default.voidlinux.org/live/current/"
    TARBALL=$(wget -qO- "$BASE" | grep -oE "void-aarch64-ROOTFS-[0-9]+\.tar\.xz" | sort -u | tail -1)
    [ -n "$TARBALL" ] || { echo "Could not find a Void aarch64 ROOTFS tarball at $BASE"; exit 1; }
    echo "Latest: $TARBALL"
    cd /tmp
    wget -q "$BASE$TARBALL" -O void.tar.xz
    ls -lh void.tar.xz

    echo "--- Creating 2GB ext4 image ---"
    dd if=/dev/zero of=/tmp/void.raw bs=1M count=2048 status=none
    mkfs.ext4 -q -F -L voidlinux /tmp/void.raw
    mkdir -p /mnt/rootfs
    mount -o loop /tmp/void.raw /mnt/rootfs
    cd /mnt/rootfs

    echo "--- Extracting rootfs ---"
    tar xJf /tmp/void.tar.xz
    rm -f /tmp/void.tar.xz
    echo "Pre-strip size: $(du -sh /mnt/rootfs | cut -f1)"

    echo "--- Phase 1: Strip caches / docs / locales ---"
    rm -rf var/cache/xbps/* var/log/* usr/lib/firmware/* \
           usr/share/doc/* usr/share/man/* usr/share/info/* 2>/dev/null || true
    find usr/share/locale -maxdepth 1 -type d ! -name locale ! -name en_US 2>/dev/null | xargs rm -rf 2>/dev/null || true
    find usr/share/zoneinfo -maxdepth 1 -type d ! -name zoneinfo ! -name UTC ! -name Etc 2>/dev/null | xargs rm -rf 2>/dev/null || true
    find usr/share/terminfo -type f ! -name "xterm*" ! -name "linux" -delete 2>/dev/null || true
    find usr/share/terminfo -empty -type d -delete 2>/dev/null || true
    echo "Post-strip size: $(du -sh /mnt/rootfs | cut -f1)"

    echo "--- Phase 2: Identity + fstab ---"
    echo "shellphone" > etc/hostname
    echo "127.0.0.1 localhost shellphone" > etc/hosts
    cat /proc/sys/kernel/random/uuid | tr -d "-" > etc/machine-id 2>/dev/null || true
    cat > etc/fstab << FSTAB
/dev/vda / ext4 rw,noatime,errors=continue 0 0
FSTAB
    # Empty root password (agetty --autologin bypasses it, but keep it explicit).
    [ -f etc/shadow ] && sed -i "s|^root:[^:]*:|root::|" etc/shadow

    echo "--- Phase 3: runit serial-console autologin on ttyAMA0 ---"
    mkdir -p etc/sv/shellphone-console
    cat > etc/sv/shellphone-console/run << "RUN"
#!/bin/sh
# Auto-login root on the serial console the VM exposes (ttyAMA0). runit keeps
# it supervised, so the shell respawns if it exits.
exec agetty --autologin root --noclear ttyAMA0 linux
RUN
    chmod +x etc/sv/shellphone-console/run
    # Enable it in the default runsvdir; disable the tty1..tty6 gettys we do not use.
    ln -sf /etc/sv/shellphone-console etc/runit/runsvdir/default/shellphone-console
    for n in 1 2 3 4 5 6; do rm -f etc/runit/runsvdir/default/agetty-tty$n; done

    echo "--- Phase 4: Network (dhcpcd on eth0) ---"
    # The Void ROOTFS ships dhcpcd; make sure it is enabled for the VM NIC.
    [ -d etc/sv/dhcpcd ] && ln -sf /etc/sv/dhcpcd etc/runit/runsvdir/default/dhcpcd 2>/dev/null || true

    echo "--- Phase 5: Root shell profile (no color — guest content) ---"
    cat > root/.bashrc << "BASHRC"
export PS1="[\u@shellphone \W]\\$ "
export TERM=xterm-256color
alias ls="ls --color=auto"
alias ll="ls -la"
BASHRC
    cat > etc/motd << "MOTD"

  ShellPhone
  Void Linux on iPhone

MOTD

    echo "--- Phase 6: Verify + package ---"
    echo "Rootfs size: $(du -sh /mnt/rootfs | cut -f1)"
    cd / && sync && umount /mnt/rootfs

    echo "--- Converting to qcow2 ---"
    qemu-img convert -f raw -O qcow2 /tmp/void.raw /output/void-arm64.qcow2
    echo "--- Compressing ---"
    gzip -9 -c /output/void-arm64.qcow2 > /output/void-arm64.qcow2.gz
    ls -lh /output/void-arm64.qcow2 /output/void-arm64.qcow2.gz
    echo "=== Done ==="
  '

echo ""
ls -lh "$BASEDIR/void-arm64.qcow2" "$BASEDIR/void-arm64.qcow2.gz" 2>/dev/null
echo ""
echo "Next: shasum -a 256 rootfs-build/void-arm64.qcow2.gz  → fill DistroCatalog + flip status."
