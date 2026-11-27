#!/bin/bash
################################################################################
# Script: kernel/build.sh
# Description: Build the HackBerry custom kernel (Raspberry Pi rpi-7.3.y,
#              bcm2712, 16K pages) into installable .deb packages in kernel/out/.
#              Runs natively on the CM5 or on any arm64 Debian host. Needs no
#              root unless --install-deps is given.
# Usage: ./kernel/build.sh [--install-deps] [--jobs N] [--config-only]
#                          [--menuconfig] [--update] [--clean]
#   --install-deps  apt-get install the build dependencies (uses sudo)
#   --deps-only     install the build dependencies and exit
#   --jobs N        parallel jobs (default: nproc)
#   --config-only   fetch, patch and configure, then stop (no compile)
#   --lean          also merge lean.config (turns off unused loadable modules only;
#                   checked so no built-in option changes and key hardware stays)
#   --menuconfig    open menuconfig after the fragment is merged, then continue
#   --update        build the current tip of KERNEL_BRANCH instead of the pinned
#                   KERNEL_SHA and print the SHA (then pin it in kernel.conf)
#   --clean         remove kernel/build before starting
#   --debug-patches also apply kernel/debug-patches/*.patch (suspend bisect hook; never for
#                   a build you publish)
################################################################################
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kernel.conf
source "$HERE/kernel.conf"

SRC="$HERE/build/linux"
OUT="$HERE/out"
JOBS="$(nproc)"
INSTALL_DEPS=false DEPS_ONLY=false LEAN=false CONFIG_ONLY=false MENUCONFIG=false UPDATE=false CLEAN=false DEBUG_PATCHES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-deps) INSTALL_DEPS=true; shift ;;
        --deps-only) INSTALL_DEPS=true; DEPS_ONLY=true; shift ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --config-only) CONFIG_ONLY=true; shift ;;
        --lean) LEAN=true; shift ;;
        --menuconfig) MENUCONFIG=true; shift ;;
        --update) UPDATE=true; shift ;;
        --clean) CLEAN=true; shift ;;
        --debug-patches) DEBUG_PATCHES=true; shift ;;
        -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

info() { echo -e "\033[0;32m[kernel]\033[0m $*"; }
warn() { echo -e "\033[1;33m[kernel]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[kernel]\033[0m $*" >&2; exit 1; }

[[ "$(uname -m)" == "aarch64" ]] || die "native arm64 build only (this is $(uname -m)); cross-compile is not wired up"

DEPS=(build-essential bc bison flex libssl-dev libelf-dev libdw-dev libncurses-dev dwarves
      rsync kmod cpio fakeroot debhelper dpkg-dev git ccache device-tree-compiler)

if $INSTALL_DEPS; then
    info "Installing build dependencies"
    SUDO=(); [[ $EUID -eq 0 ]] || SUDO=(sudo)
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y "${DEPS[@]}"
    $DEPS_ONLY && exit 0
fi

missing=()
for p in "${DEPS[@]}"; do
    dpkg -s "$p" &>/dev/null || missing+=("$p")
