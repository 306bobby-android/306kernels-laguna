#!/usr/bin/env bash
# repo init the ACK build tree and pin kernel/common to $ACK_TAG.
set -euo pipefail
. "$(dirname "$0")/common.sh"
: "${ACK_TAG:?run resolve-kernel.sh first}" "${MANIFEST_BRANCH:?}"

mkdir -p "$KERNEL_ROOT"
cd "$KERNEL_ROOT"

# Stall abort: die after 60s under 1KB/s instead of hanging the job.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=http.lowSpeedLimit GIT_CONFIG_VALUE_0=1024
export GIT_CONFIG_KEY_1=http.lowSpeedTime  GIT_CONFIG_VALUE_1=60

attempt=1
while :; do
  log "repo init -b $MANIFEST_BRANCH (attempt $attempt)"
  if repo init -u https://android.googlesource.com/kernel/manifest -b "$MANIFEST_BRANCH" --depth=1 </dev/null; then
    M=.repo/manifests/default.xml
    # repo treats a bare revision as a branch name, so pin the tag by full ref.
    sed -i "/path=\"common\"/ s|revision=\"[^\"]*\"|revision=\"refs/tags/${ACK_TAG}\"|" "$M"
    grep -q "refs/tags/${ACK_TAG}" "$M" || die "could not pin common to $ACK_TAG in $M"
    if timeout 20m repo sync -c --current-branch --no-clone-bundle --jobs-checkout="$(nproc)" -j16; then
      break
    fi
  fi
  [ "$attempt" -lt 4 ] || die "repo sync failed after $attempt attempts"
  warn "sync failed, cleaning and retrying"
  find "$KERNEL_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  sleep $((attempt * 20))
  attempt=$((attempt + 1))
done

[ -f "$COMMON/Makefile" ] || die "common/Makefile missing after sync"
GOT="$(git -C "$COMMON" describe --tags --exact-match 2>/dev/null || true)"
[ "$GOT" = "$ACK_TAG" ] || die "common is at '$GOT', expected tag $ACK_TAG"

SUBLEVEL="$(sed -n 's/^SUBLEVEL[[:space:]]*=[[:space:]]*\([0-9]\+\)[[:space:]]*$/\1/p' "$COMMON/Makefile")"
[[ "$SUBLEVEL" =~ ^[0-9]+$ ]] || die "could not read SUBLEVEL from common/Makefile"
KMI="$(grep -h '^KMI_GENERATION=' "$COMMON/build.config.common" "$COMMON/build.config.constants" 2>/dev/null | head -n1 | cut -d= -f2)"
[[ "$KMI" =~ ^[0-9]+$ ]] || die "could not read KMI_GENERATION"

setenv SUBLEVEL "$SUBLEVEL"
setenv KMI_GENERATION "$KMI"
setenv KERNEL_SOURCE_COMMIT "$(git -C "$COMMON" rev-parse HEAD)"
ok "synced $ACK_TAG: ${KERNEL_VERSION:-6.6}.$SUBLEVEL KMI $KMI commit ${KERNEL_SOURCE_COMMIT:0:12}"
