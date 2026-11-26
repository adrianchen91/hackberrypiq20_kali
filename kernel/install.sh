#!/bin/bash
################################################################################
# Script: kernel/install.sh
# Description: Install the HackBerry custom kernel built by build.sh, stage it
#              under /boot/firmware/<BOOT_PREFIX>/ and (optionally) switch the
#              Pi bootloader to it with os_prefix=. The stock 6.12 kernel and
#              its files in /boot/firmware are never touched, so rollback is
#              removing one line from config.txt.
# Usage: sudo ./kernel/install.sh [--dir DIR] [--enable | --disable] [--allow-suspend] [--dry-run]
#   --dir DIR    directory with the .deb files (default: kernel/out)
#   --enable     after staging, add os_prefix to config.txt (backed up first)
#   --disable    only remove os_prefix from config.txt (rollback) and exit
#   --allow-suspend  do not block system suspend (see below); also removes the block
#   --dry-run    print what would happen, change nothing (no root needed)
# Suspend is blocked by default: on rpi-7.3.y /sys/power/state offers 'mem', so KDE idles
# into suspend, and the CM5 then hangs at the platform stage and needs a power cycle
# (see kernel/README.md, Known not working). A systemd sleep.conf.d drop-in sets
# AllowSuspend=no so logind reports CanSuspend=no. Use --allow-suspend once it works.
# Re-running is safe: files are refreshed, config.txt is edited idempotently.
# Run it again after changing /boot/firmware/cmdline.txt so the copy follows.
################################################################################
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kernel.conf
source "$HERE/kernel.conf"

DEBDIR="$HERE/out"
ENABLE=false DISABLE=false DRY=false ALLOW_SUSPEND=false
FW=/boot/firmware
CONFIG_TXT="$FW/config.txt"
BEGIN="# hackberry-kernel-begin"
END="# hackberry-kernel-end"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DEBDIR="$2"; shift 2 ;;
        --enable) ENABLE=true; shift ;;
        --disable) DISABLE=true; shift ;;
        --allow-suspend) ALLOW_SUSPEND=true; shift ;;
        --dry-run|-D) DRY=true; shift ;;
        -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

info() { echo -e "\033[0;32m[kernel-install]\033[0m $*"; }
warn() { echo -e "\033[1;33m[kernel-install]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[kernel-install]\033[0m $*" >&2; exit 1; }
# run <cmd...>: execute, or just report in dry-run mode
run()  { if $DRY; then echo -e "\033[1;33m[DRY-RUN]\033[0m would run: $*" >&2; else "$@"; fi; }

$DRY || [[ $EUID -eq 0 ]] || die "run as root (sudo), or use --dry-run"
[[ -f "$CONFIG_TXT" ]] || die "$CONFIG_TXT not found; is /boot/firmware mounted?"

remove_prefix() {
    if grep -qF "$BEGIN" "$CONFIG_TXT"; then
        info "Removing os_prefix block from config.txt"
        run sed -i "/^$BEGIN\$/,/^$END\$/d" "$CONFIG_TXT"
    else
        info "No os_prefix block in config.txt"
    fi
}

if $DISABLE; then
    remove_prefix
    info "Next boot uses the stock kernel."
    exit 0
fi

