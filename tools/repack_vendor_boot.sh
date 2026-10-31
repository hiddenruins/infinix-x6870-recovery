#!/usr/bin/env bash
#
# Repack the stock vendor_boot image with an OrangeFox recovery ramdisk,
# keeping the stock kernel-side data (DTB + platform ramdisk) untouched.
#
#   stock vendor_boot_a.img
#     fragment 0 (type 1, "" )        : vendor_ramdisk00  (29 MB, LZ4)  <- kept
#     fragment 1 (type 2, "recovery") : vendor_ramdisk01  (3 MB, cpio)  <- replaced
#     dtb                             : stock DTB (328 KB)             <- kept
#
# Usage:
#   tools/repack_vendor_boot.sh <recovery-ramdisk-or-vendor_boot.img> <out.img>
#
# The input can be:
#   * a directory                -> packed with mkbootfs/cpio, then compressed
#   * a raw cpio archive          -> compressed with lz4 legacy (-l -12)
#   * an lz4-compressed ramdisk   -> used as-is
#   * a full vendor_boot.img      -> its "recovery" fragment is extracted and used
#                                   (works for the stock 2-fragment layout and for
#                                   CI images that carry only the recovery fragment)
#
# Env:
#   STOCK_DIR    directory with the unpacked stock vendor_boot (default:
#                stock/unpacked/vendor_boot_a)
#   STOCK_IMG    stock vendor_boot image to unpack instead of using STOCK_DIR
#                (handy in CI, where the gitignored stock/ tree is absent)
#   SCRATCH_ROOT  where temporary work dirs are created (default: <project>/.scratch)
#
# Nothing outside this project directory is written to or deleted: the scratch
# directory defaults to <project>/.scratch and is removed on exit.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
STOCK_DIR="${STOCK_DIR:-}"
STOCK_IMG="${STOCK_IMG:-}"
SCRATCH_ROOT="${SCRATCH_ROOT:-$ROOT/.scratch}"
PART_SIZE=$((64 * 1024 * 1024))

die() { echo "error: $*" >&2; exit 1; }
info() { echo ":: $*"; }
magic() { od -An -tx1 -N"$2" "$1" | tr -d ' \n'; }

