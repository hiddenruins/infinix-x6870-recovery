#!/bin/bash
# OrangeFox build flags for the Infinix X6870 (MT6878).
#
# This file is sourced by build/envsetup.sh (via vendorsetup.sh) when the
# active lunch target matches this device.

FDEVICE="x6870"

fox_get_target_device() {
    if echo "$BASH_SOURCE" | grep -q "/$FDEVICE/"; then
        FOX_BUILD_DEVICE="$FDEVICE"
    elif set | grep BASH_ARGV | grep -w \"$FDEVICE\"; then
        FOX_BUILD_DEVICE="$FDEVICE"
    elif echo "${BASH_SOURCE[0]}" | grep -q "/$FDEVICE/"; then
        FOX_BUILD_DEVICE="$FDEVICE"
    elif echo "$0" | grep -q "$FDEVICE"; then
        FOX_BUILD_DEVICE="$FDEVICE"
    fi
}

if [ -z "$1" -a -z "$FOX_BUILD_DEVICE" ]; then
    fox_get_target_device
fi

if [ "$1" = "$FDEVICE" -o "$FOX_BUILD_DEVICE" = "$FDEVICE" ]; then
    # Build name / output filename suffix (consumed by OrangeFox_A12.sh:316-317,
    # which reads it as an environment variable - a make assignment would be
    # silently ignored).
    export FOX_MAINTAINER_PATCH_VERSION=1

    # Virtual A/B, no recovery partition (recovery lives in vendor_boot)
    export FOX_VIRTUAL_AB_DEVICE=1
    export FOX_VANILLA_BUILD=1
    export FOX_ENABLE_APP_MANAGER=1

    export FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
    export FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"

    export FOX_USE_BASH_SHELL=1
    export FOX_ASH_IS_BASH=1
    export FOX_USE_TAR_BINARY=1
    export FOX_USE_LZ4_BINARY=1
    export FOX_USE_SED_BINARY=1
    export FOX_USE_XZ_UTILS=1
    export FOX_USE_ZSTD_BINARY=1
    export FOX_USE_NANO_EDITOR=1
    export FOX_USE_BUSYBOX_BINARY=1
    export FOX_USE_DATE_BINARY=1
    export FOX_USE_PATCHELF_BINARY=1
    export FOX_DELETE_AROMAFM=1

    export FOX_SETTINGS_ROOT_DIRECTORY=/data/recovery
    export FOX_MISCELLANEOUS_ROOT_DIRECTORY=/sdcard
    export FOX_ALLOW_EARLY_SETTINGS_LOAD=1

    # KernelSU / SukiSU support (device is KernelSU-rooted)
    export FOX_ENABLE_KERNELSU_SUPPORT=1
    export FOX_ENABLE_KERNELSU_NEXT_SUPPORT=1
    export FOX_ENABLE_SUKISU_SUPPORT=1
else
    if [ -z "$FOX_BUILD_DEVICE" -a -z "$BASH_SOURCE" ]; then
        echo "I: This script requires bash. Not processing the $FDEVICE $(basename $0)"
    fi
fi
