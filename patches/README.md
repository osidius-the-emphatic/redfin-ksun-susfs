# Pixel 5 KernelSU-Next + SuSFS patch series

`series` is applied in order to a clean `private/msm-google` checkout at the
Google redbull 4.19 base commit. The components are intentionally separate:

- `susfs-v2.2.0-redbull.patch` — SuSFS v2.2.0 kernel files.
- `susfs-mount-namespace-copy.patch` — preserve SUSFS mount IDs while copying a mount namespace.
- `manual-hooks-redbull.patch` — KernelSU-Next manual hooks for this tree.
- `kmi-vfsmount.patch`, `kmi-stat-crc-full.patch`, and `kmi-namei-crc-full.patch` — Pixel 5 KMI/CRC compatibility guards.
- `redbull-defconfig.patch` — redbull defconfig additions.

`ksun-disable-seccomp-filter-count.patch` is applied inside the pinned
KernelSU-Next checkout, not to the Google kernel tree.

## KMI compatibility safeguards

These three patches are intentionally tied to the exact Google base in
`../config/versions.env`; they must be reviewed and revalidated whenever that
base changes.

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
