#!/bin/bash
################################################################################
# Script: kernel/test-suspend.sh
# Description: Staged suspend-to-RAM test. Walks the kernel's pm_test levels
#              (freezer, devices, platform, processors, core); each one runs the
#              real suspend path up to that point, waits about 5 s and resumes,
#              so a driver that cannot suspend shows up without powering down.
#              With --real it then does a full suspend woken by the RTC alarm.
# Usage: sudo ./kernel/test-suspend.sh [--real] [--debug] [--level NAME] [SECONDS]
#   --real        after the staged levels pass, suspend for real and wake from the RTC.
#                 If resume fails the machine hangs and needs a power cycle: save work first.
#   --level NAME  run only that pm_test level (freezer, devices, platform, processors, core)
#   --debug       for hunting a hang: keep the console alive during suspend, print every
#                 device's suspend/resume callback and run them one at a time, so the last
#                 line on the screen (or the debug UART, ttyAMA10) names the culprit.
#                 Settings are restored on exit. Needs a power cycle if it does hang.
# Log: kernel/build/suspend-test.log
################################################################################
set -uo pipefail

REAL=false
DEBUG=false
ONLY=""
SECS=20
while (($#)); do
    case "$1" in
        --real) REAL=true ;;
        --debug) DEBUG=true ;;
        --level) shift; ONLY="${1:-}" ;;
        --level=*) ONLY="${1#--level=}" ;;
        ''|*[!0-9]*) echo "usage: $0 [--real] [--debug] [--level NAME] [SECONDS]" >&2; exit 2 ;;
        *) SECS="$1" ;;
    esac
    shift
done
case "$ONLY" in ''|freezer|devices|platform|processors|core) ;; *) echo "unknown level: $ONLY" >&2; exit 2 ;; esac
[[ $EUID -eq 0 ]] || { echo "run as root: sudo $0 $*" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/build/suspend-test.log"
mkdir -p "$HERE/build"
: > "$LOG"

pass=0; fail=0
ok()   { echo "[PASS] $*" | tee -a "$LOG"; pass=$((pass+1)); }
bad()  { echo "[FAIL] $*" | tee -a "$LOG"; fail=$((fail+1)); }
info() { echo "[INFO] $*" | tee -a "$LOG"; }

[[ -w /sys/power/pm_test ]] || { echo "kernel has no pm_test (CONFIG_PM_DEBUG)" >&2; exit 1; }
grep -qw mem /sys/power/state || { echo "/sys/power/state has no 'mem'; suspend unsupported" >&2; exit 1; }

declare -A SAVED
knob() { # knob FILE VALUE: set a sysfs/proc value and remember the old one
    [[ -w "$1" ]] || return 0
    SAVED["$1"]="$(cat "$1")"
    echo "$2" > "$1" 2>/dev/null || true
}
cleanup() {
    echo none > /sys/power/pm_test 2>/dev/null
    local f
    for f in "${!SAVED[@]}"; do echo "${SAVED[$f]}" > "$f" 2>/dev/null || true; done
}
trap cleanup EXIT

if $DEBUG; then
    knob /sys/module/printk/parameters/console_suspend N   # keep printing after consoles would sleep
    knob /proc/sys/kernel/printk "8 8 1 8"                 # every level to the console
    knob /sys/power/pm_debug_messages 1
    knob /sys/power/pm_print_times 1                       # 'calling X' / 'X returned' per device
    knob /sys/power/pm_async 0                             # one device at a time, so the last line is the culprit
    info "debug on: console stays live, per-device PM messages, synchronous callbacks"
fi

# Messages that mean a suspend or resume problem
BAD_RE='PM: (Some devices failed|failed to suspend|failed to resume)|failed to suspend|failed to resume|suspend of devices failed|Freezing .* failed|timed out|Oops|BUG:|WARNING:|Call trace|firmware trap|brcmf_fw_crashed|I/O error|xHCI host controller not responding|hc died'

kernel_msgs_since() { journalctl -k --since "@$1" --no-pager 2>/dev/null; }

echo "kernel $(uname -r), mem_sleep: $(cat /sys/power/mem_sleep 2>/dev/null)" | tee -a "$LOG"

# --- staged levels -------------------------------------------------------------
for level in freezer devices platform processors core; do
    [[ -z "$ONLY" || "$ONLY" == "$level" ]] || continue
    grep -qw "$level" /sys/power/pm_test || { info "pm_test level '$level' not offered, skipped"; continue; }
    sync
    t0=$(date +%s)
    echo "$level" > /sys/power/pm_test
    if echo mem > /sys/power/state 2>>"$LOG"; then
        msgs=$(kernel_msgs_since "$t0")
        echo "$msgs" >> "$LOG"
        if grep -Eq "$BAD_RE" <<<"$msgs"; then
            bad "level '$level': suspended but the kernel reported problems"
            grep -E "$BAD_RE" <<<"$msgs" | head -5 | sed 's/^/        /'
            break
        fi
        ok "level '$level' suspend and resume"
    else
        bad "level '$level': write to /sys/power/state failed"
        kernel_msgs_since "$t0" | tail -15 | tee -a "$LOG" | sed 's/^/        /'
        break
    fi
    sleep 2
done
echo none > /sys/power/pm_test

# --- device state after the staged levels ---------------------------------------
if ((fail == 0)); then
    for ifc in wlan0; do
        if [[ "$(cat /sys/class/net/$ifc/operstate 2>/dev/null)" == up ]]; then ok "$ifc still up"; else info "$ifc not up (may still be reconnecting)"; fi
    done
fi

# --- full suspend ---------------------------------------------------------------
if $REAL; then
    if ((fail > 0)); then
        info "skipping the real suspend because a staged level failed"
    elif [[ ! -e /sys/class/rtc/rtc0/wakealarm ]]; then
        info "no RTC wake alarm; skipping the real suspend"
    else
        info "real suspend for ${SECS}s: the screen will go off; it wakes by itself"
        sync
        t0=$(date +%s)
        if rtcwake -m mem -s "$SECS" >>"$LOG" 2>&1; then
            t1=$(date +%s)
            slept=$((t1 - t0))
            if ((slept >= SECS - 2)); then ok "real suspend/resume (away ${slept}s, asked for ${SECS}s)"; else bad "woke after ${slept}s, expected about ${SECS}s"; fi
            msgs=$(kernel_msgs_since "$t0")
            echo "$msgs" >> "$LOG"
            if grep -Eq "$BAD_RE" <<<"$msgs"; then
                bad "kernel reported problems during the real suspend"
                grep -E "$BAD_RE" <<<"$msgs" | head -8 | sed 's/^/        /'
            else
                ok "no suspend/resume errors in the kernel log"
            fi
        else
            bad "rtcwake failed (see $LOG)"
        fi
    fi
fi

echo
echo "RESULT: $pass passed, $fail failed. Full log: $LOG"
((fail == 0))
