#!/usr/bin/env bash
# Integrate KernelSU-Next into the ACK source. Two flavors:
#   stable  official repo at a release tag (KSUN_TAG; "latest" = newest GitHub
#           release). Kprobes-hooked, no kernel patch; susfs is the release's
#           guard LKM. Pairs with the manager apk of that same release.
#   susfs   pershoot/KernelSU-Next dev-susfs (KSUN_SUSFS_REF): upstream dev plus
#           in-kernel susfs hooks for the susfs4ksu patch (setup-susfs.sh).
#           Pairs with upstream's dev manager CI build; the UAPI number is what
#           the manager gates on, so it is checked against upstream dev here.
set -euo pipefail
. "$(dirname "$0")/common.sh"

FLAVOR="${FLAVOR:-stable}"
KSUN_UPSTREAM="https://github.com/KernelSU-Next/KernelSU-Next.git"
case "$FLAVOR" in
  stable) KSUN_REPO="${KSUN_REPO:-$KSUN_UPSTREAM}"; KSUN_REF="${KSUN_TAG:-latest}" ;;
  susfs)  KSUN_REPO="${KSUN_REPO:-https://github.com/pershoot/KernelSU-Next.git}"; KSUN_REF="${KSUN_SUSFS_REF:-dev-susfs}" ;;
  *) die "FLAVOR must be stable or susfs, got '$FLAVOR'" ;;
esac
DIR="$KERNEL_ROOT/KernelSU-Next"

cd "$KERNEL_ROOT"
[ -d "$COMMON/drivers" ] || die "no $COMMON/drivers"
[ ! -e "$COMMON/drivers/kernelsu" ] || die "drivers/kernelsu already exists"
[ ! -e "$DIR" ] || die "$DIR already exists"

uapi_of() { sed -n 's/.*KERNEL_SU_UAPI_VERSION = \([0-9]*\);.*/\1/p' | head -n1; }

if [ "$FLAVOR" = stable ]; then
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
else
  sha="$(resolve_ref "$KSUN_REPO" "$KSUN_REF")"
fi
require_sha "$sha"
log "KernelSU-Next ($FLAVOR): $KSUN_REPO @ $KSUN_REF -> $sha"
retry git clone --no-checkout "$KSUN_REPO" "$DIR"
git -C "$DIR" fetch -q origin "$sha"
git -C "$DIR" checkout -q --detach "$sha"
[ ! -f "$DIR/.git/shallow" ] || die "KernelSU-Next clone is shallow; version count would be wrong"

if [ "$FLAVOR" = stable ]; then
  [ "$(git -C "$DIR" describe --tags --exact-match HEAD)" = "$KSUN_REF" ] || die "HEAD of $DIR is not $KSUN_REF"
  base=HEAD
  tag="$KSUN_REF"
else
  retry git -C "$DIR" fetch -q "$KSUN_UPSTREAM" dev
  dev_tip="$(git -C "$DIR" rev-parse FETCH_HEAD)"
  base="$(git -C "$DIR" merge-base HEAD "$dev_tip")"
  tag="$(git -C "$DIR" describe --tags --abbrev=0 "$base")"
  ours="$(git -C "$DIR" show HEAD:uapi/supercall.h | uapi_of)"
  theirs="$(git -C "$DIR" show "$dev_tip":uapi/supercall.h | uapi_of)"
  [ -n "$ours" ] && [ -n "$theirs" ] || die "could not read KERNEL_SU_UAPI_VERSION"
  [ "$ours" = "$theirs" ] || die "dev-susfs speaks UAPI $ours but upstream dev is at $theirs; the dev manager build would refuse this kernel. Wait for pershoot to rebase."
  setenv KSUN_UAPI "$ours"
  setenv KSUN_DEV_COMMIT "$dev_tip"
fi
# the manager reports 30000 + commit count of the upstream commit it was built
# from; dev-susfs adds its own commits on top, so count at the merge-base
count="$(git -C "$DIR" rev-list --count "$base")"
version=$((30000 + count))

kbuild="$DIR/kernel/Kbuild"
[ -f "$kbuild" ] && [ -f "$DIR/kernel/Kconfig" ] || die "no kernel integration in $DIR"
# Kbuild reads the version from git in this checkout, which Kleaf's sandbox may
# not see; its fallback (1 / v0.0.1) is what the manager reports as a mismatch.
anchor='# Calculate version if git version is available'
grep -qxF "$anchor" "$kbuild" || die "kernel/Kbuild shape changed; cannot pin KSU_VERSION"
awk -v a="$anchor" -v c="$count" -v t="$tag" '
  $0 == a {
    print "# CI: pinned by scripts/setup-ksun.sh"
    print "KSU_GIT_VERSION := " c
    print "KSU_GIT_TAG := " t
    print "KSU_GIT_VERSION_VALID := 1"
    print ""
  }
  { print }' "$kbuild" > "$kbuild.tmp" && mv "$kbuild.tmp" "$kbuild"
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

setenv KSUN_REF "$KSUN_REF"
setenv KSUN_TAG "$tag"
setenv KSUN_COMMIT "$sha"
setenv KSUN_VERSION_CODE "$version"
setenv KSUN_DESCRIBE "$(git -C "$DIR" describe --tags --always HEAD)"
ok "KernelSU-Next $KSUN_DESCRIBE (version $version, ${sha:0:12})"
