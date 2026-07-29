#!/bin/sh
# build-fedora.sh — Optimized Fedora 41 aarch64 rootfs for ShellPhone.
#
# Mirrors build-arch.sh's boot tuning (direct-shell console, machine-id
# pregeneration, aggressive service masking, volatile journal) but bootstraps
# Fedora with `dnf --installroot` instead of unpacking a tarball, and builds the
# ext4 image with `mkfs.ext4 -d` (populate-from-directory) so no privileged
# loop-mount is needed.
#
# IMPORTANT vs build-arch.sh: this masks serial-getty@ttyAMA0.service AND removes
# systemd-getty-generator. Without that, systemd auto-spawns an agetty on the
# console= tty that fights shellphone-console.service for /dev/ttyAMA0 — a race
# that only shows under slow (device-TCTI-like) execution and yields a flapping
# login prompt. See scripts/boot-test.sh (the finding that motivated this).
#
# Usage: /bin/sh build-fedora.sh
set -e

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
RELEASEVER=41
IMG_MB=4096   # sparse; qcow2 convert compacts to real usage

echo "=== Building Optimized Fedora ${RELEASEVER} aarch64 ==="

# Output goes to this script's own directory, resolved at run time. This was
# hardcoded to one machine's external volume until the licence-audit cleanup, which
# meant the script only ever worked on the author's Mac.
OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker run --rm \
  --cap-add SYS_CHROOT --cap-add MKNOD \
  -v "${OUTPUT_DIR}:/output" \
  fedora:${RELEASEVER} bash -c '
    set -e
    R=/rootfs

    echo "--- Builder tools ---"
    dnf install -y -q --setopt=install_weak_deps=False \
        e2fsprogs qemu-img util-linux >/dev/null

    echo "--- Phase 0: dnf --installroot minimal Fedora ---"
    # Lean but functional: systemd + networking + dnf5 + core userland. No docs,
    # no weak deps, no kernel/bootloader (ShellPhone supplies the kernel).
    dnf install -y --installroot=$R --releasever='"$RELEASEVER"' --use-host-config \
        --setopt=install_weak_deps=False --setopt=tsflags=nodocs \
        --setopt=keepcache=False \
        systemd systemd-networkd systemd-resolved \
        dnf5 dnf5-plugins fedora-release fedora-gpg-keys \
        glibc-minimal-langpack bash coreutils util-linux shadow-utils passwd \
        iproute iputils procps-ng ncurses vim-minimal less sudo which \
        >/dev/null
    echo "Installed size: $(du -sh $R | cut -f1)"

    echo "--- Phase 1: Aggressive stripping ---"
    rm -rf $R/var/cache/dnf/* $R/var/cache/libdnf5/* 2>/dev/null || true
    rm -rf $R/usr/share/doc/* $R/usr/share/man/* $R/usr/share/info/* 2>/dev/null || true
    rm -rf $R/usr/lib/firmware/* 2>/dev/null || true
    find $R/usr/share/locale -maxdepth 1 -type d ! -name locale ! -name en_US -exec rm -rf {} + 2>/dev/null || true
    find $R/usr/share/zoneinfo -maxdepth 1 -type d ! -name zoneinfo ! -name UTC ! -name Etc -exec rm -rf {} + 2>/dev/null || true
    find $R -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find $R/usr/share/terminfo -type f ! -name "xterm*" ! -name "linux" -delete 2>/dev/null || true
    rm -rf $R/usr/share/i18n 2>/dev/null || true
    echo "Post-strip size: $(du -sh $R | cut -f1)"

    echo "--- Phase 2: root password (empty) + machine-id ---"
    chroot $R sh -c "passwd -d root >/dev/null 2>&1 || true"
    sed -i "s|^root:[^:]*:|root::|" $R/etc/shadow 2>/dev/null || true
    echo shellphone > $R/etc/hostname
    echo "127.0.0.1 localhost shellphone" > $R/etc/hosts
    cat /proc/sys/kernel/random/uuid | tr -d "-" > $R/etc/machine-id
    # Ensure `dnf` resolves (F41 ships dnf5; guarantee the plain name works).
    chroot $R sh -c "command -v dnf >/dev/null 2>&1 || ln -sf /usr/bin/dnf5 /usr/bin/dnf"

    echo "--- Phase 3: Direct shell console (bypass agetty/login/PAM) ---"
    cat > $R/etc/systemd/system/shellphone-console.service << SVC
[Unit]
Description=ShellPhone Console
After=systemd-logind.service
ConditionPathExists=/dev/ttyAMA0

[Service]
Environment=HOME=/root USER=root LOGNAME=root SHELL=/bin/bash TERM=xterm-256color
WorkingDirectory=/root
ExecStart=/bin/bash --login
Restart=always
RestartSec=0
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/ttyAMA0
TTYReset=yes
TTYVHangup=yes
UtmpIdentifier=ttyAMA0
UtmpMode=login

[Install]
WantedBy=multi-user.target
SVC
    mkdir -p $R/etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/shellphone-console.service \
           $R/etc/systemd/system/multi-user.target.wants/shellphone-console.service
    ln -sf /usr/lib/systemd/system/multi-user.target $R/etc/systemd/system/default.target

    echo "--- Phase 3b: KILL the console race — no stray getty on ttyAMA0 ---"
    # systemd-getty-generator spawns serial-getty@<console>.service from console=.
    # Remove the generator and hard-mask the instance so ONLY our console service
    # owns /dev/ttyAMA0. This is the fix for the flapping-login bug seen on Arch.
    rm -f $R/usr/lib/systemd/system-generators/systemd-getty-generator 2>/dev/null || true
    chroot $R systemctl mask serial-getty@ttyAMA0.service getty@tty1.service \
        console-getty.service getty.target 2>/dev/null || true

    echo "--- Phase 4: Network (deterministic static SLIRP config) ---"
    # systemd-networkd is unreliable in this minimal image: udev does not mark the
    # virtio NIC "initialized", so networkd leaves eth0 in state "pending" and never
    # configures it (Network File: n/a) — no DHCP lease, no network. ShellPhone
    # always uses QEMU SLIRP user-mode networking, which is a FIXED topology
    # (guest 10.0.2.15/24, gateway 10.0.2.2, DNS 10.0.2.3), so a static oneshot is
    # both simpler and 100% reliable. Verified: eth0 UP+LOWER_UP, gateway pingable.
    cat > $R/etc/systemd/system/shellphone-net.service << 'NETSVC'
[Unit]
Description=ShellPhone static network (QEMU SLIRP)
DefaultDependencies=no
After=systemd-tmpfiles-setup.service
Before=shellphone-console.service network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'ip link set eth0 up; ip addr add 10.0.2.15/24 dev eth0 2>/dev/null; ip route add default via 10.0.2.2 2>/dev/null; printf "nameserver 10.0.2.3\n" > /etc/resolv.conf; true'

[Install]
WantedBy=multi-user.target
NETSVC
    ln -sf /etc/systemd/system/shellphone-net.service \
           $R/etc/systemd/system/multi-user.target.wants/shellphone-net.service
    # Real resolv.conf (not the systemd-resolved stub symlink, which needs resolved).
    rm -f $R/etc/resolv.conf
    printf 'nameserver 10.0.2.3\n' > $R/etc/resolv.conf
    # networkd/resolved don't work here and only add boot cost — mask them.
    chroot $R systemctl mask systemd-networkd.service systemd-networkd.socket \
        systemd-resolved.service systemd-networkd-wait-online.service 2>/dev/null || true

    echo "--- Phase 5: Mask boot-time cost centers ---"
    for svc in \
        systemd-firstboot.service first-boot-complete.target \
        dnf-makecache.timer dnf-makecache.service \
        systemd-modules-load.service systemd-random-seed.service \
        systemd-timesyncd.service systemd-time-wait-sync.service \
        systemd-networkd-wait-online.service \
        systemd-journal-flush.service systemd-sysctl.service \
        systemd-fsck-root.service systemd-fsck@.service \
        systemd-machine-id-commit.service \
        systemd-update-utmp.service systemd-update-utmp-runlevel.service \
        systemd-hwdb-update.service systemd-vconsole-setup.service \
        systemd-pcrphase.service systemd-pcrphase-sysinit.service \
        systemd-pcrphase-initrd.service systemd-pcrmachine.service \
        ldconfig.service selinux-autorelabel.target \
        fstrim.timer logrotate.timer; do
        chroot $R systemctl mask "$svc" 2>/dev/null || true
    done

    echo "--- Phase 6: Remove unnecessary systemd generators ---"
    GEN=$R/usr/lib/systemd/system-generators
    for gen in systemd-cryptsetup-generator systemd-debug-generator \
               systemd-fstab-generator systemd-gpt-auto-generator \
               systemd-hibernate-resume-generator systemd-rc-local-generator \
               systemd-run-generator systemd-system-update-generator \
               systemd-veritysetup-generator; do
        rm -f "$GEN/$gen" 2>/dev/null || true
    done
    rm -rf $R/usr/lib/systemd/system-environment-generators/* 2>/dev/null || true

    echo "--- Phase 7: systemd + journald tuning ---"
    mkdir -p $R/etc/systemd/system.conf.d $R/etc/systemd/journald.conf.d
    cat > $R/etc/systemd/system.conf.d/shellphone.conf << SYSD
[Manager]
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=5s
DefaultDeviceTimeoutSec=5s
LogLevel=warning
DumpCore=no
CrashShell=no
SYSD
    cat > $R/etc/systemd/journald.conf.d/shellphone.conf << JRNL
[Journal]
Storage=volatile
RuntimeMaxUse=4M
RuntimeKeepFree=2M
JRNL

    echo "--- Phase 8: SELinux permissive (no relabel cost, no denials) ---"
    mkdir -p $R/etc/selinux
    cat > $R/etc/selinux/config << SEL
SELINUX=disabled
SELINUXTYPE=targeted
SEL

    echo "--- Phase 9: fstab (noatime) ---"
    cat > $R/etc/fstab << FSTAB
/dev/vda / ext4 rw,noatime,errors=continue 0 0
FSTAB

    echo "--- Phase 10: Root shell env + MOTD ---"
    cat > $R/root/.bashrc << BASHRC
export PS1="\[\e[32m\]\u@shellphone\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\\$ "
export TERM=xterm-256color
export EDITOR=vi
alias ls="ls --color=auto"
alias ll="ls -la"
alias ..="cd .."
BASHRC
    cat > $R/root/.profile << PROFILE
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
PROFILE
    cat > $R/etc/motd << MOTD

  ShellPhone
  Fedora Linux on iPhone

MOTD
    mkdir -p $R/etc/profile.d
    cat > $R/etc/profile.d/shellphone.sh << PROF
#!/bin/sh
if [ -z "\$SHELLPHONE_SHOWN" ]; then
    export SHELLPHONE_SHOWN=1
    cat /etc/motd 2>/dev/null
    IP=\$(ip -4 addr show eth0 2>/dev/null | awk "/inet /{print \\\$2}")
    [ -n "\$IP" ] && printf "  Network: %s\n\n" "\$IP"
fi
PROF
    chmod +x $R/etc/profile.d/shellphone.sh

    echo "--- Phase 11: Verify tree ---"
    echo "Rootfs size: $(du -sh $R | cut -f1)"
    echo "getty generator present: $([ -e $R/usr/lib/systemd/system-generators/systemd-getty-generator ] && echo YES-BAD || echo no-good)"
    echo "serial-getty@ttyAMA0 masked: $([ -L $R/etc/systemd/system/serial-getty@ttyAMA0.service ] && readlink $R/etc/systemd/system/serial-getty@ttyAMA0.service | grep -q /dev/null && echo yes-good || echo NO-BAD)"

    echo "--- Phase 12: Build ext4 image from directory (no loop mount) ---"
    rm -f /tmp/fedora.raw
    mkfs.ext4 -q -F -L fedora -d $R -m 0 /tmp/fedora.raw '"$IMG_MB"'M
    e2fsck -fy /tmp/fedora.raw >/dev/null 2>&1 || true

    echo "--- Converting to qcow2 + compressing ---"
    qemu-img convert -f raw -O qcow2 /tmp/fedora.raw /output/fedora-41.qcow2
    gzip -9 -c /output/fedora-41.qcow2 > /output/fedora-41.qcow2.gz
    ls -lh /output/fedora-41.qcow2 /output/fedora-41.qcow2.gz
    echo "=== Done ==="
  '

echo ""
ls -lh "$BASEDIR/fedora-41.qcow2" "$BASEDIR/fedora-41.qcow2.gz" 2>/dev/null
