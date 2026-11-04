# First-run risks

Things ported from WildKernels that could not be exercised locally (no Kleaf
build was run here). Everything up to the build step was dry-run against the
real `android15-6.6-2026-04_r33` tree and applied cleanly.

1. `tools/bazel build --config=fast //common:kernel_aarch64/Image` on the
   `common-android15-6.6-2026-04` manifest: WildKernels builds every 6.6 leg
   this way, but with a manifest branch tip, not a pinned tag. The tag is on
   the same branch, so tooling should match.
2. `scripts/prepare-build.sh` rewrites the last line of `scripts/setlocalversion`
   to `echo "6.6.127-android15-8-306kernels"` and strips `-maybe-dirty` from
   `build/kernel/kleaf/impl/stamp.bzl`. If `uname -r` on device shows a
   different string, Kleaf is overriding the release string somewhere else.
3. The protected-exports removal deletes `android/abi_gki_protected_exports_aarch64`
   and its `protected_exports_list` entries. 6.6 does not have
   `protected_module_names_list`, and its `modules.bzl` builds the protected
   module list from a function, so that part is a no-op (same as WildKernels).
4. KernelSU-Next kernel code comes from `pershoot/KernelSU-Next` `dev-susfs`
   (upstream `dev` has no susfs hooks). The reported version is
   30000 + commit count at the merge-base with `dev` (33455 at the time of
   writing), which is what the official manager also reports for that commit.
5. susfs: branch tip of `gki-android15-6.6` plus two pershoot cherry-picks
   (`6387756`, `161c058`). Both picked cleanly on 2026-11-03; if the branch
   moves they may conflict and the job will fail loudly.
6. Droidspaces SYSVIPC padding hunk applied with fuzz 2 / offset 11 on this
   tag. The result was inspected and is correct (`ANDROID_KABI_USE(6, ...)`
   inside `task_struct`), but re-check after an ACK bump.
7. The ACK tag tree ships a stray `mm/rmap.c.rej` upstream. It is not ours
   and is harmless; the "collect rejects" step only copies files newer than
   `Makefile`, so it will not show up there.
8. Runner disk: a 6.6 Kleaf tree plus bazel cache is close to the limit even
   after the free-disk-space step. If the job dies with ENOSPC, drop
   `--disk_cache`.
