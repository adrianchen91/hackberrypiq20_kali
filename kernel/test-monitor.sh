#!/bin/bash
################################################################################
# Script: kernel/test-monitor.sh
# Description: Passive monitor-mode smoke test for the nexmon-patched brcmfmac.
#              Takes wlan0 down (the nexmon firmware halts if monitor mode is
#              enabled while wlan0 is associated), adds mon0, sets a channel,
#              captures for a few seconds, then restores wlan0. Receive only
#              unless --inject is given.
# Usage: sudo ./kernel/test-monitor.sh [--inject] [CHANNEL]     (default channel 6)
#   --inject  also run the standard 'aireplay-ng --test' injection check. This
#             TRANSMITS ordinary probe requests (no deauth or attack traffic) on
#             the chosen channel; use a non-DFS channel with an AP on it (2.4 GHz 1/6/11,
#             5 GHz 36-48 or 149-165). Check first: nmcli dev wifi list. DFS channels
#             (52-144) need radar detection and must not be transmitted on.
# WiFi is OFF for about a minute: run from the local terminal, not over WiFi.
# Output is also saved to kernel/build/monitor-test.log.
################################################################################
set -u
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HERE/build"
LOG="$HERE/build/monitor-test.log"
exec > >(tee "$LOG") 2>&1

INJECT=false
CH=6
for a in "$@"; do
    case "$a" in
        --inject) INJECT=true ;;
        [0-9]*) CH="$a" ;;
        *) echo "unknown argument: $a"; exit 2 ;;
    esac
done
PCAP=/tmp/hb-monitor-test.pcap
FAILED=0
ok()   { echo "[PASS] $*"; }
bad()  { echo "[FAIL] $*"; FAILED=1; }
crashed() { journalctl -k --since "@$1" --no-pager 2>/dev/null | grep -q 'brcmf_fw_crashed\|firmware trap'; }
phy_of_wlan0() { iw dev wlan0 info | awk '/wiphy/ {print "phy"$2}'; }

CON=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: '$2=="wlan0"{print $1; exit}')
echo "kernel $(uname -r)  brcmfmac $(modinfo -F version brcmfmac) srcversion $(cat /sys/module/brcmfmac/srcversion)"
echo "wlan0 connection: ${CON:-none}   monitor channel: $CH"

restore() {
    iw dev mon0 del 2>/dev/null
    rm -f "$PCAP"
    nmcli dev set wlan0 managed yes 2>/dev/null
    ip link set wlan0 up 2>/dev/null
    [[ -n "$CON" ]] && nmcli con up "$CON" >/dev/null 2>&1
    for _ in $(seq 1 20); do   # DHCP can take a while; wait up to 20 s
        state=$(nmcli -t -f DEVICE,STATE dev | grep '^wlan0:' | cut -d: -f2)
        [[ "$state" == "connected" ]] && break
        sleep 1
    done
    if [[ "$state" == "connected" ]]; then ok "wlan0 restored ($state)"; else bad "wlan0 is '$state' after restore"; fi
}
trap restore EXIT

T0=$(date +%s)
nmcli dev set wlan0 managed no
ip link set wlan0 down
sleep 2

iw dev mon0 del 2>/dev/null
iw phy "$(phy_of_wlan0)" interface add mon0 type monitor && ok "mon0 created" || { bad "could not create mon0"; exit 1; }
sleep 1
ip link set mon0 up && ok "mon0 up" || bad "mon0 would not come up"
sleep 4
if crashed "$T0"; then bad "FIRMWARE CRASHED when mon0 came up"; exit 2; fi
ok "no firmware crash after mon0 up"

iw dev mon0 info | grep -q 'type monitor' && ok "mon0 reports type monitor" || bad "mon0 is not type monitor"
iw dev mon0 set channel "$CH" && ok "set_monitor_channel works (channel $CH)" || bad "set channel $CH failed"
sleep 2

timeout 15 tcpdump -i mon0 -c 300 -w "$PCAP" >/dev/null 2>&1
N=$(tcpdump -r "$PCAP" 2>/dev/null | wc -l)
[[ "$N" -gt 0 ]] && ok "captured $N frames" || bad "captured no frames in 15 s"
tcpdump -r "$PCAP" 2>/dev/null | grep -qi beacon && ok "saw beacon frames" || echo "[INFO] no beacons seen"
tcpdump -r "$PCAP" -e -c 1 2>&1 | grep -qi 'radiotap\|signal' && ok "radiotap headers present" || echo "[INFO] could not confirm radiotap headers"
if crashed "$T0"; then bad "FIRMWARE CRASHED during capture"; fi

if $INJECT; then
    if ! command -v aireplay-ng >/dev/null; then
        bad "aireplay-ng not installed (apt install aircrack-ng)"
    else
        echo "--- injection test (aireplay-ng --test) on channel $CH"
        INJ=$(timeout 60 aireplay-ng --test mon0 2>&1)
        echo "$INJ" | sed 's/^/    /' | tail -15
        if echo "$INJ" | grep -q 'Injection is working'; then ok "injection works"
        elif echo "$INJ" | grep -qi 'No Answer'; then bad "injected but no AP answered (quiet channel, or injection not reaching the air)"
        else bad "injection test did not complete"; fi
        if crashed "$T0"; then bad "FIRMWARE CRASHED during injection"; fi
    fi
fi

iw dev mon0 del && ok "mon0 removed" || bad "could not remove mon0"

echo "--- kernel messages during test"
journalctl -k --since "@$T0" --no-pager 2>/dev/null | grep -iE 'brcmf.*(crash|trap|error)|BUG|Oops|Call trace' | tail -10
echo
[[ $FAILED -eq 0 ]] && echo "RESULT: monitor mode OK" || echo "RESULT: FAILURES above"
