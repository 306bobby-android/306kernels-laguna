#!/usr/bin/env bash
# Decide which ACK tag to build from LineageOS's gs-6.6 kernel manifest.
#
# Lineage pins kernel/common to a monthly ACK release tag, e.g.
#   <project path="common/gki" name="kernel/common" revision="refs/tags/android15-6.6-2026-04_r33" .../>
# Everything else (family, KMI branch, repo manifest branch) derives from that tag.
#
# usage: resolve-kernel.sh [lineage_branch] [ack_tag_override]
set -euo pipefail
. "$(dirname "$0")/common.sh"

LINEAGE_BRANCH="${1:-lineage-24.0}"
ACK_TAG_OVERRIDE="${2:-}"
MANIFEST_URL="https://raw.githubusercontent.com/LineageOS/android_kernel_google_gs-6.6_manifest/${LINEAGE_BRANCH}/default.xml"

if [ -n "$ACK_TAG_OVERRIDE" ]; then
  ACK_TAG="$ACK_TAG_OVERRIDE"
  log "ACK tag overridden by input: $ACK_TAG"
else
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  log "fetching $MANIFEST_URL"
  retry curl -fsSL --max-time 60 -o "$tmp" "$MANIFEST_URL" || die "could not fetch Lineage manifest"
  ACK_TAG="$(python3 - "$tmp" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
hits = [p for p in root.iter("project") if p.get("name") == "kernel/common"]
if len(hits) != 1:
    sys.exit(f"expected exactly one kernel/common project, found {len(hits)}")
rev = hits[0].get("revision") or ""
if not rev.startswith("refs/tags/"):
    sys.exit(f"kernel/common revision is not a tag: '{rev}'")
print(rev[len("refs/tags/"):])
PY
)" || die "manifest parse failed"
fi

# android15-6.6-2026-04_r33 -> android15 / 6.6 / 2026-04 / 33
if [[ "$ACK_TAG" =~ ^(android[0-9]+)-([0-9]+\.[0-9]+)-([0-9]{4}-[0-9]{2})_r([0-9]+)$ ]]; then
  ANDROID_VERSION="${BASH_REMATCH[1]}"
  KERNEL_VERSION="${BASH_REMATCH[2]}"
  OS_PATCH_LEVEL="${BASH_REMATCH[3]}"
else
  die "unrecognised ACK tag '$ACK_TAG' (want android<NN>-<x.y>-<yyyy-mm>_r<n>)"
fi
FAMILY="${ANDROID_VERSION}-${KERNEL_VERSION}"
[ "$FAMILY" = "android15-6.6" ] || die "this repo only builds android15-6.6, manifest says $FAMILY"

ACK_URL="https://android.googlesource.com/kernel/common"
git ls-remote --exit-code --tags "$ACK_URL" "refs/tags/${ACK_TAG}" >/dev/null \
  || die "tag $ACK_TAG does not exist on $ACK_URL"

# The monthly repo manifest branch carries the matching build tooling. Google
# retires old ones (sometimes under deprecated/), so fall back to the family
# branch: only kernel/common is pinned to the tag, the rest is tooling.
MANIFEST_REPO="https://android.googlesource.com/kernel/manifest"
for cand in "common-${FAMILY}-${OS_PATCH_LEVEL}" "deprecated/common-${FAMILY}-${OS_PATCH_LEVEL}" "common-${FAMILY}"; do
  if git ls-remote --exit-code --heads "$MANIFEST_REPO" "refs/heads/${cand}" >/dev/null 2>&1; then
    MANIFEST_BRANCH="$cand"
    break
  fi
done
[ -n "${MANIFEST_BRANCH:-}" ] || die "no usable kernel/manifest branch for $FAMILY"
[ "$MANIFEST_BRANCH" = "common-${FAMILY}-${OS_PATCH_LEVEL}" ] \
  || warn "monthly manifest branch missing, using $MANIFEST_BRANCH for build tooling"

setenv LINEAGE_BRANCH   "$LINEAGE_BRANCH"
setenv ACK_TAG          "$ACK_TAG"
setenv FAMILY           "$FAMILY"
setenv ANDROID_VERSION  "$ANDROID_VERSION"
setenv KERNEL_VERSION   "$KERNEL_VERSION"
setenv OS_PATCH_LEVEL   "$OS_PATCH_LEVEL"
setenv MANIFEST_BRANCH  "$MANIFEST_BRANCH"

ok "lineage_branch=$LINEAGE_BRANCH ack_tag=$ACK_TAG family=$FAMILY os_patch_level=$OS_PATCH_LEVEL manifest_branch=$MANIFEST_BRANCH"
