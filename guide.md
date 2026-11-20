# Pixel 5 (redfin): KernelSU-Next + SuSFS build, package, and flash guide

[English](guide.md) | [Українська](guide.uk.md)

This is the reproducible workflow for the Pixel 5 (`redfin`) Android 14 kernel in this repository. It builds KernelSU-Next with legacy SuSFS v2 support while retaining compatibility with the stock `/vendor` kernel modules.

The scripts prepare the source tree and create images. They do **not** flash the phone. Run the build and package commands yourself; both can take time.

## Scope and assumptions

- Device: Google Pixel 5 (`redfin`).
- Stock release used for this project: Android 14 `UP1A.231105.001.B2`.
- Kernel branch: `android-msm-redbull-4.19-android14`.
- Required kernel base commit: `7b0944645172e8b690d42f68c8973ccb0ca45730`.
- Kernel configuration: `private/msm-google/build.config.redbull.vintf`.
- Build host: WSL/Linux.
- Bootloader: unlocked.

Do not use `build_redbull.sh` for this project. It selects a different configuration and is not the VINTF/KMI-compatible build path used here.

## Repository layout

| Path | Purpose |
| --- | --- |
| `build_ksu_next_susfs_kmi.sh` | Resets the source to the pinned base, applies the patch series, builds the kernel, and writes build proof. It does not package or flash. |
| `package_kernel_images.sh` | Packages the already-built kernel into `boot.img` and `vendor_boot.img`. It does not build or flash. |
| `patches/` | Ordered, reviewable KernelSU-Next, SuSFS, manual-hook, KMI, and configuration patches. |
| `patches/series` | Authoritative order of the patch series. |
| `config/versions.env` | Pinned Google kernel base and KernelSU-Next revision. |
| `tools/verify_stock_vendor_module_abi.sh` | Internal ABI check against stock vendor modules. |
| `out/android-msm-pixel-4.19/dist/` | Build output, proof, ABI report, and final kernel artifacts. Not tracked by Git. |
| `stock-images/` | Matching factory `boot.img`, `vendor_boot.img`, and `vendor.img`. Not tracked by Git. |
| `repacked-images/` | Image packages produced by the packaging script. Not tracked by Git. |

KernelSU-Next and SuSFS are intentionally separate patches. This makes upgrades reviewable and prevents a KernelSU update from silently changing SuSFS code.

## 1. Prerequisites

Install the Android kernel build dependencies, `repo`, Git, Python 3, `lz4`, `cpio`, `fastboot`, and `adb`. The scripts use `unpack_bootimg`, `mkbootimg`, and `avbtool` from the Google checkout; only `lz4` and `cpio` must be in `PATH` for packaging.

For post-flash root verification and permission management, install the
KernelSU-Next Manager APK matching the embedded KernelSU-Next component.

Keep these factory-image files for the target release available:

- `boot.img`
- `vendor_boot.img`
- `vendor.img`
- `vbmeta.img`
- `vbmeta_system.img`

Use files extracted from the same factory image installed on the phone. Do not combine boot or vbmeta images from another build. Before the first flash, save a copy of the known-good stock images outside this repository; they are the recovery path.

## 2. Choose directories and open WSL

The GitHub project repository and the Google `repo` checkout are separate. Run
the scripts from the checkout root and they need no arguments or exported
variables. Choose these paths for your machine:

```bash
KERNEL_CHECKOUT="$HOME/dev/redbull-kernel"
PROJECT="$KERNEL_CHECKOUT/ksun-susfs"
cd "$KERNEL_CHECKOUT"
```

These are example locations, not fixed requirements. `KERNEL_CHECKOUT` is only
needed when launching from another directory; otherwise the current directory
is used. `PROJECT` may be any directory containing this repository.

The shared script inputs are:

| Input | Default | Override |
| --- | --- | --- |
| `KERNEL_CHECKOUT` | Current directory | `--kernel-checkout PATH` |
| `STOCK_IMAGES` | `$KERNEL_CHECKOUT/stock-images` | `--stock-images PATH` |
| `DIST` | `$KERNEL_CHECKOUT/out/android-msm-pixel-4.19/dist` | `--dist PATH` |

