# 306kernels-laguna

GKI `android15-6.6` kernel for the Pixel 10 family with KernelSU-Next and
Droidspaces support, built on GitHub Actions and shipped as an AnyKernel3 zip.
susfs comes from the KernelSU-Next release itself (see below).

Devices: Pixel 10 (frankel), Pixel 10 Pro (blazer), Pixel 10 Pro XL (mustang),
Pixel 10 Pro Fold (rango). Flash it on crDroid or LineageOS `lineage-24.0` builds.

## Which kernel gets built

The ACK revision is not chosen by hand. Each run reads LineageOS's
[gs-6.6 kernel manifest](https://github.com/LineageOS/android_kernel_google_gs-6.6_manifest)
and builds `kernel/common` at the exact tag Lineage pins (currently
`android15-6.6-2026-04_r33`). So the kernel always matches what the ROM's
vendor modules were built against, and the KMI stays stock
(`uname -r` looks like `6.6.127-android15-8-306kernels`).

The workflow accepts an `ack_tag` override and a `lineage_branch` input for
testing a newer or older tag.

## What is in it

- KernelSU-Next, kernel side taken from an official
  [release tag](https://github.com/KernelSU-Next/KernelSU-Next/releases)
  (the newest one by default; `ksun_ref` pins another). It hooks through
  kprobes, so the ACK source is not patched for it. Install the manager apk
  attached to the **same** release; the release notes of every zip name it.
- susfs: KernelSU-Next 3.x no longer carries susfs hooks in the kernel tree.
  Each release ships a `android15-6.6_susfs_guard_lkm.ko` that `ksud` loads
  at boot, before module scripts run. Turn it on once in the manager's
  settings ("Enable auto load"), then install the
  [susfs4ksu-module](https://github.com/sidex15/susfs4ksu-module) as usual.
  The module needs no exported symbols (it resolves everything through
  kallsyms) and ksuinit rewrites its vermagic, so it loads on this kernel
  although the version string differs from stock.
- Droidspaces-OSS: the kABI-safe config set plus the SYSVIPC padding patch, so
  containers work without rebuilding vendor modules. `--cpus` and
  `--pids-limit` are intentionally unavailable (they break the kABI).

Nothing else: no scheduler mods, no BBR, no extra "performance" patches.

## Flashing

1. Grab the zip from Releases.
2. Flash it from recovery (adb sideload works on Lineage recovery) or with
   KernelFlasher / Franco Kernel Manager if you are already rooted.
3. Install the KernelSU-Next manager of the matching release, enable susfs
   auto-load in its settings, then install the susfs module.

The zip only touches the `boot` partition. Every ROM update replaces `boot`,
so re-flash the kernel after each OTA. To go back to stock, flash the ROM's
`boot.img` or dirty-flash the ROM.

## Layout

```
.github/workflows/build.yml   the one job
scripts/                      each step is a plain bash script (run locally with WORKSPACE=...)
configs/                      CONFIG lists applied to gki_defconfig
anykernel/                    AnyKernel3 template; CI drops Image in here and zips it
```

The Kleaf/ACK handling mirrors [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS);
the root setup does not (WildKernels builds the dev branch plus their own
manager, this repo tracks the released pairs).
