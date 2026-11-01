#!/usr/bin/env bash
#
# Turn the OrangeFox installer zip produced by the build into a zip that can be
# flashed *from an already-working OrangeFox recovery* on this device.
#
# Why this is needed: the build puts an LZ4-compressed recovery fragment
# (42,096,904 B) in the zip. The vendor_boot installer branch dumps the current
# image, swaps in that fragment and repacks it. With the stock platform ramdisk
# (29,200,444 B) that is ~71.6 MB, which does not fit the 64 MiB partition, and
# the upstream branch has no size check and writes *both* slots.
#
# This script:
#   * extracts the recovery fragment from the built vendor_boot image and
#     recompresses it with zstd -19 (29,068,168 B) - the stock kernel has
#     CONFIG_RD_ZSTD=y and no LZ4 compression can reach that size;
#   * replaces vendor_ramdisk_recovery.cpio in the zip with that fragment;
#   * patches update-binary so the repack is size-checked against the real
#     partition and written only to the slot recovery is running from, leaving
#     the other slot's vendor_boot untouched as a fallback;
#   * re-signs the zip with SignApk when the build tree is available, or strips
#     the now-invalid signature so the zip is clearly unsigned.
#
# The stock platform ramdisk is never included: the installer reuses the one
# already on the device, so no stock blobs are published.
#
# Usage:
#   tools/prepare_update_zip.sh <vendor_boot.img> <OrangeFox.zip> <out-update.zip> [--fox-root DIR]
#
# --fox-root points at the OrangeFox source tree (the one with out/ and build/);
# it is only used to find signapk.jar and the test keys.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }
info() { echo ":: $*"; }

[ $# -ge 3 ] || die "usage: $0 <vendor_boot.img> <OrangeFox.zip> <out-update.zip> [--fox-root DIR]"
IMAGE="$1"
ZIP="$2"
OUT="$3"
shift 3
FOX_ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --fox-root) FOX_ROOT="$2"; shift 2 ;;
        --fox-root=*) FOX_ROOT="${1#*=}"; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -f "$IMAGE" ] || die "missing image: $IMAGE"
[ -f "$ZIP" ]   || die "missing zip: $ZIP"
[ -n "$OUT" ]   || die "missing output path"

