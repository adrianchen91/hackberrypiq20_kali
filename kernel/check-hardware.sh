#!/bin/bash
################################################################################
# Script: kernel/check-hardware.sh
# Description: Verify that every driver this device uses today exists in a lean
#              kernel build. Collects modules from (1) lsmod, (2) drivers bound to
#              devices in sysfs, (3) modalias resolution for every device, then
#              checks each against the module list of a built kernel package or,
#              without one, against the modules removed by lean.config.
# Usage: ./kernel/check-hardware.sh [--deb PATH]      (default: kernel/out image deb)
# Run it on the device you care about while it runs a FULL kernel (the stock 6.12 or
# the full 6.18 build), with display, touch, keyboard, audio and Bluetooth in use, so
# the module list reflects everything it needs. Needs no root.
################################################################################
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deb) DEB="$2"; shift 2 ;;
        -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ -n "$DEB" ]] || DEB=$(ls "$HERE"/out/linux-image-*.deb 2>/dev/null | head -1)
[[ -f "$DEB" ]] || { echo "no image deb found (build first, or pass --deb)"; exit 1; }

norm() { tr '-' '_'; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Modules available in the kernel package
dpkg-deb -c "$DEB" | awk '{print $6}' | grep -E '\.ko(\.zst|\.xz|\.gz)?$' | sed -E 's#.*/##; s#\.ko(\.zst|\.xz|\.gz)?$##' | norm | sort -u > "$TMP/available"

# What this device uses: loaded modules + modules of drivers bound in sysfs + alias resolution
{
    lsmod | awk 'NR>1 {print $1}'
    for d in /sys/bus/*/drivers/*/module; do [[ -e "$d" ]] && basename "$(readlink -f "$d")"; done
    find /sys/devices -name modalias -readable 2>/dev/null | while read -r f; do
        a=$(cat "$f" 2>/dev/null); [[ -n "$a" ]] && modprobe -R "$a" 2>/dev/null
    done
} | norm | sort -u > "$TMP/used"

# Modules that are built in don't appear as .ko; ignore names the running kernel reports as built-in
sed 's#.*/##; s#\.ko.*##' "/lib/modules/$(uname -r)/modules.builtin" 2>/dev/null | norm | sort -u > "$TMP/builtin"
comm -23 "$TMP/used" "$TMP/builtin" > "$TMP/used_pre"
# A loaded loadable module has /sys/module/<name>/initstate; built-in drivers listed in sysfs do not
: > "$TMP/used_mods"
while read -r m; do
    if [[ -d "/sys/module/$m" && ! -e "/sys/module/$m/initstate" ]]; then continue; fi
    # Names that modprobe cannot resolve are built-in drivers or alias leftovers, not modules to keep
    modprobe --show-depends "$m" >/dev/null 2>&1 || continue
    echo "$m" >> "$TMP/used_mods"
done < "$TMP/used_pre"

[[ -n "${LIST_USED:-}" ]] && { cp "$TMP/used_mods" "$LIST_USED"; }
missing=$(comm -23 "$TMP/used_mods" "$TMP/available")
# Out-of-tree DKMS modules (battery driver) are rebuilt for the new kernel by DKMS, not shipped in the package
dkms_mods=""
for m in $missing; do
    path=$(modinfo -n "$m" 2>/dev/null)
    [[ "$path" == */updates/* ]] && dkms_mods="$dkms_mods $m"
done
for m in $dkms_mods; do missing=$(echo "$missing" | grep -vx "$m"); done
[[ -n "$dkms_mods" ]] && echo "provided by DKMS (rebuilt on install):$dkms_mods"
echo "kernel package: $(basename "$DEB")"
echo "modules in package: $(wc -l < "$TMP/available")   modules this device uses: $(wc -l < "$TMP/used_mods")"
if [[ -z "$missing" ]]; then
    echo "[PASS] every module this device uses is in the package"
    exit 0
fi
echo "[FAIL] used by this device but NOT in the package:"
echo "$missing" | sed 's/^/    /'
exit 1
