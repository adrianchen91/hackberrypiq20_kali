# Kernel uplift plan: Raspberry Pi 6.12 -> 6.18 LTS (bcm2712) for HackBerry Pi CM5 Q20

Status: plan only, nothing implemented. Facts below were checked on 2026-11-23.

## Baseline

| Item | Today | Target |
|---|---|---|
| Kernel | `6.12.34+rpt-rpi-2712` (Raspberry Pi OS packaged, 16K pages) | `6.18.x` from `raspberrypi/linux` branch `rpi-6.18.y` |
| Upstream | 6.12 LTS | 6.18 LTS (kernel.org shows 6.18.64 longterm; `rpi-6.18.y` Makefile is at 6.18.64, tip `a40f73532`, 2026-11-20) |
| Config base | packaged `bcm2712_defconfig` | `arch/arm64/configs/bcm2712_defconfig` on `rpi-6.18.y` |
| Out-of-tree | `hackberrypi-max17048` (DKMS-style, `/usr/src`), `brcmfmac-nexmon-6.12.2` | see Phase 3 |

Other branches exist (`rpi-6.19.y` and `rpi-7.0.y` to `rpi-7.4.y`), but 6.18 is the only LTS among them, so it is the right pick for a long-lived device. Raspberry Pi tags firmware drops as `stable_YYYYMMDD` (latest `stable_20261103`); use it for the matching `/boot/firmware` blobs.

## Phase 0: Safety net (do first)

1. Keep the packaged 6.12 kernel installed and bootable. Never remove `linux-image-*-rpi-2712`.
2. Use a separate `kernel=` entry so the custom kernel is selectable and revertible from `config.txt`:
   - Install as `/boot/firmware/kernel_2712_618.img`, DTBs in `/boot/firmware/` (or an `os_prefix`-style subdir), then `kernel=kernel_2712_618.img` in an `[all]` block.
   - Rollback = delete one line (or edit config.txt from another machine).
3. Back up `/boot/firmware` and `/lib/modules`. Know how to mount the NVMe/SD from another host.
4. Build on a fast machine (cross-compile `aarch64-linux-gnu-`) or on the CM5 itself using `ccache`. A native CM5 build takes roughly 40-60 min with a trimmed config.

## Phase 1: Build baseline (no custom changes yet)

1. `git clone --depth=1 -b rpi-6.18.y https://github.com/raspberrypi/linux` (pin the commit SHA in the repo).
2. `make bcm2712_defconfig`, set `CONFIG_LOCALVERSION="-hackberry-2712"` (keep 16K pages: `ARM64_16K_PAGES=y`, `-v8-16k` upstream default; do not switch to 4K because Kali userland, and some prebuilt tooling, were validated on 16K here, and 4K costs Pi 5 performance).
3. Package with `make bindeb-pkg` (produces `linux-image`, `linux-headers`) so dpkg owns it, `apt` can remove it, and the existing headers-based Makefile in `hackberrypiq20` keeps working. Include DTBs and overlays via a small post-install hook (bindeb-pkg does not install to `/boot/firmware` by itself).
4. Boot-test unchanged first. Success criteria: boots, NVMe, WiFi/BT, USB, HDMI/DPI display, touch, keyboard, battery, suspend if used.

## Phase 2: HackBerry-specific hardware

Findings from the 6.18 tree:

