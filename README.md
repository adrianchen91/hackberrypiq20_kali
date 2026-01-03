# Optimisations for Hackberry Pi CM5 Q20

This repository contains optimizations, configurations, and setup utilities for the [HackBerry Pi CM5 Q20](https://github.com/ZitaoTech/HackberryPiCM5) device running Kali Linux. The HackBerry Pi is a portable penetration testing device that combines the Compute Module 5 (CM5) with multiple display options and integrated peripherals.

## Quick Start with Setup Script

The `hackberrypiq20setup.sh` script automates many of these optimizations. It's designed to work gracefully, continuing even if some optional components fail.

**Basic usage:**
```bash
sudo ./hackberrypiq20setup.sh
```

**With options:**
```bash
# Enable fstab optimization and auto-login
sudo ./hackberrypiq20setup.sh -f -u kali

# Set custom CPU governor to performance mode
sudo ./hackberrypiq20setup.sh -g performance

# Install optional greetd display manager
sudo ./hackberrypiq20setup.sh -d

# View all options
sudo ./hackberrypiq20setup.sh -h
```

**Enabled by default** (can be disabled with flags):
- raspi-config installation
- rpi-eeprom setup
- Service optimization
- Power management (NVMe, CPU governor)
- Networking optimization (NetworkManager + netplan)
- Xorg display configuration

**Disabled by default** (can be enabled with flags):
- Fstab noatime optimization (`-f`)
- Greetd display manager (`-d`)
- Device tree compilation (`-t`)
- Auto-login configuration (`-u`)

---

## Manual Configuration Sections

Below are the detailed manual steps for each optimization. Most are automated in the setup script.

## Raspberry Pi config package workarounds

Kali only has `kalipi-config` which is lacking compared to the official Raspberry Pi version. This installs the official `raspi-config` utility which provides better hardware configuration options.

**What this does:**
- Installs the official RPi config tool from the Debian trixie branch
- Provides access to hardware settings like GPU memory, camera enable/disable, etc.
- Automatically handled by setup script

```
sudo mkdir -p /opt/
cd /opt && sudo git clone https://github.com/RPi-Distro/raspi-config.git
cd /opt/raspi-config && git checkout trixie
sudo ln -s /opt/raspi-config/raspi-config /usr/bin/raspi-config
```

## Raspberry Pi eeprom package workarounds

Kali has no rpi-eeprom package in its repositories. The eeprom utilities are essential for updating firmware and managing the bootloader on the Raspberry Pi compute modules.

**What this does:**
- Clones the official Raspberry Pi eeprom repository
- Links the CM5-specific firmware (firmware-2712) for use on this device
- Provides tools like `rpi-eeprom-update` for firmware management
- Handles bootloader and EEPROM configuration
- Automatically handled by setup script

```
sudo mkdir -p /opt/
cd /opt && sudo git clone https://github.com/raspberrypi/rpi-eeprom.git
# Link 2712 since we are cm5
sudo ln -s /opt/rpi-eeprom/firmware-2712 /usr/bin/firmware

sudo ln -s /opt/rpi-eeprom/rpi-eeprom-config /usr/bin/rpi-eeprom-config
sudo ln -s /opt/rpi-eeprom/rpi-eeprom-update /usr/bin/rpi-eeprom-update
sudo ln -s /opt/rpi-eeprom/rpi-eeprom-update-default /usr/bin/rpi-eeprom-update-default
sudo ln -s /opt/rpi-eeprom/rpi-eeprom-digest /usr/bin/rpi-eeprom-digest
```

## Display and Battery Device Tree

The HackBerry Pi CM5 Q20 has custom hardware (display controllers, battery management, keyboard) that requires device tree overlays to function correctly. This step compiles and installs the HackBerry-specific device tree.

**What this does:**
- Compiles the custom device tree blob (`.dtbo` file) for HackBerry hardware
- Enables proper support for the display outputs (HDMI and LCD)
- Enables battery charging and monitoring
- Only runs if the file `/boot/firmware/overlays/hackberrypicm5.dtbo` is not already present
- **Requires system reboot** after installation
- Automatically handled by setup script with `-t` flag (optional)
```
cd /opt && sudo git clone https://github.com/adrianchen91/hackberrypiq20
cd /opt/hackberrypiq20 && git checkout ac-module-rework

sudo apt install -y make linux-headers-rpi-2712
make && sudo make install
sudo reboot
```

## Disk Write Reduction

The `noatime` mount option reduces write operations to the storage device by not updating the access time metadata. This is particularly beneficial for NVMe SSDs as it reduces unnecessary wear and improves performance.

**Why this matters:**
- Every file read normally updates the "accessed time" in the filesystem, causing a write
- On SSDs, this increases wear and slightly reduces performance
- `noatime` disables this, reducing write amplification
- System still tracks modification and change times (`mtime` and `ctime`)
- Minimal impact on functionality - most applications don't rely on access times

**Implementation:**
Update your root mount point to include `noatime` in `/etc/fstab`. Perform a backup first.

For example below where the ROOT-UUID is from `blkid`:

```
UUID=<YOUR-ROOT-UUID>  /  ext4  defaults,noatime,errors=remount-ro  0 1
```

The setup script can apply this automatically with the `-f` flag:
```bash
sudo ./hackberrypiq20setup.sh -f
```

## NVMe Powersave Config

NVMe SSDs can enter power-saving states to reduce power consumption. This configuration enables ASPM (Active State Power Management) and sets NVMe to use low-power states when idle.

**Inspiration:** https://github.com/quasialex/hackberrycm5

**What this does:**
- **PCIe ASPM (L1.2 states):** Reduces PCIe link power when device is idle
- **NVMe power states:** Allows NVMe controller to enter lower power modes
- **fstrim:** Automatically trims free space blocks, improving SSD longevity and performance
- Automatically enabled by setup script

**Performance impact:** Negligible (< 1% in most workloads). Power savings can be 10-30% when idle.

**Manual steps:**```
sudo sed -i "s/ds=nocloud cfg80211.ieee80211_regdom=AU/ds=nocloud pcie_aspm.policy=powersave cfg80211.ieee80211_regdom=AU/g" /boot/firmware/cmdline.txt

sudo tee /etc/modprobe.d/nvme.conf >/dev/null <<'EOF'
options nvme_core default_ps_max_latency_us=5500
EOF
sudo update-initramfs -u

sudo systemctl enable --now fstrim.timer
```

## CPU Governor Optimisation

The CPU governor controls CPU frequency scaling. Different governors provide different tradeoffs between power consumption and performance.

**Available governors:**
- **powersave:** Runs CPU at lowest frequency to minimize power, prioritizes battery life
- **performance:** Runs CPU at maximum frequency for maximum performance
- **ondemand:** Dynamically scales based on demand
- **conservative:** Like ondemand but more gradual
- **schedutil:** Uses kernel scheduler information (modern, usually best)

**Default:** Powersave (optimal for battery-powered penetration testing device)

**What this does:**
- Installs `linux-cpupower` for CPU frequency management
- Creates a systemd service that applies the governor at boot
- Allows you to specify governor via command line: `sudo ./hackberrypiq20setup.sh -g performance`
- Automatically handled by setup script

**Manual configuration:**
```
sudo apt install -y linux-cpupower
sudo tee /etc/systemd/system/cpufreq-tune.sesrvice >/dev/null <<'EOF'
[Unit]
Description=Custom CPU frequency scaling with schedutil
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g powersave

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now cpufreq-tune.service
```

## Service Optimisation

Kali Linux includes many services that aren't necessary for a portable penetration testing device. Disabling unused services reduces boot time, improves responsiveness, and reduces power consumption.

**Services disabled and why:**

| Service | Purpose | Why disabled |
|---------|---------|-------------|
| `bluetooth.service` | Bluetooth daemon | Can be toggled from GUI when needed; disabled by default for security |
| `packagekit.service` | Automatic updates | Manual update control preferred; reduces background load |
| `wpa_supplicant.service` | WiFi supplicant | NetworkManager will start it if needed |
| `phpsessionclean.*` | PHP session cleanup | Unnecessary if PHP isn't being used as a service |
| `ModemManager.service` | Modem management | Not needed for this device |
| `colord.service` | Color management | Minimal benefit on a CLI-focused penetration testing tool |
| `NetworkManager-wait-online.service` | Network wait timeout | Causes ~1 minute boot delay waiting for network |
| `networking-wait-online.service` | Old networking wait | Deprecated, causes boot delays |

**Result:** Faster boot times and reduced background processes

**Manually applied:**
# Keep BlueZ off by default (you toggle from GUI when needed)
sudo systemctl disable --now bluetooth.service 2>/dev/null || true

# PackageKit (updates) off
sudo systemctl disable --now packagekit.service 2>/dev/null || true

# Keep wpa_supplicant by default (NetworkManager can start it)
sudo systemctl disable --now wpa_supplicant.service 2>/dev/null || true

# PHP’s session cleaner off (you said PHP stays, but not the timer)
sudo systemctl disable --now phpsessionclean.service phpsessionclean.timer 2>/dev/null || true

# ModemManager + colord weren’t needed
sudo systemctl disable --now ModemManager.service colord.service 2>/dev/null || true

# NetworkManager-wait-online causes long stalls (you saw ~1m); disable:
sudo systemctl disable --now NetworkManager-wait-online.service 2>/dev/null || true

# networking-wait-online causes long stalls (you saw ~1m); disable:
sudo systemctl disable --now networking-wait-online 2>/dev/null || true
```

## Networking Optimisation: NetworkManager + Netplan

Modern Linux systems are moving away from traditional networking toward netplan + NetworkManager. This provides better wireless management, VPN support, and dynamic configuration.

**What this does:**
- Configures netplan to use NetworkManager as the rendering backend
- Disables the old `networking.service` 
- Ensures NetworkManager is enabled and running
- Provides a unified interface for WiFi, Ethernet, VPN, and other network connections
- Supports connection profiles, automatic reconnection, and better CLI tools

**Why NetworkManager:**
- Better WiFi management (critical for penetration testing)
- VPN support without systemd-networkd complexity
- nmcli command-line tool for scripting
- GNOME/KDE integration
- Automatic reconnection with backoff

**Automatically handled by setup script** (enabled by default, can disable with `-n`)

**Manual configuration:**
## Ensure NetworkManager handles the networking
sudo tee /etc/netplan/50-cloud-init.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF

sudo netplan apply
sudo netplan generate

sudo systemctl disable --now networking 2>/dev/null || true

sudo systemctl enable --now NetworkManager
```

## Display Configuration for HackBerry Pi CM5 Q20

The HackBerry Pi CM5 Q20 has 6 potential display outputs:
- 2× HDMI ports (both can be used simultaneously)
- 1× LCD panel (DPI-1 or DPI-1-1 depending on driver version)

This Xorg configuration ensures all display outputs are detected correctly and the LCD is set as the primary display.

**What this does:**
- Marks both HDMI outputs as non-primary (allows secondary displays)
- Marks the LCD panel as primary (your main display)
- Prevents X11 from getting confused about which display is which
- Automatically handled by setup script (enabled by default, can disable with `-x`)

**Note:** X11 only allows ONE primary display. The LCD is set as primary since it's the integrated display.

**Configuration:**
sudo tee /etc/X11/xorg.conf.d/10-hackberry-display.conf >/dev/null <<'EOF'
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

```

## Display Manager: Greetd (Optional)

The default Kali display manager may not work well with the HackBerry's custom keyboard and hardware. Greetd with tuigreet provides a lightweight, keyboard-friendly login interface.

**What this does:**
- Replaces the default display manager with greetd
- Uses tuigreet for a terminal-based login interface
- Configures keyboard hotkeys to match HackBerry's keyboard layer 2:
  - F12 (or Fn+Power): Power off
  - F1 (or Fn+Cmd): Execute arbitrary command
  - F5 (or Fn+Session): Switch sessions
- Supports auto-login (optional, disabled by default)

**Enable with:**
```bash
sudo ./hackberrypiq20setup.sh -d
```

**Manual setup:**
sudo apt install -y greetd tuigreet

sudo usermod -aG video _greetd

sudo usermod -aG render _greetd

sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
# The VT to run the greeter on. Can be "next", "current" or a number
# designating the VT.
vt = 7

# The default session, also known as the greeter.
[default_session]

# `agreety` is the bundled agetty/login-lookalike. You can replace `/bin/sh`
# with whatever you want started, such as `sway`.
#command = "/usr/sbin/agreety --cmd '${SHELL:-/bin/sh}'"
# Customise the command and session hot keys to F1 and F5 to align with default Hackberry Pi CM5 keyboard layer 2
command = "tuigreet --time --asterisks --remember-session --kb-power 12 --kb-command 1 --kb-sessions 5 --cmd '${SHELL:-/bin/sh}'"
# if using wlgreet
#command = "sway --config /etc/greetd/sway-config"

# The user to run the command as. The privileges this user must have depends
# on the greeter. A graphical greeter may for example require the user to be
# in the `video` group.
user = "_greetd"
EOF

sudo apt update
sudo apt install -y kali-desktop-kde qt6-wayland xdg-desktop-portal xdg-desktop-portal-kde plasma-desktop plasma-workspace plasma-framework powerdevil upower qt6-base-bin qml6-module-qtnetwork qml6-module-org-kde-notifications
```

**Remove XFCE (optional):**
```bash
# Caution: This removes XFCE. Make sure you're happy with KDE first!
sudo apt purge --autoremove --allow-remove-essential kali-desktop-xfce
```

---

## Optional - Install Antigravity

Antigravity is an automated penetration testing framework. Add their repository for regular updates:

```bash
sudo apt update
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null
sudo apt install antigravity
```

---

## Optional - Install Brave Browser

Brave is a privacy-focused browser based on Chromium. It blocks ads and trackers by default:

```bash
sudo apt install curl
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
sudo apt update
sudo apt install brave-browser
```

---

## Troubleshooting

**Q: Boot is still slow**
- Check `systemd-analyze blame` to see what's taking time
- Some services may be waiting for network/USB devices
- You may need to disable additional services based on your use case

**Q: HDMI displays don't work**
- Compile device tree with `-t` flag
- Verify both HDMI ports are inserted fully
- Check `xrandr` output for detected displays

**Q: WiFi isn't connecting**
- Ensure NetworkManager is running: `systemctl status NetworkManager`
- Use `nmcli` to debug: `nmcli device wifi list`
- Check logs: `journalctl -u NetworkManager`

**Q: Script failed on some step**
- Read the error message carefully
- Most failures are non-critical (optional features)
- Script continues and provides summary at end
- Check exit code: `echo $?` (0 = all OK, 1 = some failures)

---

## Related Projects

- [HackBerry Pi CM5](https://github.com/ZitaoTech/HackberryPiCM5) - Main HackBerry project
- [RPi-Distro/raspi-config](https://github.com/RPi-Distro/raspi-config) - Official Raspberry Pi configuration tool
- [RPi-Distro/rpi-eeprom](https://github.com/raspberrypi/rpi-eeprom) - Raspberry Pi firmware tools
- [Inspirations from hackberrycm5 optimizations](https://github.com/quasialex/hackberrycm5)
