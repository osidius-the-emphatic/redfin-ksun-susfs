# Pixel 5 KernelSU-Next + SuSFS patch series

`series` is applied in order to a clean `private/msm-google` checkout at the
Google redbull 4.19 base commit. The components are intentionally separate:

- `susfs-v2.2.0-redbull.patch` — SuSFS v2.2.0 kernel files.
- `susfs-v2.2.0-hardening.patch` — corrective fixes on top of the SuSFS hooks:
  `getdents*` no longer returns `-EINVAL` when the final batch is entirely
  hidden, `__access_remote_vm` looks up the VMA for every page, and
  `/proc/kallsyms` retains the stock `%px`/`show_value` behaviour when symbol
  hiding is off. Pinned by `SUSFS_HARDENING_PATCH_SHA256` in
  `config/versions.env`.
- `susfs-mount-namespace-copy.patch` — preserve SUSFS mount IDs while copying a mount namespace.
- `susfs-open-redirect-redbull.patch` — SuSFS VFS open-redirect hook only.
- `ksun-supercall-reboot-redbull.patch` — call the KSU/SuSFS reboot dispatcher
  from the normal 4.19 reboot syscall context rather than a reboot kprobe.
- `kmi-vfsmount.patch`, `kmi-stat-crc-full.patch`, and `kmi-namei-crc-full.patch` — Pixel 5 KMI/CRC compatibility guards.
- `redbull-defconfig.patch` — redbull defconfig additions.
- `ksun-v342-redfin-port.patch` — official KernelSU-Next v3.4.2 Linux 4.19
  compatibility and built-in SuSFS bridge. It is
  applied inside the pinned KernelSU-Next checkout, not to the Google kernel
  tree. The redfin defconfig separately enables `CONFIG_KALLSYMS_ALL`, which
  is required by the arm64 syscall-table resolver.
- `ksun-v342-runtime-fixes.patch` — redfin 4.19 runtime fixes applied inside
  the pinned KernelSU-Next checkout after the main port: PMD section mapping
  for the syscall table, exact AArch64 `B`-only CFI syscall-entry thunk resolution, a safe pre-5.10
  seccomp-cache no-op, and bounded kernel-argv copying for SULog. Because this
  is a Git-format patch against the KernelSU checkout, the build script applies
  it with `git apply --check --whitespace=error` followed by `git apply`.

## KMI compatibility safeguards

These three patches are intentionally tied to the exact Google base in
`../config/versions.env`; they must be reviewed and revalidated whenever that
base changes.

`config/versions.env` also pins the SHA-256 of
`susfs-v2.2.0-redbull.patch`. The build script validates that hash before it
resets the source checkout.

The new-file hunk for `include/linux/susfs_def.h` is declared as `+1,116`.
Strict application must retain its closing macro lines and include guard.

The focused v3.4.2 port patch also contains the new compatibility sources
`kernel/compat/kernel_compat.c` and `kernel/compat/kernel_compat.h`. Strict
application must create both files; they are required by the KSU Kbuild.

- `kmi-vfsmount.patch` consumes `ANDROID_KABI_RESERVE(1)` for the SuSFS mount
  ID instead of appending a configuration-dependent field. This preserves the
  expected layout for vendor modules built against the Android KABI reserve.
- `kmi-stat-crc-full.patch` hides the SuSFS-only includes and helper prototype
  from `genksyms`. Thus the exported-symbol CRC calculated for
  `generic_fillattr` remains compatible with the stock module expectation.
- `kmi-namei-crc-full.patch` likewise keeps SuSFS-only declarations out of
  `genksyms` while preserving the normal compiler view used by the kernel.

These patches are not a general ABI guarantee. Before packaging, the build
script runs `tools/verify_stock_vendor_module_abi.sh` against the matching
stock `vendor.img`; packaging must stop unless that report has zero CRC
mismatches and zero missing symbols. Device testing remains required after a
successful ABI report.