- **Battery fuel gauge**: mainline `drivers/power/supply/max17040_battery.c` already supports `maxim,max17048` (`CONFIG_BATTERY_MAX17040=m` is in the defconfig). The out-of-tree `hackberrypi-max17048` module can probably be dropped. Action: change the compatible in `hackberrypicm5.dts` from `hackberrypi,max17048-battery` to `maxim,max17048`, test `/sys/class/power_supply/`, then retire the DKMS package. If the custom driver exposes something mainline does not, keep it and rebuild against 6.18 headers (watch for `power_supply` API changes between 6.12 and 6.18).
- **Display**: overlay uses `panel-dpi` + `dpi` pinctrl (`dpi_18bit_cpadhi_gpio0`) on `rp1_gpio`. Re-compile the overlay against 6.18 DT includes and check `vc4-kms-dpi` behaviour; DRM panel and vc4 changed a fair amount across 6.13-6.18.
- **Touch**: `edt-ft5406` via `CONFIG_TOUCHSCREEN_EDT_FT5X06=m`, in the defconfig already.
- **Upstream the overlay**: carry `hackberrypicm5.dts` in-tree as `arch/arm64/boot/dts/overlays/hackberrypicm5-overlay.dts` in a local patch set (`patches/` dir in this repo), so it builds and installs with the kernel instead of the separate `make && make install` flow. Optionally propose it to `raspberrypi/linux` as a PR.
- Add the `-t` path of `hackberrypiq20setup.sh` equivalent: skip the DT build if the installed kernel package already ships the overlay.

## Phase 3: Pentest-specific (the biggest risk)

