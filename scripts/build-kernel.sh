#!/usr/bin/env bash
# Kleaf build of the GKI image, then sanity-check the resolved .config.
set -euo pipefail
. "$(dirname "$0")/common.sh"

cd "$KERNEL_ROOT"
[ -x tools/bazel ] || die "tools/bazel missing; this is not a Kleaf tree"
tools/bazel build --config=fast --disk_cache="${BAZEL_DISK_CACHE:-$HOME/.cache/bazel}" //common:kernel_aarch64/Image

CONFIG_FILE="bazel-bin/common/kernel_aarch64_config/out_dir/.config"
[ -f "$CONFIG_FILE" ] || CONFIG_FILE="$(find bazel-bin/common -maxdepth 4 -name .config -type f 2>/dev/null | head -n1 || true)"
[ -n "$CONFIG_FILE" ] || die "could not locate the generated .config"
log "checking $CONFIG_FILE"
for want in CONFIG_KSU=y CONFIG_KSU_SUSFS=y CONFIG_SYSVIPC=y CONFIG_IPC_NS=y CONFIG_PID_NS=y CONFIG_ARM64_4K_PAGES=y; do
  grep -qx "$want" "$CONFIG_FILE" || die "$want missing from final .config"
done
grep -E '^#? ?CONFIG_KSU' "$CONFIG_FILE" || true

IMG=bazel-bin/common/kernel_aarch64/Image
[ -f "$IMG" ] || die "no Image at $IMG"
log "susfs strings in Image: $(grep -ac susfs "$IMG" || true)"
mkdir -p "$WORKSPACE/out"
cp "$IMG" "$WORKSPACE/out/Image"
ok "Image built: $(stat -c %s "$WORKSPACE/out/Image") bytes"
