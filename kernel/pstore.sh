#!/bin/bash
################################################################################
# Script: kernel/pstore.sh
# Description: Keep the kernel log across a hang or panic, so a freeze that leaves
#              nothing on disk (like the suspend hang, see kernel/README.md) can be
#              read after the reboot. Reserves 2 MiB of RAM on the kernel command line
#              (reserve_mem=) and points ramoops at it (ramoops.mem_name=); the pstore
#              console (CONFIG_PSTORE_CONSOLE) mirrors every printk into it. A hung
#              board only reboots by itself if the hardware watchdog fires (systemd
#              RuntimeWatchdog, about 15 s), and the log only survives if the firmware
#              leaves RAM alone on that reset. A power cycle clears RAM. --panic-test
#              shows whether it works at all.
#              (The stock ramoops-pi5 overlay was tried first: the firmware skipped the
#              dtoverlay line without a message, so the command line is used instead.)
# Usage: sudo ./kernel/pstore.sh --enable | --disable | --check | --show
#                                 | --panic-test --yes     [--dry-run]
#   --enable      add the options to /boot/firmware/cmdline.txt and the staged copy
#                 (backed up once); reboot to apply
#   --disable     remove them again
#   --check       is ramoops registered on the running kernel? (no root needed)
#   --show        list and tail what the last boot recovered, and copy it to
#                 kernel/build/pstore-<time>/ (needs root to read /sys/fs/pstore)
#   --panic-test  sync, set kernel.panic=5 and crash the kernel with sysrq-c, then
#                 run --show after the reboot. Unclean shutdown: save your work first
#   --dry-run     print what would happen, change nothing
# Re-run --enable after kernel/install.sh: it copies the stock cmdline.txt over the
# staged one (the stock file is edited too, so the options normally survive).
################################################################################
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kernel.conf
source "$HERE/kernel.conf"

FW=/boot/firmware
CONFIG_TXT="$FW/config.txt"
CMDLINES=("$FW/cmdline.txt" "$FW/$BOOT_PREFIX/cmdline.txt")
BEGIN="# hackberry-pstore-begin"   # config.txt block from the abandoned overlay attempt
END="# hackberry-pstore-end"
LABEL=hbpstore
# 2 MiB: 1 MiB console log, 8 x 128 KiB crash records. Align to 64 KiB (pages are 16 KiB).
TOKENS="reserve_mem=2M:65536:$LABEL ramoops.mem_name=$LABEL ramoops.record_size=131072 ramoops.console_size=1048576 ramoops.ftrace_size=0 ramoops.pmsg_size=0 ramoops.ecc=0"
SAVE_DIR="$HERE/build/pstore-$(date +%Y%m%d-%H%M%S)"

MODE="" DRY=false YES=false
for a in "$@"; do
    case "$a" in
        --enable|--disable|--check|--show|--panic-test) MODE="$a" ;;
        --yes) YES=true ;;
        --dry-run|-D) DRY=true ;;
        -h|--help) sed -n '3,27p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done
[[ -n "$MODE" ]] || { sed -n '3,27p' "$0" >&2; exit 2; }

info() { echo -e "\033[0;32m[pstore]\033[0m $*"; }
warn() { echo -e "\033[1;33m[pstore]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[pstore]\033[0m $*" >&2; exit 1; }
run()  { if $DRY; then echo -e "\033[1;33m[DRY-RUN]\033[0m would run: $*" >&2; else "$@"; fi; }
need_root() { $DRY || [[ $EUID -eq 0 ]] || die "run as root (sudo), or use --dry-run"; }

kernel_log() { journalctl -k -b --no-pager 2>/dev/null || dmesg 2>/dev/null || true; }
registered() { kernel_log | grep -qE 'pstore: Registered ramoops|ramoops: using'; }

# Drop our options (and nothing else) from one cmdline file.
strip_tokens() {
    run sed -i -E "s/ +(reserve_mem=[^ ]*:$LABEL|ramoops\\.[a-z_]+=[^ ]*)//g" "$1"
}

remove_config_block() {   # leftover from the overlay attempt
    if [[ -f "$CONFIG_TXT" ]] && grep -qF "$BEGIN" "$CONFIG_TXT"; then
        info "Removing the old overlay block from config.txt"
        run sed -i "/^$BEGIN\$/,/^$END\$/d" "$CONFIG_TXT"
    fi
}

case "$MODE" in
    --enable)
        need_root
        remove_config_block
        for f in "${CMDLINES[@]}"; do
            if [[ ! -f "$f" ]]; then warn "$f not found, skipped"; continue; fi
            [[ "$(wc -l < "$f")" -le 1 ]] || die "$f has more than one line; edit it by hand"
            info "Adding the pstore options to $f"
            run cp -n "$f" "$f.pre-hb-pstore"
            strip_tokens "$f"
            run sed -i "1s/ *\$/ $TOKENS/" "$f"
        done
        info "Reboot, then: ./kernel/pstore.sh --check"
        info "Rollback: sudo $0 --disable"
        ;;
    --disable)
        need_root
        remove_config_block
        for f in "${CMDLINES[@]}"; do
            [[ -f "$f" ]] || continue
            info "Removing the pstore options from $f"
            strip_tokens "$f"
        done
        ;;
    --check)
        if registered; then
            kernel_log | grep -E 'pstore:|ramoops|reserve_mem|Reserved' | tail -4 | cut -c1-170
            info "ramoops is registered; the log is being mirrored into RAM"
        else
            kernel_log | grep -iE 'reserve_mem|ramoops' | tail -3 | cut -c1-170 || true
            die "ramoops is not registered on this boot (options missing, or not rebooted yet)"
        fi
        ;;
    --show)
        mkdir -p "$SAVE_DIR"
        found=0
        for d in /sys/fs/pstore /var/lib/systemd/pstore; do
            [[ -r "$d" ]] || { warn "cannot read $d (needs root)"; continue; }
            while IFS= read -r f; do
                found=1
                echo "== $f"
                cp -p "$f" "$SAVE_DIR/$(echo "$f" | tr '/' '_')" 2>/dev/null || true
            done < <(find "$d" -type f 2>/dev/null | sort)
        done
        if ((found)); then
            info "Copied to $SAVE_DIR"
            newest=$(find /sys/fs/pstore /var/lib/systemd/pstore -type f -name '*console*' 2>/dev/null | sort | tail -n1)
            [[ -n "$newest" ]] || newest=$(find /sys/fs/pstore /var/lib/systemd/pstore -type f 2>/dev/null | sort | tail -n1)
            echo "---- last 60 lines of $newest"
            tail -n 60 "$newest" 2>/dev/null || true
        else
            rmdir "$SAVE_DIR" 2>/dev/null || true
            info "Nothing recovered from the last boot"
        fi
        ;;
    --panic-test)
        need_root
        registered || die "ramoops is not registered; run --enable, reboot and --check first"
        if ! $YES; then
            warn "This crashes the kernel on purpose (sysrq-c) and reboots in about 5 s."
            warn "Save your work, then run: sudo $0 --panic-test --yes"
            exit 1
        fi
        info "Marking the log, syncing, then crashing the kernel"
        echo "pstore-test: marker before crash $(date +%T)" > /dev/kmsg
        sync
        run sysctl -q kernel.panic=5
        run sh -c 'echo c > /proc/sysrq-trigger'
        ;;
esac
