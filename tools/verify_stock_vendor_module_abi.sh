#!/usr/bin/env bash
# Verify Module.symvers against stock Pixel 5 vendor modules.
# This reads vendor.img only; it never modifies the image.
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "ERROR: $*" >&2; exit 1; }
ROOT="$(pwd -P)"
while [[ ! -d "$ROOT/tools/mkbootimg" || ! -d "$ROOT/private/msm-google" ]]; do
  parent="$(dirname "$ROOT")"; [[ "$parent" != "$ROOT" ]] || die 'run from the redbull-kernel checkout.'; ROOT="$parent"
done
DIST="$ROOT/out/android-msm-pixel-4.19/dist"
VENDOR_IMG=''; SYMVERS=''; REPORT=''
usage() { echo "Usage: $0 --stock-vendor-img PATH [--dist PATH] [--report PATH] [--kernel-module-symvers PATH]"; }
while (($#)); do
  case "$1" in
    --stock-vendor-img) (($# >= 2)) || die 'missing path after --stock-vendor-img'; VENDOR_IMG="$2"; shift 2 ;;
    --dist) (($# >= 2)) || die 'missing path after --dist'; DIST="$2"; shift 2 ;;
    --report) (($# >= 2)) || die 'missing path after --report'; REPORT="$2"; shift 2 ;;
    --kernel-module-symvers) (($# >= 2)) || die 'missing path after --kernel-module-symvers'; SYMVERS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n "$VENDOR_IMG" ]] || { usage >&2; die '--stock-vendor-img is required.'; }
[[ -f "$VENDOR_IMG" ]] || die "vendor image not found: $VENDOR_IMG"
SYMVERS="${SYMVERS:-$(dirname "$DIST")/private/msm-google/Module.symvers}"
[[ -f "$SYMVERS" ]] || die "kernel Module.symvers not found: $SYMVERS"
command -v debugfs >/dev/null || die 'debugfs is required (e2fsprogs).'
command -v modprobe >/dev/null || die 'modprobe is required.'
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/redfin-vendor-abi.XXXXXX")"
trap 'rm -rf -- "$WORKDIR"' EXIT
MODULES_LOAD="$WORKDIR/modules.load"
debugfs -R "dump -p /lib/modules/modules.load $MODULES_LOAD" "$VENDOR_IMG" >/dev/null 2>&1 || true
[[ -s "$MODULES_LOAD" ]] || die 'vendor.img has no /lib/modules/modules.load.'
declare -A KERNEL_CRC
while read -r crc symbol _; do [[ -n "$symbol" ]] && KERNEL_CRC["$symbol"]="$crc"; done < "$SYMVERS"
REPORT="${REPORT:-$DIST/stock-vendor-module-abi-kmi-full-report.txt}"
mkdir -p "$(dirname "$REPORT")"
{
  echo "kernel_module_symvers=$SYMVERS"
  echo "stock_vendor_img=$VENDOR_IMG"
  echo $'module\tsymbol\tstock_crc\tkernel_crc'
} > "$REPORT"
checked=0; mismatches=0; missing=0
while IFS= read -r module; do
  module="${module%%#*}"; module="${module//[[:space:]]/}"; [[ -n "$module" ]] || continue
  module="${module##*/}"; [[ "$module" == *.ko ]] || continue
  extracted="$WORKDIR/$module"
  debugfs -R "dump -p /lib/modules/$module $extracted" "$VENDOR_IMG" >/dev/null 2>&1 || true
  [[ -f "$extracted" ]] || die "cannot extract /lib/modules/$module from vendor.img."
  ((checked += 1))
  while read -r crc symbol; do
    [[ -n "$symbol" ]] || continue
    kernel_crc="${KERNEL_CRC[$symbol]:-MISSING}"
    if [[ "$kernel_crc" == MISSING ]]; then
      printf '%s\t%s\t%s\t%s\n' "$module" "$symbol" "$crc" "$kernel_crc" >> "$REPORT"; ((missing += 1))
    elif [[ "$kernel_crc" != "$crc" ]]; then
      printf '%s\t%s\t%s\t%s\n' "$module" "$symbol" "$crc" "$kernel_crc" >> "$REPORT"; ((mismatches += 1))
    fi
  done < <(modprobe --dump-modversions "$extracted")
done < "$MODULES_LOAD"
{
  echo "checked_vendor_modules=$checked"
  echo "crc_mismatches=$mismatches"
  echo "missing_kernel_symbols=$missing"
} >> "$REPORT"
echo "Checked stock vendor modules: $checked"
echo "CRC mismatches: $mismatches; missing kernel symbols: $missing"
echo "Report: $REPORT"
((mismatches == 0 && missing == 0)) || die 'dist is not compatible with stock vendor.img; do not package or flash.'
echo 'OK: current dist is compatible with stock vendor modules.'
