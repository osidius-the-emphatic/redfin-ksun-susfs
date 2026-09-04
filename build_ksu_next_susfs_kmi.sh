#!/usr/bin/env bash
# Pixel 5/redfin: reproducible KernelSU-Next + SuSFS build.
# Kernel integration is a strict patch series; no ready-file tarballs are used.
# This script never packages or flashes images.
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "ERROR: $*" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(pwd -P)"
KERNEL_DIR="$ROOT/private/msm-google"
KSU_DIR="$KERNEL_DIR/KernelSU-Next"
PATCH_DIR="$SCRIPT_DIR/patches"
DIST="$ROOT/out/android-msm-pixel-4.19/dist"
STOCK_IMAGES_DIR="$ROOT/stock-images"
VERSIONS_FILE="$SCRIPT_DIR/config/versions.env"
[[ -f "$VERSIONS_FILE" ]] || die "versions file not found: $VERSIONS_FILE"
# shellcheck disable=SC1091
source "$VERSIONS_FILE"
KSU_REF="${KSUN_REF:?KSUN_REF is not set}"
KSU_EXPECTED_COMMIT="${KSUN_EXPECTED_COMMIT:?KSUN_EXPECTED_COMMIT is not set}"
GOOGLE_BASE_COMMIT="${GOOGLE_BASE_COMMIT:?GOOGLE_BASE_COMMIT is not set}"
KSU_URL="https://github.com/sidex15/KernelSU-Next.git"
LOCAL_BRANCH="redbull-ksu-susfs-kmi"