1. **Nexmon / brcmfmac monitor mode and injection** (checked 2026-11-23): feasible, not a blocker, but needs a real forward-port.
   - Upstream `seemoo-lab/nexmon` only ships driver patches up to `brcmfmac_6.6.y-nexmon`. The installed `brcmfmac-nexmon-dkms 6.12.2` is Kali's port, built from an older base (it lacks `acpi.c`, `cyw/`, `bca/`, `fwvid.c` that 6.12 has), so it cannot be dropped into 6.18 as-is.
   - The nexmon delta is small and marked: about 14 hunks across `cfg80211.c`, `core.c`, `common.c` plus the new `nexmon_ioctls.h` (netlink ioctl handler, firmware-side monitor vif, `set_monitor_channel`). Kali already handles the 6.13+ `set_monitor_channel(wiphy, net_device, chandef)` signature.
   - Test-apply of those hunks onto `rpi-6.18.y`: 12 of 14 apply cleanly (with offsets), 2 fail: (a) the replacement of `brcmf_mon_add_vif()` (nexmon creates the monitor interface in firmware; 6.18 has a different upstream implementation using `pub->mon_if`), and (b) the `cfg80211_ops` table hunk. These two need hand-porting, roughly 100 lines, then an on-device test of monitor mode, channel set, injection, and `nexutil`.
   - Plan: carry the result as `kernel/patches/0001-brcmfmac-nexmon.patch` built into the kernel package. **Remove `brcmfmac-nexmon-dkms`** on 6.18 (DKMS installs to `/updates`, which would shadow the in-tree module). Keep `firmware-nexmon` (userspace firmware blob, kernel independent).
   - **Done:** the forward-port is in `kernel/patches/0001-brcmfmac-nexmon.patch` (base `rpi-6.18.y` `a40f73532`). It compiles cleanly against 6.18 with `bcm2712_defconfig` (`brcmfmac.ko` built, no warnings or errors from the touched files). The two failed hunks became: a firmware-created monitor vif (`brcmf_mon_add_vif`, with upstream's software version kept under `#else`), `del_iface` routing monitor through the apsta delete path, and the `set_monitor_channel` ops entry.
   - Not yet verified: runtime behaviour on the CM5, and the nexmon firmware (`firmware-nexmon 0.2`) working with the 6.18 driver on the CM5's CYW43455. Treat onboard monitor mode as "likely, confirm on hardware"; keep the USB adapter fallback.
2. Out-of-tree injection drivers Kali users commonly need (`rtl8812au`, `rtl88xxau`, `8814au`) are partly obsoleted by in-tree `RTW88_8812AU/8814AU/8821AU`. Test injection (`aireplay-ng --test`) on in-tree before carrying DKMS builds.
3. Confirm `CONFIG_MAC80211`/`CFG80211` allow monitor + injection, and keep `CONFIG_CFG80211_CERTIFICATION_ONUS=y` plus `CONFIG_CFG80211_REG_RELAX_NO_IR=y` for channel/regdomain flexibility (defconfig default may be stricter).
4. Verify tooling kernel features: `CONFIG_BPF_SYSCALL`, `CONFIG_TUN`, `CONFIG_WIREGUARD`, `CONFIG_NETFILTER_XT_*`, `CONFIG_USB_GADGET` plus configfs/`dwc2`/RP1 USB device mode (for HID/ethernet gadget use), `CONFIG_BT_HCIBTUSB`.

## Phase 4: Improvements that justify a custom kernel

Ordered by value for a battery-powered handheld.

Power and battery
- Keep `CONFIG_PREEMPT=y` (upstream default) but consider `PREEMPT_DYNAMIC` (boot-selectable `preempt=voluntary`) so one image serves both.
- `CONFIG_HZ=100` or `250` with `NO_HZ_IDLE` (check that the Pi default 250/300 is not forcing extra wakeups); `CONFIG_RCU_NOCB_CPU` off unless needed.
- `CPU_FREQ_DEFAULT_GOV_SCHEDUTIL` (defconfig defaults to `ONDEMAND`); `schedutil` plus EAS-less 4x A76 is smoother and cheaper at idle. Matches the existing `-g` governor flag in the setup script.
- Keep PCIe ASPM available (`PCIEASPM_POWERSAVE`) so `pcie_aspm.policy=powersave` is a default instead of a cmdline param; build NVMe in with a sane default `nvme_core.default_ps_max_latency_us` (kernel param is still needed since it is a core param, keep the existing script logic).
- Disable unused hardware that wakes or costs RAM: other SBC overlays/DRM panels (`DRM_PANEL_*` except `SIMPLE`, `LVDS`), Pi DSI touchscreens, camera ISP/CSI if no camera, `VIDEO_*` stacks, sound cards not used, `CAN`, `IIO` sensors, `NFC`, `INFINIBAND`.

Performance and size
- `CONFIG_ZSWAP_DEFAULT_ON=y` with `zstd` + `zsmalloc`, `ZRAM` available; shrinks swap I/O on NVMe.
- Compile with `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE`, and optionally `-mcpu=cortex-a76` via `KCFLAGS` (CM5 is Cortex-A76 only). Test for stability; gain is small.
- `CONFIG_LTO_CLANG_THIN` is optional and slow; skip unless builds are on a fast host.
- Module compression `ZSTD` instead of `XZ` (faster boot/module load, bigger on disk by a little). Kernel image `Image` (Pi bootloader loads uncompressed or gzip).
- BBR + `fq` as defaults (`TCP_CONG_BBR=m` already; make `DEFAULT_TCP_CONG=bbr`, `DEFAULT_NET_SCH=fq`).

Security and hardening (relevant for a pentest device that carries credentials)
- Merge `arch/arm64/configs/hardening.config` (present in 6.18) with `scripts/kconfig/merge_config.sh`, then relax what breaks tooling: keep `DEVMEM`/`/dev/mem` policy as needed for GPIO tools, keep `BPF_UNPRIV_DEFAULT_OFF`, keep module loading (no lockdown) so DKMS USB WiFi drivers still load.
- Enable `SECURITY_LANDLOCK`, `SECURITY_YAMA`, `RANDOMIZE_KSTACK_OFFSET_DEFAULT`, `INIT_ON_ALLOC_DEFAULT_ON`. Check Kali's AppArmor assumption (`SECURITY_APPARMOR=y` is already in defconfig).
- Do not enable module signature enforcement unless you also sign DKMS output.

Features available only (or better) in 6.18 vs 6.12
- Newer scheduler and EEVDF tuning, `sched_ext` (`CONFIG_SCHED_CLASS_EXT`, optional), improved `io_uring`, `zswap` improvements, newer `rtw89`/`mt76`/`brcmfmac` drivers, RP1/`pinctrl-rp1`, `bcm2712` clk/power fixes. Worth a quick review of the Raspberry Pi 6.18 release notes before building.
- Rust is not needed; leave off.

Debug
- Disable heavy debug (`DEBUG_INFO` off or `DEBUG_INFO_REDUCED`, `SCHED_TRACER` off) to cut build size and time. Keep `FTRACE`/`KPROBES` if you use perf.

## Phase 5: Integrate into this repo

Status: scaffolded in `kernel/` (see `kernel/README.md`): `build.sh`, `install.sh`, `kernel.conf`, `hackberry.config`, `-K` in the setup script and a verify section. The config fragment was checked against 6.18 (no drift); the full build, install and boot are untested. The notes below are the original design.

Build time on the CM5 (4x Cortex-A76 at 2.4 GHz, 16 GB RAM): measured 174 minutes for the first full `bcm2712_defconfig` build at `-j4` (about 9,500 objects, 1,922 modules, 40 MB image deb). The earlier 25-45 minute estimate was wrong. A lean profile that drops unused DVB/webcam/NIC/filesystem drivers would cut this substantially; `ccache` makes rebuilds after small changes fast. Needs about 10 GB free disk and runs hot.

Deployment without publishing packages: the repo carries the recipe (pinned SHA, config fragment, patches) and the setup script gets a `-K` mode that (1) installs build deps, (2) reuses `kernel/out/*.deb` if present, otherwise builds on-device, (3) installs the debs, copies DTBs/overlays, sets `kernel=` in `config.txt`, removes the nexmon/battery DKMS packages that the kernel now replaces, and (4) leaves 6.12 as a fallback entry. Copying a prebuilt `kernel/out/` from another machine to a fresh CM5 skips the build entirely.

1. `kernel/` directory: `build.sh` (clone pinned SHA, apply `patches/*.patch`, merge `hackberry.fragment` onto `bcm2712_defconfig`, `bindeb-pkg`), `hackberry.config` fragment holding only our deltas (small, reviewable), `patches/` (overlay DTS, nexmon port if any).
2. `hackberrypiq20setup.sh`: add a `-K` flag (default off) to install the custom kernel `.deb`, write the `kernel=` line in `config.txt`, and keep the existing cmdline logic. Respect `--dry-run`.
3. `hackberrypiq20verify.sh`: add checks for running kernel version, `/proc/config.gz` or `/boot/config-*` markers, overlay loaded, battery power_supply present, WiFi monitor capability.
4. README section covering build, install, rollback, and upgrade cadence.
5. CI (optional): GitHub Actions cross-build on `ubuntu-24.04-arm` to catch breakage against new `rpi-6.18.y` tips; publish `.deb` as release assets.

## Phase 6: Validation checklist

- Boots 3 times cold, once with battery only; `dmesg` clean of new errors/warnings (`dmesg -l err,warn`).
- NVMe speed and idle power draw compared with 6.12 (`fio`, plus a battery drain test of 30 min idle).
- Display (DPI) at native resolution with touch; HDMI hotplug; backlight/brightness.
- Keyboard (Q20), battery percentage and charging status.
- WiFi/BT onboard and USB adapters; monitor mode and injection tests.
- Suspend/resume if used; `vcgencmd`/thermal and throttling checks under `stress-ng`.
- Kali tools smoke test (aircrack-ng, nmap, bettercap, Wireshark capture, Metasploit start).

## Maintenance

- Track `rpi-6.18.y` monthly (stable point releases land often); rebuild and rerun Phase 6 subset. 6.18 is LTS so this branch will be supported for years; revisit around the next LTS.
- Keep `/boot/firmware` blobs (`start*.elf`, `fixup*.dat`, bootloader EEPROM via `rpi-eeprom`) in sync with the `stable_*` tag used for the kernel.

## Open questions / risks (decide before starting)

Decided: keep 16K pages; no published `.deb` releases (local build + deploy tooling instead, see Phase 5).
Still open: finish the nexmon forward-port and confirm it on hardware; decide native versus remote build after measuring the first on-device build.