`GOOGLE_BASE_COMMIT` and the KernelSU revision are fixed in
`config/versions.env`; there is no `KERNEL_COMMIT` parameter. This keeps the
source version in one place and makes both scripts consistent.

## 3. Obtain or reuse the Google source tree

For a new checkout, initialize and synchronize the Google kernel manifest, then
clone this project into the chosen `PROJECT`:

```bash
mkdir -p "$KERNEL_CHECKOUT"
cd "$KERNEL_CHECKOUT"
repo init -u https://android.googlesource.com/kernel/manifest \
  -b android-msm-redbull-4.19-android14
repo sync -j8
git clone https://github.com/osidius-the-emphatic/redfin-ksun-susfs.git "$PROJECT"
```

The commands do not have a required progress format. A successful `repo init`,
`repo sync`, and `git clone` exits with status `0`; any fatal error or non-zero
status means that the checkout is incomplete and must be fixed before building.

If the kernel checkout and project repository already exist, do not repeat
these commands. Confirm that `private/msm-google`, `build`, and
`$PROJECT/patches/series` are present, then continue with section 4.

### Repeat a build with an existing checkout

No manual reset is needed. By default, the builder runs `repo forall -c 'git
reset --hard && git clean -fd'` and `repo sync -l -d` before applying patches.
This resets all `repo` projects, including the previous local integration.

Disable either action only when deliberately preserving the current checkout:

```bash
bash "$PROJECT/build_ksu_next_susfs_kmi.sh" --no-reset-repo --no-sync-repo
```

The reset is destructive. Preserve experiments in another checkout or commit
them before starting the builder. If the local checkout is incomplete, run
ordinary `repo sync` once before retrying.

Remove generated output when a clean rebuild is required:

```bash
rm -rf "$KERNEL_CHECKOUT/out/android-msm-pixel-4.19"
```

`out/` is generated output. Remove only this exact directory after confirming
that `KERNEL_CHECKOUT` is the intended kernel checkout.

## 4. Place the stock images

Create the directory named by `STOCK_IMAGES` and copy the matching factory
`boot.img`, `vendor_boot.img`, `vendor.img`, `vbmeta.img`, and
`vbmeta_system.img` into it. The same variable is passed to both scripts. The
scripts find Android image tools inside the checkout automatically; no
`MKBOOTIMG`, `UNPACK_BOOTIMG`, or `AVBTOOL` exports are needed.

Check inputs before starting the long build:

```bash
test -f "$STOCK_IMAGES/boot.img"
test -f "$STOCK_IMAGES/vendor_boot.img"
test -f "$STOCK_IMAGES/vendor.img"
test -f "$STOCK_IMAGES/vbmeta.img"
test -f "$STOCK_IMAGES/vbmeta_system.img"
command -v lz4
command -v cpio
```

Expected result:

- Each `test -f` command prints nothing and returns status `0` when the file exists. A missing file returns status `1`; stop and correct the path.
- Each `command -v` command prints the executable path (for example, `/usr/bin/lz4`) and returns status `0`. If it prints nothing or returns non-zero, install the missing tool or make it available in `PATH`.

When checking a command manually, run `echo $?` immediately afterward to read
its status. Do not continue to the build until all seven checks succeed.

## 5. Build KernelSU-Next + SuSFS

This is the long-running step. The script resets and synchronizes the `repo`
checkout by default, checks out the pinned KernelSU-Next revision, applies the
ordered patches, builds with the VINTF configuration, and writes evidence to
`dist/`.

The resulting kernel release is `4.19.278-ksun-susfs-g<integration-sha>`, where the SHA identifies the one local commit containing the applied integration. It deliberately does not use the uninformative `00001` Git-distance suffix.

```bash
cd "$KERNEL_CHECKOUT"
bash "$PROJECT/build_ksu_next_susfs_kmi.sh"
```

