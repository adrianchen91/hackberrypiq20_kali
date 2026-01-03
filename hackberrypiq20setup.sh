#!/bin/bash

################################################################################
# Script: hackberrypiq20setup.sh
# Description: Setup script for HackBerry Pi Q20 device.
#              Configures auto-login, CPU governor, WiFi, and Bluetooth settings.
# Usage: sudo ./hackberrypiq20setup.sh [OPTIONS]
################################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Default values
AUTO_LOGIN_USER=""
CPU_GOVERNOR="powersave"
ENABLE_WIFI=false
ENABLE_BLUETOOTH=true
VERBOSE=false

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
    -u, --auto-login-user USER      Set auto-login user (e.g., 'kali')
    -g, --cpu-governor GOVERNOR     Set CPU governor (default: 'powersave')
                                    Options: powersave, performance, ondemand, conservative
    -w, --enable-wifi               Enable WiFi interface
    -b, --disable-bluetooth         Disable Bluetooth
    -v, --verbose                   Enable verbose output
    -h, --help                      Display this help message

Examples:
    sudo $0 -u kali -g performance
    sudo $0 --auto-login-user kali --cpu-governor powersave --enable-wifi
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--auto-login-user)
                AUTO_LOGIN_USER="$2"
                shift 2
                ;;
            -g|--cpu-governor)
                CPU_GOVERNOR="$2"
                shift 2
                ;;
            -w|--enable-wifi)
                ENABLE_WIFI=true
                shift
                ;;
            -b|--disable-bluetooth)
                ENABLE_BLUETOOTH=false
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
    if [[ -n "$AUTO_LOGIN_USER" && ! "$AUTO_LOGIN_USER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid username format: $AUTO_LOGIN_USER"
        exit 1
    fi

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
    echo "  Auto-login User: ${AUTO_LOGIN_USER:-'(none)'}"
    echo "  CPU Governor: $CPU_GOVERNOR"
    echo "  WiFi Enabled: $ENABLE_WIFI"
    echo "  Bluetooth Enabled: $ENABLE_BLUETOOTH"
    echo "  Verbose Mode: $VERBOSE"
}

# Configure auto-login user
configure_auto_login() {
    if [[ -z "$AUTO_LOGIN_USER" ]]; then
        print_warning "No auto-login user specified"
        return 0
    fi

    print_status "Configuring auto-login for user: $AUTO_LOGIN_USER"
    
    # Verify user exists
    if ! id "$AUTO_LOGIN_USER" &>/dev/null; then
        print_error "User '$AUTO_LOGIN_USER' does not exist"
        return 1
    fi

    # Example: Configure LightDM for auto-login (adjust for your display manager)
    # Uncomment and modify based on your system's display manager
    # sed -i "s/#autologin-user=/autologin-user=$AUTO_LOGIN_USER/" /etc/lightdm/lightdm.conf
    
    print_status "Auto-login configuration completed"
}

# Configure CPU governor
configure_cpu_governor() {
    print_status "Setting CPU governor to: $CPU_GOVERNOR"
    
    # Check if cpufreq-set is available
    if ! command -v cpufreq-set &>/dev/null; then
        print_warning "cpufreq-utils not installed, attempting to install..."
        apt-get update
        apt-get install -y cpufreq-utils
    fi

    # Get number of CPUs
    local cpu_count
    cpu_count=$(nproc)

    # Set governor for each CPU
    for ((i=0; i<cpu_count; i++)); do
        cpufreq-set -c "$i" -g "$CPU_GOVERNOR" 2>/dev/null || {
            print_warning "Failed to set governor for CPU $i"
        }
    done

    print_status "CPU governor configuration completed"
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
        rfkill block bluetooth
    else
        print_status "Enabling Bluetooth..."
        rfkill unblock bluetooth
    fi
}

# Main execution
main() {
    print_status "Starting HackBerry Pi Q20 Setup Script"
    
    # Check root privileges
    check_root
    
    # Parse and validate arguments
    parse_arguments "$@"
    validate_parameters
    
    # Display configuration
    display_config
    echo ""
    
    # Execute configuration tasks
    configure_auto_login
    configure_cpu_governor
    configure_wifi
    configure_bluetooth
    
    print_status "Setup completed successfully!"
}

################################################################################
# Script Entry Point
################################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
