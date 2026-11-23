#!/bin/bash

################################################################################
# Script: hackberrypiq20verify.sh
# Description: Read-only verification that hackberrypiq20setup.sh (default
#              options) has been applied. Changes nothing. Run it before and
#              after the setup script, or after a reinstall.
# Usage: bash ./hackberrypiq20verify.sh [-g GOVERNOR] [-k]
#          -g GOVERNOR  expected CPU governor (default: powersave)
#          -k           skip KDE per-user checks
# Exit code: 0 if no FAIL, 1 otherwise. WARN/SKIP never fail the run.
################################################################################

set -u

EXPECT_GOV="powersave"
CHECK_KDE=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        -g) EXPECT_GOV="$2"; shift 2 ;;
        -k) CHECK_KDE=false; shift ;;
        -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

PASS=0; FAIL=0; WARN=0
ok()   { echo -e "\033[0;32m[PASS]\033[0m $*"; ((PASS++)); }
bad()  { echo -e "\033[0;31m[FAIL]\033[0m $*"; ((FAIL++)); }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; ((WARN++)); }
skip() { echo -e "\033[1;33m[SKIP]\033[0m $*"; }
section() { echo; echo "== $* =="; }

# check <description> <command...>  (PASS if command succeeds)
check() {
    local desc="$1"; shift
    if "$@" &>/dev/null; then ok "$desc"; else bad "$desc"; fi
}

section "CPU governor and activity LED"
unit=/etc/systemd/system/cpufreq-tune.service
check "cpufreq-tune.service exists" test -f "$unit"
check "cpufreq-tune.service enabled" systemctl is-enabled cpufreq-tune.service
check "unit sets governor $EXPECT_GOV" grep -q "frequency-set -g $EXPECT_GOV\$" "$unit"
check "unit sets ACT LED trigger to cpu" grep -q "echo cpu | /usr/bin/tee /sys/class/leds/ACT/trigger" "$unit"
gov=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null)
[[ "$gov" == "$EXPECT_GOV" ]] && ok "live governor is $gov" || bad "live governor is '$gov' (expected $EXPECT_GOV)"
if [[ -r /sys/class/leds/ACT/trigger ]]; then
    grep -q '\[cpu\]' /sys/class/leds/ACT/trigger && ok "ACT LED trigger is [cpu]" || bad "ACT LED trigger is not [cpu]"
else
    skip "no ACT LED"
fi

section "NVMe / PCIe power"
grep -qE '(^|[[:space:]])pcie_aspm.policy=powersave' /proc/cmdline && ok "booted with pcie_aspm.policy=powersave" \
    || { grep -q 'pcie_aspm.policy=powersave' /boot/firmware/cmdline.txt 2>/dev/null \
         && warn "in cmdline.txt but not in running kernel (reboot needed)" || bad "pcie_aspm.policy=powersave missing"; }
check "nvme.conf has default_ps_max_latency_us=5500" grep -q 'default_ps_max_latency_us=5500' /etc/modprobe.d/nvme.conf
grep -q 'nvme_core.default_ps_max_latency_us=5500' /boot/firmware/cmdline.txt 2>/dev/null \
    && ok "cmdline.txt has nvme_core.default_ps_max_latency_us=5500 (nvme_core is built-in)" \
    || bad "nvme_core.default_ps_max_latency_us=5500 missing from cmdline.txt"
live=$(cat /sys/module/nvme_core/parameters/default_ps_max_latency_us 2>/dev/null)
[[ "$live" == "5500" ]] && ok "live nvme_core latency is 5500" || warn "live nvme_core latency is '${live:-n/a}' (reboot needed after cmdline change)"
check "fstrim.timer enabled" systemctl is-enabled fstrim.timer

section "System tuning (sysctl, journald, WiFi power save)"
[[ "$(sysctl -n vm.swappiness 2>/dev/null)" == "10" ]] && ok "vm.swappiness=10" || bad "vm.swappiness != 10"
[[ "$(sysctl -n vm.dirty_writeback_centisecs 2>/dev/null)" == "1500" ]] && ok "vm.dirty_writeback_centisecs=1500" || bad "vm.dirty_writeback_centisecs != 1500"
[[ "$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)" == "50" ]] && ok "vm.vfs_cache_pressure=50" || bad "vm.vfs_cache_pressure != 50"
check "journald drop-in present" grep -q 'SystemMaxUse=100M' /etc/systemd/journald.conf.d/99-hackberry.conf
check "NetworkManager wifi.powersave=3 drop-in present" grep -q 'wifi.powersave = 3' /etc/NetworkManager/conf.d/99-wifi-powersave.conf

