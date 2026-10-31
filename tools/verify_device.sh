#!/usr/bin/env bash
#
# Read-only sanity check of the values in device/infinix/x6870 that cannot be
# derived from the stock dumps (kernel/module match, backlight scale, USB-OTG
# node, battery path, input device names).
#
# Usage:
#   tools/verify_device.sh            # uses `adb` from $PATH
#   ADB="adb -s SERIAL" tools/verify_device.sh
#
# Nothing is written to the device.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DEVICE_TREE="$ROOT/device/infinix/x6870"
ADB="${ADB:-adb}"

if ! command -v "${ADB%% *}" >/dev/null; then
    echo "error: adb not found (set ADB=/path/to/adb)" >&2
    exit 1
fi

if ! $ADB get-state >/dev/null 2>&1; then
    echo "error: no device/emulator visible to: $ADB" >&2
    echo "       boot the phone (or recovery) and enable adb, then retry." >&2
    exit 1
fi

fail=0

if [ -t 1 ]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_OK=''; C_WARN=''; C_BAD=''; C_OFF=''
fi

ok()   { printf '  %sok%s    %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %swarn%s  %s\n' "$C_WARN" "$C_OFF" "$*"; }
bad()  { printf '  %sFAIL%s  %s\n' "$C_BAD" "$C_OFF" "$*"; fail=$((fail + 1)); }
head2() { printf '\n== %s ==\n' "$*"; }

# shellcheck disable=SC2086
dev() { $ADB shell "$@" 2>/dev/null | tr -d '\r'; }

head2 "device"
slot="$(dev getprop ro.boot.slot_suffix)"
locked="$(dev getprop ro.boot.flash.locked)"
model="$(dev getprop ro.product.device)"
echo "  slot: ${slot:-?}   bootloader locked: ${locked:-?}   ro.product.device: ${model:-?}"
[ "${locked:-1}" = "0" ] && ok "bootloader is unlocked" || warn "bootloader reports locked=${locked:-?}"

head2 "kernel vs. bundled modules"
kernel="$(dev uname -r)"
echo "  uname -r       : ${kernel:-?}"
echo "  /proc/version  : $(dev cat /proc/version)"

mod="$DEVICE_TREE/recovery/root/lib/modules/$(ls "$DEVICE_TREE/recovery/root/lib/modules" 2>/dev/null | grep -m1 '\.ko$')"
if [ -n "${mod:-}" ] && [ -f "$mod" ]; then
    modver="$(grep -a -o 'vermagic=[^ ]*' "$mod" | head -1 | cut -d= -f2-)"
    echo "  module vermagic: ${modver:-?}  ($(basename "$mod"))"
    if [ -n "$kernel" ] && [ "$kernel" = "$modver" ]; then
        ok "kernel and bundled modules match"
    else
        # MediaTek kernels are built from the vendor module tree separately from
        # the GKI kernel, so uname -r and the module vermagic often differ even
        # on a stock, working system. The modules are still loaded, so this is
        # informational; a real failure shows up as missing /proc/modules entries.
        warn "kernel '$kernel' != module vermagic '$modver'"
        loaded="$(dev 'grep -c "^leds_mtk " /proc/modules')"
        if [ "${loaded:-0}" -ge 1 ]; then
            ok "stock modules with this vermagic are loaded (leds_mtk present) - kernel accepts them"
        else
            warn "no leds_mtk module loaded; check dmesg for 'version magic' errors"
        fi
    fi
else
    warn "no .ko files in $DEVICE_TREE/recovery/root/lib/modules"
fi

head2 "backlight"
led=/sys/class/leds/lcd-backlight
maxb="$(dev cat "$led/max_brightness")"
curb="$(dev cat "$led/brightness")"
echo "  $led/max_brightness = ${maxb:-?}"
echo "  $led/brightness     = ${curb:-?}"
if [ -z "${maxb:-}" ]; then
    bad "$led does not exist - TW_BRIGHTNESS_PATH is wrong"
elif [ "$maxb" = "5119" ]; then
    ok "max_brightness is 5119 (TW_MAX_BRIGHTNESS := 5119 matches)"
elif [ "$maxb" = "2047" ]; then
    warn "max_brightness is 2047 (stock DTS value); set TW_MAX_BRIGHTNESS := 2047 in BoardConfig.mk"
else
    warn "max_brightness is $maxb; update TW_MAX_BRIGHTNESS (currently 5119)"
fi

head2 "block devices / USB-OTG"
echo "  whole disks (removable=1 means USB/SD):"
for d in $(dev 'ls /sys/block | grep "^sd"'); do
    printf '    %-5s size=%-12s removable=%s\n' "$d" \
        "$(dev "cat /sys/block/$d/size")" "$(dev "cat /sys/block/$d/removable")"
done
otg="$(dev 'ls /dev/block/sdd1 /dev/block/sde1 2>/dev/null' | tr '\n' ' ')"
if [ -n "${otg// /}" ]; then
    ok "found candidate OTG partition(s): $otg"
else
    warn "no /dev/block/sdd1 or /dev/block/sde1 present (plug a USB stick to test twrp.flags /usb_otg)"
fi
echo "  by-name entries: $(dev ls /dev/block/by-name | wc -l)"

head2 "battery"
batt=/sys/class/power_supply/battery
if [ "$(dev "[ -d $batt ] && echo yes")" = "yes" ]; then
    ok "$batt exists"
    echo "  capacity: $(dev cat "$batt/capacity")%  status: $(dev cat "$batt/status")"
else
    bad "$batt does not exist - TW_CUSTOM_BATTERY_PATH is wrong"
    echo "  available supplies: $(dev ls /sys/class/power_supply | tr '\n' ' ')"
fi

head2 "input devices (TW_INPUT_BLACKLIST)"
names="$(dev getevent -pl | sed -n 's/^ *name: *"\(.*\)"/\1/p')"
[ -n "${names:-}" ] || names="$(dev 'cat /proc/bus/input/devices' | sed -n 's/^N: Name="\(.*\)"/\1/p')"
printf '%s\n' "${names:-<none>}" | sed 's/^/    /'
if printf '%s\n' "${names:-}" | grep -qx 'tran-keys'; then
    ok "'tran-keys' exists, TW_INPUT_BLACKLIST will drop it"
else
    warn "'tran-keys' not found; check TW_INPUT_BLACKLIST in BoardConfig.mk"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
    echo "All hard checks passed."
else
    echo "$fail hard check(s) failed - fix those before flashing."
fi
exit "$((fail > 0))"
