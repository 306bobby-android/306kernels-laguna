#!/usr/bin/env bash
# Integrate KernelSU-Next (susfs-integrated tree) into the ACK source.
# Mirrors WildKernels' root-setup for flavor "next".
#
# KSUN_REPO / KSUN_REF: where the kernel-side code comes from. Default is
# pershoot's dev-susfs branch: upstream KernelSU-Next/KernelSU-Next `dev` has no
# susfs support in-tree; pershoot mirrors `dev` and layers the susfs hooks on
# top. The manager is still the official KernelSU-Next release.
set -euo pipefail
. "$(dirname "$0")/common.sh"

KSUN_REPO="${KSUN_REPO:-https://github.com/pershoot/KernelSU-Next.git}"
KSUN_REF="${KSUN_REF:-dev-susfs}"
KSUN_UPSTREAM_BRANCH="${KSUN_UPSTREAM_BRANCH:-dev}"   # what the version counter is measured against
DIR="$KERNEL_ROOT/KernelSU-Next"

cd "$KERNEL_ROOT"
[ -d "$COMMON/drivers" ] || die "no $COMMON/drivers"
[ ! -e "$COMMON/drivers/kernelsu" ] || die "drivers/kernelsu already exists"
[ ! -e "$DIR" ] || die "$DIR already exists"

sha="$(resolve_ref "$KSUN_REPO" "$KSUN_REF")"
require_sha "$sha"
log "KernelSU-Next: $KSUN_REPO @ $KSUN_REF -> $sha"
retry git clone --no-checkout "$KSUN_REPO" "$DIR"
git -C "$DIR" fetch origin "$sha"
git -C "$DIR" checkout --detach "$sha"
[ "$(git -C "$DIR" rev-parse HEAD)" = "$sha" ] || die "KernelSU-Next checkout mismatch"
[ -f "$DIR/.git/shallow" ] && die "KernelSU-Next clone is shallow; version count would be wrong"

# kernel/Kbuild derives KSU_VERSION from `git rev-parse --abbrev-ref HEAD`,
# which is the literal "HEAD" on a detached checkout and makes the version
# depend on clone layout. Pin it: 30000 + commit count at the merge-base with
# upstream dev, which is also the number the official manager reports.
base="$(git -C "$DIR" merge-base HEAD "refs/remotes/origin/${KSUN_UPSTREAM_BRANCH}" 2>/dev/null || echo "$sha")"
count="$(git -C "$DIR" rev-list --count "$base")"
tag="$(git -C "$DIR" describe --tags --abbrev=0 "$base" 2>/dev/null || echo unknown)"
version=$((30000 + count))
kbuild="$DIR/kernel/Kbuild"
[ -f "$kbuild" ] && [ -f "$DIR/kernel/Kconfig" ] && [ -f "$DIR/kernel/Makefile" ] || die "no kernel integration in $DIR"
if grep -q 'BASE_BRANCH' "$kbuild" && ! grep -q '^# CI: deterministic KSU_VERSION' "$kbuild"; then
  {
    echo ''
    echo '# CI: deterministic KSU_VERSION (appended by scripts/setup-ksun.sh).'
    echo "KSU_VERSION := $version"
    echo "KSU_VERSION_TAG := \"$tag\""
  } >> "$kbuild"
fi
# Older Kbuilds hard-error at mrproper time when neither KPROBES nor KSU_SUSFS
# is set yet (no .config exists then). Demote to a warning; no-op today.
if grep -q 'KernelSU requires either CONFIG_KPROBES' "$kbuild"; then
  sed -i 's/$(error "KernelSU requires either CONFIG_KPROBES=y or CONFIG_KSU_SUSFS=y")/$(warning "KernelSU requires either CONFIG_KPROBES=y or CONFIG_KSU_SUSFS=y")/' "$kbuild"
fi

rel="$(realpath --relative-to="$COMMON/drivers" "$DIR/kernel")"
ln -s "$rel" "$COMMON/drivers/kernelsu"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$COMMON/drivers/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$COMMON/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$COMMON/drivers/Kconfig" \
  || sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' "$COMMON/drivers/Kconfig"

"$REPO_ROOT/scripts/set-kernel-config.sh" "$REPO_ROOT/configs/ksu.config"

setenv KSUN_COMMIT "$sha"
setenv KSUN_BASE_COMMIT "$base"
setenv KSUN_VERSION_CODE "$version"
setenv KSUN_DESCRIBE "$(git -C "$DIR" describe --tags --always)"
ok "KernelSU-Next $KSUN_DESCRIBE (version $version, base ${base:0:12})"
