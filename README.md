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
| `OrangeFox-R12.0_1-Unofficial-x6870.zip` | unmodified OrangeFox installer zip; contains `recovery.img` (md5-identical to the release `vendor_boot.img`), `vendor_ramdisk_recovery.cpio` (LZ4, 42.1 MB), `magiskboot` and helper scripts | **do not flash on a fresh device**: its install branch repacks ~71.6 MB without a size check and writes both slots (see below). Use the update zip instead once OrangeFox is installed |
| `OrangeFox-x6870-vendor_boot-update.zip` | the same zip with a **zstd** `vendor_ramdisk_recovery.cpio` (29.1 MB) and a patched installer | **the zip update path**, flashed *from a working OrangeFox* (see below) |
| `recovery-installer.zip` | third-party generic installer with the raw `vendor_boot.img` added | **do not use**; the workflow now defaults to not producing it |

Why the plain OrangeFox zip is not the initial install path here:

- Its `recovery.img` is the same un-repacked image as the release `vendor_boot.img`, so
  flashing it gives a recovery without the stock platform ramdisk (black screen).
- Its `vendor_boot` installer branch (`FOX_INSTALLER_VENDOR_BOOT_RAMDISK_INSTALL`) dumps
  the current vendor_boot, replaces the recovery fragment with the 42.1 MB LZ4 cpio and
  repacks: ~71.6 MB, which does not fit, and that branch has no partition-size check. It
  then writes the result to **both** slots, so it would overwrite your only stock copy
  (slot B is unprovisioned on this device).
- `flash-whole-image.sh` flashes that same un-repacked `recovery.img`;
  `flash-ramdisk.sh` uses `fastboot flash vendor_boot:recovery` with the 42.1 MB LZ4
  ramdisk, which also cannot fit.

`recovery-installer.zip` is worse: its `update-binary` looks for `recovery.img` /
`twrp*.img`, and when there is no dedicated recovery partition it targets **`boot`**.
On this device it finds no usable image and aborts; if it did find one, it would
overwrite `boot_a`/`boot_b` with a vendor_boot image. Leave it alone.

`OrangeFox-x6870-vendor_boot-update.zip` is produced by
`tools/prepare_update_zip.sh` (run by CI after every vendor_boot build). It keeps the
stock blobs on the device: the installer dumps the installed vendor_boot and only
replaces the recovery fragment. It also refuses to write an image that does not fit and
writes only the slot recovery is running from. On this device slot B is unprovisioned,
so the fallback for a bad update is `stock/vendor_boot_a.img`, not the other slot. The
**first** installation must still go through the repacked full image.

## Updating from an already-working OrangeFox (zip)

Once OrangeFox boots on the device, future builds can be installed without fastboot:

1. Copy `OrangeFox-x6870-vendor_boot-update.zip` to internal storage / USB-OTG.
2. In OrangeFox: **Install**, select the zip, swipe to confirm.
3. Read the log. It must print `Vendor_boot device ...`, `Installing only the ramdisk`,
   the `Repacked image: ... bytes; /dev/block/by-name/vendor_boot_a: 67108864 bytes`
   line, and then write only the current slot.
4. Reboot. The other slot is untouched; on this device fall back with
   `fastboot flash vendor_boot_a stock/vendor_boot_a.img` (slot B is zero-filled).

The patched installer aborts without writing anything if the repacked image is larger
than the partition, if `ro.boot.slot_suffix` is empty, or if it cannot unpack the dumped
image. It also refuses to run on a build where `orangefox.vendor_boot.recovery` is not
true (i.e. when OrangeFox is not running from vendor_boot).

Do not flash the update zip from Android/Magisk, and do not use it as the first install:
on a stock device the installer would dump the stock vendor_boot and still need the
stock platform ramdisk, which is present, but the device must already be running
OrangeFox for the ramdisk-only branch to be selected safely.

## Repack a CI build (required for `vendorboot`)

CI uploads `vendor_boot.img` **without** the stock platform ramdisk. After every build:

```bash
# 1. download the release's vendor_boot.img
# 2. merge its recovery fragment into the stock layout
STOCK_IMG=stock/vendor_boot_a.img \
  ./tools/repack_vendor_boot.sh ~/Downloads/vendor_boot.img out/vendor_boot-ofox.img

# 3. flash the result to the active slot (this device: slot _a)
adb reboot bootloader
fastboot flash vendor_boot_a out/vendor_boot-ofox.img
fastboot reboot            # boot Android first; then use Power+VolUp or adb reboot recovery
```

The script detects the input format (lz4/zstd/gzip/cpio), keeps it if it fits, otherwise
decompresses it and recompresses with `zstd -19 -T1`. It asserts that the DTB and the
stock platform ramdisk are byte-identical to the stock image, that the recovery fragment
decompresses back to the same cpio, and refuses if the result exceeds the 64 MiB
partition. When `avbtool` is installed it also appends the same unsigned
(`Algorithm: NONE`) AVB hash footer the stock image and CI artifact carry, padding the
image to exactly 64 MiB (`AVB_FOOTER=0` opts out).

## Safe flashing and rollback

### Before you flash

1. Confirm the live `vendor_boot_a` is still byte-identical to the dump the repack used.
   On a GSI, `ro.build.*` describe the GSI and the vendor/super partitions, not the
   stock system the dump came from, so compare the partition itself:

   ```bash
   adb shell 'md5sum /dev/block/by-name/vendor_boot_a'   # 55daed772d88d3b2c447d7e38957eea7
   md5sum stock/vendor_boot_a.img
   ```

   If they differ, **re-dump the active slot's `vendor_boot` and `boot`** and repack from
   the new dump: the platform-ramdisk kernel modules must match the running kernel, or
   display/touch/storage will not come up. Also read the real bootloader state from
   `/proc/bootconfig` (`androidboot.verifiedbootstate`); a GSI or root solution may spoof
   the `ro.boot.*` properties - this device reports `green` there while the bootloader is
   actually `orange`/unlocked.
2. Verify the repacked image (the repack script already does the hard checks):

   ```bash
   IMAGE=out/vendor_boot-ofox.img
   stat -c '%s %n' "$IMAGE"                                  # exactly 67108864
   unpack_bootimg --boot_img "$IMAGE" --format info           # header v4, 2 fragments
   avbtool info_image --image "$IMAGE" | head -8              # Algorithm: NONE
   ```

   It must report `header version: 4`, `vendor_ramdisk00` type `0x1`, and
   `vendor_ramdisk01` type `0x2`, name `recovery`. The AVB footer must be
   `Algorithm: NONE` (there is no signing key, exactly like stock). Never flash the CI
   artifact directly: its platform ramdisk is empty. To check the hash descriptor as
   well, `avbtool verify_image --image ...` reconstructs the file name from the
   partition name, so copy the image to `.../vendor_boot.img` first.
3. Back up every boot-critical partition from the active slot while Android still works,
   and copy `stock/` off the repo (it is gitignored):

   ```bash
   for p in vendor_boot_a boot_a init_boot_a dtbo_a vbmeta_a; do
     adb shell "su -c 'dd if=/dev/block/by-name/$p of=/sdcard/$p.img bs=1M'"
     adb pull /sdcard/$p.img stock/
   done
   md5sum stock/vendor_boot_a.img   # must be 55daed772d88d3b2c447d7e38957eea7
   ```

   Also copy `stock/` (about 150 MB now) to a USB stick or cloud storage.
   Dumping slot B is pointless on this device: every `*_b` partition is zero-filled
   (unprovisioned), so it is not a usable spare. `init_boot_a` may be patched by
   KernelSU/Magisk - keep that copy for reference, but it is not a stock fallback.

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
   Verify the rollback command itself is accepted (a no-op that re-selects the current
   slot):

   ```bash
   fastboot --set-active=a      # use the slot printed by getvar current-slot
   ```

   Also power the phone off and test the hardware key combo (power + volume-down)
   once, then `fastboot reboot` back to Android. That is the entry point you will
   use if a recovery image ever bootloops.

### Why a vendor_boot mistake cannot require an auth flash

Fastboot/preloader/lk live in partitions this project never writes
(`preloader`, `lk`, GPT; this procedure also leaves `vbmeta` alone). A bad `vendor_boot`
is consumed *after* lk has already run, so it cannot stop the bootloader from starting:
power + volume-down at power-on still lands in fastboot, where you can restore the stock
image. The auth-flash / service-centre path is only needed when `preloader`/`lk`/GPT are
corrupted, which this procedure does not touch.