# --- locate and install packages ----------------------------------------------
shopt -s nullglob
images=("$DEBDIR"/linux-image-*.deb)
headers=("$DEBDIR"/linux-headers-*.deb)
shopt -u nullglob
[[ ${#images[@]} -eq 1 ]] || die "expected exactly one linux-image deb in $DEBDIR (found ${#images[@]}); run kernel/build.sh"

KVER="$(dpkg-deb -f "${images[0]}" Package)"
KVER="${KVER#linux-image-}"
[[ "$KVER" == *-rpi-* ]] && die "kernel release '$KVER' contains '-rpi-'; raspi-firmware hook would overwrite the stock kernel"
info "Kernel release: $KVER (prefix $BOOT_PREFIX)"

# DKMS source for the stock-kernel nexmon driver must not build for this kernel:
# a DKMS copy in /updates would shadow the nexmon-patched in-tree brcmfmac.
if dpkg -s brcmfmac-nexmon-dkms &>/dev/null; then
    nexmon_ver="$(dpkg-query -W -f='${Version}' brcmfmac-nexmon-dkms)"
    info "Restricting brcmfmac-nexmon DKMS ($nexmon_ver) to the stock 6.12 kernel"
    run install -d /etc/dkms
    if ! $DRY; then
        printf '%s\n' '# Written by hackberrypiq20_kali kernel/install.sh' \
            '# The custom 7.3 kernel carries the nexmon patch in-tree.' \
            'BUILD_EXCLUSIVE_KERNEL="^6\.12\."' > /etc/dkms/brcmfmac-nexmon.conf
    fi
fi

# Suspend hangs the CM5 on rpi-7.3.y (pm_test 'platform' stage), and KDE's idle timer
# triggers it by itself, so tell logind that no sleep state is available.
SLEEP_CONF=/etc/systemd/sleep.conf.d/hackberry-no-suspend.conf
if $ALLOW_SUSPEND; then
    if [[ -e "$SLEEP_CONF" ]]; then
        info "Removing $SLEEP_CONF (suspend allowed again)"
        run rm -f "$SLEEP_CONF"
    fi
else
    info "Blocking system suspend ($SLEEP_CONF); it hangs on this kernel, see kernel/README.md"
    run install -d /etc/systemd/sleep.conf.d
    if ! $DRY; then
        printf '%s\n' '# Written by hackberrypiq20_kali kernel/install.sh' \
            '# Suspend hangs the CM5 on rpi-7.3.y. Re-run install.sh with --allow-suspend to remove.' \
            '[Sleep]' 'AllowSuspend=no' 'AllowHibernation=no' \
            'AllowSuspendThenHibernate=no' 'AllowHybridSleep=no' > "$SLEEP_CONF"
    fi
fi

info "Installing packages"
run apt-get install -y --reinstall "${images[@]}" "${headers[@]}"

$DRY || [[ -d "/lib/modules/$KVER" ]] || die "/lib/modules/$KVER missing after install"
$DRY || [[ -f "/boot/vmlinuz-$KVER" ]] || die "/boot/vmlinuz-$KVER missing after install"

# --- stage boot files ---------------------------------------------------------
DST="$FW/$BOOT_PREFIX"
DTB_SRC="/usr/lib/linux-image-$KVER"
info "Staging boot files in $DST"
run install -d "$DST/overlays"
run install -m 0755 "/boot/vmlinuz-$KVER" "$DST/kernel_2712.img"

if [[ -f "/boot/initrd.img-$KVER" ]] || $DRY; then
    run install -m 0755 "/boot/initrd.img-$KVER" "$DST/initramfs_2712"
else
    warn "no initrd for $KVER; config.txt has auto_initramfs=1 but nothing will be loaded"
fi

if $DRY; then
    echo -e "\033[1;33m[DRY-RUN]\033[0m would copy $DTB_SRC/broadcom/bcm27*.dtb and $DTB_SRC/overlays/* into $DST" >&2
else
    dtbs=("$DTB_SRC"/broadcom/bcm2712*.dtb)
    [[ ${#dtbs[@]} -gt 0 ]] || die "no bcm2712 dtbs under $DTB_SRC/broadcom"
    install -m 0644 "${dtbs[@]}" "$DST/"
    if compgen -G "$DTB_SRC/overlays/*" >/dev/null; then
        cp -f "$DTB_SRC"/overlays/* "$DST/overlays/"
    else
        warn "package has no overlays; copying stock overlays from $FW/overlays"
        cp -f "$FW"/overlays/* "$DST/overlays/"
    fi
fi

# HackBerry overlay is built separately with dtc and is kernel independent
if [[ -f "$FW/overlays/hackberrypicm5.dtbo" ]]; then
    run install -m 0644 "$FW/overlays/hackberrypicm5.dtbo" "$DST/overlays/"
else
    warn "hackberrypicm5.dtbo not found in $FW/overlays; display/battery overlay missing (run setup script -t first)"
fi

# Same kernel command line as the stock kernel
run install -m 0644 "$FW/cmdline.txt" "$DST/cmdline.txt"

# --- switch the bootloader ----------------------------------------------------
if $ENABLE; then
    remove_prefix
    run cp -n "$CONFIG_TXT" "$CONFIG_TXT.pre-hb-kernel"
    info "Adding os_prefix=$BOOT_PREFIX/ to config.txt"
    if $DRY; then
        echo -e "\033[1;33m[DRY-RUN]\033[0m would append [all] os_prefix=$BOOT_PREFIX/ block to $CONFIG_TXT" >&2
    else
        printf '\n%s\n[all]\nos_prefix=%s/\n%s\n' "$BEGIN" "$BOOT_PREFIX" "$END" >> "$CONFIG_TXT"
    fi
    info "Reboot to use $KVER. Verify with: bash hackberrypiq20verify.sh"
    info "Rollback: sudo $0 --disable   (or delete the block between '$BEGIN' and '$END' in config.txt)"
else
    info "Staged only. Enable with: sudo $0 --enable"
fi