usage() {
  cat <<'EOF'
Usage:
  ./build_ksu_next_susfs_kmi.sh [--stock-images-dir PATH]

Options:
  --stock-images-dir PATH  directory containing the matching stock vendor.img
                           (default: ./stock-images)
  -h, --help               show this help
EOF
}
while (($#)); do
  case "$1" in
    --stock-images-dir)
      (($# >= 2)) || die '--stock-images-dir requires a path.'
      STOCK_IMAGES_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done
STOCK_VENDOR_IMG="$STOCK_IMAGES_DIR/vendor.img"
[[ -d "$KERNEL_DIR/.git" && -x "$ROOT/build/build.sh" ]] || die 'run from the redbull-kernel checkout root.'
[[ -f "$KERNEL_DIR/build.config.redbull.vintf" ]] || die 'build.config.redbull.vintf not found.'
[[ -f "$PATCH_DIR/series" ]] || die 'patches/series not found.'
[[ -f "$STOCK_VENDOR_IMG" ]] || die "matching stock vendor.img not found: $STOCK_VENDOR_IMG"
GOOGLE_HEAD="$(git -C "$KERNEL_DIR" rev-parse HEAD)"
[[ "$GOOGLE_HEAD" == "$GOOGLE_BASE_COMMIT" ]] || die "unexpected Google base commit: $GOOGLE_HEAD"
while IFS= read -r patch_name; do
  patch_name="${patch_name%$'\r'}"
  [[ -z "$patch_name" || "$patch_name" == \#* ]] && continue
  [[ -f "$PATCH_DIR/$patch_name" ]] || die "patch not found: $patch_name"
done < "$PATCH_DIR/series"
if ! git -C "$KERNEL_DIR" diff --quiet || ! git -C "$KERNEL_DIR" diff --cached --quiet; then
  git -C "$KERNEL_DIR" status -uno --short >&2
  die 'the Google tree has tracked changes; run repo reset/sync first.'
fi
SECCOMP_STOCK_SHA="$(sha256sum "$KERNEL_DIR/include/linux/seccomp.h" | awk '{print $1}')"

echo '== 1/5: pinned KernelSU-Next =='
if [[ -e "$KSU_DIR" && ! -d "$KSU_DIR/.git" ]]; then die "$KSU_DIR exists but is not a Git clone."; fi
[[ -d "$KSU_DIR/.git" ]] || git clone "$KSU_URL" "$KSU_DIR"
git -C "$KSU_DIR" fetch --tags origin "refs/tags/$KSU_REF:refs/tags/$KSU_REF"
if [[ "$(git -C "$KSU_DIR" rev-parse --is-shallow-repository)" == true ]]; then
  git -C "$KSU_DIR" fetch --unshallow origin
fi
git -C "$KSU_DIR" reset --hard
git -C "$KSU_DIR" clean -fdx
git -C "$KSU_DIR" checkout --detach "$KSU_REF"
KSU_HEAD="$(git -C "$KSU_DIR" rev-parse HEAD)"
[[ "$KSU_HEAD" == "$KSU_EXPECTED_COMMIT" ]] || die "unexpected KSU commit: $KSU_HEAD"
rm -f "$KERNEL_DIR/drivers/kernelsu"
ln -s "../KernelSU-Next/kernel" "$KERNEL_DIR/drivers/kernelsu"
grep -q 'obj-\$(CONFIG_KSU) += kernelsu/' "$KERNEL_DIR/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_DIR/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig" || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig"
grep -Eq '^config[[:space:]]+KSU_SUSFS$' "$KERNEL_DIR/drivers/kernelsu/Kconfig" || die 'the KSU tag does not contain KSU_SUSFS.'

echo '== 2/5: KSU compatibility patch =='
patch --batch --fuzz=0 --forward -d "$KSU_DIR" -p1 < "$PATCH_DIR/ksun-disable-seccomp-filter-count.patch" || die 'the KSU seccomp patch failed.'

echo '== 3/5: strict kernel patch series =='
while IFS= read -r patch_name; do
  patch_name="${patch_name%$'\r'}"
  [[ -z "$patch_name" || "$patch_name" == \#* ]] && continue
  echo "-- $patch_name"
  patch --batch --fuzz=0 --forward -d "$KERNEL_DIR" -p1 < "$PATCH_DIR/$patch_name" || die "failed to apply $patch_name"
done < "$PATCH_DIR/series"
for spec in 'kernel/reboot.c:ksu_handle_sys_reboot' 'fs/exec.c:ksu_handle_execveat' 'drivers/input/input.c:ksu_handle_input_handle_event' 'fs/open.c:ksu_handle_faccessat' 'fs/stat.c:susfs_generic_fillattr_spoofer' 'fs/read_write.c:ksu_handle_vfs_read' 'fs/susfs.c:SUSFS_VERSION'; do
  rel="${spec%%:*}"; token="${spec##*:}"
  grep -q "$token" "$KERNEL_DIR/$rel" || die "missing $token in $rel"
done

echo '== 4/5: local SCM commit =='
git -C "$KERNEL_DIR" switch -C "$LOCAL_BRANCH"
git -C "$KERNEL_DIR" add -u
git -C "$KERNEL_DIR" add -- drivers/kernelsu fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h
if ! git -C "$KERNEL_DIR" diff --cached --quiet; then git -C "$KERNEL_DIR" commit -m 'Local KernelSU-Next and SuSFS patch-series integration'; fi
INTEGRATION_SHA="$(git -C "$KERNEL_DIR" rev-parse --short=12 HEAD)"
KERNEL_VERSION="$(awk '
  /^VERSION =/ { version=$3 }
  /^PATCHLEVEL =/ { patchlevel=$3 }
  /^SUBLEVEL =/ { sublevel=$3 }
  END { if (version != "" && patchlevel != "" && sublevel != "") print version "." patchlevel "." sublevel }
' "$KERNEL_DIR/Makefile")"
[[ -n "$KERNEL_VERSION" ]] || die 'cannot determine kernel version from Makefile.'
KERNEL_RELEASE="$KERNEL_VERSION-ksun-susfs-g$INTEGRATION_SHA"
printf '%s\n' "-ksun-susfs-g$INTEGRATION_SHA" > "$KERNEL_DIR/.scmversion"

echo '== 5/5: VINTF kernel build =='
(
  cd "$ROOT"
  SKIP_MRPROPER=1 BUILD_CONFIG=private/msm-google/build.config.redbull.vintf \
    "$ROOT/build/build.sh"
)
FINAL_CONFIG="$DIST/.config"
KERNEL_RELEASE_FILE="$ROOT/out/android-msm-pixel-4.19/private/msm-google/include/config/kernel.release"
UTS_RELEASE_FILE="$ROOT/out/android-msm-pixel-4.19/private/msm-google/include/generated/utsrelease.h"
[[ -f "$FINAL_CONFIG" ]] || die 'final .config was not generated.'
[[ -f "$DIST/Image.lz4-dtb" ]] || die 'final Image.lz4-dtb was not generated.'
[[ -f "$DIST/vmlinux" ]] || die 'final vmlinux was not generated.'
[[ -f "$KERNEL_RELEASE_FILE" ]] || die 'generated kernel.release was not found.'
[[ "$(<"$KERNEL_RELEASE_FILE")" == "$KERNEL_RELEASE" ]] ||
  die "unexpected kernel release: $(<"$KERNEL_RELEASE_FILE")"
[[ -f "$UTS_RELEASE_FILE" ]] || die 'generated utsrelease.h was not found.'
ACTUAL_UTS_RELEASE="$(sed -n 's/^#define UTS_RELEASE "\(.*\)"$/\1/p' "$UTS_RELEASE_FILE")"
[[ "$ACTUAL_UTS_RELEASE" == "$KERNEL_RELEASE" ]] ||
  die "unexpected UTS release: $ACTUAL_UTS_RELEASE"
for expected in \
  'CONFIG_CFI=y' 'CONFIG_CFI_CLANG=y' 'CONFIG_CFI_CLANG_SHADOW=y' \
  '# CONFIG_THINLTO is not set' 'CONFIG_TRIM_UNUSED_KSYMS=y' \
  'CONFIG_KPROBES=y' 'CONFIG_KSU=y' 'CONFIG_KSU_MANUAL_HOOK=y' \
  'CONFIG_KSU_SUSFS=y' 'CONFIG_KSU_SUSFS_SUS_PATH=y' \
  'CONFIG_KSU_SUSFS_SUS_MOUNT=y' 'CONFIG_KSU_SUSFS_SUS_KSTAT=y' \
  'CONFIG_KSU_SUSFS_OPEN_REDIRECT=y'; do
  grep -Fxq "$expected" "$FINAL_CONFIG" || die "final .config is missing: $expected"
done
SECCOMP_POST_SHA="$(sha256sum "$KERNEL_DIR/include/linux/seccomp.h" | awk '{print $1}')"
[[ "$SECCOMP_STOCK_SHA" == "$SECCOMP_POST_SHA" ]] || die 'seccomp.h changed unexpectedly.'
if grep -q 'filter_count' "$KERNEL_DIR/include/linux/seccomp.h"; then
  die 'seccomp.filter_count was added; this build is unsafe for stock modules.'
fi
echo '== ABI check: stock vendor modules =='
bash "$SCRIPT_DIR/tools/verify_stock_vendor_module_abi.sh" \
  --stock-vendor-img "$STOCK_VENDOR_IMG" --dist "$DIST"
PROOF="$DIST/ksu-next-susfs-build-proof.txt"
{
  echo "google_base_commit=$GOOGLE_BASE_COMMIT"
  echo "ksun_ref=$KSU_REF"
  echo "ksun_commit=$KSU_HEAD"
  echo "kernel_release=$KERNEL_RELEASE"
  echo "ksun_rev_count=$(git -C "$KSU_DIR" rev-list --count HEAD)"
  echo "ksun_version_code=$(expr 30000 + $(git -C "$KSU_DIR" rev-list --count HEAD) + 200)"
  echo "seccomp_stock_sha256=$SECCOMP_STOCK_SHA"
  echo "seccomp_post_build_sha256=$SECCOMP_POST_SHA"
  echo "final_config_sha256=$(sha256sum "$FINAL_CONFIG" | awk '{print $1}')"
  echo "image_lz4_dtb_sha256=$(sha256sum "$DIST/Image.lz4-dtb" | awk '{print $1}')"
  echo "vmlinux_sha256=$(sha256sum "$DIST/vmlinux" | awk '{print $1}')"
  echo "patch_series=$PATCH_DIR/series"
} > "$PROOF"
echo 'Build completed. Packaging and flashing are separate operations.'
echo "KSU tag: $KSU_REF ($KSU_HEAD)"
echo "Patch series: $PATCH_DIR/series"
echo "Proof: $PROOF"