# Print the vendor_ramdisk<N> name whose type matches $2 (e.g. 0x1) in the
# `unpack_bootimg --format info` dump $1.
select_fragment() {
    awk -v want="$2" '
        /^[[:space:]]*vendor_ramdisk[0-9]+:[[:space:]]*\{/ { n = $1; sub(":", "", n) }
        n != "" && $0 ~ ("type: " want) { print n; exit }' "$1"
}

[ $# -eq 2 ] || die "usage: $0 <recovery-ramdisk-or-vendor_boot.img> <out.img>"
IN="$1"
OUT="$2"

command -v mkbootimg >/dev/null || die "mkbootimg not found"
command -v lz4 >/dev/null || die "lz4 not found"
command -v unpack_bootimg >/dev/null || die "unpack_bootimg not found"

[ -e "$IN" ] || die "missing input $IN"

mkdir -p "$SCRATCH_ROOT"
WORK="$(mktemp -d -p "$SCRATCH_ROOT" repack.XXXXXX)"
trap 'rm -rf "$WORK"; rmdir "$SCRATCH_ROOT" 2>/dev/null || true' EXIT

# --- 0. resolve the stock (kernel side) data ------------------------------
if [ -n "$STOCK_IMG" ]; then
    [ -f "$STOCK_IMG" ] || die "missing STOCK_IMG $STOCK_IMG"
    info "unpacking stock vendor_boot: $STOCK_IMG"
    unpack_bootimg --boot_img "$STOCK_IMG" --out "$WORK/stock" >/dev/null
    unpack_bootimg --boot_img "$STOCK_IMG" --format info > "$WORK/stock.info"

    # The platform ramdisk is the type 0x1 fragment. On a stock 2-fragment
    # image that is vendor_ramdisk00; fall back to it if types are not declared.
    PLAT="$(select_fragment "$WORK/stock.info" 0x1)"
    [ -n "$PLAT" ] || PLAT=vendor_ramdisk00
    [ -f "$WORK/stock/$PLAT" ] || die "stock image has no platform ramdisk ($PLAT)"

    mkdir -p "$WORK/stockdir"
    cp "$WORK/stock/$PLAT" "$WORK/stockdir/vendor_ramdisk00"
    [ -f "$WORK/stock/dtb" ] || die "stock image has no dtb"
    cp "$WORK/stock/dtb" "$WORK/stockdir/dtb"
    if [ -f "$WORK/stock/bootconfig" ]; then
        cp "$WORK/stock/bootconfig" "$WORK/stockdir/bootconfig"
    else
        : > "$WORK/stockdir/bootconfig"
    fi
    STOCK_DIR="$WORK/stockdir"
fi
STOCK_DIR="${STOCK_DIR:-$ROOT/stock/unpacked/vendor_boot_a}"

[ -f "$STOCK_DIR/vendor_ramdisk00" ] || die "missing $STOCK_DIR/vendor_ramdisk00"
[ -f "$STOCK_DIR/dtb" ]             || die "missing $STOCK_DIR/dtb"

# Size budget: the partition is 64 MiB and the stock platform ramdisk plus the
# DTB already use ~30 MB of it. Whatever is left has to hold the compressed
# recovery fragment, so print the arithmetic instead of only failing later.
# Layout: header+table padded to a page, then each blob 4 KiB-aligned.
align4k() { echo $(( (($1) + 4095) / 4096 * 4096 )); }
PLAT_SIZE=$(stat -c %s "$STOCK_DIR/vendor_ramdisk00")
DTB_SIZE=$(stat -c %s "$STOCK_DIR/dtb")
FIXED=$(( 4096 + $(align4k "$PLAT_SIZE") + $(align4k "$DTB_SIZE") ))
BUDGET=$(( PART_SIZE - FIXED ))
info "partition budget: $PART_SIZE bytes; header+align 4096, platform ramdisk $PLAT_SIZE, dtb $DTB_SIZE"
info "recovery fragment must stay under $BUDGET bytes (compressed, $(( BUDGET / 1024 )) KiB)"

# --- 1. get a recovery fragment -------------------------------------------
if [ -d "$IN" ]; then
    info "input is a directory, packing it into a ramdisk"
    if command -v mkbootfs >/dev/null; then
        mkbootfs "$IN" > "$WORK/recovery.cpio"
    else
        command -v cpio >/dev/null || die "need mkbootfs or cpio to pack a directory"
        ( cd "$IN" && find . -print0 \
            | cpio --null -o -H newc --owner root:root --quiet ) > "$WORK/recovery.cpio"
    fi
    FRAG="$WORK/recovery.cpio"
else
    FRAG="$IN"
fi

# vendor_boot magic is "VNDRBOOT" (56 4e 44 52 42 4f 4f 54)
if [ "$(magic "$FRAG" 8)" = "564e4452424f4f54" ]; then
    info "input is a vendor_boot image, locating its recovery fragment"
    unpack_bootimg --boot_img "$FRAG" --out "$WORK/vb" >/dev/null

    # Pick the fragment declared as type 0x2 (RECOVERY). The stock image puts it
    # second (vendor_ramdisk01); an image built with
    # BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT has only that one fragment,
    # so it shows up as vendor_ramdisk00.
    SEL="$(unpack_bootimg --boot_img "$FRAG" --format info | select_fragment /dev/stdin 0x2)"

    if [ -z "$SEL" ]; then
        set -- "$WORK"/vb/vendor_ramdisk*
        if [ $# -eq 1 ] && [ -f "$1" ]; then
            SEL="$(basename "$1")"
            info "no type-2 fragment declared; using the only fragment ($SEL)"
        else
            die "cannot identify the recovery fragment in $IN"
        fi
    fi

    FRAG="$WORK/vb/$SEL"
    [ -f "$FRAG" ] || die "declared recovery fragment $SEL is missing from $IN"
    info "recovery fragment: $SEL ($(stat -c %s "$FRAG") bytes)"

    if [ "$(md5sum < "$FRAG")" = "$(md5sum < "$STOCK_DIR/vendor_ramdisk00")" ]; then
        die "$IN only carries the stock platform ramdisk - no recovery is built into it"
    fi
fi

# --- 2. normalise compression ---------------------------------------------
if [ "$(magic "$FRAG" 4)" = "02214c18" ] || [ "$(magic "$FRAG" 4)" = "04224d18" ]; then
    info "ramdisk already lz4-compressed"
    RECOVERY_RD="$FRAG"
else
    info "compressing ramdisk with lz4 legacy (-l -12)"
    RECOVERY_RD="$WORK/recovery.ramdisk.lz4"
    lz4 -l -12 -f "$FRAG" "$RECOVERY_RD" >/dev/null
fi

[ -f "$STOCK_DIR/bootconfig" ] || : > "$STOCK_DIR/bootconfig"

# --- 3. repack -------------------------------------------------------------
info "repacking (stock dtb + stock platform ramdisk + new recovery fragment)"
mkbootimg \
    --header_version 4 \
    --pagesize 0x00001000 \
    --base 0x00000000 \
    --kernel_offset 0x40000000 \
    --ramdisk_offset 0x66f00000 \
    --tags_offset 0x47c80000 \
    --dtb_offset 0x47c80000 \
    --vendor_cmdline "bootopt=64S3,32N2,64N2" \
    --board '' \
    --dtb "$STOCK_DIR/dtb" \
    --vendor_bootconfig "$STOCK_DIR/bootconfig" \
    --ramdisk_type 1 --ramdisk_name '' \
    --vendor_ramdisk_fragment "$STOCK_DIR/vendor_ramdisk00" \
    --ramdisk_type 2 --ramdisk_name recovery \
    --vendor_ramdisk_fragment "$RECOVERY_RD" \
    --vendor_boot "$OUT"

# --- 4. sanity checks ------------------------------------------------------
SIZE=$(stat -c %s "$OUT")
info "output: $OUT ($SIZE bytes)"
info "recovery fragment: $(stat -c %s "$RECOVERY_RD") bytes compressed"
info "budget was $BUDGET bytes for that fragment, $PART_SIZE for the whole image"

if [ "$SIZE" -gt "$PART_SIZE" ]; then
    die "image is $SIZE bytes, $(( SIZE - PART_SIZE )) over the 64 MiB vendor_boot partition - trim the recovery ramdisk (TW_EXCLUDE_* / OF_* switches, or a smaller kernel module set)"
fi

info "verifying repacked image"
unpack_bootimg --boot_img "$OUT" --out "$WORK/check" >/dev/null
md5_sum() { md5sum "$1" | cut -d' ' -f1; }
[ "$(md5_sum "$WORK/check/dtb")" = "$(md5_sum "$STOCK_DIR/dtb")" ] \
    || die "DTB changed during repack"
[ "$(md5_sum "$WORK/check/vendor_ramdisk00")" = "$(md5_sum "$STOCK_DIR/vendor_ramdisk00")" ] \
    || die "platform ramdisk changed during repack"

info "OK - DTB and platform ramdisk are byte-identical to stock"