done
[[ ${#missing[@]} -eq 0 ]] || die "missing packages: ${missing[*]} (run with --install-deps)"

free_gb=$(df -BG --output=avail "$HERE" | tail -1 | tr -dc '0-9')
[[ "$free_gb" -ge 12 ]] || warn "only ${free_gb}G free; a build needs about 10G"

$CLEAN && { info "Cleaning kernel/build"; rm -rf "${HERE:?}/build"; }

# --- fetch -------------------------------------------------------------------
mkdir -p "$SRC" "$OUT"
cd "$SRC"
[[ -d .git ]] || { git init -q; git remote add origin "$KERNEL_REPO"; }

if $UPDATE; then
    info "Fetching tip of $KERNEL_BRANCH"
    git fetch -q --depth=1 origin "$KERNEL_BRANCH"
    TARGET="$(git rev-parse FETCH_HEAD)"
    info "Tip is $TARGET (pinned: $KERNEL_SHA). Update kernel.conf once it boots well."
else
    TARGET="$KERNEL_SHA"
    if ! git cat-file -e "$TARGET^{commit}" 2>/dev/null; then
        info "Fetching $TARGET"
        git fetch -q --depth=1 origin "$TARGET" || {
            warn "direct SHA fetch failed, fetching $KERNEL_BRANCH"
            git fetch -q --depth=1 origin "$KERNEL_BRANCH"
            git cat-file -e "$TARGET^{commit}" 2>/dev/null \
                || die "$TARGET is not the tip of $KERNEL_BRANCH any more; fetch full history or pin a newer SHA"
        }
    fi
fi

info "Checking out $TARGET"
git checkout -q -f "$TARGET"
git clean -fdxq

# --- patch -------------------------------------------------------------------
shopt -s nullglob
for p in "$HERE"/patches/*.patch; do
    info "Applying $(basename "$p")"
    git apply --index "$p" || die "patch failed: $p (rebase it onto $TARGET)"
done
if $DEBUG_PATCHES; then
    for p in "$HERE"/debug-patches/*.patch; do
        warn "Applying DEBUG patch $(basename "$p") (do not publish this build)"
        git apply --index "$p" || die "debug patch failed: $p (rebase it onto $TARGET)"
    done
fi
shopt -u nullglob

# --- configure ---------------------------------------------------------------
CC_ARGS=()
if command -v ccache &>/dev/null; then
    CC_ARGS=("CC=ccache gcc")
    info "Using ccache"
fi

info "Configuring (bcm2712_defconfig + hackberry.config)"
make -s "${CC_ARGS[@]}" bcm2712_defconfig
scripts/kconfig/merge_config.sh -m .config "$HERE/hackberry.config" >/dev/null
make -s "${CC_ARGS[@]}" olddefconfig

# --- lean profile: turn off unused loadable modules, never built-in code ------
if $LEAN; then
    info "Applying lean.config"
    cp .config "$SRC/.config.full"
    scripts/kconfig/merge_config.sh -m .config "$HERE/lean.config" >/dev/null
    make -s "${CC_ARGS[@]}" olddefconfig

    # 1. Nothing built-in may change, except sub-options of removed modules that
    #    lean.config explicitly allows (the kernel image must stay identical so
    #    modules from a full build still load).
    allow=$(sed -n 's/^# allow-y-change: *//p' "$HERE/lean.config")
    viol=0
    while IFS= read -r line; do
        grep -qxF "$line" .config && continue
        key="${line%%=*}"; key="${key#CONFIG_}"
        ok=false
        for pfx in $allow; do [[ "$key" == "$pfx"* ]] && ok=true; done
        $ok || { warn "lean changed a built-in option: $line"; viol=1; }
    done < <(grep '=y$' "$SRC/.config.full")
    [[ $viol -eq 0 ]] || die "lean.config would change built-in options (see above)"

    # 2. Hardware and features this device relies on must survive
    for k in DRM_VC4 SND_SOC SND_SOC_HDMI_CODEC SND_USB_AUDIO BT BT_BREDR BT_RFCOMM BT_BNEP BT_HIDP \
             BT_HCIUART BT_HCIUART_BCM BT_HCIBTUSB BATTERY_MAX17040 TOUCHSCREEN_EDT_FT5X06 BRCMFMAC \
             RTW88 RTW89 MT7921U RT2800USB ATH9K_HTC RTL8XXXU USB_VIDEO_CLASS USB_SERIAL_FTDI_SIO \
             USB_SERIAL_CP210X USB_GADGET CAN DVB_USB_RTL28XXU DVB_RTL2832_SDR NF_TABLES; do
        want=$(grep -E "^CONFIG_${k}=" "$SRC/.config.full" | head -1)
        have=$(grep -E "^CONFIG_${k}=" .config | head -1)
        [[ -z "$want" || "$want" == "$have" ]] || die "lean dropped required option: $k"
    done
    nm_full=$(grep -c '=m$' "$SRC/.config.full"); nm_lean=$(grep -c '=m$' .config)
    info "Lean: modules $nm_full -> $nm_lean (built-in options unchanged, required hardware kept)"
    rm -f "$SRC/.config.full"
fi
$MENUCONFIG && make "${CC_ARGS[@]}" menuconfig

# Every explicit line in the fragment must have survived olddefconfig
drift=0
while IFS= read -r line; do
    [[ "$line" =~ ^CONFIG_[A-Z0-9_]+= ]] || continue
    key="${line%%=*}" want="${line#*=}"
    if [[ "$want" == "n" ]]; then
        grep -qE "^(# $key is not set|$key=n)$" .config || { warn "config drift: wanted $key=n"; drift=1; }
    else
        grep -qxF "$line" .config || { warn "config drift: wanted $line, got: $(grep -E "^(# )?$key[= ]" .config || echo missing)"; drift=1; }
    fi
done < "$HERE/hackberry.config"
[[ $drift -eq 0 ]] && info "All fragment options applied" || warn "Some options did not apply (see above); fix hackberry.config"

grep -qx 'CONFIG_ARM64_16K_PAGES=y' .config || die "16K pages not enabled in the final config"

if $CONFIG_ONLY; then
    info "Config only: $SRC/.config"
    exit 0
fi

# --- build -------------------------------------------------------------------
info "Building with -j$JOBS (first full build took 174 min on a CM5 with -j4; ccache makes rebuilds much faster)"
start=$SECONDS
make -j"$JOBS" "${CC_ARGS[@]}" LOCALVERSION= KDEB_PKGVERSION="$(make -s kernelversion)-1hackberry" bindeb-pkg
info "Build finished in $(( (SECONDS - start) / 60 )) min"

# --- collect -----------------------------------------------------------------
rm -f "$OUT"/*.deb
mv ../linux-image-*.deb ../linux-headers-*.deb "$OUT"/
rm -f ../linux-libc-dev_*.deb ../linux-image-*-dbg_*.deb ../*.buildinfo ../*.changes
cp .config "$OUT/config-$(make -s LOCALVERSION= kernelrelease | tr -d +)"
echo "$TARGET" > "$OUT/KERNEL_SHA"

info "Packages in $OUT:"
ls -lh "$OUT"
info "Deploy with: sudo $HERE/install.sh --enable"
