#!/bin/sh
# build-debian-trixie-lean.sh — Ultra-lean Debian 13 "trixie" for ShellPhone
# Goal: fastest possible systemd boot on a serial-console VM under TCTI.
#
# Retarget of build-debian-lean.sh (bookworm) — the trixie pivot (Workstream A).
# trixie ships a much newer systemd, so the phase-5/6/7 masking and
# generator-removal lists are RE-DERIVED against what trixie actually installs
# (masks/deletes fail *silently* when unit names drift between systemd versions),
# not replayed verbatim from bookworm. The build log prints the real unit-file and
# generator inventory so drift is visible on every build.
#
# Output: debian-trixie.qcow2 (+ .gz) in $OUTPUT (default: this script's dir).
# Override the output dir:  OUTPUT=/path/to/out sh build-debian-trixie-lean.sh
set -e

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${OUTPUT:-$BASEDIR}"
mkdir -p "$OUTPUT"

echo "=== Building Ultra-Lean Debian 13 (trixie) arm64 ==="
echo "Output dir: $OUTPUT"

docker run --rm --privileged \
  -v "$OUTPUT":/output \
  debian:trixie bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get install -y -qq debootstrap e2fsprogs qemu-utils >/dev/null

    dd if=/dev/zero of=/tmp/debian.raw bs=1M count=512 status=none
    mkfs.ext4 -q -F -L debian /tmp/debian.raw

    mkdir -p /mnt/rootfs
    mount -o loop /tmp/debian.raw /mnt/rootfs

    echo "--- Phase 1: Minimal debootstrap (trixie) ---"
    # Include list carried over from the bookworm-lean build with one drop:
    # apt-transport-https is obsolete (its functionality moved into apt); in trixie
    # it survives only as a transitional dummy, so it is dropped. debootstrap fails
    # loudly if any remaining include is gone, which is the per-package existence
    # check the dev guide (A1) asks for. (Verified against trixie in a build probe:
    # systemd 257; the pcr/tpm and ssh-generator units below are trixie-era.)
    debootstrap --variant=minbase \
      --include=systemd,systemd-sysv,udev,dbus,iproute2,iputils-ping,wget,ca-certificates,procps,nano,bash-completion,less \
      --exclude=e2fsprogs,dmsetup,fdisk \
      --arch=arm64 trixie /mnt/rootfs http://deb.debian.org/debian

    cd /mnt/rootfs

    # trixie is merged-/usr: /lib, /bin, /sbin are symlinks into /usr. Reference the
    # real /usr paths so rm/find never depend on the compatibility symlinks.
    SYSTEMD_SYSTEM=usr/lib/systemd/system
    GEN_DIR=usr/lib/systemd/system-generators
    ENV_GEN_DIR=usr/lib/systemd/system-environment-generators

    echo "--- Phase 2: Hostname and machine-id (pre-generate to skip runtime) ---"
    echo "shellphone" > etc/hostname
    echo "127.0.0.1 localhost shellphone" > etc/hosts
    # Pre-generate machine-id (systemd skips generation if it exists)
    cat /proc/sys/kernel/random/uuid | tr -d "-" > etc/machine-id

    echo "--- Phase 3: Root autologin (direct shell, bypass PAM completely) ---"
    # Instead of agetty -> login -> PAM -> shell, run the shell directly on the TTY:
    # the fastest possible path to a prompt. COLORTERM=truecolor is new for trixie
    # (SwiftTerm renders 24-bit SGR but the guest never claimed it before); it will
    # be folded back into the other images per the dev guide (A2).
    cat > etc/systemd/system/shellphone-console.service << SVC
[Unit]
Description=ShellPhone Console
After=systemd-logind.service
ConditionPathExists=/dev/ttyAMA0

[Service]
Environment=HOME=/root USER=root LOGNAME=root SHELL=/bin/bash TERM=xterm-256color COLORTERM=truecolor
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

    echo "--- Phase 4: Default target + essential services only ---"
    ln -sf "/$SYSTEMD_SYSTEM/multi-user.target" etc/systemd/system/default.target

    # Network
    mkdir -p etc/systemd/network
    cat > etc/systemd/network/eth0.network << NET
