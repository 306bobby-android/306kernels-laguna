#!/usr/bin/env bash
# Integrate KernelSU-Next into the ACK source at a release tag.
#
# KSUN_REF is a tag of KSUN_REPO, or "latest" for the newest GitHub release;
# the manager apk attached to that same release is the one that pairs with it.
# The 3.x kernel side hooks through kprobes, so no kernel patch is needed, and
# susfs is the release's guard LKM (ksud loads it; manager: "Enable auto load"),
# not a susfs4ksu kernel patch.
set -euo pipefail
. "$(dirname "$0")/common.sh"

KSUN_REPO="${KSUN_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
KSUN_REF="${KSUN_REF:-latest}"
DIR="$KERNEL_ROOT/KernelSU-Next"

cd "$KERNEL_ROOT"
[ -d "$COMMON/drivers" ] || die "no $COMMON/drivers"
[ ! -e "$COMMON/drivers/kernelsu" ] || die "drivers/kernelsu already exists"
[ ! -e "$DIR" ] || die "$DIR already exists"

if [ "$KSUN_REF" = latest ]; then
  api="${KSUN_REPO#https://github.com/}"
  api="https://api.github.com/repos/${api%.git}/releases/latest"
  auth=()
  if [ -n "${GH_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $GH_TOKEN"); fi
  KSUN_REF="$(curl -fsSL "${auth[@]}" "$api" | jq -r '.tag_name // empty')"
  [ -n "$KSUN_REF" ] || die "could not resolve the latest release of $KSUN_REPO"
fi
# an annotated tag lists twice; the ^{} line is the commit
sha="$(git ls-remote --tags "$KSUN_REPO" "refs/tags/$KSUN_REF" "refs/tags/$KSUN_REF^{}" \
       | awk '/\^\{\}$/ { peeled=$1 } !/\^\{\}$/ { tag=$1 } END { print (peeled ? peeled : tag) }')"
[ -n "$sha" ] || die "'$KSUN_REF' is not a tag on $KSUN_REPO"
require_sha "$sha"
log "KernelSU-Next: $KSUN_REPO @ $KSUN_REF -> $sha"
retry git clone --no-checkout "$KSUN_REPO" "$DIR"
git -C "$DIR" checkout -q --detach "$sha"
[ "$(git -C "$DIR" describe --tags --exact-match HEAD)" = "$KSUN_REF" ] || die "HEAD of $DIR is not $KSUN_REF"
[ ! -f "$DIR/.git/shallow" ] || die "KernelSU-Next clone is shallow; version count would be wrong"

count="$(git -C "$DIR" rev-list --count HEAD)"
version=$((30000 + count))
kbuild="$DIR/kernel/Kbuild"
[ -f "$kbuild" ] && [ -f "$DIR/kernel/Kconfig" ] || die "no kernel integration in $DIR"
# Kbuild reads the version from git in this checkout, which Kleaf's sandbox may
# not see; its fallback (1 / v0.0.1) is what the manager reports as a mismatch.
anchor='# Calculate version if git version is available'
grep -qxF "$anchor" "$kbuild" || die "kernel/Kbuild shape changed; cannot pin KSU_VERSION"
awk -v a="$anchor" -v c="$count" -v t="$KSUN_REF" '
  $0 == a {
    print "# CI: pinned by scripts/setup-ksun.sh"
    print "KSU_GIT_VERSION := " c
    print "KSU_GIT_TAG := " t
    print "KSU_GIT_VERSION_VALID := 1"
    print ""
  }
  { print }' "$kbuild" > "$kbuild.tmp" && mv "$kbuild.tmp" "$kbuild"

rel="$(realpath --relative-to="$COMMON/drivers" "$DIR/kernel")"
ln -s "$rel" "$COMMON/drivers/kernelsu"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$COMMON/drivers/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$COMMON/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$COMMON/drivers/Kconfig" \
  || sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' "$COMMON/drivers/Kconfig"

"$REPO_ROOT/scripts/set-kernel-config.sh" "$REPO_ROOT/configs/ksu.config"

setenv KSUN_TAG "$KSUN_REF"
setenv KSUN_COMMIT "$sha"
setenv KSUN_VERSION_CODE "$version"
ok "KernelSU-Next $KSUN_REF (version $version, ${sha:0:12})"