section "Touchscreen sleep hook"
check "hackberry-touch helper installed" test -x /usr/local/sbin/hackberry-touch
check "systemd-sleep hook installed" test -x /usr/lib/systemd/system-sleep/hackberry-touch
check "hackberry-touch.service enabled" systemctl is-enabled hackberry-touch.service
check "hackberry-touch.service active" systemctl is-active hackberry-touch.service
for d in /sys/class/input/input*; do
    [[ "$(basename "$(readlink -f "$d/device/driver" 2>/dev/null)")" == "edt_ft5x06" ]] || continue
    [[ "$(<"$d/inhibited")" == 0 ]] && ok "touchscreen currently enabled (screen on)" || warn "touchscreen currently inhibited (expected only while screen is off)"
done
for d in /sys/class/input/input*; do
    grep -qi 'HACKBerryPiQ20' "$d/name" 2>/dev/null || continue
    [[ "$(cat "$d/inhibited" 2>/dev/null)" == 1 ]] && bad "$(<"$d/name") is inhibited (keyboard/trackpad must stay on)" || ok "$(<"$d/name") not inhibited"
done

section "Networking"
check "NetworkManager enabled" systemctl is-enabled NetworkManager
check "NetworkManager active" systemctl is-active NetworkManager
if [[ -r /etc/netplan/50-cloud-init.yaml ]]; then
    grep -q 'renderer: NetworkManager' /etc/netplan/50-cloud-init.yaml && ok "netplan renderer is NetworkManager" || bad "netplan renderer not NetworkManager"
else
    warn "cannot read /etc/netplan/50-cloud-init.yaml (run with sudo to check)"
fi
systemctl is-enabled networking.service &>/dev/null && bad "networking.service still enabled" || ok "networking.service not enabled"

section "Disabled services"
for u in bluetooth.service packagekit.service wpa_supplicant.service phpsessionclean.service \
         phpsessionclean.timer ModemManager.service colord.service NetworkManager-wait-online.service \
         networking-wait-online.service cups-browsed.service man-db.timer e2scrub_all.timer fwupd-refresh.timer; do
    if ! systemctl list-unit-files "$u" 2>/dev/null | grep -q "^$u"; then
        skip "$u not installed"
    else
        state=$(systemctl is-enabled "$u" 2>/dev/null)
        case "$state" in
            enabled|enabled-runtime|alias|linked)
                bad "$u is still $state" ;;
            static|indirect|generated|transient)
                # No [Install] section: it cannot be disabled, only kept from running
                if systemctl is-active "$u" &>/dev/null; then
                    warn "$u is $state and currently running"
                else
                    ok "$u is $state and not running (nothing to disable)"
                fi ;;
            *) ok "$u not enabled ($state)" ;;
        esac
    fi
done
if command -v rfkill &>/dev/null; then
    rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes' && ok "Bluetooth soft-blocked (default)" || warn "Bluetooth not soft-blocked (fine if you used -b)"
fi

section "Display and tools"
check "Xorg HackBerry display config present" test -f /etc/X11/xorg.conf.d/10-hackberry-display.conf
check "raspi-config linked" test -x /usr/bin/raspi-config
check "rpi-eeprom-update linked" test -x /usr/bin/rpi-eeprom-update
if dpkg-query -W -f='${Status}' kali-desktop-kde 2>/dev/null | grep -q 'ok installed'; then
    check "qml6-module-qtnetwork installed" dpkg -s qml6-module-qtnetwork
    check "qml6-module-org-kde-notifications installed" dpkg -s qml6-module-org-kde-notifications
fi

section "KDE (per user)"
if ! $CHECK_KDE; then
    skip "KDE checks disabled (-k)"
elif ! dpkg-query -W -f='${Status}' kali-desktop-kde 2>/dev/null | grep -q 'ok installed'; then
    skip "KDE not installed"
elif ! command -v kreadconfig6 &>/dev/null; then
    skip "kreadconfig6 not found"
