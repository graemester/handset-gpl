#!/bin/sh
# build-arch.sh — Optimized Arch Linux ARM aarch64 rootfs for ShellPhone
# Applies all debian-lean boot tuning: generator removal, volatile journal,
# direct shell console, machine-id pregeneration, aggressive masking.
# Usage: /bin/sh build-arch.sh
set -e

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
ARCH_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"

echo "=== Building Optimized Arch Linux ARM aarch64 ==="

docker run --rm --privileged \
  -v "$BASEDIR:/output" \
  ubuntu:24.04 bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get install -y -qq wget e2fsprogs qemu-utils >/dev/null

    echo "--- Downloading Arch ARM ---"
    cd /tmp
    wget -q "'"$ARCH_URL"'" -O arch.tar.gz
    ls -lh arch.tar.gz

    echo "--- Creating 3GB ext4 image ---"
    dd if=/dev/zero of=/tmp/arch.raw bs=1M count=3072 status=none
    mkfs.ext4 -q -F -L archlinux /tmp/arch.raw

    mkdir -p /mnt/rootfs
    mount -o loop /tmp/arch.raw /mnt/rootfs
    cd /mnt/rootfs

    echo "--- Extracting rootfs ---"
    tar xzf /tmp/arch.tar.gz
    rm -f /tmp/arch.tar.gz
    echo "Pre-strip size: $(du -sh /mnt/rootfs | cut -f1)"

    echo "--- Phase 1: Aggressive stripping ---"
    # Pacman cache and DB
    rm -rf var/cache/pacman/pkg/*
    rm -rf var/lib/pacman/sync/*
    # Logs
    rm -rf var/log/*
    # Firmware (not needed in VM)
    rm -rf usr/lib/firmware/*
    # Docs
    rm -rf usr/share/doc/*
    rm -rf usr/share/man/*
    rm -rf usr/share/info/*
    rm -rf usr/share/gtk-doc 2>/dev/null || true
    # Locales (keep only en_US)
    find usr/share/locale -maxdepth 1 -type d ! -name locale ! -name en_US 2>/dev/null | xargs rm -rf 2>/dev/null || true
    # Timezones (keep only UTC/Etc)
    find usr/share/zoneinfo -maxdepth 1 -type d ! -name zoneinfo ! -name UTC ! -name Etc 2>/dev/null | xargs rm -rf 2>/dev/null || true
    # Python cache
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    # Perl (if not needed)
    rm -rf usr/share/perl5 2>/dev/null || true
    # i18n
    rm -rf usr/share/i18n 2>/dev/null || true
    # Terminfo (keep only xterm and linux)
    find usr/share/terminfo -type f ! -name "xterm*" ! -name "linux" -delete 2>/dev/null || true
    find usr/share/terminfo -empty -type d -delete 2>/dev/null || true
    echo "Post-strip size: $(du -sh /mnt/rootfs | cut -f1)"

    echo "--- Phase 2: PAM fixes for serial console ---"
    # Add ttyAMA0 to securetty
    if [ -f etc/securetty ]; then
        echo "ttyAMA0" >> etc/securetty
    else
        printf "ttyAMA0\nttyS0\ntty1\n" > etc/securetty
    fi
    # Disable pam_securetty
    if [ -f etc/pam.d/login ]; then
        sed -i "s|^auth.*required.*pam_securetty.so|#auth required pam_securetty.so|" etc/pam.d/login
    fi
    # Ensure pam_unix.so has nullok for passwordless root
    for f in etc/pam.d/system-auth etc/pam.d/system-local-login; do
        if [ -f "$f" ] && ! grep -q "nullok" "$f"; then
            sed -i "s|pam_unix.so|pam_unix.so nullok|g" "$f"
        fi
    done
    # Empty root password
    if [ -f etc/shadow ]; then
        sed -i "s|^root:[^:]*:|root::|" etc/shadow
    fi

    echo "--- Phase 3: Hostname and machine-id (pre-generate to skip runtime) ---"
    echo "shellphone" > etc/hostname
    echo "127.0.0.1 localhost shellphone" > etc/hosts
    cat /proc/sys/kernel/random/uuid | tr -d "-" > etc/machine-id

    echo "--- Phase 4: Direct shell console (bypass agetty/login/PAM) ---"
    # Fastest path to prompt — run bash directly on TTY
    cat > etc/systemd/system/shellphone-console.service << SVC
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
    mkdir -p etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/shellphone-console.service etc/systemd/system/multi-user.target.wants/shellphone-console.service

    # Default target: multi-user
    ln -sf /usr/lib/systemd/system/multi-user.target etc/systemd/system/default.target

    echo "--- Phase 5: Network ---"
    mkdir -p etc/systemd/network
    cat > etc/systemd/network/eth0.network << NET
[Match]
Name=eth0
[Network]
DHCP=yes
NET
    ln -sf /usr/lib/systemd/system/systemd-networkd.service etc/systemd/system/multi-user.target.wants/systemd-networkd.service
    ln -sf /usr/lib/systemd/system/systemd-resolved.service etc/systemd/system/multi-user.target.wants/systemd-resolved.service
    ln -sf /run/systemd/resolve/stub-resolv.conf etc/resolv.conf

    echo "--- Phase 6: Aggressively mask unnecessary services ---"
    # KILL the console race: systemd-getty-generator auto-spawns an agetty on the
    # console= tty (serial-getty@ttyAMA0) that fights shellphone-console.service
    # for /dev/ttyAMA0. Under slow (device-TCTI-like) boot this flaps between the
    # bash console and a "login:" prompt. Hard-mask so ONLY our console owns it.
    for svc in serial-getty@ttyAMA0.service getty@tty1.service \
               console-getty.service getty.target; do
        chroot /mnt/rootfs systemctl mask "$svc" 2>/dev/null || true
    done
    # Timers
    for svc in fstrim.timer logrotate.timer man-db.timer shadow.timer \
               systemd-tmpfiles-clean.timer; do
        chroot /mnt/rootfs systemctl mask "$svc" 2>/dev/null || true
    done
    # Module loading (everything compiled into kernel)
    for svc in systemd-modules-load.service \
               modprobe@configfs.service modprobe@dm_mod.service \
               modprobe@drm.service modprobe@efi_pstore.service \
               modprobe@fuse.service modprobe@loop.service; do
        chroot /mnt/rootfs systemctl mask "$svc" 2>/dev/null || true
    done
    # Hardware (unnecessary in VM)
    for svc in keyboard-setup.service console-setup.service \
               systemd-hwdb-update.service systemd-vconsole-setup.service \
               systemd-pcrmachine.service systemd-pcrfs-root.service \
               systemd-pcrphase-initrd.service systemd-pcrphase-sysinit.service \
               systemd-pcrphase.service ldconfig.service; do
        chroot /mnt/rootfs systemctl mask "$svc" 2>/dev/null || true
    done
    # Time sync (VM gets time from host)
    for svc in systemd-timesyncd.service systemd-time-wait-sync.service; do
        chroot /mnt/rootfs systemctl mask "$svc" 2>/dev/null || true
    done
    # Network wait
    chroot /mnt/rootfs systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
    # Random seed
    chroot /mnt/rootfs systemctl mask systemd-random-seed.service 2>/dev/null || true
    # Utmp/wtmp accounting
    for svc in systemd-update-utmp.service systemd-update-utmp-runlevel.service; do
        chroot /mnt/rootfs systemctl mask "$svc" 2>/dev/null || true
    done
    # Journal flush (keep in RAM only)
    chroot /mnt/rootfs systemctl mask systemd-journal-flush.service 2>/dev/null || true
    # Sysctl
    chroot /mnt/rootfs systemctl mask systemd-sysctl.service 2>/dev/null || true
    # Fsck (VM always has clean shutdown via snapshot)
    chroot /mnt/rootfs systemctl mask systemd-fsck-root.service 2>/dev/null || true
    chroot /mnt/rootfs systemctl mask systemd-fsck@.service 2>/dev/null || true
    # Machine credentials
    chroot /mnt/rootfs systemctl mask systemd-machine-id-commit.service 2>/dev/null || true
    chroot /mnt/rootfs systemctl mask systemd-credential-watcher.service 2>/dev/null || true
    # First-boot (skip all first-boot setup — we configure everything here)
    chroot /mnt/rootfs systemctl mask systemd-firstboot.service 2>/dev/null || true
    chroot /mnt/rootfs systemctl mask first-boot-complete.target 2>/dev/null || true
    # Pacman keyring init (huge time sink — 10+ seconds on TCTI)
    chroot /mnt/rootfs systemctl mask archlinux-keyring-wkd-sync.timer 2>/dev/null || true
    chroot /mnt/rootfs systemctl mask archlinux-keyring-wkd-sync.service 2>/dev/null || true

    echo "--- Phase 7: Remove unnecessary systemd generators ---"
    GEN_DIR=usr/lib/systemd/system-generators
    for gen in systemd-cryptsetup-generator systemd-debug-generator \
               systemd-fstab-generator systemd-gpt-auto-generator \
               systemd-getty-generator \
               systemd-hibernate-resume-generator systemd-rc-local-generator \
               systemd-run-generator systemd-system-update-generator \
               systemd-sysv-generator systemd-veritysetup-generator; do
        rm -f "$GEN_DIR/$gen" 2>/dev/null
    done
    rm -rf usr/lib/systemd/system-environment-generators/* 2>/dev/null || true

    echo "--- Phase 8: systemd tuning ---"
    mkdir -p etc/systemd/system.conf.d
    cat > etc/systemd/system.conf.d/shellphone.conf << SYSD
[Manager]
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=5s
DefaultDeviceTimeoutSec=5s
LogLevel=warning
LogTarget=journal
DumpCore=no
CrashShell=no
SYSD

    # Journal: RAM only, small size
    mkdir -p etc/systemd/journald.conf.d
    cat > etc/systemd/journald.conf.d/shellphone.conf << JRNL
[Journal]
Storage=volatile
RuntimeMaxUse=4M
RuntimeKeepFree=2M
JRNL

    echo "--- Phase 9: fstab (noatime for performance) ---"
    cat > etc/fstab << FSTAB
/dev/vda / ext4 rw,noatime,errors=continue 0 0
FSTAB

    echo "--- Phase 10: Root setup ---"
    mkdir -p root
    cat > root/.bashrc << BASHRC
export PS1="\[\e[32m\]\u@shellphone\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\\$ "
export TERM=xterm-256color
export EDITOR=nano
alias ls="ls --color=auto"
alias ll="ls -la"
alias ..="cd .."
BASHRC
    cat > root/.profile << PROFILE
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
PROFILE

    echo "--- Phase 11: MOTD and profile ---"
    cat > etc/motd << MOTD

  ShellPhone
  Arch Linux ARM on iPhone

MOTD

    mkdir -p etc/profile.d
    cat > etc/profile.d/shellphone.sh << PROF
#!/bin/sh
stty cols 52 rows 40 2>/dev/null
if [ -z "\$SHELLPHONE_SHOWN" ]; then
    export SHELLPHONE_SHOWN=1
    cat /etc/motd 2>/dev/null
    IP=\$(ip -4 addr show eth0 2>/dev/null | awk "/inet /{print \\\$2}")
    [ -n "\$IP" ] && printf "  Network: %s\n\n" "\$IP"
fi
PROF
    chmod +x etc/profile.d/shellphone.sh

    echo "--- Phase 12: Verify ---"
    echo "Rootfs size: $(du -sh /mnt/rootfs | cut -f1)"
    echo "Masked: $(find etc/systemd/system -name "*.service" -type l -exec readlink {} \; 2>/dev/null | grep -c /dev/null) services"
    echo "Generators: $(ls usr/lib/systemd/system-generators/ 2>/dev/null | wc -l)"

    cd / && sync && umount /mnt/rootfs

    echo "--- Converting to qcow2 ---"
    qemu-img convert -f raw -O qcow2 /tmp/arch.raw /output/arch-arm64.qcow2

    echo "--- Compressing ---"
    gzip -9 -c /output/arch-arm64.qcow2 > /output/arch-arm64.qcow2.gz

    ls -lh /output/arch-arm64.qcow2 /output/arch-arm64.qcow2.gz
    echo "=== Done ==="
  '

echo ""
ls -lh "$BASEDIR/arch-arm64.qcow2" "$BASEDIR/arch-arm64.qcow2.gz" 2>/dev/null
