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
fit as-is; `recovery.img` inside the zip has the same problem and the zip installer is
not usable for the first install on this device (see "What the CI release contains").
It must be repacked into the stock layout (see below).

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

## What the CI release contains

| asset | what it actually is | what to do with it |
|---|---|---|
| `vendor_boot.img` | raw build: AOSP **empty** platform ramdisk (2.2 MB) + OrangeFox recovery fragment (LZ4, 42.1 MB), padded to 64 MiB with an unsigned AVB footer | **never flash it**; it is the input for `tools/repack_vendor_boot.sh` |
| `OrangeFox-R12.0_1-Unofficial-x6870.zip` | OrangeFox installer zip; contains `recovery.img` (md5-identical to the release `vendor_boot.img`), `vendor_ramdisk_recovery.cpio` (LZ4, 42.1 MB), `magiskboot` and helper scripts | **do not flash yet** on this device (see below) |
| `recovery-installer.zip` | third-party generic installer with the raw `vendor_boot.img` added | **do not use**; the workflow now defaults to not producing it |

Why the zip is not the initial install path here:

- Its `recovery.img` is the same un-repacked image as the release `vendor_boot.img`, so
  flashing it gives a recovery without the stock platform ramdisk (black screen).
- Its `vendor_boot` installer branch (`FOX_INSTALLER_VENDOR_BOOT_RAMDISK_INSTALL`) dumps
  the current vendor_boot, replaces the recovery fragment with the 42.1 MB LZ4 cpio and
  repacks: ~71.6 MB, which does not fit, and that branch has no partition-size check. It
  then writes the result to **both** slots, so you lose the stock spare.
- `flash-whole-image.sh` flashes that same un-repacked `recovery.img`;
  `flash-ramdisk.sh` uses `fastboot flash vendor_boot:recovery` with the 42.1 MB LZ4
  ramdisk, which also cannot fit.

`recovery-installer.zip` is worse: its `update-binary` looks for `recovery.img` /
`twrp*.img`, and when there is no dedicated recovery partition it targets **`boot`**.
On this device it finds no usable image and aborts; if it did find one, it would
overwrite `boot_a`/`boot_b` with a vendor_boot image. Leave it alone.

Once OrangeFox is already running you can rebuild the zip with a zstd
`vendor_ramdisk_recovery.cpio` (and a zstd-aware, size-checked installer) if you want
zip-based updates; the first installation must go through the repacked full image below.

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

## Safe flashing and rollback

### Before you flash

1. Confirm the phone is still on the build the stock dump came from:

   ```bash
   adb shell getprop ro.build.id ro.build.version.incremental ro.boot.slot_suffix ro.boot.verifiedbootstate
   ```

   Expected at capture time: `BP2A.250605.031.A3`, `301500017`, `_a`, `orange`.
   If an OTA changed the build, **re-dump the active slot's `vendor_boot` and `boot`**
   and repack from the new dump: the platform-ramdisk kernel modules must match the
   running kernel, or display/touch/storage will not come up.
2. Verify the repacked image (the repack script already does the hard checks):

   ```bash
   IMAGE=out/vendor_boot-ofox.img
   stat -c '%s %n' "$IMAGE"                                  # must be <= 67108864
   unpack_bootimg --boot_img "$IMAGE" --format info           # header v4, 2 fragments
   ```

   It must report `header version: 4`, `vendor_ramdisk00` type `0x1`, and
   `vendor_ramdisk01` type `0x2`, name `recovery`. Never flash the CI artifact
   directly: its platform ramdisk is empty.
3. Back up every boot-critical partition from both slots while Android still works,
   and copy `stock/` off the repo (it is gitignored):

   ```bash
   for p in vendor_boot_a vendor_boot_b boot_a boot_b init_boot_a init_boot_b dtbo_a dtbo_b; do
     adb shell "su -c 'dd if=/dev/block/by-name/$p of=/sdcard/$p.img bs=1M'"
     adb pull /sdcard/$p.img stock/
   done
   md5sum stock/vendor_boot_a.img   # must be 55daed772d88d3b2c447d7e38957eea7
   ```

   Also copy `stock/` (about 350 MB now) to a USB stick or cloud storage.
   If `vendor_boot_b.img` and `boot_b.img` match their `_a` counterparts, slot B
   is a bit-identical spare and can be used for a bootloop-safe test.