else
    kuser="${SUDO_USER:-$(id -un)}"
    khome=$(getent passwd "$kuser" | cut -d: -f6)
    kr() { # file group key  (group may be "A/B" for nested groups)
        local file="$1" grp="$2" key="$3" args=() g IFS=/
        for g in $grp; do args+=(--group "$g"); done
        sudo -H -u "$kuser" kreadconfig6 --file "$file" "${args[@]}" --key "$key" 2>/dev/null \
            || kreadconfig6 --file "$file" "${args[@]}" --key "$key" 2>/dev/null
    }
    expect() { # desc file group key value
        local cur; cur=$(kr "$2" "$3" "$4")
        [[ "$cur" == "$5" ]] && ok "$1 ($4=$cur)" || warn "$1: $4='${cur:-unset}' (script default: $5; a user-set value is kept on purpose)"
    }
    expect "blur effect disabled"     kwinrc          Plugins          blurEnabled false
    expect "borderless maximized"     kwinrc          Windows          BorderlessMaximizedWindows true
    expect "auto-lock on"             kscreenlockerrc Daemon           Autolock true
    expect "auto-lock timeout 10 min" kscreenlockerrc Daemon           Timeout 10
    expect "Konsole menu bar hidden"  konsolerc       MainWindow       MenuBar Disabled
    expect "animation factor"         kdeglobals      KDE              AnimationDurationFactor 0.25
    for app in org.kde.discover.notifier org.kde.kdeconnect.daemon; do
        f="$khome/.config/autostart/$app.desktop"
        if [[ -e "/etc/xdg/autostart/$app.desktop" ]]; then
            grep -q '^Hidden=true' "$f" 2>/dev/null && ok "$app autostart hidden" || bad "$app autostart not hidden"
        fi
    done
    command -v balooctl6 &>/dev/null && { balooctl6 status 2>&1 | grep -qi disabled && ok "Baloo disabled" || warn "Baloo not disabled"; }
    if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
        [[ "$XDG_SESSION_TYPE" == "wayland" ]] && ok "session is Wayland" || warn "session is $XDG_SESSION_TYPE (expected wayland)"
    fi
fi

section "Hardware watchdog"
check "watchdog drop-in present" grep -q 'RuntimeWatchdogSec=15' /etc/systemd/system.conf.d/99-hackberry-watchdog.conf
if [[ -e /dev/watchdog0 ]]; then
    ok "/dev/watchdog0 present ($(cat /sys/class/watchdog/watchdog0/identity 2>/dev/null))"
    wd=$(systemctl show -p RuntimeWatchdogUSec --value 2>/dev/null)
    [[ "$wd" == "15s" ]] && ok "systemd RuntimeWatchdog is $wd" || bad "systemd RuntimeWatchdog is '${wd:-n/a}' (expected 15s; run systemctl daemon-reexec or reboot)"
else
    warn "no /dev/watchdog0"
fi

section "Custom kernel (optional, setup -K)"
if grep -q '^# hackberry-kernel-begin' /boot/firmware/config.txt 2>/dev/null; then
    prefix=$(sed -n 's/^os_prefix=//p' /boot/firmware/config.txt | tail -1)
    ok "config.txt selects custom kernel (os_prefix=$prefix)"
    for f in kernel_2712.img cmdline.txt overlays/hackberrypicm5.dtbo; do
        check "/boot/firmware/${prefix}$f present" test -f "/boot/firmware/${prefix}$f"
    done
    ls /boot/firmware/"${prefix}"bcm2712*.dtb &>/dev/null && ok "bcm2712 dtbs staged" || bad "no bcm2712 dtbs in /boot/firmware/${prefix}"
    cmp -s /boot/firmware/cmdline.txt "/boot/firmware/${prefix}cmdline.txt" && ok "staged cmdline.txt matches stock" \
        || warn "staged cmdline.txt differs from /boot/firmware/cmdline.txt (re-run kernel/install.sh)"
    case "$(uname -r)" in
        *-hackberry-*)
            ok "running custom kernel $(uname -r)"
            [[ "$(getconf PAGESIZE)" == "16384" ]] && ok "16K page size" || bad "page size is $(getconf PAGESIZE), expected 16384"
            [[ -d /sys/class/power_supply ]] && ls /sys/class/power_supply | grep -qi 'max1704\|battery' \
                && ok "battery power_supply present" || warn "no battery power_supply (overlay/driver for this kernel?)"
            modinfo -F version brcmfmac 2>/dev/null | grep -q nexmon && ok "brcmfmac is the nexmon build" || warn "brcmfmac is not the nexmon build"
            [[ -e /sys/class/net/wlan0 ]] && ok "wlan0 present" || bad "wlan0 missing (brcmfmac failed to load?)"
            dmesg 2>/dev/null | grep -qiE 'brcmf.*(firmware.*(fail|error)|timeout)' && warn "brcmfmac errors in dmesg" || ok "no brcmfmac firmware errors in dmesg"
            ;;
        *) warn "os_prefix is set but running $(uname -r) (reboot, or the bootloader fell back)" ;;
    esac
else
    skip "custom kernel not enabled (running $(uname -r))"
fi

echo
echo "================================================================"
echo "Verification: $PASS passed, $FAIL failed, $WARN warnings"
echo "================================================================"
[[ $FAIL -eq 0 ]]
