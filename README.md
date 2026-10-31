# OrangeFox Recovery for Infinix X6870 (Note 50s)

OrangeFox Recovery 12.1 build configuration for Infinix X6870 (MediaTek MT6878, Dimensity 7300).

## Device Info

- **Device:** Infinix Note 50s / X6870
- **Platform:** MediaTek MT6878
- **Stock firmware:** Android 16 / SDK 36
- **Recovery build base:** OrangeFox 12.1 (Android 12.1)
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
| `DEVICE_MAKEFILE` | `twrp_x6870.mk` | The only product makefile in `AndroidProducts.mk` (`fox_x6870.mk` is inherited from `device.mk`) |
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
- Use `tools/repack_vendor_boot.sh` to repack a recovery ramdisk into a stock-style vendor_boot image locally. It keeps the stock platform ramdisk + DTB untouched and zstd-compresses the recovery fragment so the result fits the 64 MiB partition.
- KernelSU/SukiSU support flags are enabled via `vendorsetup.sh`.
- VBMeta/AVB: `BOARD_AVB_ENABLE := true`, but no signing key is set, so avbtool appends
  an unsigned hash footer (`--algorithm NONE`) like the stock vendor_boot. AVB must stay
  enabled: OrangeFox 12.1 runs its post-build step (`Fox_After_Recovery_Image`, which
  produces `OrangeFox-*.img`, the md5 and the zip installer) only from the AVB branch of
  build/make's vendor_boot rule.

## Building locally

Build the recovery with the normal OrangeFox flow:

```bash
cd fox_12.1
source build/envsetup.sh
lunch twrp_x6870-eng
mka vendorbootimage
```

This produces `out/target/product/x6870/OrangeFox-*.img` (plus the `.zip` installer),
whose recovery fragment is **LZ4-compressed**. Because the stock platform ramdisk
already occupies 29.2 MB of the 64 MiB partition, that image is ~71.6 MB and does not
fit as-is: it must be repacked into the stock layout (see below).

OrangeFox's own `FOX_REFERENCE_VENDOR_BOOT_IMAGE` hook
(`process_reference_vendor_boot_image()`) repacks with `magiskboot`, which reuses the
stock fragment's LZ4 compression. That path ends in `FATAL ERROR ... greater than the
partition size` on this device, so it cannot be used here. `tools/repack_vendor_boot.sh`
is the supported path; it recompresses only the recovery fragment with zstd.

### Why zstd

The stock 6.1 kernel is built with `CONFIG_RD_ZSTD=y` / `CONFIG_ZSTD_DECOMPRESS=y`
(verified with `scripts/extract-ikconfig` on `stock/boot_a.img`) and has no XZ/LZMA
support. For the ~84 MB raw OrangeFox cpio:

| compression | size | fits 64 MiB vendor_boot? |
|---|---|---|
| stock platform ramdisk (LZ4, kept untouched) | 29,200,444 B | — |
| recovery fragment, LZ4 (`-l -12`) | 42,096,890 B | no (71.6 MB total) |
| recovery fragment, gzip `-9` | 37,451,887 B | no (~66.7 MB total) |
| recovery fragment, **zstd `-19 -T1`** | **29,068,634 B** | **yes (58.6 MB total)** |

`tools/repack_vendor_boot.sh` therefore keeps the stock platform ramdisk and DTB
byte-identical (it verifies this after repacking) and compresses the recovery fragment
with zstd whenever the input fragment does not already fit.

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

The script detects the input format (lz4/zstd/gzip/cpio), keeps it if it fits, otherwise
decompresses it and recompresses with `zstd -19 -T1`. It asserts that the DTB and the
stock platform ramdisk are byte-identical to the stock image, that the recovery fragment
decompresses back to the same cpio, and refuses if the result exceeds the 64 MiB
partition.

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