Still, do the write test below until you have seen `OKAY` from fastboot at least once,
and keep `stock/vendor_boot_a.img` where fastboot and a rooted Android can reach it.

On this device `vbmeta_a` carries `Flags: 3` (disable-verity + disable-verification), so
the bootloader does not check the `vendor_boot` hash at all and the unsigned
`Algorithm: NONE` footer cannot fail verification. That only removes the *rejection* of a
bad image: a wrong platform ramdisk still boots to a black screen, so the rollback is
still the real safety net.

### Flash procedure (direct, active slot)

This device ships with only slot A provisioned. Every `*_b` partition (`boot`,
`vendor_boot`, `init_boot`, `dtbo`, `vbmeta`) is zero-filled, so slot B cannot boot and
`fastboot --set-active=b` would leave you with no bootable slot. Flash the active slot
directly.

The rollback source is `stock/vendor_boot_a.img`, proved byte-identical to the live
partition above. lk/preloader/fastboot are never touched, so a bad image is always
recoverable through fastboot.

```bash
# 1. write test: the same bytes already in the partition
fastboot flash vendor_boot_a stock/vendor_boot_a.img      # must print OKAY

# 2. the real image
fastboot flash vendor_boot_a out/vendor_boot-ofox.img     # must print OKAY
fastboot reboot

# 3. Android must still boot normally (the platform fragment is stock-identical);
#    then enter recovery
adb shell getprop ro.boot.slot_suffix                    # _a
adb reboot recovery
```

Normal Android boot keeps working after this flash: only the type-`0x2` recovery
fragment changes, and the bootloader uses it only when booting recovery.

Do not run `fastboot --set-active=b` on this device. If the bootloader ever falls back to
the empty slot B by itself, `fastboot --set-active=a` restores slot A.

### If slot B is provisioned (other units)

Some units may ship with both slots populated. Check before using the inactive-slot
route:

```bash
adb shell 'md5sum /dev/block/by-name/vendor_boot_a /dev/block/by-name/vendor_boot_b'
```

Only if `vendor_boot_b` is non-zero **and** `boot_b`/`init_boot_b`/`dtbo_b`/`vbmeta_b`
match their `_a` counterparts can you leave A stock and test on B:

```bash
fastboot flash vendor_boot_b out/vendor_boot-ofox.img
fastboot --set-active=b
fastboot reboot
# fallback: fastboot --set-active=a
```

### If something goes wrong

| symptom | escape hatch |
|---|---|
| Recovery black-screens but Android still boots | `adb reboot bootloader` then `fastboot flash vendor_boot_a stock/vendor_boot_a.img && fastboot reboot` |
| Recovery and Android both fail, fastboot works | hold power ~15 s, then power + volume-down: `fastboot flash vendor_boot_a stock/vendor_boot_a.img && fastboot reboot` |
| The slot shows `_b` (bootloader switched to the empty slot) | `fastboot --set-active=a && fastboot reboot` |
| Fastboot works but you prefer not to use it | from rooted Android: `adb push stock/vendor_boot_a.img /sdcard/ && adb shell "su -c 'dd if=/sdcard/vendor_boot_a.img of=/dev/block/by-name/vendor_boot_a bs=1M'"` |
| Fastboot does not enumerate | MTK BROM/Preloader + SP Flash Tool with the official X6870 firmware (auth flash, service centre territory). Only reachable if preloader/lk/GPT is damaged - never done by this project |

No other partition is modified when flashing `vendor_boot_a`: `boot`, `init_boot`,
`dtbo`, `vbmeta*` and `super` are left alone. (`init_boot_a` on this unit already carries
the KernelSU patch; leave it as-is.) Do **not** re-lock the bootloader while a non-stock
`vendor_boot` is installed.

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
- `tools/prepare_update_zip.sh` - Builds the flashable-from-recovery vendor_boot update zip
- `tools/verify_device.sh` - Read-only on-device checks for the values that need the phone
- `stock/` - Stock images and extracted components for reference/repacking

