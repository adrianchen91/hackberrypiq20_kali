#!/bin/bash

################################################################################
# Script: hackberrypiq20setup.sh
# Description: Setup script for HackBerry Pi CM5 Q20 device.
#              Configures auto-login, CPU governor, power management, service
#              optimization, and other system performance settings.
# Usage: sudo ./hackberrypiq20setup.sh [OPTIONS]
# Maintainer: adrianchen91
# Source: https://github.com/adrianchen91/hackberrypiq20_kali
# CODEOWNERS: @adrianchen91
################################################################################

set -uo pipefail  # Exit on undefined variables and pipe failures, but allow error recovery

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Tracking variables
FAILED_OPERATIONS=()
SKIPPED_OPERATIONS=()
SKIPPED_BY_FLAG=()
SUCCESS_COUNT=0
FAIL_COUNT=0

# Default values
CPU_GOVERNOR="powersave"
ENABLE_WIFI=false
ENABLE_BLUETOOTH=false
ENABLE_SERVICE_OPTIMIZATION=true
ENABLE_POWER_MANAGEMENT=true
ENABLE_FSTAB_OPTIMIZATION=false
ENABLE_RASPI_CONFIG=true
ENABLE_EEPROM=true
ENABLE_GREETD=false
ENABLE_NETWORKING_OPTIMIZATION=true
ENABLE_XORG_CONFIG=true
ENABLE_DEVICE_TREE=false
VERBOSE=false
ENABLE_BRAVE=false
ENABLE_ANTIGRAVITY=false
ENABLE_CLOUD_CLEANUP=false
ENABLE_KDE_OPTIMIZATION=true
ENABLE_TOUCH_SLEEP=true
ONLY_TOUCH_SLEEP=false
DRY_RUN=false
ENABLE_CUSTOM_KERNEL=false
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Functions
################################################################################

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Track operation results
track_success() {
    ((SUCCESS_COUNT++))
}

track_failure() {
    local operation="$1"
    FAILED_OPERATIONS+=("$operation")
    ((FAIL_COUNT++))
}

track_skip() {
    local operation="$1"
    SKIPPED_OPERATIONS+=("$operation")
}

track_skip_flag() {
    local operation="$1"
    SKIPPED_BY_FLAG+=("$operation")
}

# Check if script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Usage: sudo $0 [OPTIONS]"
        exit 1
    fi
    print_status "Running as root"
}

# Display usage information
usage() {
    cat << EOF
Usage: sudo $0 [OPTIONS]

Options:
    -g, --cpu-governor GOVERNOR     Set CPU governor (default: 'powersave')
                                    Options: powersave, performance, ondemand, conservative, schedutil
    -w, --enable-wifi               Enable WiFi interface
    -b, --enable-bluetooth          Enable Bluetooth (disabled by default)
    -s, --disable-service-opt       Disable service optimization
    -p, --disable-power-mgmt        Disable power management configuration
    -f, --enable-fstab-opt          Enable fstab optimization (noatime)
    -r, --disable-raspi-config      Skip raspi-config installation
    -e, --disable-eeprom            Skip rpi-eeprom setup
    -d, --enable-greetd             Install and configure greetd display manager (optional)
    -n, --disable-network-opt       Skip networking optimization
    -x, --disable-xorg-config       Skip Xorg configuration
    -t, --enable-device-tree        Setup HackBerry device tree (conditional)
    -v, --verbose                   Enable verbose output
    --install-brave                Install Brave browser
    --install-antigravity          Install Antigravity package and repository
    -D, --dry-run                   Show what would change without modifying anything (no root needed)
    -K, --custom-kernel             Build (if needed), install and enable the custom 6.18 kernel from kernel/ (slow: ~30-45 min build on the CM5)
    -k, --disable-kde-opt           Skip KDE Plasma tuning (animations, blur, borderless maximized, lock, splash, Konsole, autostarts)
    --only-touch-sleep              Run ONLY the touchscreen sleep hook step, nothing else (combine with -D to preview)
    --disable-touch-sleep           Skip the touchscreen sleep hook (touch off while screen is blanked/suspended)
    --enable-cloud-cleanup         Enable cloud-init cleanup/optimisation (disables cloud-init services)
    -h, --help                      Display this help message

Examples:
    sudo $0 -g performance
    sudo $0 --cpu-governor powersave --enable-wifi --enable-bluetooth
    sudo $0 -f
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--cpu-governor)
                CPU_GOVERNOR="$2"
                shift 2
                ;;
            -w|--enable-wifi)
                ENABLE_WIFI=true
                shift
                ;;
            -b|--enable-bluetooth)
                ENABLE_BLUETOOTH=true
                shift
                ;;
            -s|--disable-service-opt)
                ENABLE_SERVICE_OPTIMIZATION=false
                shift
                ;;
            -p|--disable-power-mgmt)
                ENABLE_POWER_MANAGEMENT=false
                shift
                ;;
            -f|--enable-fstab-opt)
                ENABLE_FSTAB_OPTIMIZATION=true
                shift
                ;;
            -r|--disable-raspi-config)
                ENABLE_RASPI_CONFIG=false
                shift
                ;;
            -e|--disable-eeprom)
                ENABLE_EEPROM=false
                shift
                ;;
            -d|--enable-greetd)
                ENABLE_GREETD=true
                shift
                ;;
            -n|--disable-network-opt)
                ENABLE_NETWORKING_OPTIMIZATION=false
                shift
                ;;
            -x|--disable-xorg-config)
                ENABLE_XORG_CONFIG=false
                shift
                ;;
            -t|--enable-device-tree)
                ENABLE_DEVICE_TREE=true
                shift
                ;;
            -D|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -K|--custom-kernel)
                ENABLE_CUSTOM_KERNEL=true
                shift
                ;;
            -k|--disable-kde-opt)
                ENABLE_KDE_OPTIMIZATION=false
                shift
                ;;
            --only-touch-sleep)
                ONLY_TOUCH_SLEEP=true
                shift
                ;;
            --disable-touch-sleep)
                ENABLE_TOUCH_SLEEP=false
                shift
                ;;
            --install-brave)
                ENABLE_BRAVE=true
                shift
                ;;
            --install-antigravity)
                ENABLE_ANTIGRAVITY=true
                shift
                ;;
            --enable-cloud-cleanup)
                ENABLE_CLOUD_CLEANUP=true
                shift
                ;;
            --disable-cloud-cleanup)
                ENABLE_CLOUD_CLEANUP=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate parameters
validate_parameters() {
    case "$CPU_GOVERNOR" in
        powersave|performance|ondemand|conservative|schedutil)
            ;;
        *)
            print_error "Invalid CPU governor: $CPU_GOVERNOR"
            echo "Valid options: powersave, performance, ondemand, conservative, schedutil"
            exit 1
            ;;
    esac
}

