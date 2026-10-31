# OrangeFox Recovery for Infinix X6870 (Note 50s)

OrangeFox Recovery 12.1 build configuration for Infinix X6870 (MediaTek MT6878, Dimensity 7300).

## Device Info

- **Device:** Infinix Note 50s / X6870
- **Platform:** MediaTek MT6878
- **Android:** 16 / SDK 36
- **Boot scheme:** A/B, Virtual A/B, Dynamic Partitions
- **Recovery:** Lives in vendor_boot recovery ramdisk fragment (no dedicated recovery partition)

## Build via GitHub Actions

This repo can be built using the OrangeFox Recovery Builder pattern. Use one of the reference builders:

- [kinguser981/OrangeFox-Recovery-Builder-2024](https://github.com/kinguser981/OrangeFox-Recovery-Builder-2024)
- [bnsmb/OrangeFox-Recovery-Builder-2024](https://github.com/bnsmb/OrangeFox-Recovery-Builder-2024)

### Recommended workflow parameters (OrangeFox 12.1)

| Parameter | Value | Notes |
|-----------|-------|-------|
| `MANIFEST_BRANCH` | `12.1` | Use OrangeFox 12.1 |
| `DEVICE_TREE_URL` | `https://github.com/<your-username>/<this-repo>.git` or local path equivalent | Point to this device tree |
| `DEVICE_TREE_BRANCH` | `main` (or your branch) | Branch containing this tree |
| `DEVICE_PATH` | `device/infinix/x6870` | Must match `DEVICE_PATH` in `BoardConfig.mk` |
| `DEVICE_NAME` | `x6870` | As defined in `AndroidProducts.mk` / makefiles |
| `DEVICE_MAKEFILE` | `fox_x6870.mk` | Or use `twrp_x6870.mk` depending on builder |
| `BUILD_TARGET` | `vendorboot` | Recovery is in vendor_boot (see BoardConfig) |
| `STOCK_VENDOR_BOOT_URL` | *(optional)* | If empty, CI uploads an un-repacked image that you must repack locally |
| `RECOVERY_INSTALLER` | `true`/`false` | Optional |
| `RECOVERY_TAR` | `false` | Not a Samsung device |

### Notes specific to this device

- `TARGET_NO_KERNEL := true` - stock kernel remains in `boot.img`. Do **not** replace boot.
- `BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true` with recovery as fragment type 2.
- **The stock platform ramdisk (fragment 0) must be preserved.** It carries all 248 MTK
  kernel modules (display panel, DRM, touch helpers, storage). An AOSP-built
  `vendor_boot.img` replaces it with an empty one, so the recovery boots to a black
  screen. The stock dump is deliberately kept out of git, so **CI uploads an un-repacked
  image**; repack it locally after every build (see below). Setting
  `STOCK_VENDOR_BOOT_URL` makes CI do the repack itself instead.
- `FOX_VIRTUAL_AB_DEVICE := 1`, `FOX_VANILLA_BUILD := 1` are set in `vendorsetup.sh`.
- Use `tools/verify_device.sh` to read back the values that cannot be derived from the
  stock dumps (kernel/module vermagic, backlight scale, USB-OTG node, battery path,
  input device names).
- Use `tools/repack_vendor_boot.sh` to repack a recovery ramdisk into a stock-style vendor_boot image locally.
- KernelSU/SukiSU support flags are enabled via `vendorsetup.sh`.
- VBMeta/AVB: `BOARD_AVB_ENABLE := false` as configured.

## Repack a CI build (required for `vendorboot`)

CI uploads `vendor_boot.img` **without** the stock platform ramdisk. After every build:

```bash
# 1. download the release's vendor_boot.img
# 2. merge its recovery fragment into the stock layout
STOCK_IMG=stock/vendor_boot_a.img \
  ./tools/repack_vendor_boot.sh ~/Downloads/vendor_boot.img out/vendor_boot-ofox.img

# 3. flash the result (slot _a shown; use vendor_boot_b if you boot from slot b)
adb reboot bootloader
fastboot flash vendor_boot_a out/vendor_boot-ofox.img
fastboot reboot recovery
```

The script asserts that the DTB and the stock platform ramdisk are byte-identical to
the stock image, and refuses if the result exceeds the 64 MiB partition.

## Local repack (from a built recovery ramdisk)

```bash
# Build gives recovery ramdisk (or vendor_boot with recovery fragment).
# To produce vendor_boot.img compatible with stock layout:
./tools/repack_vendor_boot.sh <recovery-ramdisk-dir-or-img> out/vendor_boot-ofox.img

# Verify against stock
STOCK_DIR=stock/unpacked/vendor_boot_a ./tools/repack_vendor_boot.sh <input> <out>

# Or point straight at the stock image (what CI does):
STOCK_IMG=stock/vendor_boot_a.img ./tools/repack_vendor_boot.sh <input> <out>
```

## On-device verification

```bash
# read-only: dumps slot, vermagic, backlight, sd* nodes, battery, input names
./tools/verify_device.sh
```

## Files of interest

- `device/infinix/x6870/fox_x6870.mk` - OrangeFox UI/options
- `device/infinix/x6870/vendorsetup.sh` - OrangeFox build flags (exported env vars)
- `device/infinix/x6870/BoardConfig.mk` - Platform/boot/recovery/VB config
- `tools/repack_vendor_boot.sh` - Vendor_boot repacker (preserves DTB + platform ramdisk)
- `tools/verify_device.sh` - Read-only on-device checks for the values that need the phone
- `stock/` - Stock images and extracted components for reference/repacking