Do not run packaging until this command succeeds.

The successful output must include:

- unchanged `seccomp.h` SHA-256 before and after the build;
- a `kernel_release=4.19.278-ksun-susfs-g<integration-sha>` entry in the proof;
- enabled KernelSU and SuSFS configuration checks;
- SHA-256 hashes for `Image.lz4-dtb` and `vmlinux`;
- an ABI report with zero CRC mismatches and zero missing symbols.

The key output files are:

```text
out/android-msm-pixel-4.19/dist/ksu-next-susfs-build-proof.txt
out/android-msm-pixel-4.19/dist/stock-vendor-module-abi-kmi-full-report.txt
```

Any ABI mismatch or missing symbol is a failed build for stock `vendor.img`: do not package or flash it. The KMI patches preserve the CRCs required by stock vendor modules without removing SuSFS.

## 6. Inspect the build result

Before packaging, inspect the proof and ABI result directly:

```bash
cd "$KERNEL_CHECKOUT"
sed -n '1,240p' out/android-msm-pixel-4.19/dist/ksu-next-susfs-build-proof.txt
sed -n '1,260p' out/android-msm-pixel-4.19/dist/stock-vendor-module-abi-kmi-full-report.txt
test -s out/android-msm-pixel-4.19/dist/Image.lz4-dtb
```

These files are machine-readable evidence, not extra inputs to the next command. A successful build exits with status 0, creates both files, and prints their paths. In the proof, `seccomp_stock_sha256` and `seccomp_post_build_sha256` must be identical, image hashes must be present, and the KernelSU/SuSFS configuration checks must have passed. In the ABI report, `crc_mismatches=0` and `missing_kernel_symbols=0` are mandatory; `checked_vendor_modules` must be positive (111 for the referenced stock image). Any non-zero mismatch, missing file, or non-zero command exit means stop: do not package or flash.

`sed` only prints the evidence; it does not change anything. `test -s` prints nothing and returns 0 when the kernel image exists and is non-empty; a missing or empty image returns 1. The proof records the exact KernelSU source commit, `seccomp` integrity checks, final configuration checksum, and image hashes. The patch series is recorded separately in `patches/series`.

## 7. Package boot and vendor_boot

Packaging is separate from building. It consumes the successful `dist/Image.lz4-dtb` and stock boot artifacts, then writes a new directory below `repacked-images/`.

```bash
cd "$KERNEL_CHECKOUT"
bash "$PROJECT/package_kernel_images.sh"
```

The script prints the exact output directory. Inspect it before flashing; it must contain replacement `boot.img`, `vendor_boot.img`, checksums, proof, and packaging metadata.

There is normally no reason to maintain separate stock-image paths: both
scripts use the same `$KERNEL_CHECKOUT/stock-images` default. Set
`STOCK_IMAGES` or pass `--stock-images` only when the images live elsewhere.

Never overwrite the stock input images. Generated images belong in `repacked-images/`; stock inputs remain immutable recovery artifacts.

## 8. Flash the generated images

Flashing changes the device. Confirm the output directory and hashes, then reboot to the bootloader:

```bash
adb reboot bootloader
fastboot devices
fastboot getvar current-slot
```

Record the reported slot (`a` or `b`). This is the target slot for the new
kernel. On an A/B device, flashing `boot` or `vendor_boot` without an explicit
slot writes the current slot; the other slot keeps its previous contents and
remains available as a fallback. If the new slot fails to boot and is not
marked successful, the bootloader may automatically try the other slot. You
can also switch manually with `fastboot set_active a` or `fastboot set_active b`.

Use the generated `boot.img` and `vendor_boot.img` from the package, together
with the matching factory `vbmeta.img` and `vbmeta_system.img` from
`STOCK_IMAGES`. The established Pixel 5 protocol flashes both vbmeta
partitions to both slots while disabling AVB verification and verity:

```bash
PACKAGE_DIR="$KERNEL_CHECKOUT/repacked-images/redbull.xxxxxx"  # use the directory printed by packaging
fastboot flash boot "$PACKAGE_DIR/boot.img"
fastboot flash vendor_boot "$PACKAGE_DIR/vendor_boot.img"
fastboot flash --slot all --disable-verity --disable-verification vbmeta "$STOCK_IMAGES/vbmeta.img"
fastboot flash --slot all --disable-verity --disable-verification vbmeta_system "$STOCK_IMAGES/vbmeta_system.img"
fastboot reboot
```

`PACKAGE_DIR` prevents accidentally flashing a stock image or an older package. Replace `redbull.xxxxxx` with the actual directory name; do not type the placeholder literally. `--slot all` applies only to `vbmeta` and `vbmeta_system`; the generated boot images are flashed only to the current slot.

`--disable-verity` and `--disable-verification` deliberately change the AVB
state. Use only the matching factory `vbmeta.img` and `vbmeta_system.img` for
the installed release. Do not flash `vendor.img`; this workflow leaves the
stock vendor partition unchanged.

Changing the AVB state can affect access to encrypted user data. Keep a current
backup before flashing, and be prepared for Android to require a data wipe if
the device cannot validate or unlock the existing data. In this project, a
previous test that used an incomplete vbmeta protocol required a reset, but the
reset was not a controlled proof that the `--disable-*` flags themselves caused
it.

It is also not established whether `vbmeta.img` and `vbmeta_system.img` must be
flashed with these flags on every later kernel update, or only once. The flags
are written into the vbmeta state by the vbmeta flash operation; flashing a new
`boot` or `vendor_boot` does not by itself rewrite that state. However, the
Pixel 5-specific interaction with encrypted data and the TEE is not documented
well enough to prove that a boot/vendor_boot-only update is always safe. Until
that is tested on this device without losing data, treat the full four-image
protocol above as the safe default. A controlled later test can flash only
boot/vendor_boot on the other slot, verify that `/data` remains accessible, and
then establish whether a shorter routine is reliable; do not infer that from a
single successful boot.

## 9. Verify the booted kernel

First confirm that the phone booted and identify the running kernel. These
commands do not require root:

```bash
adb wait-for-device
adb shell uname -r
```

The `uname -r` result must be the `4.19.278-ksun-susfs-g<integration-sha>`
value recorded in the build proof. If the phone is online but reports another
release, stop: it booted a different kernel.

The KernelSU-Next driver is built into the kernel, but the Manager is a
separate Android application. Root is not automatically granted to the ADB
shell. Open the installed
KernelSU-Next Manager, go to its General settings, and explicitly enable root
access for ADB/shell (the exact label can vary by Manager version). Only then
run the root check:

```bash
adb shell su -c id
```

The result should include `uid=0(root)` and normally a KernelSU SELinux context such as `u:r:ksu:s0`. If the Manager has not granted root to ADB/shell, this command will fail or return a non-root identity; that is a permission-setting result, not proof that the kernel failed to boot.

The following module-list check normally works without root, while reading the
kernel log requires the root access verified above:

```bash
adb shell 'grep "^incrementalfs " /proc/modules'
adb shell su -c 'dmesg | grep -Ei "incrementalfs|disagrees about version|invalid module format"'
```

`incrementalfs` in `/proc/modules` with no `disagrees about version` or `invalid module format` message is the runtime counterpart to the ABI audit.

KernelSU builds do not all expose `/proc/ksu/version` or `/proc/ksu/susfs_enabled_features`. Their absence alone is not a failure. Verify through `su`, the KernelSU-Next manager, and the build proof.

## 10. Recovery

If the device fails to boot, return to the bootloader and restore the known-good stock `boot.img` and `vendor_boot.img` for the installed factory release:

```bash
fastboot flash boot "$STOCK_IMAGES/boot.img"
fastboot flash vendor_boot "$STOCK_IMAGES/vendor_boot.img"
fastboot reboot
```