# Display configuration
display_config() {
    print_status "Configuration:"
    echo "  CPU Governor: $CPU_GOVERNOR"
    echo "  WiFi Enabled: $ENABLE_WIFI"
    echo "  Bluetooth Enabled: $ENABLE_BLUETOOTH"
    echo "  Service Optimization: $ENABLE_SERVICE_OPTIMIZATION"
    echo "  Power Management: $ENABLE_POWER_MANAGEMENT"
    echo "  Fstab Optimization: $ENABLE_FSTAB_OPTIMIZATION"
    echo "  Raspi-config: $ENABLE_RASPI_CONFIG"
    echo "  Rpi-eeprom: $ENABLE_EEPROM"
    echo "  Greetd: $ENABLE_GREETD"
    echo "  Network Optimization: $ENABLE_NETWORKING_OPTIMIZATION"
    echo "  Xorg Config: $ENABLE_XORG_CONFIG"
    echo "  Device Tree: $ENABLE_DEVICE_TREE"
    echo "  Verbose Mode: $VERBOSE"
    echo "  Brave Install: $ENABLE_BRAVE"
    echo "  Antigravity Install: $ENABLE_ANTIGRAVITY"
    echo "  Cloud Cleanup: $ENABLE_CLOUD_CLEANUP"
    echo "  KDE Optimization: $ENABLE_KDE_OPTIMIZATION"
    echo "  Touch Sleep Hook: $ENABLE_TOUCH_SLEEP"
    echo "  Custom Kernel: $ENABLE_CUSTOM_KERNEL"
    echo "  Dry Run: $DRY_RUN"
}

# Write the cpufreq-tune unit (single source of truth for new and updated installs)
cpufreq_unit_text() {
    # The leading '-' on ExecStartPre keeps the unit working if the ACT LED is absent
    cat <<EOF
[Unit]
Description=Custom CPU frequency scaling with $CPU_GOVERNOR
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/sh -c 'echo cpu | /usr/bin/tee /sys/class/leds/ACT/trigger'
ExecStart=/usr/bin/cpupower frequency-set -g $CPU_GOVERNOR

[Install]
WantedBy=multi-user.target
EOF
}

write_cpufreq_unit() {
    cpufreq_unit_text | tee "$1" >/dev/null
}

# Configure CPU governor
configure_cpu_governor() {
    if ! $ENABLE_POWER_MANAGEMENT; then
        print_warning "Power management disabled, skipping CPU governor configuration"
        track_skip_flag "CPU governor"
        return 0
    fi

    print_status "Setting CPU governor to: $CPU_GOVERNOR"
    
    # Install linux-cpupower if not available
    if ! which cpupower &>/dev/null; then
        print_status "Installing linux-cpupower..."
        if ! apt-get update && apt-get install -y linux-cpupower 2>/dev/null; then
            print_warning "Failed to install linux-cpupower, attempting to continue"
        fi
    fi

    # Check if service already exists
    local service_file="/etc/systemd/system/cpufreq-tune.service"
    if [[ -f "$service_file" ]]; then
        print_status "cpufreq-tune service already exists"
        
        # Extract current governor from the service file
        local current_governor
        current_governor=$(grep -oP 'frequency-set -g \K\S+' "$service_file" | head -1)
        
        if [[ "$current_governor" == "$CPU_GOVERNOR" ]]; then
            print_status "Service already configured with governor: $current_governor"
            # Rewrite the unit if it drifted from the expected content (e.g. missing ACT LED trigger)
            if [[ "$(cat "$service_file")" != "$(cpufreq_unit_text)" ]]; then
                print_status "Unit content differs from expected, updating (ACT LED trigger = cpu)..."
                if write_cpufreq_unit "$service_file"; then
                    systemctl daemon-reload
                    if systemctl enable --now cpufreq-tune.service 2>/dev/null; then
                        track_success
                        return 0
                    fi
                    print_warning "Failed to restart cpufreq-tune.service"
                    track_failure "CPU governor service"
                    return 1
                fi
                print_error "Failed to update cpufreq-tune service file"
                track_failure "CPU governor"
                return 1
            fi
            # Check if service is enabled
            if systemctl is-enabled cpufreq-tune.service &>/dev/null; then
                print_status "cpufreq-tune service already enabled"
                track_skip "CPU governor"
                return 0
            fi
        else
            # Governor differs, update the service
            print_status "Governor mismatch: service has '$current_governor', updating to '$CPU_GOVERNOR'..."
            if write_cpufreq_unit "$service_file"; then
                systemctl daemon-reload
                if systemctl enable --now cpufreq-tune.service 2>/dev/null; then
                    print_status "CPU governor updated and service restarted"
                    track_success
                    return 0
                else
                    print_warning "Failed to restart cpufreq-tune.service"
                    track_failure "CPU governor service"
                    return 1
                fi
            else
                print_error "Failed to update cpufreq-tune service file"
                track_failure "CPU governor"
                return 1
            fi
        fi
        
        # Check if service is enabled (for unchanged governor case)
        if systemctl is-enabled cpufreq-tune.service &>/dev/null; then
            track_skip "CPU governor"
            return 0
        else
            print_status "Enabling existing cpufreq-tune service..."
            systemctl daemon-reload
            if systemctl enable --now cpufreq-tune.service 2>/dev/null; then
                print_status "CPU governor configuration completed"
                track_success
                return 0
            else
                print_warning "Failed to enable cpufreq-tune.service"
                track_failure "CPU governor service"
                return 1
            fi
        fi
    fi

    # Create systemd service for CPU frequency scaling
    print_status "Creating cpufreq-tune systemd service..."
    if write_cpufreq_unit "$service_file"; then
        # Enable and start the service
        systemctl daemon-reload
        if systemctl enable --now cpufreq-tune.service 2>/dev/null; then
            print_status "CPU governor configuration completed"
            track_success
            return 0
        else
            print_warning "Failed to enable cpufreq-tune.service"
            track_failure "CPU governor service"
            return 1
        fi
    else
        print_error "Failed to create cpufreq-tune service file"
        track_failure "CPU governor"
        return 1
    fi
}

# Configure WiFi
configure_wifi() {
    print_status "Configuring WiFi (Enabled: $ENABLE_WIFI)"
    
    if $ENABLE_WIFI; then
        print_status "Enabling WiFi interface..."
        # Example: nmcli radio wifi on
    else
        print_status "WiFi remains in current state"
    fi
}

