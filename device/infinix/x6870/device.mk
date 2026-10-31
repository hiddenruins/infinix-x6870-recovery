#
# Copyright (C) 2026 The OrangeFox Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Product makefiles are parsed BEFORE BoardConfig.mk, so DEVICE_PATH cannot be
# inherited from there - it has to be defined here, before the inherits below.
DEVICE_PATH := device/infinix/x6870

# The device uses dynamic partitions (super). Declare it so that the dynamic
# partition code paths (and OrangeFox OF_ENABLE_ALL_PARTITION_TOOLS / lptools)
# are enabled - but do not build super.img / super_empty.img from this tree.
# PRODUCT_BUILD_SUPER_PARTITION defaults to PRODUCT_USE_DYNAMIC_PARTITIONS and
# would otherwise add the super size-check target to "droid".
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true
PRODUCT_BUILD_SUPER_PARTITION := false

# Virtual A/B helpers (snapuserd etc.)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch_with_vendor_ramdisk.mk)

# Note: Android 12.1 has no max-page-size check for prebuilt ELF files. That
# check (and its PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE escape hatch) only exists
# in newer build systems, so nothing is needed here.

# OrangeFox UI defaults for this device
$(call inherit-product, $(DEVICE_PATH)/fox_x6870.mk)

TW_DEFAULT_LANGUAGE := en
TW_USE_TOOLBOX := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_LIBRESETPROP := true
TW_EXCLUDE_APEX := true

# recovery/root (fstab, twrp.flags, init.recovery.mt6878.rc, extra modules) is
# picked up automatically from TARGET_RECOVERY_DEVICE_DIRS, which defaults to
# $(TARGET_DEVICE_DIR). No PRODUCT_COPY_FILES needed.
