# Pixel 5 KernelSU-Next + SuSFS

[English](README.md) | [Українська](README.uk.md)

This repository contains a reproducible, patch-based workflow for building a custom Android 14 kernel for Google Pixel 5 (`redfin`). The resulting kernel integrates KernelSU-Next and legacy SuSFS v2 while preserving the kernel ABI expected by the stock modules in `/vendor`.

## Purpose

The project turns the pinned Google kernel source into a verifiable KernelSU-Next + SuSFS kernel and packages that kernel into replacement `boot.img` and `vendor_boot.img` images. The stock `vendor.img` is used as an ABI reference and remains an input artifact.

KernelSU-Next and SuSFS are maintained as separate patch groups. Upstream revisions, patch order, and compatibility changes are therefore visible in Git and can be reviewed or updated independently.

## Upstream sources

- **Google kernel:** [android.googlesource.com/kernel/msm](https://android.googlesource.com/kernel/msm), branch `android-msm-redbull-4.19-android14`, base commit `7b0944645172e8b690d42f68c8973ccb0ca45730`. A GitHub mirror is available at [aosp-mirror/kernel_msm](https://github.com/aosp-mirror/kernel_msm).
- **KernelSU-Next:** [sidex15/KernelSU-Next](https://github.com/sidex15/KernelSU-Next), ref `v3.3.0-legacy-susfs-v2`, commit [`36679224f26d03f2bb105c4686cf390eb63178c2`](https://github.com/sidex15/KernelSU-Next/commit/36679224f26d03f2bb105c4686cf390eb63178c2).
- **SuSFS v2.2.0 reference port:** [sreeshankark/android_kernel_oneplus_avicii](https://github.com/sreeshankark/android_kernel_oneplus_avicii), branch `14`, commit [`3f46c998`](https://github.com/sreeshankark/android_kernel_oneplus_avicii/commit/3f46c998). The Pixel 5 adaptation is recorded in `patches/susfs-v2.2.0-redbull.patch`; the build does not clone a separate SuSFS tree.

The exact revisions used by the build are recorded in `config/versions.env`; the patch files in this repository are the reviewable integration layer between those sources and the Pixel 5 kernel tree.

The series includes `susfs-mount-namespace-copy.patch`, which preserves SUSFS mount IDs when an existing mount namespace is copied through `CLONE_NEWNS`.

## Why this workflow uses legacy SuSFS v2

The target is the Pixel 5 Android 14 / Linux 4.19 Google base pinned in
`config/versions.env`. This workflow uses the separately reviewable v2.2.0
reference-port adaptation and KernelSU-Next's matching
`v3.3.0-legacy-susfs-v2` integration ref because the complete patch series is
maintained and ABI-audited against that exact base. This is a compatibility
choice, not a claim that another SuSFS branch is inherently less secure.

No migration to another SuSFS line is currently declared. Any such migration
must be treated as a new integration: pin the candidate sources, rebase every
patch in `patches/series`, apply them without fuzz, complete a clean build,
and require a zero-mismatch stock-vendor ABI report before package or device
testing.

## Licensing and provenance

Executable material and original integration patches are `GPL-2.0-only`; the
README and guide documentation are `CC-BY-4.0`. Patches derived from upstream
projects retain their applicable upstream notices and terms. See
[LICENSE](LICENSE) for scope and [NOTICE](NOTICE) for third-party provenance.

## Inputs

- Pixel 5 (`redfin`) Android 14 kernel checkout under WSL/Linux.
- Matching factory `boot.img`, `vendor_boot.img`, and `vendor.img` in one `stock-images/` directory.
- Android kernel build tools and platform tools (`repo`, Git, Python 3, `lz4`, `cpio`, `mkbootimg`, `unpack_bootimg`, `avbtool`, `fastboot`, and `adb`).
- An unlocked bootloader for device testing.

The pinned Google base and KernelSU-Next revision are recorded in `config/versions.env`. The authoritative patch order is `patches/series`.

## Outputs

The build script produces the kernel and machine-readable evidence in `out/android-msm-pixel-4.19/dist/`:

- `Image.lz4-dtb` and `vmlinux`;
- `ksu-next-susfs-build-proof.txt`, containing source, configuration, integrity, and image hashes;
- `stock-vendor-module-abi-kmi-full-report.txt`, which must report zero CRC mismatches and zero missing symbols.

After a successful build and ABI audit, the packaging script creates replacement `boot.img` and `vendor_boot.img` in a new directory below `repacked-images/`. The release string identifies the integration commit, for example `4.19.278-ksun-susfs-g<integration-sha>`.

Neither script flashes a device. Flashing is a separate, manual step using the generated images; the detailed procedure also covers verification and recovery.

## Workflow

1. Prepare or synchronize the kernel checkout and place the matching stock images in `stock-images/`.
2. Run `build_ksu_next_susfs_kmi.sh` to reset to the pinned base, apply the patch series, build the kernel, and run the stock-vendor ABI audit.
3. Continue only when the build proof and ABI report show a successful build with zero mismatches.
4. Run `package_kernel_images.sh` to create `boot.img` and `vendor_boot.img`.
5. Inspect the package and flash the generated images manually if desired.

See [guide.md](guide.md) for the complete build, packaging, flashing, verification, recovery, and update instructions.
