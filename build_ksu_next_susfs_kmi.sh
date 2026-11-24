#!/usr/bin/env bash
# Pixel 5/redfin: reproducible KernelSU-Next + SuSFS build.
# Kernel integration is a strict patch series; no ready-file tarballs are used.
# This script never packages or flashes images.
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "ERROR: $*" >&2; exit 1; }
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KERNEL_CHECKOUT="${KERNEL_CHECKOUT:-$(pwd -P)}"
PATCH="$SCRIPT/patches"
DIST="${DIST:-}"
STOCK_IMAGES="${STOCK_IMAGES:-}"
RESET_REPO="${RESET_REPO:-1}"
SYNC_REPO="${SYNC_REPO:-1}"
VERSIONS_FILE="$SCRIPT/config/versions.env"
[[ -f "$VERSIONS_FILE" ]] || die "versions file not found: $VERSIONS_FILE"
# shellcheck disable=SC1091
source "$VERSIONS_FILE"
KSU_REF="${KSUN_REF:?KSUN_REF is not set}"
KSU_EXPECTED_COMMIT="${KSUN_EXPECTED_COMMIT:?KSUN_EXPECTED_COMMIT is not set}"
KSU_RUNTIME_PATCH_REL="${KSUN_RUNTIME_PATCH:?KSUN_RUNTIME_PATCH is not set}"
KSU_RUNTIME_PATCH_EXPECTED_SHA256="${KSUN_RUNTIME_PATCH_SHA256:?KSUN_RUNTIME_PATCH_SHA256 is not set}"
GOOGLE_BASE_COMMIT="${GOOGLE_BASE_COMMIT:?GOOGLE_BASE_COMMIT is not set}"
KSU_URL="${KSUN_REPO:?KSUN_REPO is not set}"
SUSFS_PATCH_REL="${SUSFS_REDFIN_PATCH:?SUSFS_REDFIN_PATCH is not set}"
SUSFS_PATCH_EXPECTED_SHA256="${SUSFS_REDFIN_PATCH_SHA256:?SUSFS_REDFIN_PATCH_SHA256 is not set}"
[[ "$SUSFS_PATCH_REL" == patches/* ]] || die "SUSFS_REDFIN_PATCH must be below patches/: $SUSFS_PATCH_REL"
SUSFS_PATCH="$SCRIPT/$SUSFS_PATCH_REL"
[[ -f "$SUSFS_PATCH" ]] || die "pinned SuSFS patch not found: $SUSFS_PATCH_REL"
SUSFS_PATCH_ACTUAL_SHA256="$(sha256sum "$SUSFS_PATCH" | awk '{print $1}')"
[[ "$SUSFS_PATCH_ACTUAL_SHA256" == "$SUSFS_PATCH_EXPECTED_SHA256" ]] ||
  die "pinned SuSFS patch hash mismatch: expected $SUSFS_PATCH_EXPECTED_SHA256, got $SUSFS_PATCH_ACTUAL_SHA256"
SUSFS_HARDENING_REL="${SUSFS_HARDENING_PATCH:?SUSFS_HARDENING_PATCH is not set}"
SUSFS_HARDENING_EXPECTED_SHA256="${SUSFS_HARDENING_PATCH_SHA256:?SUSFS_HARDENING_PATCH_SHA256 is not set}"
[[ "$SUSFS_HARDENING_REL" == patches/* ]] || die "SUSFS_HARDENING_PATCH must be below patches/: $SUSFS_HARDENING_REL"
SUSFS_HARDENING_PATCH_FILE="$SCRIPT/$SUSFS_HARDENING_REL"
[[ -f "$SUSFS_HARDENING_PATCH_FILE" ]] || die "pinned SuSFS hardening patch not found: $SUSFS_HARDENING_REL"
SUSFS_HARDENING_ACTUAL_SHA256="$(sha256sum "$SUSFS_HARDENING_PATCH_FILE" | awk '{print $1}')"
[[ "$SUSFS_HARDENING_ACTUAL_SHA256" == "$SUSFS_HARDENING_EXPECTED_SHA256" ]] ||
  die "pinned SuSFS hardening patch hash mismatch: expected $SUSFS_HARDENING_EXPECTED_SHA256, got $SUSFS_HARDENING_ACTUAL_SHA256"
[[ "$KSU_RUNTIME_PATCH_REL" == patches/* ]] ||
  die "KSUN_RUNTIME_PATCH must be below patches/: $KSU_RUNTIME_PATCH_REL"
KSU_RUNTIME_PATCH="$SCRIPT/$KSU_RUNTIME_PATCH_REL"
[[ -f "$KSU_RUNTIME_PATCH" ]] || die "pinned KSUN runtime patch not found: $KSU_RUNTIME_PATCH_REL"
KSU_RUNTIME_PATCH_ACTUAL_SHA256="$(sha256sum "$KSU_RUNTIME_PATCH" | awk '{print $1}')"
[[ "$KSU_RUNTIME_PATCH_ACTUAL_SHA256" == "$KSU_RUNTIME_PATCH_EXPECTED_SHA256" ]] ||
  die "pinned KSUN runtime patch hash mismatch: expected $KSU_RUNTIME_PATCH_EXPECTED_SHA256, got $KSU_RUNTIME_PATCH_ACTUAL_SHA256"
LOCAL_BRANCH="redbull-ksu-susfs-kmi"

usage() {
  cat <<'EOF'
Usage:
  ./build_ksu_next_susfs_kmi.sh [options]

Options:
  --kernel-checkout PATH  redbull-kernel checkout (default: current directory)
  --stock-images PATH  directory containing the matching stock vendor.img
                           (default: $KERNEL_CHECKOUT/stock-images)
  --dist PATH           build directory (default: $KERNEL_CHECKOUT/out/android-msm-pixel-4.19/dist)
  --reset-repo           reset tracked and untracked files in all repo projects (default)
  --no-reset-repo        preserve current repo project worktrees
  --sync-repo             run 'repo sync -l -d' after reset (default)
  --no-sync-repo          do not synchronize repo projects
  -h, --help               show this help
EOF
}
while (($#)); do
  case "$1" in
    --kernel-checkout)
      (($# >= 2)) || die '--kernel-checkout requires a path.'
      KERNEL_CHECKOUT="$2"
      ROOT="$KERNEL_CHECKOUT"
      KERNEL="$KERNEL_CHECKOUT/private/msm-google"
      shift 2
      ;;
    --stock-images)
      (($# >= 2)) || die '--stock-images requires a path.'
      STOCK_IMAGES="$2"
      shift 2
      ;;
    --dist)
      (($# >= 2)) || die '--dist requires a path.'
      DIST="$2"
      shift 2
      ;;
    --reset-repo) RESET_REPO=1; shift ;;
    --no-reset-repo) RESET_REPO=0; shift ;;
    --sync-repo) SYNC_REPO=1; shift ;;
    --no-sync-repo) SYNC_REPO=0; shift ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done
KERNEL_CHECKOUT="$(cd "$KERNEL_CHECKOUT" && pwd -P)" || die "kernel checkout not found: $KERNEL_CHECKOUT"
ROOT="$KERNEL_CHECKOUT"
KERNEL="$KERNEL_CHECKOUT/private/msm-google"
KSU="$KERNEL/KernelSU-Next"
STOCK_IMAGES="${STOCK_IMAGES:-$KERNEL_CHECKOUT/stock-images}"
DIST="${DIST:-$KERNEL_CHECKOUT/out/android-msm-pixel-4.19/dist}"
STOCK_VENDOR_IMG="$STOCK_IMAGES/vendor.img"
[[ -d "$KERNEL/.git" && -x "$ROOT/build/build.sh" ]] || die 'run from the redbull-kernel checkout root.'
for value_name in RESET_REPO SYNC_REPO; do
  value="${!value_name}"
  case "$value" in 0|1) ;; *) die "$value_name must be 0 or 1 (got: $value)" ;; esac
done
if [[ "$RESET_REPO" == 1 || "$SYNC_REPO" == 1 ]]; then
  command -v repo >/dev/null 2>&1 || die 'repo command not found; use --no-reset-repo --no-sync-repo or install repo.'
  [[ -d "$ROOT/.repo" ]] || die "repo metadata not found: $ROOT/.repo"
  if [[ "$RESET_REPO" == 1 ]]; then echo '== 0/5: reset repo projects =='; (cd "$ROOT" && repo forall -c 'git reset --hard && git clean -fd'); fi
  if [[ "$SYNC_REPO" == 1 ]]; then echo '== 0/5: sync repo projects =='; (cd "$ROOT" && repo sync -l -d); fi
fi
[[ -f "$KERNEL/build.config.redbull.vintf" ]] || die 'build.config.redbull.vintf not found.'
[[ -f "$PATCH/series" ]] || die 'patches/series not found.'
[[ -f "$STOCK_VENDOR_IMG" ]] || die "matching stock vendor.img not found: $STOCK_VENDOR_IMG"
git -C "$KERNEL" cat-file -e "$GOOGLE_BASE_COMMIT^{commit}" \
  || die "pinned Google base commit is unavailable locally: $GOOGLE_BASE_COMMIT; run repo sync once."

# Never allow a proof or module manifest from an earlier build to authenticate
# files produced by this invocation.
rm -f -- "$DIST/ksu-next-susfs-build-proof.txt" "$DIST/ksu-next-susfs-modules.sha256"
echo '== 0/5: reset pinned Google kernel source =='
git -C "$KERNEL" reset --hard "$GOOGLE_BASE_COMMIT"
git -C "$KERNEL" clean -fd
GOOGLE_HEAD="$(git -C "$KERNEL" rev-parse HEAD)"
[[ "$GOOGLE_HEAD" == "$GOOGLE_BASE_COMMIT" ]] || die "failed to reset Google base commit: $GOOGLE_HEAD"
while IFS= read -r patch_name; do
  patch_name="${patch_name%$'\r'}"
  [[ -z "$patch_name" || "$patch_name" == \#* ]] && continue
  [[ -f "$PATCH/$patch_name" ]] || die "patch not found: $patch_name"
done < "$PATCH/series"
grep -Fxq "${SUSFS_PATCH_REL#patches/}" "$PATCH/series" ||
  die "pinned SuSFS patch is not listed in patches/series: $SUSFS_PATCH_REL"
grep -Fxq "${SUSFS_HARDENING_REL#patches/}" "$PATCH/series" ||
  die "pinned SuSFS hardening patch is not listed in patches/series: $SUSFS_HARDENING_REL"
SECCOMP_STOCK_SHA="$(sha256sum "$KERNEL/include/linux/seccomp.h" | awk '{print $1}')"

echo '== 1/5: pinned KernelSU-Next =='
if [[ -e "$KSU" && ! -d "$KSU/.git" ]]; then die "$KSU exists but is not a Git clone."; fi
if [[ -d "$KSU/.git" ]]; then
  git -C "$KSU" remote set-url origin "$KSU_URL"
else
  git clone "$KSU_URL" "$KSU"
fi
if ! git -C "$KSU" cat-file -e "$KSU_EXPECTED_COMMIT^{commit}" 2>/dev/null; then
  echo "== 1/5: fetching missing KernelSU-Next revision $KSU_REF =="
  git -C "$KSU" fetch --tags origin "$KSU_REF" \
    || die "pinned KernelSU-Next commit is unavailable locally and fetch failed: $KSU_EXPECTED_COMMIT"
fi
if ! git -C "$KSU" cat-file -e "$KSU_EXPECTED_COMMIT^{commit}" 2>/dev/null; then
  die "pinned KernelSU-Next commit is unavailable after fetch: $KSU_EXPECTED_COMMIT"
fi
git -C "$KSU" reset --hard
git -C "$KSU" clean -fdx
git -C "$KSU" checkout --detach "$KSU_EXPECTED_COMMIT"
KSU_HEAD="$(git -C "$KSU" rev-parse HEAD)"
[[ "$KSU_HEAD" == "$KSU_EXPECTED_COMMIT" ]] || die "unexpected KSU commit: $KSU_HEAD"
rm -f "$KERNEL/drivers/kernelsu"
ln -s "../KernelSU-Next/kernel" "$KERNEL/drivers/kernelsu"
grep -q 'obj-\$(CONFIG_KSU) += kernelsu/' "$KERNEL/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$KERNEL/drivers/Kconfig" || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL/drivers/Kconfig"

echo '== 2/5: KSU compatibility patch =='
patch --batch --fuzz=0 --forward -d "$KSU" -p1 < "$PATCH/ksun-v342-redfin-port.patch" || die 'the official v3.4.2 redfin compatibility patch failed.'
git -C "$KSU" apply --check --whitespace=error "$KSU_RUNTIME_PATCH" || die 'the v3.4.2 redfin runtime compatibility patch check failed.'
git -C "$KSU" apply --whitespace=error "$KSU_RUNTIME_PATCH" || die 'the v3.4.2 redfin runtime compatibility patch failed.'
grep -Eq '^config[[:space:]]+KSU_SUSFS$' "$KERNEL/drivers/kernelsu/Kconfig" || die 'the v3.4.2 redfin port did not add KSU_SUSFS.'
grep -q 'pmd_sect' "$KSU/kernel/hook/arm64/patch_memory.c" || die 'the v3.4.2 redfin runtime patch did not add PMD section support.'
grep -q 'ksu_resolve_syscall_entry_target' "$KSU/kernel/hook/arm64/syscall_hook.c" || die 'the v3.4.2 redfin runtime patch did not add CFI syscall-entry resolution.'

echo '== 3/5: strict kernel patch series =='
while IFS= read -r patch_name; do
  patch_name="${patch_name%$'\r'}"
  [[ -z "$patch_name" || "$patch_name" == \#* ]] && continue
  echo "-- $patch_name"
  patch --batch --fuzz=0 --forward -d "$KERNEL" -p1 < "$PATCH/$patch_name" || die "failed to apply $patch_name"
done < "$PATCH/series"
for spec in 'drivers/kernelsu/Kbuild:hook/syscall_event_bridge.o' 'drivers/kernelsu/hook/syscall_hook_manager.c:ksu_syscall_hook_manager_init' 'fs/open.c:susfs_open_redirect_spoof_do_sys_openat' 'fs/stat.c:susfs_generic_fillattr_spoofer' 'fs/susfs.c:SUSFS_VERSION'; do
  rel="${spec%%:*}"; token="${spec##*:}"
  grep -q "$token" "$KERNEL/$rel" || die "missing $token in $rel"
done

echo '== 4/5: local SCM commit =='
git -C "$KERNEL" switch -C "$LOCAL_BRANCH"
git -C "$KERNEL" add -u
git -C "$KERNEL" add -- drivers/kernelsu fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h
if ! git -C "$KERNEL" diff --cached --quiet; then git -C "$KERNEL" commit -m 'Local KernelSU-Next and SuSFS patch-series integration'; fi
INTEGRATION_SHA="$(git -C "$KERNEL" rev-parse --short=12 HEAD)"
KERNEL_VERSION="$(awk '
  /^VERSION =/ { version=$3 }
  /^PATCHLEVEL =/ { patchlevel=$3 }
  /^SUBLEVEL =/ { sublevel=$3 }
  END { if (version != "" && patchlevel != "" && sublevel != "") print version "." patchlevel "." sublevel }
' "$KERNEL/Makefile")"
[[ -n "$KERNEL_VERSION" ]] || die 'cannot determine kernel version from Makefile.'
KERNEL_RELEASE="$KERNEL_VERSION-ksun-susfs-g$INTEGRATION_SHA"
printf '%s\n' "-ksun-susfs-g$INTEGRATION_SHA" > "$KERNEL/.scmversion"

echo '== 5/5: VINTF kernel build =='
OUTPUT_KERNEL_DIR="$ROOT/out/android-msm-pixel-4.19/private/msm-google"
OUTPUT_MAKEFILE="$OUTPUT_KERNEL_DIR/Makefile"
# A previously interrupted out-of-tree Kbuild setup can leave a zero-byte
# generated wrapper Makefile. The upstream mkmakefile script deliberately
# preserves any readable file at that path, which makes later *config targets
# fail with "No rule to make target". A zero-byte wrapper has no useful state
# and is safe to remove; the first Kbuild config target recreates it.
if [[ -e "$OUTPUT_MAKEFILE" && ! -s "$OUTPUT_MAKEFILE" ]]; then
  echo '== 5/5: remove stale zero-byte output Makefile =='
  rm -f "$OUTPUT_MAKEFILE"
fi
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
  'CONFIG_KPROBES=y' 'CONFIG_KALLSYMS_ALL=y' 'CONFIG_KSU=y' \
  'CONFIG_KSU_SUSFS=y' 'CONFIG_KSU_SUSFS_SUS_PATH=y' \
  'CONFIG_KSU_SUSFS_SUS_MOUNT=y' 'CONFIG_KSU_SUSFS_SUS_KSTAT=y' \
  'CONFIG_KSU_SUSFS_OPEN_REDIRECT=y'; do
  grep -Fxq "$expected" "$FINAL_CONFIG" || die "final .config is missing: $expected"
done
SECCOMP_POST_SHA="$(sha256sum "$KERNEL/include/linux/seccomp.h" | awk '{print $1}')"
[[ "$SECCOMP_STOCK_SHA" == "$SECCOMP_POST_SHA" ]] || die 'seccomp.h changed unexpectedly.'
if grep -q 'filter_count' "$KERNEL/include/linux/seccomp.h"; then
  die 'seccomp.filter_count was added; this build is unsafe for stock modules.'
fi
echo '== ABI check: stock vendor modules =='
bash "$SCRIPT/tools/verify_stock_vendor_module_abi.sh" \
  --stock-vendor-img "$STOCK_VENDOR_IMG" --dist "$DIST"
PROOF="$DIST/ksu-next-susfs-build-proof.txt"
MODULES_MANIFEST="$DIST/ksu-next-susfs-modules.sha256"
(
  cd "$DIST"
  find . -maxdepth 1 -type f -name '*.ko' -printf '%P\n' | LC_ALL=C sort |
    xargs -r -d '\n' sha256sum
) > "$MODULES_MANIFEST"
[[ -s "$MODULES_MANIFEST" ]] || die "no .ko modules found in $DIST for the proof manifest."
{
  echo "google_base_commit=$GOOGLE_BASE_COMMIT"
  echo "ksun_repo=$KSU_URL"
  echo "ksun_ref=$KSU_REF"
  echo "ksun_commit=$KSU_HEAD"
  echo "ksun_runtime_patch_sha256=$KSU_RUNTIME_PATCH_ACTUAL_SHA256"
  echo "susfs_patch_sha256=$SUSFS_PATCH_ACTUAL_SHA256"
  echo "susfs_hardening_patch_sha256=$SUSFS_HARDENING_ACTUAL_SHA256"
  echo "kernel_release=$KERNEL_RELEASE"
  echo "ksun_rev_count=$(git -C "$KSU" rev-list --count HEAD)"
  echo "ksun_version_code=$(expr 30000 + $(git -C "$KSU" rev-list --count HEAD))"
  echo "seccomp_stock_sha256=$SECCOMP_STOCK_SHA"
  echo "seccomp_post_build_sha256=$SECCOMP_POST_SHA"
  echo "final_config_sha256=$(sha256sum "$FINAL_CONFIG" | awk '{print $1}')"
  echo "image_lz4_dtb_sha256=$(sha256sum "$DIST/Image.lz4-dtb" | awk '{print $1}')"
  echo "vmlinux_sha256=$(sha256sum "$DIST/vmlinux" | awk '{print $1}')"
  echo "module_count=$(wc -l < "$MODULES_MANIFEST")"
  echo "modules_manifest_sha256=$(sha256sum "$MODULES_MANIFEST" | awk '{print $1}')"
  echo "patch_series=$PATCH/series"
} > "$PROOF"
echo 'Build completed. Packaging and flashing are separate operations.'
echo "KSU tag: $KSU_REF ($KSU_HEAD)"
echo "Patch series: $PATCH/series"
echo "Proof: $PROOF"
