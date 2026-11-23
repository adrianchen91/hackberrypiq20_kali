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
./kernel/build.sh                       # 25-45 min on a CM5 (estimate)
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

## Unverified until first boot

- `os_prefix` handling of overlays and `auto_initramfs` on the CM5 bootloader.
- Whether the `dtoverlay=hackberrypicm5` overlay and the `hackberrypi-max17048`
  DKMS module work on 6.18 (mainline `max17040_battery` supports MAX17048 and may
  replace the DKMS module).
- The `/etc/dkms/brcmfmac-nexmon.conf` override being honoured.
- Nexmon monitor mode and injection at runtime.

## Updating the kernel

1. `./kernel/build.sh --update`, boot-test it.
2. Put the printed SHA in `kernel.conf`.
3. If a patch no longer applies, rebase it onto the new tree and replace the
   file in `patches/`.