# Resolve to absolute paths now: the script chdirs into the extracted zip later.
case "$IMAGE" in /*) ;; *) IMAGE="$PWD/$IMAGE" ;; esac
case "$ZIP"   in /*) ;; *) ZIP="$PWD/$ZIP" ;; esac
case "$OUT"   in /*) ;; *) OUT="$PWD/$OUT" ;; esac

if [ -n "$FOX_ROOT" ]; then
    export PATH="$FOX_ROOT/out/host/linux-x86/bin:$PATH"
fi
command -v zstd >/dev/null || die "zstd not found"
command -v unzip >/dev/null || die "unzip not found"
command -v zip >/dev/null || die "zip not found"
command -v python3 >/dev/null || die "python3 not found"

SCRATCH="${SCRATCH_ROOT:-$ROOT/.scratch}"
mkdir -p "$SCRATCH"
WORK="$(mktemp -d -p "$SCRATCH" updatezip.XXXXXX)"
trap 'rm -rf "$WORK"; rmdir "$SCRATCH" 2>/dev/null || true' EXIT

magic() { od -An -tx1 -N"$2" "$1" | tr -d ' \n'; }

# --- 1. recovery fragment out of the built image ---------------------------
# The vendor_boot header is parsed here directly instead of with unpack_bootimg:
# CI builds mkbootimg but not its unpack counterpart, and the layout is simple.
info "parsing $IMAGE"
mkdir -p "$WORK/img"
FRAG="$WORK/img/vendor_ramdisk_recovery"
python3 - "$IMAGE" "$FRAG" <<'PY'
import struct
import sys

src, out = sys.argv[1], sys.argv[2]
with open(src, "rb") as fh:
    data = fh.read()

if len(data) < 2128 or data[:8] != b"VNDRBOOT":
    sys.exit(f"{src}: not a vendor_boot image")

header_version, page_size = struct.unpack_from("<II", data, 8)
if page_size == 0 or page_size & (page_size - 1):
    sys.exit(f"{src}: bad page size {page_size}")

# header_size is at 2096, vendor_ramdisk_size at 24 (vendor_boot_img_hdr_v3/v4)
header_size = struct.unpack_from("<I", data, 2096)[0]
vendor_ramdisk_size = struct.unpack_from("<I", data, 24)[0]
base = (header_size + page_size - 1) // page_size * page_size

if header_version == 3:
    if base + vendor_ramdisk_size > len(data):
        sys.exit(f"{src}: truncated vendor ramdisk")
    frag = data[base:base + vendor_ramdisk_size]
    print("fragment: header v3, single vendor ramdisk")
elif header_version == 4:
    table_size, entry_num, entry_size = struct.unpack_from("<III", data, 2112)
    dtb_size = struct.unpack_from("<I", data, 2100)[0]
    # Layout: header, vendor ramdisk, dtb, vendor ramdisk table, bootconfig.
    dtb_off = (base + vendor_ramdisk_size + page_size - 1) // page_size * page_size
    table_off = (dtb_off + dtb_size + page_size - 1) // page_size * page_size
    if entry_size < 108:
        sys.exit(f"{src}: bad vendor_ramdisk_table_entry_size {entry_size}")
    if table_off + table_size > len(data):
        sys.exit(f"{src}: truncated vendor ramdisk table")

    entries = []
    for i in range(entry_num):
        off = table_off + i * entry_size
        r_size, r_off, r_type = struct.unpack_from("<III", data, off)
        name = data[off + 12:off + 44].split(b"\0", 1)[0].decode("ascii", "replace")
        entries.append((r_type, name, r_off, r_size))
        print(f"fragment: type=0x{r_type:x} name={name!r} size={r_size}")

    # type 0x2 is VENDOR_RAMDISK_TYPE_RECOVERY
    chosen = next((e for e in entries if e[0] == 2), None)
    if chosen is None:
        if len(entries) == 1:
            chosen = entries[0]
            print("fragment: no type-0x2 entry, using the only fragment")
        else:
            sys.exit(f"{src}: no recovery (type 0x2) fragment")

    start = base + chosen[2]
    if start + chosen[3] > len(data):
        sys.exit(f"{src}: recovery fragment is out of bounds")
    frag = data[start:start + chosen[3]]
else:
    sys.exit(f"{src}: unsupported vendor_boot header version {header_version}")

with open(out, "wb") as fh:
    fh.write(frag)
print(f"fragment: extracted {len(frag)} bytes")
PY
[ -s "$FRAG" ] || die "could not extract the recovery fragment from $IMAGE"
info "recovery fragment: $(stat -c %s "$FRAG") bytes"

case "$(magic "$FRAG" 4)" in
    02214c18|04224d18) FRAG_FMT=lz4 ;;
    28b52ffd)          FRAG_FMT=zstd ;;
    1f8b*)             FRAG_FMT=gzip ;;
    303730373031|303730373032|303730373037) FRAG_FMT=cpio ;;
    *) die "unknown recovery fragment format (magic $(magic "$FRAG" 4))" ;;
esac
info "recovery fragment format: $FRAG_FMT"

decompress_to() {
    case "$1" in
        lz4)  lz4 -d -c "$2" > "$3" ;;
        zstd) zstd -d -q -c "$2" > "$3" ;;
        gzip) gzip -d -c "$2" > "$3" ;;
        cpio) cp "$2" "$3" ;;
        *)    return 1 ;;
    esac
}

if [ "$FRAG_FMT" = zstd ]; then
    ZST="$FRAG"
else
    command -v lz4 >/dev/null || [ "$FRAG_FMT" != lz4 ] || die "lz4 not found"
    RAW="$WORK/recovery.cpio"
    decompress_to "$FRAG_FMT" "$FRAG" "$RAW" || die "cannot decompress $FRAG"
    ZST="$WORK/recovery.cpio.zst"
    info "recompressing with zstd -19 -T1"
    zstd -19 -T1 -q -c "$RAW" > "$ZST"
fi

# Sanity: the fragment must really be an OrangeFox recovery ramdisk.
DEC="$WORK/frag.check.cpio"
zstd -d -q -c "$ZST" > "$DEC"
rm -rf "$WORK/fragcheck" && mkdir "$WORK/fragcheck"
( cd "$WORK/fragcheck" && cpio -idm --quiet < "$DEC" ) 2>/dev/null || die "zstd fragment is not a cpio archive"
for f in system/bin/recovery system/bin/twrp; do
    [ -e "$WORK/fragcheck/$f" ] || die "fragment does not contain $f - wrong image?"
done
rm -rf "$WORK/fragcheck" "$DEC"
info "zstd fragment: $(stat -c %s "$ZST") bytes"

# --- 2. modify the OrangeFox zip ------------------------------------------
info "extracting $ZIP"
mkdir -p "$WORK/zip"
unzip -q "$ZIP" -d "$WORK/zip"

cd "$WORK/zip"
if [ -f vendor_ramdisk_recovery.cpio ]; then
    RAM_NAME=vendor_ramdisk_recovery.cpio
elif [ -f ramdisk.cpio ]; then
    RAM_NAME=ramdisk.cpio
else
    die "the zip has neither vendor_ramdisk_recovery.cpio nor ramdisk.cpio - upstream layout changed"
fi
cp -f "$ZST" "$RAM_NAME"
info "replaced $RAM_NAME with the zstd fragment"

# --- 3. make the installer size-check and keep the spare slot --------------
python3 - "$WORK/zip/META-INF/com/google/android/update-binary" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
    src = fh.read()

needle = "# flash both slots"
count = src.count(needle)
if count != 1:
    sys.exit(f"update-binary: expected exactly one {needle!r} block, found {count}")

block = '''	   # x6870: refuse a repacked image that does not fit, and write only the
	   # slot recovery is running from. The other slot keeps its current
	   # vendor_boot, so a bad update is one "fastboot --set-active" away from
	   # a working system.
	   [ "$($GETPROP "orangefox.vendor_boot.recovery")" = "true" ] || abort "- This is not a vendor_boot OrangeFox recovery (orangefox.vendor_boot.recovery != true). Refusing to repack the installed image. Quitting."
	   scan_slot=$($GETPROP "ro.boot.slot_suffix")
	   [ -n "$scan_slot" ] || abort "- Cannot determine the current slot (ro.boot.slot_suffix is empty). Quitting."
	   part_bytes=$(blockdev --getsize64 "$target$scan_slot")
	   img_bytes=$(FileSize "new_recovery.img")
	   ui_print "- Repacked image: $img_bytes bytes; $target$scan_slot: $part_bytes bytes"
	   [ -n "$part_bytes" -a "$part_bytes" != "0" ] || abort "- Cannot read the size of $target$scan_slot. Quitting."
	   [ "$img_bytes" -le "$part_bytes" ] || abort "- The repacked image ($img_bytes bytes) does not fit $target$scan_slot ($part_bytes bytes). Nothing was written. Quitting."
	   for slot in "$scan_slot"; do
		ui_print "- Installing OrangeFox to $name$slot..."
		PART=$target"$slot"
		blockdev --setrw $PART
		package_extract_file "new_recovery.img" "$PART"
	   done
'''

pattern = re.compile(r"(?m)^[ \t]*# flash both slots\r?\n(?:[^\n]*\r?\n)*?[ \t]*done\r?\n")
src, n = pattern.subn(lambda _m: block, src, count=1)
if n != 1:
    sys.exit("update-binary: could not patch the vendor_boot flash loop")

with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
    fh.write(src)
print("patched update-binary: size check + current-slot-only write")
PY

# --- 4. rezip --------------------------------------------------------------
cd "$WORK/zip"
# The original META-INF signature no longer matches the modified contents.
# Drop it before zipping; signapk (below) adds a fresh one when available.
# TWRP/OrangeFox do not verify zip signatures by default, and a stale CERT.RSA
# only makes debugging harder.
rm -f META-INF/MANIFEST.MF META-INF/CERT.SF META-INF/CERT.RSA META-INF/com/android/otacert

rm -f "$WORK/modified.zip"
# -X: no extra attributes; -9: maximum deflate. The original zip is a normal
# (deflated) update zip, so this keeps the size sane.
zip -q -r -9 -X "$WORK/modified.zip" . -x '.*'

SIGNED=0
if [ -n "$FOX_ROOT" ]; then
    SIGNAPK=""
    KEYS=""
    for c in "$FOX_ROOT/out/host/linux-x86/framework/signapk.jar" \
             "$FOX_ROOT/out/host/linux-x86/framework/signapk/signapk.jar"; do
        [ -f "$c" ] && SIGNAPK="$c" && break
    done
    for d in "$FOX_ROOT/build/make/target/product/security" \
             "$FOX_ROOT/build/target/product/security"; do
        if [ -f "$d/testkey.x509.pem" ] && [ -f "$d/testkey.pk8" ]; then
            KEYS="$d"; break
        fi
    done
    if [ -n "$SIGNAPK" ] && [ -n "$KEYS" ] && command -v java >/dev/null; then
        info "signing with SignApk ($KEYS/testkey)"
        java -jar "$SIGNAPK" "$KEYS/testkey.x509.pem" "$KEYS/testkey.pk8" \
            "$WORK/modified.zip" "$WORK/signed.zip" >/dev/null 2>&1 \
            && mv -f "$WORK/signed.zip" "$WORK/modified.zip" \
            && SIGNED=1
        [ "$SIGNED" = 1 ] || info "warning: SignApk failed; leaving the zip unsigned"
    fi
fi

if [ "$SIGNED" != 1 ]; then
    info "warning: output zip is unsigned (no SignApk in the build tree)"
fi

# --- 5. verify and publish -------------------------------------------------
unzip -p "$WORK/modified.zip" "$RAM_NAME" > "$WORK/check.frag"
[ "$(magic "$WORK/check.frag" 4)" = "28b52ffd" ] || die "output zip fragment is not zstd"
unzip -p "$WORK/modified.zip" META-INF/com/google/android/update-binary \
    | grep -q 'x6870: refuse a repacked image' \
    || die "output zip does not contain the patched installer"
unzip -tq "$WORK/modified.zip" >/dev/null || die "output zip is corrupt"

mkdir -p "$(dirname "$OUT")"
mv -f "$WORK/modified.zip" "$OUT"
info "OK - $OUT ($(stat -c %s "$OUT") bytes, $(md5sum "$OUT" | cut -d' ' -f1))"
info "flash it from an already-working OrangeFox (Install -> select the zip), never from Android"
