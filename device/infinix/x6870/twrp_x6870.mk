#
# Copyright (C) 2026 The OrangeFox Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
# NOTE: gsi_keys.mk is deliberately NOT inherited. The GSI AVB keys land in the
# *first-stage ramdisk of the OS*, not in recovery, and the OrangeFox reference
# tree (device/mondrian) inherits neither. The 12.1 tree still ships
# gsi_keys.mk, but recovery does not need it.

# OrangeFox/TWRP build system
$(call inherit-product, vendor/twrp/config/common.mk)

# Device configuration
$(call inherit-product, device/infinix/x6870/device.mk)

PRODUCT_DEVICE := x6870
PRODUCT_NAME := twrp_x6870
PRODUCT_BRAND := Infinix
PRODUCT_MODEL := Infinix X6870
PRODUCT_MANUFACTURER := INFINIX
PRODUCT_RELEASE_NAME := x6870

# OrangeFox metadata.
# NOTE: OF_MAINTAINER is a make variable - orangefox.mk:216-219 turns it into
# -DOF_MAINTAINER and data.cpp:749 displays it - so it belongs here.
# The FOX_* switches are different: vendor/recovery/OrangeFox_A12.sh:315-316 reads
# FOX_MAINTAINER_PATCH_VERSION from the *environment* to name the output image, so
# a "FOX_* := ..." here would only reach the compiled-in string. They are exported
# from vendorsetup.sh instead.
OF_MAINTAINER := elric