For the A/B device, inspect the active slot first with `fastboot getvar current-slot`. Do not switch or overwrite slots casually; use the stock factory-image procedure if both slots need restoration.

## Updating KernelSU-Next or SuSFS

The `ksun-3.4.2-susfs-2.2` branch pins official KernelSU-Next `v3.4.2` and
applies `patches/ksun-v342-redfin-port.patch`. This focused patch keeps the
official driver sources and adds only the manual-hook/legacy-kernel bridge plus
the built-in SuSFS v2.2 integration. It applies with `patch --fuzz=0`; no
kernel build has been run for this branch yet.
The manual `fs/exec.c` hook is bridged to the official v3.4.2
`ksu_handle_execveat_ksud(path, argv)` runtime API and then to the 4.19
sucompat handler. The patch passes `git apply --check` on a clean v3.4.2 tree;
only a real redfin compile can validate compiler and linker compatibility.

If `check_defconfig` reports that `savedefconfig` removed
`CONFIG_KSU_MANUAL_HOOK=y`, do not add it back: this symbol has `default y` in
the KSU Kconfig. The redfin defconfig patch should keep the explicit
`CONFIG_KPROBES=y` addition only.
After removing a defconfig option, remove its entire now-empty diff hunk too;
otherwise `patch` rejects the file as malformed.

On redfin 4.19, the v3.4.2 KSU compatibility patch also supplies the
`can_umount()`/`path_umount()` backport through Kbuild and the matching
`fs/internal.h` declaration.

Do not edit generated source files or replace whole source trees with archives. Update the appropriate pinned revision and its own patch set:

1. Change the KernelSU-Next ref and commit in `config/versions.env`.
2. Refresh only KernelSU-Next-specific patches, including the seccomp backport exclusion if it still applies.
3. Refresh SuSFS-specific patches separately when the SuSFS version changes.
4. Rebase integration, KMI, and configuration patches in `patches/series` order.
5. Review the series with `git apply --check` or the build script preparation checks.
6. Perform a clean build and require a zero-mismatch vendor-module ABI report before packaging.

The stable KernelSU-Next Manager v3.4.2 uses UAPI 5 and is compatible with the
legacy kernel integration in this repository.

## Why `versions.env` exists

`config/versions.env` is the single source of truth for the upstream inputs: the Google kernel base commit and the KernelSU-Next tag/commit pair. The builder reads it before changing the source tree and refuses an unexpected commit. This prevents a patch series from being applied to an unrecorded upstream revision and makes an update a small, reviewable change instead of a hidden archive replacement. It does not contain device images or tool paths.

## Troubleshooting

### `ERROR: patch not found: susfs-v2.2.0-redbull.patch`

The usual cause was a CRLF line ending in `patches/series`, which made Bash look for a filename ending in a hidden carriage return. The tracked series now uses LF and the build script defensively removes a trailing carriage return.

```bash
cd "$PROJECT"
git status --short
file patches/series
test -f patches/susfs-v2.2.0-redbull.patch
```

### The build script reports that the pinned Google commit is unavailable

The builder performs the reset and local synchronization automatically. If the
checkout is incomplete, run ordinary `repo sync` once, then retry. Do not
change the pinned commit manually: the proof must identify a reproducible source
state.

### ABI audit reports a mismatch

Do not package or flash. Save the report, identify the changed exported symbol, and adjust the KMI compatibility patch without removing the required SuSFS feature.

### KernelSU Manager and embedded component show different numbers

Record the Manager version and the proof's source commit when comparing builds.

## Historical notes

The original incompatibility was caused by changed exported-symbol CRCs in the kernel while the Pixel 5 stock `vendor.img` retained modules built against stock CRCs. The KMI approach restores stock-module compatibility without removing SuSFS. A successful audit previously checked 111 stock vendor modules and found zero CRC mismatches and zero missing kernel symbols.

For detailed working history and investigation notes, see
[HANDOFF-context.md](HANDOFF-context.md). It is not required to execute this
procedure.

