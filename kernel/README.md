# Custom kernel (Raspberry Pi 6.18 LTS, bcm2712, 16K pages)

Status: scaffolding. The nexmon patch compiles against 6.18; the full kernel has
not been built or booted on the device yet. Background and risks are in
[../KERNEL_PLAN.md](../KERNEL_PLAN.md).

## Layout

| Path | Purpose |
|---|---|
| `kernel.conf` | Pinned upstream repo, branch and commit, local version, boot directory name |
| `hackberry.config` | Config fragment merged onto `bcm2712_defconfig` (our deltas only) |
| `patches/` | Patches applied to the pinned tree, in filename order (currently the nexmon brcmfmac port) |
| `build.sh` | Fetch, patch, configure, build `.deb` packages into `out/` |
| `install.sh` | Install the packages, stage boot files, switch the bootloader, roll back |
| `build/`, `out/` | Generated; git-ignored |

## Fresh device

```bash
sudo ./hackberrypiq20setup.sh -K        # build if needed, install, enable
sudo reboot
bash ./hackberrypiq20verify.sh          # "Custom kernel" section
```

Preview first with `bash ./hackberrypiq20setup.sh -D -K`.

## Skip the build on a fresh device

Build once, then copy `kernel/out/` (the `.deb` files, `config-*`, `KERNEL_SHA`)
into the same path of the new checkout. `setup -K` and `install.sh` use whatever
is in `kernel/out/` and only build when it is empty.

## Build only

```bash
./kernel/build.sh --install-deps        # first time
./kernel/build.sh                       # first full build: 174 min on a CM5 (measured), ccache rebuilds are much faster
./kernel/build.sh --config-only         # check the merged config quickly
./kernel/build.sh --menuconfig          # tweak interactively
./kernel/build.sh --update              # build the current branch tip instead of the pin
```

The build refuses to continue if 16K pages are not enabled and warns when a
line in `hackberry.config` does not survive `olddefconfig`.

## Install and rollback

```bash
sudo ./kernel/install.sh                # install and stage only
sudo ./kernel/install.sh --enable       # also set os_prefix in config.txt
sudo ./kernel/install.sh --disable      # rollback to the stock kernel
```

How it stays safe:

- The release string is `<ver>-hackberry-2712` and deliberately has no `-rpi-`,
  so Debian's `z50-raspi-firmware` hook skips it and leaves
  `/boot/firmware/kernel_2712.img` (the stock kernel) alone.
- Everything for the new kernel goes into `/boot/firmware/hb618/` (kernel,
  initramfs, dtbs, overlays, `cmdline.txt`) and is selected by an `os_prefix=`
  block in `config.txt`, between `# hackberry-kernel-begin` and `-end` markers.
  `config.txt` is backed up once as `config.txt.pre-hb-kernel`.
- If a boot fails, mount the boot partition from another machine and delete the
  marked block, or remove it from the console with `install.sh --disable`.
- `brcmfmac-nexmon-dkms` is limited to 6.12 via `/etc/dkms/brcmfmac-nexmon.conf`
  so a DKMS copy cannot shadow the patched in-tree module.
- Re-run `install.sh` after changing `/boot/firmware/cmdline.txt` so the staged
  copy follows.

## Verified on the device (6.18.64-hackberry-2712)

- Boots through `os_prefix` with 16K pages; display, touch, keyboard, battery and
  WiFi come up; the `/etc/dkms/brcmfmac-nexmon.conf` override is honoured.
- Nexmon monitor mode: `mon0` comes up, `set channel` works and frames are
  captured (198 frames in one 12 s test) **only when `wlan0` is down**. With
  `wlan0` associated, bringing `mon0` up makes the firmware halt (about 130 ms
  after `SET_MONITOR 2`), and the driver reloads it. Power save was ruled out.
  Take `wlan0` down first (`nmcli dev set wlan0 managed no; ip link set wlan0 down`),
  as `airmon-ng start wlan0` does.