# Configure Bluetooth
configure_bluetooth() {
    print_status "Configuring Bluetooth (Enabled: $ENABLE_BLUETOOTH)"
    
    if ! command -v rfkill &>/dev/null; then
        print_warning "rfkill not found, skipping Bluetooth configuration"
        return 0
    fi

    if ! $ENABLE_BLUETOOTH; then
        print_status "Disabling Bluetooth..."
        systemctl disable --now bluetooth.service 2>/dev/null || {
            print_warning "Failed to disable bluetooth.service (may not exist)"
        }
        rfkill block bluetooth 2>/dev/null || true
    else
        print_status "Enabling Bluetooth..."
        rfkill unblock bluetooth 2>/dev/null || {
            print_warning "rfkill not available"
        }
        systemctl enable --now bluetooth.service 2>/dev/null || {
            print_warning "Failed to enable bluetooth.service"
        }
    fi
    
    track_success
    return 0
}

# Dry-run mode: shadow every state-changing command with a function that only
# reports what it would do. Read-only commands (systemctl is-enabled, cat, grep,
# dpkg-query, kreadconfig6, ...) still run for real so the report is accurate.
dry_note() {
    echo -e "${YELLOW}[DRY-RUN]${NC} $*" >&2
}

enable_dry_run() {
    local c
    for c in apt-get git netplan sysctl update-initramfs mount usermod rfkill \
             curl make ln cp mkdir chmod gpg kwriteconfig6; do
        eval "$c() { dry_note would run: $c \"\$@\"; return 0; }"
    done

    systemctl() {
        case "${1:-}" in
            is-enabled|is-active|status|show|cat|list-units|list-unit-files)
                command systemctl "$@" ;;
            *) dry_note would run: systemctl "$@"; return 0 ;;
        esac
    }

    sed() {
        local a
        for a in "$@"; do
            if [[ "$a" == -i* ]]; then
                dry_note would run: sed "$@"
                return 0
            fi
        done
        command sed "$@"
    }

    # Report whether a file would be created, changed or left alone
    tee() {
        local f="${*: -1}" tmp
        tmp=$(mktemp)
        cat >"$tmp"
        if [[ -r "$f" ]]; then
            if cmp -s "$tmp" "$f"; then
                dry_note "$f unchanged"
            else
                dry_note "$f would change:"
                diff -u "$f" "$tmp" | command sed 's/^/    /' >&2
            fi
        elif [[ -e "$f" ]]; then
            dry_note "$f exists but is not readable here; would be rewritten"
        else
            dry_note "$f would be created:"
            command sed 's/^/    + /' "$tmp" >&2
        fi
        rm -f "$tmp"
    }

    # Drop sudo's options and run the command directly (it hits the shadows above)
    sudo() {
        local -a a=("$@")
        while [[ "${a[0]:-}" == -* ]]; do
            if [[ "${a[0]}" == -u ]]; then a=("${a[@]:2}"); else a=("${a[@]:1}"); fi
        done
        "${a[@]}"
    }
}

