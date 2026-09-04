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