- The monitor vif is created with the legacy `bsscfg:ssid` method (see the patch).
  The fix is in `patches/0001-brcmfmac-nexmon.patch`; the installed packages in
  `kernel/out/` predate it until the kernel is rebuilt.

## Verified on 7.3.6 (rpi-7.3.y, 99dc5c58)

- Boots with 16K pages and the lean config; `check-hardware.sh` passes (all 70 modules
  the device uses are present); `CONFIG_LSM` now activates Landlock and Yama.
- `test-monitor.sh` passes with `wlan0` still associated (channel 4, 201 frames,
  beacons, radiotap). The firmware does not halt on 7.3, unlike on 6.18.
- Packet injection works: `aireplay-ng --test` gets 30/30 directed probe replies.
  Upstream's monitor netdev frees every transmitted frame; the patch now sends them
  through `brcmf_netdev_start_xmit`, as the 6.12 DKMS does. Before that change
  injection never reached the air on any kernel (0/30).
  Test it on a channel with an AP (`test-monitor.sh --inject 4`); DFS channels fail.
- Bluetooth audio: the BCM4345C0 firmware loads, the A2DP sink appears in PipeWire and a
  4 s test tone plays cleanly on a speaker. `bluetooth.service` is disabled by default;
  start it with `rfkill unblock bluetooth && systemctl start bluetooth`. A longer
  playback test (dropouts) has not been done.

## Not yet verified

- The battery driver under load, and suspend on 7.3.
- Whether the upstream `interface_create` path would also work with `wlan0` down
  (the legacy path is used regardless).
- Whether `hackberrypi-max17048` can be replaced by mainline `max17040_battery`.

## Lean profile (`build.sh --lean`)

`lean.config` turns off unused loadable modules (TV tuners except the RTL-SDR chain,
gspca webcams, camera sensors, other-board audio codecs and Pi audio HATs, IIO sensors,
`fbtft` displays, cluster/server and legacy/flash filesystems, PCIe-only WiFi and NICs,
software RAID, IPVS/batman/OVS/SCTP/L2TP, usbip). USB WiFi adapters, WireGuard,
netfilter, XFS, btrfs, NFS and SMB are kept. The kernel image is the full build's image
apart from a few small built-in sub-options that only existed for the removed modules
(`CLOSURES`, `PLDMFW`, `SND_SOC_COMPRESS`, `MD_BITMAP`, ...; listed in `allow-y-change`).
`build.sh --lean` refuses to build if any other built-in option would change or a
required driver (display, HDMI audio, Bluetooth, wireless, serial, CAN, battery, touch)
would be dropped.

Measured on the CM5: full build 173 min, lean rebuild 68 min with a warm `ccache`
(1,917 -> 1,555 modules, image deb 40 MB -> 37 MB).

`./kernel/check-hardware.sh` lists every module this device actually uses (loaded,
bound in sysfs, or matched by a device alias) and checks each against a package.
Run it while a full kernel is running, before installing a lean one.

### Restoring a module without rebuilding

A module from a full build loads into a lean image when its core matches (modules that
depend on the allow-listed sub-options, such as bcache, will be refused):

```bash
cd /tmp && dpkg-deb -x ~/path/to/kernel/build/baseline-full/linux-image-*.deb full
sudo install -D full/lib/modules/*/kernel/drivers/media/usb/gspca/gspca_main.ko.zst \
     /lib/modules/$(uname -r)/extra/gspca_main.ko.zst   # repeat for the module and its dependencies
sudo depmod -a && sudo modprobe gspca_main
```

A module built against a different core is refused with a version-mismatch error,
never loaded unsafely. Keep `kernel/build/baseline-full` (git-ignored) as the source.

## Updating the kernel

1. `./kernel/build.sh --update`, boot-test it.
2. Put the printed SHA in `kernel.conf`.
3. If a patch no longer applies, rebase it onto the new tree and replace the
   file in `patches/`.