# Print summary of execution
print_summary() {
    echo ""
    echo "================================================================================"
    echo "Setup Summary"
    echo "================================================================================"
    
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
        echo -e "${GREEN}✓ Successful configurations: $SUCCESS_COUNT${NC}"
    fi
    
    # Skipped by feature flags
    if [[ ${#SKIPPED_BY_FLAG[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⊘ Skipped (by flag): ${#SKIPPED_BY_FLAG[@]}${NC}"
        for op in "${SKIPPED_BY_FLAG[@]}"; do
            echo "  - $op"
        done
    fi

    # Other skips (already present / non-actionable)
    if [[ ${#SKIPPED_OPERATIONS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⊘ Skipped (other): ${#SKIPPED_OPERATIONS[@]}${NC}"
        for op in "${SKIPPED_OPERATIONS[@]}"; do
            echo "  - $op"
        done
    fi
    
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}✗ Failed configurations: $FAIL_COUNT${NC}"
        for op in "${FAILED_OPERATIONS[@]}"; do
            echo "  - $op"
        done
        echo ""
        echo -e "${YELLOW}Note: Some configurations failed, but the script continued.${NC}"
        echo "Review the errors above to determine if manual intervention is needed."
    fi
    
    echo "================================================================================"
    echo ""
}

# Append a kernel parameter to the single line in cmdline.txt if its key is absent
add_cmdline_param() {
    local key="$1" param="$2" file="/boot/firmware/cmdline.txt"

    if [[ ! -f "$file" ]]; then
        print_warning "$file not found, cannot add $param"
        return 1
    fi
    if grep -qE "(^|[[:space:]])${key//./\\.}(=|[[:space:]]|$)" "$file"; then
        print_status "Kernel parameter $key already configured"
        return 0
    fi
    print_status "Adding kernel parameter: $param"
    cp -n "$file" "$file.backup" 2>/dev/null || true
    sed -i -E "1 s/[[:space:]]*\$/ $param/" "$file" || {
        print_warning "Failed to add $param to kernel parameters"
        return 1
    }
}

# Configure NVMe power management
configure_nvme_power() {
    if ! $ENABLE_POWER_MANAGEMENT; then
        print_warning "Power management disabled, skipping NVMe power configuration"
        track_skip_flag "NVMe power"
        return 0
    fi

    print_status "Configuring NVMe power management..."
    
    # Add PCIe ASPM power saving to kernel parameters
    add_cmdline_param "pcie_aspm.policy" "pcie_aspm.policy=powersave"
    # nvme_core is built into the Pi kernel, so modprobe.d options are ignored;
    # the parameter must be on the kernel command line to take effect.
    add_cmdline_param "nvme_core.default_ps_max_latency_us" "nvme_core.default_ps_max_latency_us=5500"

    # Configure NVMe default power state
    print_status "Configuring NVMe default power state..."
    if tee /etc/modprobe.d/nvme.conf >/dev/null <<EOF
options nvme_core default_ps_max_latency_us=5500
EOF
    then
        # Update initramfs
        print_status "Updating initramfs..."
        if ! update-initramfs -u 2>/dev/null; then
            print_warning "Failed to update initramfs"
        fi

        # Enable fstrim timer for NVMe optimization
        print_status "Enabling fstrim.timer..."
        if systemctl enable --now fstrim.timer 2>/dev/null; then
            print_status "NVMe power management configuration completed"
            track_success
            return 0
        else
            print_warning "Failed to enable fstrim.timer"
            track_failure "NVMe fstrim"
            return 1
        fi
    else
        print_error "Failed to configure NVMe power state"
        track_failure "NVMe power"
        return 1
    fi
}

# Configure fstab optimization
configure_fstab() {
    if ! $ENABLE_FSTAB_OPTIMIZATION; then
        print_warning "Fstab optimization disabled"
        track_skip_flag "fstab"
        return 0
    fi

    print_status "Optimizing fstab with noatime option..."
    
    # Get the root filesystem UUID
    local root_uuid
    root_uuid=$(blkid -s UUID -o value /dev/root 2>/dev/null || echo "")
    
    if [[ -z "$root_uuid" ]]; then
        print_warning "Could not determine root filesystem UUID"
        print_status "Manually add noatime to /etc/fstab root entry"
        track_skip "fstab"
        return 0
    fi

    # Check if noatime is already present for this specific UUID
    if grep -q "^UUID=$root_uuid[[:space:]].*noatime" /etc/fstab; then
        print_status "noatime already present for root filesystem"
        track_skip "fstab"
        return 0
    fi

    # Backup fstab
    cp /etc/fstab /etc/fstab.backup || {
        print_error "Failed to backup fstab"
        track_failure "fstab"
        return 1
    }
    print_status "Created backup at /etc/fstab.backup"

    # Add noatime to root mount entry (specific to UUID)
    if sed -i "s/^UUID=$root_uuid\([[:space:]]*\/[[:space:]]*ext4[[:space:]]*defaults\)/UUID=$root_uuid\1,noatime/" /etc/fstab; then
        # Verify the change was made
        if grep -q "^UUID=$root_uuid[[:space:]].*noatime" /etc/fstab; then
            # Test mounting with remount
            print_status "Testing mount with new options..."
            if mount -o remount / 2>/dev/null; then
                print_status "Fstab optimization completed successfully"
                track_success
                return 0
            else
                print_error "Failed to remount root filesystem with noatime"
                print_warning "Restoring from backup"
                cp /etc/fstab.backup /etc/fstab
                # Try to remount with original settings
                if mount -o remount / 2>/dev/null; then
                    print_status "Restored original fstab successfully"
                else
                    print_error "Failed to remount with original settings - manual recovery may be needed"
                fi
                track_failure "fstab"
                return 1
            fi
        else
            print_error "Failed to add noatime to fstab"
            print_warning "Restoring from backup"
            cp /etc/fstab.backup /etc/fstab
            track_failure "fstab"
            return 1
        fi
    else
        print_error "Failed to modify fstab"
        track_failure "fstab"
        return 1
    fi
}

# Configure service optimization
configure_services() {
    if ! $ENABLE_SERVICE_OPTIMIZATION; then
        print_warning "Service optimization disabled"
        track_skip_flag "service optimization"
        return 0
    fi

    print_status "Optimizing system services..."
    
    # Define services to disable
    local services_to_disable=(
        "bluetooth.service"
        "packagekit.service"
        "wpa_supplicant.service"
        "phpsessionclean.service"
        "phpsessionclean.timer"
        "ModemManager.service"
        "colord.service"
        "NetworkManager-wait-online.service"
        "networking-wait-online.service"
        "cups-browsed.service"
        "man-db.timer"
        "e2scrub_all.timer"
        "fwupd-refresh.timer"
    )

    local services_failed=0
    for service in "${services_to_disable[@]}"; do
        if systemctl disable "$service" 2>/dev/null; then
            print_status "Disabled $service"
        else
            print_warning "Service $service not found or failed to disable (continuing)"
            ((services_failed++))
        fi
    done

    if [[ $services_failed -eq 0 ]]; then
        print_status "Service optimization completed"
        track_success
    else
        print_warning "Service optimization completed with $services_failed failures (non-critical)"
        track_success
    fi
    return 0
}

# Clean up cloud-init services
configure_cloud_cleanup() {
    if ! $ENABLE_CLOUD_CLEANUP; then
        print_warning "Cloud cleanup disabled"
        track_skip_flag "cloud cleanup"
        return 0
    fi

    print_status "Disabling cloud-init services..."
    
    # Define cloud services to disable
    local cloud_services=(
        "cloud-init-main.service"
        "cloud-init-local.service"
        "cloud-init-network.service"
        "cloud-init-hotplugd.service"
        "cloud-final.service"
        "cloud-config.service"
    )

    local services_failed=0
    for service in "${cloud_services[@]}"; do
        if systemctl disable "$service" 2>/dev/null; then
            print_status "Disabled $service"
        else
            print_warning "Service $service not found or failed to disable (continuing)"
            ((services_failed++))
        fi
    done

    if [[ $services_failed -eq 0 ]]; then
        print_status "Cloud cleanup completed"
        track_success
    else
        print_warning "Cloud cleanup completed with $services_failed failures (non-critical)"
        track_success
    fi
    return 0
}

# Configure raspi-config
configure_raspi_config() {
    if ! $ENABLE_RASPI_CONFIG; then
        print_warning "Raspi-config installation disabled"
        track_skip_flag "raspi-config"
        return 0
    fi

    print_status "Installing raspi-config from official Raspberry Pi repo..."
    
    mkdir -p /opt/ || {
        print_error "Failed to create /opt/ directory"
        track_failure "raspi-config"
        return 1
    }
    
    # Check if already cloned
    if [[ -d "/opt/raspi-config" ]]; then
        print_status "raspi-config already cloned, updating..."
        if cd /opt/raspi-config && git pull; then
            print_status "raspi-config repository updated"
        else
            print_warning "Failed to update raspi-config, continuing with existing version"
        fi
    else
        print_status "Cloning raspi-config repository..."
        if ! git -C /opt clone https://github.com/RPi-Distro/raspi-config.git; then
            print_error "Failed to clone raspi-config repository"
            track_failure "raspi-config"
            return 1
        fi
        if [[ ! -d "/opt/raspi-config" ]]; then
            print_error "Clone appeared to succeed but directory not found"
            track_failure "raspi-config"
            return 1
        fi
    fi
    
    # Checkout branch
    if ! git -C /opt/raspi-config checkout trixie 2>/dev/null; then
        print_warning "Failed to checkout trixie branch"
    fi
    
    # Create symlink
    if ln -sf /opt/raspi-config/raspi-config /usr/bin/raspi-config && chmod +x /usr/bin/raspi-config; then
        print_status "raspi-config installed successfully"
        track_success
        return 0
    else
        print_error "Failed to create raspi-config symlink"
        track_failure "raspi-config"
        return 1
    fi
}

# Configure rpi-eeprom
configure_eeprom() {
    if ! $ENABLE_EEPROM; then
        print_warning "Rpi-eeprom installation disabled"
        track_skip_flag "rpi-eeprom"
        return 0
    fi

    print_status "Installing rpi-eeprom from official Raspberry Pi repo..."
    
    mkdir -p /opt/ || {
        print_error "Failed to create /opt/ directory"
        track_failure "rpi-eeprom"
        return 1
    }
    
    # Check if already cloned
    if [[ -d "/opt/rpi-eeprom" ]]; then
        print_status "rpi-eeprom already cloned, updating..."
        if cd /opt/rpi-eeprom && git pull; then
            print_status "rpi-eeprom repository updated"
        else
            print_warning "Failed to update rpi-eeprom, continuing with existing version"
        fi
    else
        print_status "Cloning rpi-eeprom repository..."
        if ! git -C /opt clone https://github.com/raspberrypi/rpi-eeprom.git; then
            print_error "Failed to clone rpi-eeprom repository"
            track_failure "rpi-eeprom"
            return 1
        fi
        if [[ ! -d "/opt/rpi-eeprom" ]]; then
            print_error "Clone appeared to succeed but directory not found"
            track_failure "rpi-eeprom"
            return 1
        fi
    fi
    
    if [[ -d "/opt/rpi-eeprom" ]]; then
        # Link firmware-2712 for CM5 architecture
        ln -sf /opt/rpi-eeprom/firmware-2712 /usr/bin/firmware || {
            print_warning "Failed to link firmware-2712"
        }
        
        # Link eeprom management tools
        ln -sf /opt/rpi-eeprom/rpi-eeprom-config /usr/bin/rpi-eeprom-config || {
            print_warning "Failed to link rpi-eeprom-config"
        }
        ln -sf /opt/rpi-eeprom/rpi-eeprom-update /usr/bin/rpi-eeprom-update || {
            print_warning "Failed to link rpi-eeprom-update"
        }
        ln -sf /opt/rpi-eeprom/rpi-eeprom-update-default /usr/bin/rpi-eeprom-update-default || {
            print_warning "Failed to link rpi-eeprom-update-default"
        }
        ln -sf /opt/rpi-eeprom/rpi-eeprom-digest /usr/bin/rpi-eeprom-digest || {
            print_warning "Failed to link rpi-eeprom-digest"
        }
        
        print_status "rpi-eeprom installed successfully"
        track_success
        return 0
    else
        print_error "Failed to access rpi-eeprom directory"
        track_failure "rpi-eeprom"
        return 1
    fi
}

# Configure HackBerry device tree
configure_device_tree() {
    if ! $ENABLE_DEVICE_TREE; then
        print_warning "Device tree setup disabled"
        track_skip_flag "device tree"
        return 0
    fi

    # Check if device tree blob is already present
    if [[ -f "/boot/firmware/overlays/hackberrypicm5.dtbo" ]]; then
        print_status "HackBerry device tree already installed"
        track_skip "device tree"
        return 0
    fi

    print_status "Installing HackBerry device tree..."
    
    mkdir -p /opt/ || {
        print_error "Failed to create /opt/ directory"
        track_failure "device tree"
        return 1
    }
    
    # Check if already cloned
    if [[ -d "/opt/hackberrypiq20" ]]; then
        print_status "hackberrypiq20 already cloned, updating..."
        if cd /opt/hackberrypiq20 && git pull; then
            print_status "hackberrypiq20 repository updated"
        else
            print_warning "Failed to update hackberrypiq20, continuing with existing version"
        fi
    else
        print_status "Cloning hackberrypiq20 repository..."
        if ! git -C /opt clone https://github.com/adrianchen91/hackberrypiq20.git; then
            print_error "Failed to clone hackberrypiq20 repository"
            track_failure "device tree"
            return 1
        fi
        if [[ ! -d "/opt/hackberrypiq20" ]]; then
            print_error "Clone appeared to succeed but directory not found"
            track_failure "device tree"
            return 1
        fi
    fi
    
    if [[ -d "/opt/hackberrypiq20" ]]; then
        # Checkout branch
        if ! git -C /opt/hackberrypiq20 checkout ac-module-rework 2>/dev/null; then
            print_warning "Failed to checkout ac-module-rework branch"
        fi
        
        # Install build dependencies
        print_status "Installing build dependencies..."
        if ! apt-get install -y make 2>/dev/null; then
            print_error "Failed to install make"
            track_failure "device tree"
            return 1
        fi
        if dpkg-query -W -f='${Status}' linux-headers-rpi-2712 2>/dev/null | grep -q "install ok installed"; then
            if ! apt-get install --reinstall -y linux-headers-rpi-2712 2>/dev/null; then
                print_error "Failed to reinstall linux-headers-rpi-2712"
                track_failure "device tree"
                return 1
            fi
        else
            if ! apt-get install -y linux-headers-rpi-2712 2>/dev/null; then
                print_error "Failed to install linux-headers-rpi-2712"
                track_failure "device tree"
                return 1
            fi
        fi
        
        # Build and install
        print_status "Building and installing device tree..."
        if make -C /opt/hackberrypiq20 clean 2>/dev/null && make -C /opt/hackberrypiq20 2>/dev/null; then
            print_status "Device tree built successfully"
            if make -C /opt/hackberrypiq20 install 2>/dev/null; then
                print_status "Device tree installed successfully"
                print_warning "System reboot required for changes to take effect"
                track_success
                return 0
            else
                print_error "Failed to install device tree"
                track_failure "device tree"
                return 1
            fi
        else
            print_error "Failed to build/install device tree"
            track_failure "device tree"
            return 1
        fi
    else
        print_error "Failed to access hackberrypiq20 directory"
        track_failure "device tree"
        return 1
    fi
}

# Configure networking with NetworkManager and netplan
configure_networking() {
    if ! $ENABLE_NETWORKING_OPTIMIZATION; then
        print_warning "Network optimization disabled"
        track_skip_flag "networking"
        return 0
    fi

    print_status "Optimizing networking configuration..."
    
    # Configure netplan to use NetworkManager
    print_status "Configuring netplan for NetworkManager..."
    if tee /etc/netplan/50-cloud-init.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
    then
        netplan apply 2>/dev/null || {
            print_warning "netplan apply failed"
        }
        netplan generate 2>/dev/null || {
            print_warning "netplan generate failed"
        }

        # Disable old networking service and NetworkManager-wait-online to prevent conflicts
        if systemctl disable --now networking 2>/dev/null; then
            print_status "Disabled old networking service"
        else
            print_warning "Failed to disable networking.service (may not exist)"
        fi

        # Enable NetworkManager
        if systemctl enable --now NetworkManager 2>/dev/null; then
            print_status "Network optimization completed"
            track_success

            if systemctl disable --now NetworkManager-wait-online.service 2>/dev/null; then
                print_status "Disabled NetworkManager-wait-online to prevent conflicts"
            else
                print_warning "NetworkManager-wait-online.service not found or failed to disable (may not exist)"
            fi

            return 0
        else
            print_error "Failed to enable NetworkManager"
            track_failure "networking"
            return 1
        fi
    else
        print_error "Failed to configure netplan"
        track_failure "networking"
        return 1
    fi
}

# Configure Xorg for HackBerry display
configure_xorg() {
    if ! $ENABLE_XORG_CONFIG; then
        print_warning "Xorg configuration disabled"
        track_skip_flag "Xorg"
        return 0
    fi

    print_status "Configuring Xorg for HackBerry display..."
    
    mkdir -p /etc/X11/xorg.conf.d/ || {
        print_warning "Failed to create Xorg config directory"
        track_failure "Xorg"
        return 1
    }
    
    if tee /etc/X11/xorg.conf.d/10-hackberry-display.conf >/dev/null <<'EOF'
Section "Monitor"
    Identifier "HDMI1"
    Option "Primary" "False"
EndSection

Section "Monitor"
    Identifier "HDMI2"
    Option "Primary" "False"
EndSection

Section "Monitor"
    Identifier "HDMI-1"
    Option "Primary" "False"
EndSection

Section "Monitor"
    Identifier "HDMI-2"
    Option "Primary" "False"
EndSection

Section "Monitor"
    Identifier "DPI-1-1"
    Option "Primary" "1"
EndSection

Section "Monitor"
    Identifier "DPI-1"
    Option "Primary" "1"
EndSection
EOF
    then
        print_status "Xorg configuration completed"
        track_success
        return 0
    else
        print_error "Failed to write Xorg configuration"
        track_failure "Xorg"
        return 1
    fi
}

# Configure greetd display manager
configure_greetd() {
    if ! $ENABLE_GREETD; then
        print_warning "Greetd installation disabled"
        track_skip_flag "greetd"
        return 0
    fi

    print_status "Installing and configuring greetd..."
    
    # Install greetd and tuigreet
    print_status "Installing greetd and tuigreet packages..."
    if ! apt-get update >/dev/null 2>&1; then
        print_warning "Failed to update package lists"
    fi
    
    if ! apt-get install -y greetd tuigreet >/dev/null 2>&1; then
        print_error "Failed to install greetd/tuigreet"
        track_failure "greetd"
        return 1
    fi

    # Extract user from existing config, or use default
    local greetd_user="_greetd"
    if [[ -f "/etc/greetd/config.toml" ]]; then
        local extracted_user
        extracted_user=$(grep -oP '^\s*user\s*=\s*"\K[^"]+' /etc/greetd/config.toml | head -1)
        if [[ -n "$extracted_user" ]]; then
            greetd_user="$extracted_user"
            print_status "Using existing greetd user from config: $greetd_user"
        fi
    fi

    # Verify the user exists
    if ! id "$greetd_user" &>/dev/null; then
        print_error "Greetd user '$greetd_user' does not exist"
        track_failure "greetd"
        return 1
    fi

    # Add greetd user to video and render groups
    print_status "Adding $greetd_user to video and render groups..."
    if usermod -aG video "$greetd_user" 2>/dev/null; then
        print_status "Added $greetd_user to video group"
    else
        print_warning "Failed to add $greetd_user to video group"
    fi
    
    if usermod -aG render "$greetd_user" 2>/dev/null; then
        print_status "Added $greetd_user to render group"
    else
        print_warning "Failed to add $greetd_user to render group"
    fi

    # Configure greetd with the correct user
    print_status "Configuring greetd..."
    if tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 7

[default_session]
command = "tuigreet --time --asterisks --remember-session --kb-power 12 --kb-command 1 --kb-sessions 5 --sessions /usr/share/wayland-sessions --cmd '\${SHELL:-/bin/sh}'"
user = "$greetd_user"
EOF
    then
        # Create systemd override to reduce kernel/boot logging in the greeter
        local override_dir="/etc/systemd/system/greetd.service.d"
        local override_file="$override_dir/override.conf"
        if [[ -f "$override_file" ]]; then
            print_status "greetd systemd override already present: $override_file"
        else
            print_status "Creating greetd systemd override to reduce kernel/boot messages in tuigreet..."
            mkdir -p "$override_dir" || print_warning "Failed to create $override_dir"
            if tee "$override_file" >/dev/null <<'UNIT'
[Service]
Type=idle
StandardOutput=tty
# Without this errors will spam on screen
StandardError=journal
# Without these bootlogs will spam on screen
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
UNIT
            then
                print_status "Created systemd override: $override_file"
                systemctl daemon-reload 2>/dev/null || print_warning "Failed to reload systemd daemon"
            else
                print_warning "Failed to write greetd override file"
            fi
        fi

        # Disable other display managers to avoid conflicts, then enable greetd
        local dm_services=(
            "lightdm.service"
            "sddm.service"
            "gdm.service"
            "gdm3.service"
            "lxdm.service"
            "xdm.service"
        )
        for dm in "${dm_services[@]}"; do
            if systemctl is-enabled "$dm" &>/dev/null || systemctl is-active "$dm" &>/dev/null; then
                print_status "Disabling conflicting display manager: $dm"
                systemctl disable --now "$dm" 2>/dev/null || print_warning "Failed to disable $dm or service not present"
            fi
        done

        # Enable and start greetd
        if systemctl enable --now greetd 2>/dev/null; then
            print_status "✓ Greetd display manager configured with user: $greetd_user"
            echo ""
            print_status "TTY Access Instructions (for troubleshooting):"
            echo "  If you need to drop to a command prompt:"
            echo "  • Using default keyboard layer 2 (Fn key active):"
            echo "    Ctrl+Alt+F5 → Access TTY login"
            echo "  • Using normal layer 1:"
            echo "    Ctrl+Alt+Fn+F5 → Access TTY login"
            echo "  • Return to graphical interface:"
            echo "    Ctrl+Alt+F7 or type 'exit' in TTY"
            echo ""
            track_success
            return 0
        else
            print_error "Failed to enable greetd service"
            track_failure "greetd service"
            return 1
        fi
    else
        print_error "Failed to write greetd configuration"
        track_failure "greetd"
        return 1
    fi
}

# Install Brave browser
configure_brave() {
    if ! $ENABLE_BRAVE; then
        print_warning "Brave installation disabled"
        track_skip_flag "brave"
        return 0
    fi

    # Check if already installed
    if command -v brave-browser &>/dev/null; then
        print_status "Brave browser already installed"
        track_skip "brave"
        return 0
    fi

    print_status "Installing Brave browser..."

    # Ensure curl is present
    if ! command -v curl &>/dev/null; then
        print_status "Installing curl..."
        apt-get update >/dev/null 2>&1 || true
        apt-get install -y curl >/dev/null 2>&1 || print_warning "Failed to install curl"
    fi

    mkdir -p /usr/share/keyrings || true
    if ! curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg; then
        print_error "Failed to download Brave keyring"
        track_failure "brave"
        return 1
    fi

    if ! curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources; then
        # Fallback to writing a simple deb entry
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list || true
    fi

    apt-get update >/dev/null 2>&1 || true
    if apt-get install -y brave-browser >/dev/null 2>&1; then
        print_status "Brave installed successfully"
        track_success
        return 0
    else
        print_warning "Failed to install brave-browser from apt repositories"
        track_failure "brave"
        return 1
    fi
}

# Install Antigravity repository and package
configure_antigravity() {
    if ! $ENABLE_ANTIGRAVITY; then
        print_warning "Antigravity installation disabled"
        track_skip_flag "antigravity"
        return 0
    fi

    # Check if already installed
    if command -v antigravity &>/dev/null; then
        print_status "Antigravity already installed"
        track_skip "antigravity"
        return 0
    fi

    print_status "Installing Antigravity repository and package..."

    apt-get update >/dev/null 2>&1 || true
    mkdir -p /etc/apt/keyrings || true

    if ! curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg >/dev/null 2>&1; then
        print_error "Failed to download and install Antigravity repo key"
        track_failure "antigravity"
        return 1
    fi

    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | tee /etc/apt/sources.list.d/antigravity.list >/dev/null

    apt-get update >/dev/null 2>&1 || true
    if apt-get install -y antigravity >/dev/null 2>&1; then
        print_status "Antigravity installed successfully"
        track_success
        return 0
    else
        print_warning "Failed to install antigravity"
        track_failure "antigravity"
        return 1
    fi
}

# KDE additional package workaround
configure_kde_workaround() {
    if dpkg-query -W -f='${Status}' kali-desktop-kde 2>/dev/null | grep -q "ok installed"; then
        print_status "kali-desktop-kde is installed, installing qtnetwork and notification module"
        apt-get update >/dev/null 2>&1 || true
        if apt-get install -y qml6-module-qtnetwork qml6-module-org-kde-notifications >/dev/null 2>&1; then
            print_status "KDE additional packages installed successfully"
            track_success
            return 0
        else
            print_warning "Failed to install KDE additional packages"
            track_failure "kde_workaround"
            return 1
        fi
    else
        print_status "Skipping KDE additional package workaround"
        track_skip "kde_workaround"
        return 0
    fi
}

# System-wide power/write tuning: sysctl, journald, WiFi power save
configure_power_tuning() {
    if ! $ENABLE_POWER_MANAGEMENT; then
        print_warning "Power management disabled, skipping system power tuning"
        track_skip_flag "power tuning"
        return 0
    fi

    print_status "Applying system power and write-reduction tuning..."
    local ok=true

    # Batch disk writeback, keep swapping and cache reclaim gentle
    if tee /etc/sysctl.d/99-hackberry-power.conf >/dev/null <<'EOF'
# Flush dirty pages every 15s instead of 5s so storage can stay idle longer
vm.dirty_writeback_centisecs = 1500
# Prefer RAM over swap (less storage I/O)
vm.swappiness = 10
# Keep dentry/inode caches longer (fewer disk lookups)
vm.vfs_cache_pressure = 50
EOF
    then
        sysctl --system >/dev/null 2>&1 || print_warning "Failed to apply sysctl settings"
    else
        print_warning "Failed to write sysctl tuning"
        ok=false
    fi

    # Cap journal size and sync it less often
    mkdir -p /etc/systemd/journald.conf.d
    if tee /etc/systemd/journald.conf.d/99-hackberry.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=100M
SyncIntervalSec=5m
RateLimitBurst=2000
EOF
    then
        systemctl restart systemd-journald 2>/dev/null || print_warning "Failed to restart systemd-journald"
    else
        print_warning "Failed to write journald tuning"
        ok=false
    fi

    # WiFi radio power save (NetworkManager: 3 = enable)
    mkdir -p /etc/NetworkManager/conf.d
    if tee /etc/NetworkManager/conf.d/99-wifi-powersave.conf >/dev/null <<'EOF'
[connection]
wifi.powersave = 3
EOF
    then
        systemctl reload NetworkManager 2>/dev/null || true
    else
        print_warning "Failed to write WiFi power save config"
        ok=false
    fi

    if $ok; then
        track_success
        return 0
    fi
    track_failure "power tuning"
    return 1
}

# Disable the touchscreen while the screen is blanked or the device is asleep.
# Only the edt_ft5x06 touch controller is touched; keyboard and trackpad are never affected.
configure_touch_sleep() {
    if ! $ENABLE_TOUCH_SLEEP; then
        print_warning "Touchscreen sleep hook disabled"
        track_skip_flag "touch sleep"
        return 0
    fi

    local src="$REPO_DIR/touchscreen"
    local f
    for f in hackberry-touch hackberry-touch-sleep hackberry-touch.service; do
        if [[ ! -f "$src/$f" ]]; then
            print_warning "Missing $src/$f, skipping touchscreen sleep hook"
            track_failure "touch sleep"
            return 1
        fi
    done

    print_status "Installing touchscreen sleep/wake hook..."
    local ok=true
    cp "$src/hackberry-touch" /usr/local/sbin/hackberry-touch \
        && chmod 755 /usr/local/sbin/hackberry-touch || ok=false
    mkdir -p /usr/lib/systemd/system-sleep || ok=false
    cp "$src/hackberry-touch-sleep" /usr/lib/systemd/system-sleep/hackberry-touch \
        && chmod 755 /usr/lib/systemd/system-sleep/hackberry-touch || ok=false
    cp "$src/hackberry-touch.service" /etc/systemd/system/hackberry-touch.service \
        && chmod 644 /etc/systemd/system/hackberry-touch.service || ok=false

    if $ok; then
        systemctl daemon-reload || true
        systemctl enable --now hackberry-touch.service \
            || { print_warning "Failed to enable hackberry-touch.service"; ok=false; }
    fi

    if $ok; then
        track_success
        return 0
    fi
    track_failure "touch sleep"
    return 1
}

# KDE Plasma tuning for low-power ARM hardware (applied for the invoking user)
configure_kde_optimization() {
    if ! $ENABLE_KDE_OPTIMIZATION; then
        print_warning "KDE optimization disabled"
        track_skip_flag "kde optimization"
        return 0
    fi

    if ! dpkg-query -W -f='${Status}' kali-desktop-kde 2>/dev/null | grep -q "ok installed"; then
        print_status "KDE not installed, skipping KDE optimization"
        track_skip "kde optimization"
        return 0
    fi

    local target_user="${SUDO_USER:-}"
    if $DRY_RUN && [[ -z "$target_user" ]]; then
        target_user="$(id -un)"
    fi
    if [[ -z "$target_user" || "$target_user" == "root" ]] || ! id "$target_user" &>/dev/null; then
        print_warning "No non-root invoking user (run via sudo); skipping per-user KDE settings"
        track_skip "kde optimization"
        return 0
    fi
    if ! command -v kwriteconfig6 &>/dev/null || ! command -v kreadconfig6 &>/dev/null; then
        print_warning "kwriteconfig6/kreadconfig6 not found, skipping KDE optimization"
        track_skip "kde optimization"
        return 0
    fi

    print_status "Applying KDE Plasma tuning for user $target_user..."
    local user_home
    user_home=$(getent passwd "$target_user" | cut -d: -f6)

    # kcfg <file> <key> <value> <group>...
    # Only sets keys the user has not already set, so re-runs never undo manual changes.
    kcfg() {
        local file="$1" key="$2" value="$3"; shift 3
        local args=() g cur
        for g in "$@"; do args+=(--group "$g"); done
        cur=$(sudo -H -u "$target_user" kreadconfig6 --file "$file" "${args[@]}" --key "$key" 2>/dev/null)
        if [[ -n "$cur" ]]; then
            if [[ "$cur" != "$value" ]]; then
                print_status "Keeping existing $file [$*] $key=$cur (script default: $value)"
            fi
            return 0
        fi
        sudo -H -u "$target_user" kwriteconfig6 --file "$file" "${args[@]}" --key "$key" "$value"
    }

    local failed=0
    {
        # Shorter animations: less GPU/CPU work and snappier feel
        kcfg kdeglobals AnimationDurationFactor 0.25 KDE
        # Keep the file indexer off (heavy on I/O and CPU)
        kcfg baloofilerc "Indexing-Enabled" false "Basic Settings"
        # Blur is costly on the Pi GPU
        kcfg kwinrc blurEnabled false Plugins
        # 720x720 screen: reclaim ~30px of height by hiding title bars on maximized windows
        # (close with Alt+F4 / Meta+Q or the task manager)
        kcfg kwinrc BorderlessMaximizedWindows true Windows
        # Auto-lock after 10 minutes
        kcfg kscreenlockerrc Autolock true Daemon
        kcfg kscreenlockerrc Timeout 10 Daemon
        # No splash screen (faster login, plain background instead)
        kcfg ksplashrc Engine none KSplash
        kcfg ksplashrc Theme None KSplash
        # Konsole: hide the menu bar (more rows on a square screen)
        kcfg konsolerc MenuBar Disabled MainWindow
    } || failed=1

    # Konsole profile sized so ~80 columns fit comfortably in 720px (only if no profile is set)
    local konsole_dir="$user_home/.local/share/konsole"
    local konsole_default
    konsole_default=$(sudo -H -u "$target_user" kreadconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile 2>/dev/null)
    if [[ -z "$konsole_default" && ! -e "$konsole_dir/HackBerry.profile" ]]; then
        sudo -H -u "$target_user" mkdir -p "$konsole_dir" || failed=1
        if sudo -H -u "$target_user" tee "$konsole_dir/HackBerry.profile" >/dev/null <<'EOF'
[Appearance]
Font=Monospace,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[General]
Name=HackBerry
Parent=FALLBACK/

[Scrolling]
HistorySize=5000
EOF
        then
            kcfg konsolerc DefaultProfile HackBerry.profile "Desktop Entry" || failed=1
        else
            failed=1
        fi
    fi

    # Hide background autostarts we don't need (user override with Hidden=true)
    local autostart_dir="$user_home/.config/autostart" app
    sudo -H -u "$target_user" mkdir -p "$autostart_dir" || failed=1
    for app in org.kde.discover.notifier org.kde.kdeconnect.daemon; do
        if [[ -e "/etc/xdg/autostart/$app.desktop" && ! -e "$autostart_dir/$app.desktop" ]]; then
            if ! sudo -H -u "$target_user" tee "$autostart_dir/$app.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=$app (disabled by hackberrypiq20setup)
Hidden=true
EOF
            then
                failed=1
            fi
        fi
    done

    unset -f kcfg
    if [[ $failed -eq 0 ]]; then
        print_status "KDE tuning applied (takes effect on next login)"
        track_success
        return 0
    fi
    print_warning "Some KDE settings failed to apply"
    track_failure "kde optimization"
    return 1
}

# Build (if needed), install and enable the custom kernel from kernel/
configure_custom_kernel() {
    if ! $ENABLE_CUSTOM_KERNEL; then
        track_skip_flag "custom kernel"
        return 0
    fi

    local kdir="$REPO_DIR/kernel"
    if [[ ! -x "$kdir/install.sh" || ! -x "$kdir/build.sh" ]]; then
        print_error "kernel/ build scripts not found in $REPO_DIR"
        track_failure "custom kernel"
        return 1
    fi

    local debs=("$kdir"/out/linux-image-*.deb)
    if [[ ! -e "${debs[0]}" ]]; then
        if $DRY_RUN; then
            dry_note "would run: kernel/build.sh --deps-only, then kernel/build.sh (no prebuilt packages in kernel/out)"
            dry_note "would run: kernel/install.sh --enable"
            track_success
            return 0
        fi
        print_warning "No prebuilt kernel in kernel/out; building on this device (30-45 min, needs ~10 GB)"
        local build_user="${SUDO_USER:-root}"
        # Dependencies as root, the build itself as the invoking user so kernel/ stays user-owned
        if ! "$kdir/build.sh" --deps-only || ! sudo -H -u "$build_user" "$kdir/build.sh"; then
            print_error "Kernel build failed"
            track_failure "custom kernel"
            return 1
        fi
    else
        print_status "Using prebuilt kernel packages from kernel/out"
    fi

    local args=(--enable)
    $DRY_RUN && args+=(--dry-run)
    if bash "$kdir/install.sh" "${args[@]}"; then
        print_status "Custom kernel installed; reboot to use it (rollback: kernel/install.sh --disable)"
        track_success
        return 0
    fi
    print_error "Custom kernel install failed"
    track_failure "custom kernel"
    return 1
}

# Main execution
main() {
    print_status "Starting HackBerry Pi CM5 Q20 Setup Script"
    
    # Parse and validate arguments
    parse_arguments "$@"
    validate_parameters

    # Check root privileges (not needed for a dry run, which changes nothing)
    if $DRY_RUN; then
        enable_dry_run
        print_warning "DRY RUN: nothing will be modified. Failures below can be artefacts of skipped steps."
    else
        check_root
    fi
    
    # Display configuration
    display_config
    echo ""
    
    # Scoped run: touchscreen hook only
    if $ONLY_TOUCH_SLEEP; then
        configure_touch_sleep || true
        print_summary
        [[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
    fi

    # Execute configuration tasks (continue even if some fail)
    configure_raspi_config || true
    configure_eeprom || true
    configure_cpu_governor || true
    configure_nvme_power || true
    configure_fstab || true
    configure_services || true
    configure_cloud_cleanup || true
    configure_device_tree || true
    configure_networking || true
    configure_xorg || true
    configure_greetd || true
    configure_brave || true
    configure_antigravity || true
    configure_kde_workaround || true
    configure_power_tuning || true
    configure_kde_optimization || true
    configure_touch_sleep || true
    configure_wifi || true
    configure_bluetooth || true
    configure_custom_kernel || true
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [[ $FAIL_COUNT -eq 0 ]]; then
        print_status "All configurations completed successfully!"
        exit 0
    else
        print_warning "Setup completed with $FAIL_COUNT failure(s)"
        exit 1
    fi
}

################################################################################
# Script Entry Point
################################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
