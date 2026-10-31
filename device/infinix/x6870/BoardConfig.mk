#
# Copyright (C) 2026 The OrangeFox Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Infinix Note 50s (X6870) - MediaTek MT6878 (Dimensity 7300)
# Stock firmware is Android 16 / SDK 36; this tree is built against the
# OrangeFox 12.1 (Android 12.1) manifest. A/B, virtual A/B, dynamic partitions.
#
# Recovery lives in the "recovery" fragment of vendor_boot; boot.img only
# carries the stock kernel, so we never touch it.
#

DEVICE_PATH := device/infinix/x6870

# ---------------------------------------------------------------- build fixes
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_MISSING_REQUIRED_MODULES := true

# ------------------------------------------------------------------------ A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    init_boot \
    vendor_boot \
    dtbo \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor

# ------------------------------------------------------------------- platform
TARGET_BOARD_PLATFORM := mt6878
TARGET_BOOTLOADER_BOARD_NAME := mt6878
TARGET_NO_BOOTLOADER := true
TARGET_OTA_ASSERT_DEVICE := X6870,x6870,Infinix-X6870,X6870-OP,mssi_64_64only_cn_armv82

# --------------------------------------------------------------- partitions
# The device has a real vendor partition (logical, inside super). Declaring the
# vendor copy-out path makes build/make treat $OUT/root/vendor as a mount point
# instead of a /system/vendor symlink (board_config.mk derives
# BOARD_USES_VENDORIMAGE from TARGET_COPY_OUT_VENDOR).
#
# This is required for the recovery ramdisk: TWRP installs its vendor prebuilts
# (vendor/bin/hw, vendor/etc/selinux, vendor/etc/vintf) straight into
# $OUT/recovery/root/vendor. With the default "system/vendor" layout the
# baseline-ramdisk rsync tries to replace that non-empty directory with the
# /system/vendor symlink and ramdisk_files-timestamp fails with
# "could not make way for new symlink: root/vendor".
#
# No vendor image is built: BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE is deliberately
# not set, so BUILDING_VENDOR_IMAGE stays empty.
TARGET_COPY_OUT_VENDOR := vendor

# --------------------------------------------------------------- architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := generic

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := generic

# ------------------------------------------------------------ boot / recovery
# The stock kernel stays in boot.img. We only build the recovery ramdisk that
# gets packed into vendor_boot as the "recovery" fragment (type 2).
TARGET_NO_KERNEL := true
TARGET_NO_RECOVERY := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_BOOT_HEADER_VERSION := 4

BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT := true
BOARD_RAMDISK_USE_LZ4 := true

# build/make forwards only BOARD_MKBOOTIMG_ARGS to mkbootimg for vendor_boot.
# Without this, mkbootimg defaults --header_version to 0 and then rejects the
# v4 fragment arguments (--ramdisk_type / --vendor_ramdisk_fragment).
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)

# Stock vendor_boot DTB (must stay byte-identical to the vendor image).
# The 12.1 build concatenates *.dtb from BOARD_PREBUILT_DTBIMAGE_DIR into
# dtb.img. The stock Android 16 vendor tree used TARGET_PREBUILT_DTB instead,
# which does not exist in the 12.1 build system - do not copy that over.
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/dtb

# Keep the built vendor_boot header aligned with the stock image. The local
# repack replaces the platform ramdisk and DTB but reuses these values.
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2

# ------------------------------------------------------------------ partitions
BOARD_FLASH_BLOCK_SIZE := 262144
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_DTBOIMG_PARTITION_SIZE := 8388608

# --------------------------------------------------------------- filesystems
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
BOARD_HAS_LARGE_FILESYSTEM := true

# -------------------------------------------------------------------- display
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888
TARGET_SCREEN_DENSITY := 440

# ------------------------------------------------------------------- recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

TW_THEME := portrait_hdpi
# Exported through soong (twrpGlobalVars_tw_framerate -> -DTW_FRAMERATE=%s).
TW_FRAMERATE := 60
TW_NO_SCREEN_BLANK := true

# Backlight: /sys/class/leds/lcd-backlight (max 5119, verified on device)
TW_BRIGHTNESS_PATH := /sys/class/leds/lcd-backlight/brightness
TW_MAX_BRIGHTNESS := 5119
TW_DEFAULT_BRIGHTNESS := 1400

# Battery / charger
TW_USE_LEGACY_BATTERY_SERVICES := true
TW_CUSTOM_BATTERY_PATH := /sys/class/power_supply/battery

# Kernel modules: stock vendor_boot fragment 0 ships /lib/modules with
# modules.load.recovery + modules.dep, so TWRP can modprobe the full stock set.
TW_LOAD_VENDOR_BOOT_MODULES := true
TW_LOAD_VENDOR_MODULES := "$(shell tr '\n' ' ' < $(DEVICE_PATH)/prebuilt/modules.load.recovery) adaptive-ts.ko focaltech_ft3683g.ko"

# Tools / features
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_LPTOOLS := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_LIBRESETPROP := true
TW_USE_TOOLBOX := true
TW_EXCLUDE_APEX := true
TW_EXTRA_LANGUAGES := false
# MTP is built unless TW_EXCLUDE_MTP is set - there is no TW_HAS_MTP switch.

# Ignore the extra Transsion key device; remove if hardware keys misbehave.
TW_INPUT_BLACKLIST := "tran-keys"

# --------------------------------------------------------------------- crypto
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_USE_FSCRYPT_POLICY := 2
BOARD_USES_METADATA_PARTITION := true

# ---------------------------------------------------------------- verified boot
# We flash only vendor_boot (stock boot/init_boot/vbmeta stay untouched).
# The bootloader must be unlocked before flashing.
BOARD_AVB_ENABLE := false

# Keep platform happy: never let the build write anti-rollback metadata that
# would not match this device.
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := 2099-12-31
