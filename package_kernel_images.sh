#!/usr/bin/env bash
#
# Packages the prepared dist/ into boot/vendor_boot for Pixel 5 (redfin).
#
# This script deliberately does NOT flash the phone. It only creates new,
# verified images in its own directory and does not reuse old
# boot_unpacked/, vendor_boot_unpacked/, or ramdisk_extracted/ directories.

set -Eeuo pipefail
IFS=$'\n\t'

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  ./package_kernel_images.sh [options]

Options:
  --stock-images-dir PATH    directory containing factory boot.img and vendor_boot.img
                             (default: ./stock-images)
  --dist PATH                build directory (default: out/android-msm-pixel-4.19/dist)
  --output-dir PATH          new output directory (default: repacked-images/redbull.XXXXXX)
  --keep-workdir             retain the temporary directory after success
  -h, --help                 show this help

Result:
  The new directory contains boot.img, vendor_boot.img, checksums.txt,
  proof.txt, and saved mkbootimg arguments for stock and final images.
  The script never overwrites an old extraction directory or runs fastboot.
EOF
}

# A repo(1) checkout has its manifest in the parent directory but is not
# itself a Git worktree. Therefore, locate it by tree structure instead of
# using `git rev-parse --show-toplevel`.
find_checkout_root() {
    local candidate parent
    candidate="$(pwd -P)"
    while :; do
        if [[ -d "$candidate/tools/mkbootimg" && -d "$candidate/private/msm-google" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
        parent="$(dirname "$candidate")"
        [[ "$parent" != "$candidate" ]] || return 1
        candidate="$parent"
    done
}

ROOT="$(find_checkout_root)" ||
    die 'run this script from the redbull-kernel checkout.'

STOCK_IMAGES_DIR="$ROOT/stock-images"
STOCK_BOOT="$STOCK_IMAGES_DIR/boot.img"
STOCK_VENDOR_BOOT="$STOCK_IMAGES_DIR/vendor_boot.img"
DIST="$ROOT/out/android-msm-pixel-4.19/dist"
OUTPUT_DIR=''
KEEP_WORKDIR=0

while (($#)); do
    case "$1" in
        --stock-images-dir)
            (($# >= 2)) || die '--stock-images-dir requires a path.'
            STOCK_IMAGES_DIR="$2"
            STOCK_BOOT="$STOCK_IMAGES_DIR/boot.img"
            STOCK_VENDOR_BOOT="$STOCK_IMAGES_DIR/vendor_boot.img"
            shift 2
            ;;
        --dist)
            (($# >= 2)) || die '--dist requires a path.'
            DIST="$2"
            shift 2
            ;;
        --output-dir)
            (($# >= 2)) || die '--output-dir requires a path.'
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --keep-workdir)
            KEEP_WORKDIR=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

for command in python3 lz4 cpio cmp find sort sha256sum stat mktemp; do
    command -v "$command" >/dev/null || die "required command not found: $command"
done

UNPACK="$ROOT/tools/mkbootimg/unpack_bootimg.py"
MKBOOTIMG="$ROOT/tools/mkbootimg/mkbootimg.py"
AVBTOOL="$ROOT/prebuilts/kernel-build-tools/linux-x86/bin/avbtool"
AVB_KEY="$ROOT/prebuilts/kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem"

for file in "$STOCK_BOOT" "$STOCK_VENDOR_BOOT" "$DIST/Image.lz4-dtb" \
            "$UNPACK" "$MKBOOTIMG" "$AVBTOOL" "$AVB_KEY"; do
    [[ -f "$file" ]] || die "required file not found: $file"
done

[[ -d "$DIST" ]] || die "dist directory not found: $DIST"

mkdir -p "$ROOT/repacked-images"
if [[ -n "$OUTPUT_DIR" ]]; then
    [[ ! -e "$OUTPUT_DIR" ]] || die "output directory already exists: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
else
    OUTPUT_DIR="$(mktemp -d "$ROOT/repacked-images/redbull.XXXXXX")"
fi
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/redbull-repack.XXXXXX")"

cleanup() {
    local status=$?
    if ((KEEP_WORKDIR)) || ((status != 0)); then
        echo "Temporary directory preserved: $WORKDIR" >&2
    else
        rm -rf -- "$WORKDIR"
    fi
    exit "$status"
}
trap cleanup EXIT

BOOT_UNPACKED="$WORKDIR/stock-boot"
VENDOR_UNPACKED="$WORKDIR/stock-vendor-boot"
STOCK_RAMDISK="$WORKDIR/stock-vendor-ramdisk"
FINAL_BOOT_UNPACKED="$WORKDIR/final-boot"
FINAL_VENDOR_UNPACKED="$WORKDIR/final-vendor-boot"
FINAL_RAMDISK="$WORKDIR/final-vendor-ramdisk"

format_mkbootimg() {
    python3 "$UNPACK" --boot_img "$1" --format mkbootimg
}

# Do not use eval: cmdline is a single argument containing spaces.
split_mkbootimg_args() {
    python3 -c 'import shlex, sys
for value in shlex.split(sys.stdin.read()):
    sys.stdout.buffer.write(value.encode() + b"\0")'
}

write_tree_manifest() {
    # Type, relative name, and symlink target. Metadata such as mtime is
    # intentionally not compared because cpio can normalize it.
    find "$1" -printf '%y\t%P\t%l\n' | LC_ALL=C sort > "$2"
}

verify_mkbootimg_parameters() {
    local stock_args=$1
    local final_args=$2
    local image_kind=$3
    python3 - "$stock_args" "$final_args" "$image_kind" <<'PY'
import shlex
import sys

stock_path, final_path, image_kind = sys.argv[1:]
ignored = {
    "--kernel", "--ramdisk", "--dtb", "--vendor_ramdisk", "--output", "--vendor_boot"
}

def pairs(path):
    values = shlex.split(open(path, encoding="utf-8").read())
    if len(values) % 2:
        raise SystemExit(f"{path}: odd mkbootimg argument count")
    result = {}
    for key, value in zip(values[::2], values[1::2]):
        if not key.startswith("--"):
            raise SystemExit(f"{path}: unexpected argument {key!r}")
        result[key] = value
    return result

stock = pairs(stock_path)
final = pairs(final_path)
for key in sorted((set(stock) | set(final)) - ignored):
    if stock.get(key) != final.get(key):
        raise SystemExit(
            f"{image_kind}: parameter {key} differs: "
            f"stock={stock.get(key)!r}, final={final.get(key)!r}"
        )
print(f"OK: {image_kind}: all header parameters and cmdline match stock")
PY
}

echo '== 1/7: Checking current dist =='
find "$DIST" -maxdepth 1 -type f -name '*.ko' -print -quit | grep -q . ||
    die "$DIST contains no .ko modules"

echo '== 2/7: Extracting only into a new mktemp directory =='
python3 "$UNPACK" --boot_img "$STOCK_BOOT" --out "$BOOT_UNPACKED"
python3 "$UNPACK" --boot_img "$STOCK_VENDOR_BOOT" --out "$VENDOR_UNPACKED"
[[ -f "$BOOT_UNPACKED/ramdisk" ]] || die 'stock boot has no ramdisk.'
[[ -f "$VENDOR_UNPACKED/vendor_ramdisk" ]] || die 'stock vendor_boot has no vendor_ramdisk.'
[[ -f "$VENDOR_UNPACKED/dtb" ]] || die 'stock vendor_boot has no dtb.'

mkdir -p "$STOCK_RAMDISK"
lz4 -d -c "$VENDOR_UNPACKED/vendor_ramdisk" | (cd "$STOCK_RAMDISK" && cpio -idm --quiet)
[[ -d "$STOCK_RAMDISK/lib/modules" ]] || die 'stock vendor ramdisk has no lib/modules.'

echo '== 3/7: Replacing exactly the modules present in stock vendor ramdisk =='
mapfile -d '' -t STOCK_MODULES < <(
    find "$STOCK_RAMDISK/lib/modules" -maxdepth 1 -type f -name '*.ko' -printf '%f\0' | LC_ALL=C sort -z
)
((${#STOCK_MODULES[@]} > 0)) || die 'no .ko modules found in stock vendor ramdisk.'

cp -a "$STOCK_RAMDISK" "$WORKDIR/new-vendor-ramdisk"
NEW_RAMDISK="$WORKDIR/new-vendor-ramdisk"
MODULES_CHANGED_FROM_STOCK=0
MODULES_IDENTICAL_TO_STOCK=0
: > "$OUTPUT_DIR/modules-different-from-stock.txt"
: > "$OUTPUT_DIR/modules-identical-to-stock.txt"
for module in "${STOCK_MODULES[@]}"; do
    [[ -f "$DIST/$module" ]] || die "required stock module absent from dist: $module"
    if cmp -s "$STOCK_RAMDISK/lib/modules/$module" "$DIST/$module"; then
        printf '%s\n' "$module" >> "$OUTPUT_DIR/modules-identical-to-stock.txt"
        ((MODULES_IDENTICAL_TO_STOCK += 1))
    else
        printf '%s\n' "$module" >> "$OUTPUT_DIR/modules-different-from-stock.txt"
        ((MODULES_CHANGED_FROM_STOCK += 1))
    fi
    cp -f -- "$DIST/$module" "$NEW_RAMDISK/lib/modules/$module"
done

echo "Replaced modules: ${#STOCK_MODULES[@]}"
echo "Different from stock: $MODULES_CHANGED_FROM_STOCK; identical: $MODULES_IDENTICAL_TO_STOCK"
NEW_VENDOR_RAMDISK="$WORKDIR/vendor_ramdisk.new"
(
    cd "$NEW_RAMDISK"
    find . -print0 | cpio --null -o -H newc --quiet | \
        lz4 -l -12 --favor-decSpeed -f - "$NEW_VENDOR_RAMDISK"
)
lz4 -d -c "$NEW_VENDOR_RAMDISK" | cpio -it --quiet >/dev/null

echo '== 4/7: Reading exact stock mkbootimg parameters =='
format_mkbootimg "$STOCK_BOOT" | tee "$OUTPUT_DIR/stock-boot-mkbootimg.args"
format_mkbootimg "$STOCK_VENDOR_BOOT" | tee "$OUTPUT_DIR/stock-vendor_boot-mkbootimg.args"

mapfile -d '' -t BOOT_ARGS < <(split_mkbootimg_args < "$OUTPUT_DIR/stock-boot-mkbootimg.args")
mapfile -d '' -t VENDOR_ARGS < <(split_mkbootimg_args < "$OUTPUT_DIR/stock-vendor_boot-mkbootimg.args")

# unpack_bootimg.py emits '--option value'. Retain all stock parameters except
# segment paths, then add the new paths below.
filtered_args=()
for ((i = 0; i < ${#BOOT_ARGS[@]}; i += 2)); do
    case "${BOOT_ARGS[i]}" in
        --kernel|--ramdisk|--output) ;;
        *) filtered_args+=("${BOOT_ARGS[i]}" "${BOOT_ARGS[i + 1]}") ;;
    esac
done
filtered_args+=(--kernel "$DIST/Image.lz4-dtb" --ramdisk "$BOOT_UNPACKED/ramdisk" --output "$OUTPUT_DIR/boot.img")
python3 "$MKBOOTIMG" "${filtered_args[@]}"

filtered_args=()
for ((i = 0; i < ${#VENDOR_ARGS[@]}; i += 2)); do
    case "${VENDOR_ARGS[i]}" in
        --dtb|--vendor_ramdisk|--vendor_boot|--output) ;;
        *) filtered_args+=("${VENDOR_ARGS[i]}" "${VENDOR_ARGS[i + 1]}") ;;
    esac
done
filtered_args+=(--dtb "$VENDOR_UNPACKED/dtb" --vendor_ramdisk "$NEW_VENDOR_RAMDISK" --vendor_boot "$OUTPUT_DIR/vendor_boot.img")
python3 "$MKBOOTIMG" "${filtered_args[@]}"

echo '== 5/7: AVB signing with factory image sizes =='
BOOT_PARTITION_SIZE="$(stat -c '%s' "$STOCK_BOOT")"
VENDOR_BOOT_PARTITION_SIZE="$(stat -c '%s' "$STOCK_VENDOR_BOOT")"
"$AVBTOOL" add_hash_footer --image "$OUTPUT_DIR/boot.img" \
    --partition_name boot --partition_size "$BOOT_PARTITION_SIZE" \
    --key "$AVB_KEY" --algorithm SHA256_RSA2048
"$AVBTOOL" add_hash_footer --image "$OUTPUT_DIR/vendor_boot.img" \
    --partition_name vendor_boot --partition_size "$VENDOR_BOOT_PARTITION_SIZE" \
    --key "$AVB_KEY" --algorithm SHA256_RSA2048

"$AVBTOOL" info_image --image "$OUTPUT_DIR/boot.img" > "$OUTPUT_DIR/boot-avb-info.txt"
"$AVBTOOL" info_image --image "$OUTPUT_DIR/vendor_boot.img" > "$OUTPUT_DIR/vendor_boot-avb-info.txt"

echo '== 6/7: Extracting final images and performing byte-for-byte checks =='
python3 "$UNPACK" --boot_img "$OUTPUT_DIR/boot.img" --out "$FINAL_BOOT_UNPACKED"
python3 "$UNPACK" --boot_img "$OUTPUT_DIR/vendor_boot.img" --out "$FINAL_VENDOR_UNPACKED"
cmp -s "$FINAL_BOOT_UNPACKED/kernel" "$DIST/Image.lz4-dtb" ||
    die 'kernel in final boot.img does not match current dist/Image.lz4-dtb.'
cmp -s "$FINAL_BOOT_UNPACKED/ramdisk" "$BOOT_UNPACKED/ramdisk" ||
    die 'ramdisk in final boot.img differs from stock ramdisk.'
cmp -s "$FINAL_VENDOR_UNPACKED/dtb" "$VENDOR_UNPACKED/dtb" ||
    die 'dtb in final vendor_boot.img differs from stock dtb.'

mkdir -p "$FINAL_RAMDISK"
lz4 -d -c "$FINAL_VENDOR_UNPACKED/vendor_ramdisk" | (cd "$FINAL_RAMDISK" && cpio -idm --quiet)
write_tree_manifest "$STOCK_RAMDISK" "$WORKDIR/stock-tree.txt"
write_tree_manifest "$FINAL_RAMDISK" "$WORKDIR/final-tree.txt"
cmp -s "$WORKDIR/stock-tree.txt" "$WORKDIR/final-tree.txt" ||
    die 'file/symlink layout in final vendor ramdisk differs from stock.'

while IFS= read -r -d '' stock_file; do
    relative="${stock_file#"$STOCK_RAMDISK"/}"
    [[ "$relative" == lib/modules/*.ko ]] && continue
    cmp -s "$stock_file" "$FINAL_RAMDISK/$relative" ||
        die "unexpected non-module change in vendor ramdisk: $relative"
done < <(find "$STOCK_RAMDISK" -type f -print0)

for module in "${STOCK_MODULES[@]}"; do
    cmp -s "$FINAL_RAMDISK/lib/modules/$module" "$DIST/$module" ||
        die "module in final vendor_boot does not match dist: $module"
done

format_mkbootimg "$OUTPUT_DIR/boot.img" | tee "$OUTPUT_DIR/final-boot-mkbootimg.args"
format_mkbootimg "$OUTPUT_DIR/vendor_boot.img" | tee "$OUTPUT_DIR/final-vendor_boot-mkbootimg.args"
verify_mkbootimg_parameters "$OUTPUT_DIR/stock-boot-mkbootimg.args" \
    "$OUTPUT_DIR/final-boot-mkbootimg.args" 'boot.img'
verify_mkbootimg_parameters "$OUTPUT_DIR/stock-vendor_boot-mkbootimg.args" \
    "$OUTPUT_DIR/final-vendor_boot-mkbootimg.args" 'vendor_boot.img'

echo '== 7/7: Input evidence =='
{
    echo "created_utc=$(date -u +%FT%TZ)"
    echo "git_head=$(git -C "$ROOT/private/msm-google" rev-parse HEAD 2>/dev/null || echo unavailable)"
    echo 'git_status_porcelain:'
    git -C "$ROOT/private/msm-google" status --porcelain -uno 2>/dev/null || true
    echo 'stock_and_output_sha256:'
    sha256sum "$STOCK_BOOT" "$STOCK_VENDOR_BOOT" "$DIST/Image.lz4-dtb" \
        "$OUTPUT_DIR/boot.img" "$OUTPUT_DIR/vendor_boot.img"
    echo "stock_modules_replaced=${#STOCK_MODULES[@]}"
    echo "stock_modules_different_from_current_dist=$MODULES_CHANGED_FROM_STOCK"
    echo "stock_modules_identical_to_current_dist=$MODULES_IDENTICAL_TO_STOCK"
    echo 'all_final_stock_modules_match_current_dist=yes'
    echo 'boot_kernel_matches_current_dist=yes'
    echo 'boot_ramdisk_matches_stock=yes'
    echo 'vendor_dtb_matches_stock=yes'
    echo 'vendor_non_module_files_match_stock=yes'
    echo 'mkbootimg_parameters_and_cmdlines_match_stock=yes'
} | tee "$OUTPUT_DIR/proof.txt"

sha256sum "$OUTPUT_DIR/boot.img" "$OUTPUT_DIR/vendor_boot.img" > "$OUTPUT_DIR/checksums.txt"

echo
echo 'DONE: images were built and verified; no flashing was performed.'
echo "Result: $OUTPUT_DIR"
echo "  $OUTPUT_DIR/boot.img"
echo "  $OUTPUT_DIR/vendor_boot.img"
echo "  $OUTPUT_DIR/proof.txt"
