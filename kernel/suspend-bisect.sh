#!/bin/bash
################################################################################
# Script: kernel/suspend-bisect.sh
# Description: Find the PM callback or stage where the CM5 suspend hangs, by binary
#              search. Needs a kernel built with `build.sh --debug-patches` (patch 0004,
#              the pm_restart_after hook) and kernel/pstore.sh enabled.
#              Each probe runs the pm_test 'platform' suspend with pm_restart_after=K,
#              which warm-resets the machine right before event K (pstore keeps the log
#              across that reset). If the machine hangs before event K it never resets
#              and you have to power-cycle it. The highest K that still resets is the
#              event that hangs, and its name is in the log.
# Usage: sudo ./kernel/suspend-bisect.sh --next      run the next probe (save work first)
#        sudo ./kernel/suspend-bisect.sh --result    after the reboot or power cycle,
#                                                    record what happened
#        ./kernel/suspend-bisect.sh --status | sudo ./kernel/suspend-bisect.sh --reset
# Loop: --next, wait for the reset (or 60 s then power-cycle), --result, repeat until
#       it prints the culprit. About 11 probes. State: kernel/build/bisect.state.
################################################################################
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HERE/build/bisect.state"
LOGDIR="$HERE/build/bisect"
PARAM=/sys/module/kernel/parameters/pm_restart_after
PSTORE_DIRS=(/sys/fs/pstore /var/lib/systemd/pstore)
HI_DEFAULT=1500

info() { echo -e "\033[0;32m[bisect]\033[0m $*"; }
warn() { echo -e "\033[1;33m[bisect]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[bisect]\033[0m $*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "run as root: sudo $0 $*"; }

lo=0 hi=$HI_DEFAULT pending="" started=0 completed=0 name=""
load() { [[ -f "$STATE" ]] && source "$STATE"; return 0; }
save() {
    mkdir -p "$HERE/build"
    printf 'lo=%s\nhi=%s\npending=%s\nstarted=%s\ncompleted=%s\nname=%q\n' \
        "$lo" "$hi" "$pending" "$started" "$completed" "$name" > "$STATE"
}

status() {
    info "range: event $lo was reached, event $((hi + 1)) was not; searching ($lo, $hi]"
    [[ -z "$pending" ]] || info "probe K=$pending is pending: run --result"
    [[ -z "$name" ]] || info "last reached event named: $name"
}

culprit() {
    info "Done: the hang is event $lo."
    [[ -z "$name" ]] || info "That event: $name"
    info "Logs of each reached probe: $LOGDIR/"
}

MODE="${1:-}"
load
case "$MODE" in
    --status) status ;;
    --reset)
        need_root "$@"; lo=0 hi=$HI_DEFAULT pending="" started=0 completed=0 name=""; save
        info "State reset (searching events 1..$HI_DEFAULT)" ;;
    --next)
        need_root "$@"
        [[ -w "$PARAM" ]] || die "$PARAM missing: boot a kernel built with build.sh --debug-patches"
        [[ -z "$pending" ]] || die "probe K=$pending is unresolved: run --result first"
        ((lo < hi)) || { culprit; exit 0; }
        K=$(((lo + hi + 1) / 2))
        pending=$K started=$(date +%s) completed=0; save
        info "Probe K=$K (range $lo..$hi). Save your work. The machine should reset by itself;"
        info "if nothing happens for 60 s, power-cycle it and run --result."
        sync
        echo "$K" > "$PARAM"
        "$HERE/test-suspend.sh" --debug --level platform
        # still here: the kernel survived the whole suspend, so nothing hung
        echo 0 > "$PARAM"
        completed=1; save
        warn "The suspend ran to the end without resetting or hanging (K=$K was never reached)."
        warn "Run --result to record that." ;;
    --result)
        need_root "$@"
        [[ -n "$pending" ]] || die "no probe is pending: run --next"
        K=$pending; marker="pm-bisect: restarting before event $K:"; hit=""
        for d in "${PSTORE_DIRS[@]}"; do
            [[ -d "$d" ]] || continue
            while IFS= read -r f; do
                [[ "$(stat -c %Y "$f")" -ge "$started" ]] || continue
                if grep -aq -- "$marker" "$f" 2>/dev/null; then hit="$f"; break 2; fi
            done < <(find "$d" -type f 2>/dev/null)
        done
        if [[ -n "$hit" ]]; then
            mkdir -p "$LOGDIR"; cp -p "$hit" "$LOGDIR/probe-$K.log"
            name="$(grep -a -- "$marker" "$hit" | tail -n1 | sed -E "s/.*restarting before event $K: *//")"
            lo=$K
            info "K=$K: reached (the machine reset). Event $K is: $name"
        elif ((completed)); then
            pending=""; save
            warn "K=$K: the suspend completed normally, so the hang did not reproduce this time."
            warn "Run --next again (or --reset to start over)."; exit 0
        else
            hi=$((K - 1))
            info "K=$K: not reached (it hung before that event)"
        fi
        pending="" completed=0; save
        if ((lo >= hi)); then culprit; else status; info "Next: sudo $0 --next"; fi ;;
    *) sed -n '3,19p' "$0"; exit 2 ;;
esac