[Match]
Name=eth0
[Network]
DHCP=yes
NET
    ln -sf "/$SYSTEMD_SYSTEM/systemd-networkd.service" etc/systemd/system/multi-user.target.wants/systemd-networkd.service
    ln -sf "/$SYSTEMD_SYSTEM/systemd-resolved.service" etc/systemd/system/multi-user.target.wants/systemd-resolved.service
    ln -sf /run/systemd/resolve/stub-resolv.conf etc/resolv.conf

    echo "--- Phase 5: Inventory the ACTUAL trixie units, then mask ---"
    # Print the real inventory so unit-name drift vs bookworm is visible in the log.
    echo "[inventory] installed unit files (trixie):"
    chroot /mnt/rootfs systemctl list-unit-files --no-legend 2>/dev/null | awk "{print \"  \" \$1}" || true

    # mask_if_present: mask only units that exist; report any that do not so a
    # renamed/removed unit surfaces instead of failing silently (dev guide A2).
    mask_if_present() {
        for svc in "$@"; do
            if chroot /mnt/rootfs systemctl mask "$svc" 2>/dev/null; then
                :
            else
                echo "[mask] skipped (absent in trixie): $svc"
            fi
        done
    }

    # Timers (background maintenance)
    mask_if_present apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer \
                    fstrim.timer logrotate.timer man-db.timer dpkg-db-backup.timer

    # Module loading (everything is compiled into the kernel; no modules)
    mask_if_present systemd-modules-load.service \
                    modprobe@configfs.service modprobe@dm_mod.service \
                    modprobe@drm.service modprobe@efi_pstore.service \
                    modprobe@fuse.service modprobe@loop.service

    # Hardware detection/setup (unnecessary in a headless VM). The TPM/PCR family
    # grew in newer systemd — mask the known names AND glob-mask anything matching
    # the pcr*/tpm2* patterns so trixie-era additions are covered.
    mask_if_present keyboard-setup.service console-setup.service \
                    systemd-hwdb-update.service systemd-pcrmachine.service \
                    systemd-pcrfs-root.service systemd-pcrphase-initrd.service \
                    systemd-pcrphase-sysinit.service systemd-pcrphase.service \
                    systemd-pcrlock.service systemd-pcrextend.service \
                    systemd-tpm2-setup.service systemd-tpm2-setup-early.service \
                    systemd-boot-check-no-failures.service
    # Glob-mask the whole pcr/tpm family (systemd 257 ships ~20 units incl. the new
    # systemd-pcrlock-* set and tpm2.target) so trixie-era additions are covered
    # without hardcoding every name.
    for unit in $(chroot /mnt/rootfs systemctl list-unit-files --no-legend 2>/dev/null \
                    | awk "{print \$1}" | grep -E "^(systemd-(pcr|tpm)|tpm2\.)" || true); do
        mask_if_present "$unit"
    done

    # Time sync (portal does SNTP on resume; host owns the clock otherwise)
    mask_if_present systemd-timesyncd.service systemd-time-wait-sync.service

    # Network wait (do not block login on the network coming up)
    mask_if_present systemd-networkd-wait-online.service

    # Random seed (kernel has good entropy; not needed in a VM)
    mask_if_present systemd-random-seed.service

    # Utmp/wtmp accounting (single-user VM)
    mask_if_present systemd-update-utmp.service systemd-update-utmp-runlevel.service

    # Journal flush to disk (kept in RAM only for speed — see phase 7 Storage=volatile)
    mask_if_present systemd-journal-flush.service systemd-journald-sync@.service

    # Sysctl (no kernel params to set at boot)
    mask_if_present systemd-sysctl.service

    # Fsck (the VM always shuts down clean)
    mask_if_present systemd-fsck-root.service systemd-fsck@.service

    # Machine credential loading
    mask_if_present systemd-machine-id-commit.service systemd-credential-watcher.service

    echo "--- Phase 6: Remove unnecessary systemd generators (re-derived) ---"
    # Generators run at every boot scanning for fstab/crypttab/etc. Re-derive the
    # deletion list from what trixie actually ships rather than replaying bookworm.
    echo "[inventory] generators present (trixie):"
    ls "$GEN_DIR" 2>/dev/null | awk "{print \"  \" \$1}" || true
    # Deletion denylist: generators this appliance never needs (no crypt/RAID/LVM,
    # no GPT auto-mount, no hibernate, no SysV, no verity/integrity/TPM). Guarded so
    # a name that is absent in trixie is simply skipped.
    # (Verified against the trixie systemd 257 generator set in a build probe.
    # systemd-ssh-generator is new since systemd 256 — it would synthesize ssh
    # socket units at every boot; this image ships no sshd, so drop it.
    # NOTE: systemd-getty-generator is deliberately NOT removed — it is kept at
    # exact bookworm-lean parity (console=ttyAMA0 handling), a change we cannot
    # boot-verify from a cloud session. See docs/debian-trixie-qa.md section 1.)
    for gen in systemd-cryptsetup-generator systemd-debug-generator \
               systemd-fstab-generator systemd-gpt-auto-generator \
               systemd-hibernate-resume-generator systemd-rc-local-generator \
               systemd-run-generator systemd-system-update-generator \
               systemd-sysv-generator systemd-veritysetup-generator \
               systemd-integritysetup-generator systemd-tpm2-generator \
               systemd-ssh-generator systemd-bless-boot-generator; do
        if [ -e "$GEN_DIR/$gen" ]; then rm -f "$GEN_DIR/$gen"; else echo "[gen] absent: $gen"; fi
    done
    echo "[inventory] generators remaining after prune:"
    ls "$GEN_DIR" 2>/dev/null | awk "{print \"  \" \$1}" || true

    # Also remove system-environment-generators (none needed in this image)
    rm -rf "$ENV_GEN_DIR"/* 2>/dev/null || true

    echo "--- Phase 7: systemd tuning ---"
    mkdir -p etc/systemd/system.conf.d
    cat > etc/systemd/system.conf.d/shellphone.conf << SYSD
[Manager]
# Aggressive timeouts for the VM environment
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=5s
DefaultDeviceTimeoutSec=5s
# Minimize logging overhead
LogLevel=warning
LogTarget=journal
# Do not dump core on crash
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

    echo "--- Phase 8: fstab (minimal, noatime for performance) ---"
    cat > etc/fstab << FSTAB
/dev/vda / ext4 rw,noatime,errors=continue 0 0
FSTAB

    echo "--- Phase 9: APT sources (trixie) ---"
    cat > etc/apt/sources.list << APT
deb http://deb.debian.org/debian trixie main
deb http://deb.debian.org/debian trixie-updates main
deb http://security.debian.org/debian-security trixie-security main
APT

    echo "--- Phase 10: Root setup ---"
    # Empty password for root
    sed -i "s|^root:[^:]*:|root::|" etc/shadow
    # Ensure root home exists
    mkdir -p root
    # Bash profile
    cat > root/.bashrc << BASHRC
export PS1="\[\e[32m\]\u@shellphone\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\\$ "
export TERM=xterm-256color
export COLORTERM=truecolor
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
  Debian 13 (trixie) on iPhone

MOTD

    mkdir -p etc/profile.d
    cat > etc/profile.d/shellphone.sh << PROF
#!/bin/sh
stty cols 52 rows 40 2>/dev/null
export COLORTERM=truecolor
if [ -z "\$SHELLPHONE_SHOWN" ]; then
    export SHELLPHONE_SHOWN=1
    cat /etc/motd 2>/dev/null
    IP=\$(ip -4 addr show eth0 2>/dev/null | awk "/inet /{print \\\$2}")
    [ -n "\$IP" ] && printf "  Network: %s\n\n" "\$IP"
fi
PROF
    chmod +x etc/profile.d/shellphone.sh

    echo "--- Phase 12: Strip for size ---"
    # merged-/usr: docs/man/info still live under usr/share; confirm the paths the
    # bookworm build rm-ed by path did not move.
    rm -rf usr/share/doc/*
    rm -rf usr/share/man/*
    rm -rf usr/share/info/*
    rm -rf var/cache/apt/archives/*.deb
    rm -rf var/lib/apt/lists/*
    rm -rf usr/share/lintian 2>/dev/null
    rm -rf usr/share/bug 2>/dev/null
    find usr/share/locale -maxdepth 1 -type d ! -name locale ! -name en_US | xargs rm -rf 2>/dev/null || true
    find usr/share/zoneinfo -maxdepth 1 -type d ! -name zoneinfo ! -name UTC ! -name Etc | xargs rm -rf 2>/dev/null || true
    # Remove __pycache__ and .pyc files
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true

    echo "--- Phase 13: Verify ---"
    echo "Rootfs size: $(du -sh /mnt/rootfs | cut -f1)"
    echo "Unit files: $(find "$SYSTEMD_SYSTEM" -name '*.service' | wc -l) services"
    echo "Generators: $(ls "$GEN_DIR" 2>/dev/null | wc -l) generators"
    echo "Masked: $(find etc/systemd/system -name '*.service' -type l -exec readlink {} \; 2>/dev/null | grep -c /dev/null) services"

    cd / && sync && umount /mnt/rootfs

    echo "--- Converting to qcow2 ---"
    qemu-img convert -f raw -O qcow2 /tmp/debian.raw /output/debian-trixie.qcow2

    echo "--- Compressing ---"
    gzip -9 -c /output/debian-trixie.qcow2 > /output/debian-trixie.qcow2.gz

    ls -lh /output/debian-trixie.qcow2 /output/debian-trixie.qcow2.gz
    echo "SHA-256 (compressed asset, for DistroCatalog.swift):"
    sha256sum /output/debian-trixie.qcow2.gz
    echo "=== Done ==="
  ' 2>&1
