#!/usr/bin/env bash
# Fetch susfs4ksu for this family, apply its kernel patch and the post-patch
# fixes WildKernels carries for android15-6.6 + KernelSU-Next.
set -euo pipefail
. "$(dirname "$0")/common.sh"
: "${FAMILY:?}" "${SUBLEVEL:?}" "${OS_PATCH_LEVEL:?}"

SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-${FAMILY}}"
SUSFS_REF="${SUSFS_REF:-}"          # optional sha pin; default = branch tip
SUSFS_DIR="$WORKSPACE/susfs4ksu"
# pershoot's fixes for the next flavor. Both touch only kernel_patches/fs/susfs.c.
PERSHOOT_PICKS=(
  6387756d64b3ab9ececefc4523627a9ee05a7519  # fs/susfs: Allow core to be built with no features
  161c058fed5544a6573d87124f346dadd5c4962d  # fs/susfs: Implement SuSFS and Toolkit coexistence
)

[ ! -e "$SUSFS_DIR" ] || die "$SUSFS_DIR already exists"
log "susfs4ksu: $SUSFS_REPO -b $SUSFS_BRANCH"
retry git clone -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR"
if [ -n "$SUSFS_REF" ]; then git -C "$SUSFS_DIR" checkout "$SUSFS_REF"; fi
SUSFS_COMMIT="$(git -C "$SUSFS_DIR" rev-parse HEAD)"
git -C "$SUSFS_DIR" fetch https://gitlab.com/pershoot/susfs4ksu.git "${PERSHOOT_PICKS[@]}"
for c in "${PERSHOOT_PICKS[@]}"; do
  git -C "$SUSFS_DIR" cherry-pick "$c" || die "cherry-pick $c failed; susfs tip moved under us"
done

PATCH="50_add_susfs_in_gki-${FAMILY}.patch"
cd "$COMMON"
cp "$SUSFS_DIR"/kernel_patches/fs/* fs/
cp "$SUSFS_DIR"/kernel_patches/include/linux/* include/linux/
cp "$SUSFS_DIR/kernel_patches/$PATCH" ./

python3 "$REPO_ROOT/scripts/susfs_guard_priority_helpers.py" fs/susfs.c
# Only -le gates from WildKernels' 6.6 fake patches; all are below our sublevel today.
if [ "$SUBLEVEL" -le 30 ]; then die "sublevel $SUBLEVEL needs the task_mmu.c smaps reshape; not carried here"; fi
if [ "$SUBLEVEL" -le 92 ]; then sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c; fi
if [ "$SUBLEVEL" -le 57 ]; then sed -i '/^#include <linux\/sched\/sysctl.h>$/a #include <linux/zswap.h>' mm/memory.c; fi
python3 "$REPO_ROOT/scripts/susfs_restore_context.py" "$PATCH" "$PWD"

# No --forward: an already-applied or reversed hunk must fail, not be skipped.
patch -p1 < "$PATCH"
python3 "$REPO_ROOT/scripts/susfs_fdinfo_fanotify_arity.py" "$PWD"
# OPEN_REDIRECT calls VMA_PAD_START(), which only exists on trees with Google's
# page-size-migration feature. Provide a no-padding fallback where absent.
if grep -q 'VMA_PAD_START(' fs/proc/task_mmu.c && ! grep -qE '#include <linux/pgsize_migration(_inline)?\.h>|define VMA_PAD_START' fs/proc/task_mmu.c; then
  sed -i '1a #ifndef VMA_PAD_START\n#define VMA_PAD_START(vma) ((vma)->vm_end)\n#endif' fs/proc/task_mmu.c
fi

# selinux_hide.c on 6.6+: clang -Werror on `if (fnptr)` and the three
# *_with_policy helpers must not be static (hooks.c/selinuxfs.c reference them
# after the susfs patch). Idempotent; current pershoot tree already complies.
while IFS= read -r -d '' f; do
  if grep -q "extern void security_dump_masked_av_fn" "$f"; then
    sed -i 's/if (security_dump_masked_av_fn)/if (\&security_dump_masked_av_fn)/g; s/if (security_dump_masked_av_fn != NULL)/if (\&security_dump_masked_av_fn != NULL)/g; s/if (context_struct_compute_av_fn)/if (\&context_struct_compute_av_fn)/g; s/if (context_struct_compute_av_fn != NULL)/if (\&context_struct_compute_av_fn != NULL)/g' "$f"
  elif grep -q "if (security_dump_masked_av_fn" "$f"; then
    sed -i 's/if (security_dump_masked_av_fn)/if (security_dump_masked_av_fn != NULL)/g; s/if (context_struct_compute_av_fn)/if (context_struct_compute_av_fn != NULL)/g' "$f"
  fi
  sed -i 's/^static int security_context_to_sid_with_policy/int security_context_to_sid_with_policy/; s/^static int security_sid_to_context_with_policy/int security_sid_to_context_with_policy/; s/^static void security_compute_av_user_with_policy/void security_compute_av_user_with_policy/; s/^static void __nocfi security_compute_av_user_with_policy/void __nocfi security_compute_av_user_with_policy/' "$f"
done < <(find "$KERNEL_ROOT" -name selinux_hide.c -not -path '*/.git/*' -print0)

"$REPO_ROOT/scripts/set-kernel-config.sh" "$REPO_ROOT/configs/susfs.config"

setenv SUSFS_COMMIT "$SUSFS_COMMIT"
setenv SUSFS_VERSION "$(sed -n 's/^#define SUSFS_VERSION[[:space:]]*"\(.*\)"/\1/p' include/linux/susfs.h)"
ok "susfs $SUSFS_VERSION @ ${SUSFS_COMMIT:0:12} applied"
