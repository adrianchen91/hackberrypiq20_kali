
## Raspberry Pi eeprom package workarounds

### Kali has no rpi-eeprom package; we can workaround this
sudo mkdir -p /opt/
cd /opt && sudo git clone https://github.com/raspberrypi/rpi-eeprom.git
# Link 2712 since we are cm5
sudo ln -s /opt/rpi-eeprom/firmware-2712 /usr/bin/firmware

sudo ln -s /opt/rpi-eeprom/rpi-eeprom-config /usr/bin/rpi-eeprom-config
sudo ln -s /opt/rpi-eeprom/rpi-eeprom-update /usr/bin/rpi-eeprom-update
sudo ln -s /opt/rpi-eeprom/rpi-eeprom-update-default /usr/bin/rpi-eeprom-update-default
sudo ln -s /opt/rpi-eeprom/rpi-eeprom-digest /usr/bin/rpi-eeprom-digest

cd /opt && sudo git clone https://github.com/RPi-Distro/raspi-config.git
sudo ln -s /opt/raspi-config/raspi-config /usr/bin/raspi-config

## NVMe Powersave Config
### Some inspirations are from https://github.com/quasialex/hackberrycm5

sudo sed -i "s/ds=nocloud cfg80211.ieee80211_regdom=AU/ds=nocloud pcie_aspm.policy=powersave cfg80211.ieee80211_regdom=AU/g

sudo apt install -y linux-cpupower
sudo tee /etc/systemd/system/cpufreq-tune.sesrvice >/dev/null <<'EOF'\n[Unit]\nDescription=Custom CPU frequency scaling with schedutil\nAfter=multi-user.target\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/cpupower frequency-set -g powersave\n\n[Install]\nWantedBy=multi-user.target\nEOF\n\nsudo systemctl enable --now cpufreq-tune.service
sudo apt install make linux-headers-rpi-2712

# Keep BlueZ off by default (you toggle from GUI when needed)
sudo systemctl disable --now bluetooth.service

# PackageKit (updates) off
sudo systemctl disable --now packagekit.service

# Keep wpa_supplicant by default (NetworkManager can start it)
sudo systemctl disable --now wpa_supplicant.service

# PHP’s session cleaner off (you said PHP stays, but not the timer)
sudo systemctl disable --now phpsessionclean.service phpsessionclean.timer

# ModemManager + colord weren’t needed
sudo systemctl disable --now ModemManager.service colord.service 2>/dev/null || true

# NetworkManager-wait-online causes long stalls (you saw ~1m); disable:
sudo systemctl disable --now NetworkManager-wait-online.service 2>/dev/null || true

# networking-wait-online causes long stalls (you saw ~1m); disable:
sudo systemctl disable --now networking-wait-online 2>/dev/null || true

## Ensure NetworkManager handles the networking
sudo tee /etc/netplan/50-cloud-init.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF

sudo netplan apply
sudo netplan generate

sudo tee /etc/X11/xorg.conf.d/10-dpi.conf >/dev/null <<'EOF'
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

sudo tee /etc/modprobe.d/nvme.conf >/dev/null <<'EOF'\noptions nvme_core default_ps_max_latency_us=5500\nEOF\nsudo update-initramfs -u

sudo systemctl enable --now greetd

sudo usermod -aG video _greetd

sudo usermod -aG render _greetd

sudo apt install -y kali-desktop-kde qt6-wayland xdg-desktop-portal xdg-desktop-portal-kde plasma-desktop plasma-workspace plasma-framework
powerdevil upower qt6-base-bin

sudo apt install greetd tuigreet

sudo update-alternatives --config x-session-manager

/boot/firmware/cmdline.txt

/boot/firmware/config.txt

/etc/greetd/config.toml
```
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
```

sudo apt install qml6-module-qtnetwork

sudo apt install qml6-module-org-kde-notifications

sudo apt purge --autoremove --allow-remove-essential kali-desktop-xfce

sudo mkdir -p /etc/apt/keyrings\ncurl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \\n  sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg\necho "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \\n  sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null

sudo apt update

sudo apt install antigravity



curl -L --output /usr/bin/rpi-eeprom-digest https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/master/rpi-eeprom-digest && sudo chmod +x /usr/bin/rpi-eeprom-digest

/usr/bin/rpi-eeprom-digest https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/master/rpi-eeprom-digest && sudo chmod +x /usr/bin/rpi-eeprom-digest

```
[Service]
Type = "idle"
StandardOutput = "tty"
# Without this errors will spam on screen
StandardError = "journal"
# Without these bootlogs will spam on screen
TTYReset = true
TTYVHangup = true
TTYVTDisallocate = true
```

DISPLAY=:0; xrandr --listmonitors

sudo apt install lm-sensor