4. Make sure fastboot works **before** writing anything:

   ```bash
   adb reboot bootloader
   fastboot devices
   fastboot getvar current-slot
   fastboot getvar is-userspace    # must print "no" (real bootloader, not fastbootd)
   fastboot getvar slot-count      # expect 2
   ```

   If `fastboot devices` lists nothing here, **stop** and fix USB/udev first. The
   rollback plan depends on reaching this mode from a phone that does not boot.
   Verify the rollback command itself works (no-op, writes the current slot again):

   ```bash
   fastboot --set-active=a      # use the slot printed by getvar current-slot
   ```

   Also power the phone off and test the hardware key combo (power + volume-down)
   once, then `fastboot reboot` back to Android. That is the entry point you will
   use if a recovery image ever bootloops.

### Why a vendor_boot mistake cannot require an auth flash

Fastboot/preloader/lk live in partitions this project never writes
(`preloader`, `lk`, `vbmeta`, GPT). A bad `vendor_boot` is consumed *after* lk has
already run, so it cannot stop the bootloader from starting: power + volume-down at
power-on still lands in fastboot, where you can restore the stock image. The
auth-flash / service-centre path is only needed when `preloader`/`lk`/GPT are
corrupted, which this procedure does not touch.

Still, do the write test below until you have seen `OKAY` from fastboot at least once,
and never flash the only working slot first.

### Flash bootloop-safely (recommended: inactive slot)

Only do this if step 3 showed slot B is provisioned and identical to A. The idea is to
leave slot A 100% stock and test OrangeFox on B, so the only recovery action needed is
`fastboot --set-active=a`.

```bash
# 1. prove fastboot can authenticate a write, using the stock image you just dumped
fastboot flash vendor_boot_b stock/vendor_boot_b.img     # must print OKAY

# 2. put OrangeFox on the inactive slot
fastboot flash vendor_boot_b out/vendor_boot-ofox.img

# 3. boot the other slot and check Android first
fastboot --set-active=b
fastboot reboot
adb shell getprop ro.boot.slot_suffix                  # _b

# 4. then test recovery
adb reboot recovery
```

If OrangeFox boots, you are done: slot A still has the untouched stock vendor_boot.
If you want OrangeFox on A too, repeat the same steps for `vendor_boot_a` as a second
phase, while B (now known-good) stays as the spare.

### If slot B is empty or differs from A

Do not switch to it. Fall back to flashing the active slot `vendor_boot_a` directly,
but only after step 4 succeeded and after the write test:

```bash
fastboot flash vendor_boot_a stock/vendor_boot_a.img     # write test, same bytes
fastboot flash vendor_boot_a out/vendor_boot-ofox.img
fastboot reboot
```

### If something goes wrong

| symptom | escape hatch |
|---|---|
| OrangeFox/Android on B bootloops | hold power ~15 s, then power + volume-down into fastboot: `fastboot --set-active=a && fastboot reboot` |
| Android on B does not boot but fastboot works | same: `fastboot --set-active=a`; slot A was never modified |
| Recovery black-screens but Android boots | `adb reboot bootloader` then `fastboot flash vendor_boot_a stock/vendor_boot_a.img && fastboot reboot` (or restore B) |
| Fastboot works but you prefer not to use it | from rooted Android: `adb push stock/vendor_boot_a.img /sdcard/ && adb shell "su -c 'dd if=/sdcard/vendor_boot_a.img of=/dev/block/by-name/vendor_boot_a bs=1M'"` |
| Fastboot does not enumerate | MTK BROM/Preloader + SP Flash Tool with the official X6870 firmware (auth flash, service centre territory). Only reachable if preloader/lk/GPT is damaged - never done by this project |

No other partition is modified when flashing `vendor_boot_*`: `boot`, `init_boot`,
`dtbo`, `vbmeta*` and `super` stay stock. Do **not** re-lock the bootloader while a
non-stock `vendor_boot` is installed.

### On-device checklist in OrangeFox

- `adb devices` lists the recovery; `adb shell` works.
- Screen, brightness slider and touch work.
- `cat /sys/class/leds/lcd-backlight/max_brightness` prints `5119`.
- `cat /proc/modules | wc -l` is non-trivial and `dmesg | grep -i 'version magic'`
  shows no module load failures (some vermagic mismatch lines are normal on this
  device; missing modules are not).
- `/tmp/recovery.log` has no fatal errors.
- Back up `Boot` and `Vendor Boot` to external storage before changing anything else,
  then test flashing a zip, `/data` decryption and USB-OTG.

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

