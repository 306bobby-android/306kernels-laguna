#!/usr/bin/env bash
# Kleaf build of the GKI image, then sanity-check the resolved .config.
set -euo pipefail
. "$(dirname "$0")/common.sh"

cd "$KERNEL_ROOT"
[ -x tools/bazel ] || die "tools/bazel missing; this is not a Kleaf tree"
# Stamp the image with the ACK tag's commit date instead of the epoch-0 that
# Kleaf's hermetic build otherwise writes into "Linux version ... #1 SMP".
SOURCE_DATE_EPOCH="$(git -C "$COMMON" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH
KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$SOURCE_DATE_EPOCH" '+%a %b %d %H:%M:%S UTC %Y')"
export KBUILD_BUILD_TIMESTAMP
tools/bazel build --config=fast --disk_cache="${BAZEL_DISK_CACHE:-$HOME/.cache/bazel}" //common:kernel_aarch64/Image

CONFIG_FILE="bazel-bin/common/kernel_aarch64_config/out_dir/.config"
[ -f "$CONFIG_FILE" ] || CONFIG_FILE="$(find bazel-bin/common -maxdepth 4 -name .config -type f 2>/dev/null | head -n1 || true)"
[ -n "$CONFIG_FILE" ] || die "could not locate the generated .config"
log "checking $CONFIG_FILE"
# KPROBES: stable's KernelSU-Next hooks; KALLSYMS_ALL: its susfs guard LKM resolves unexported symbols by name
want="CONFIG_KSU=y CONFIG_KPROBES=y CONFIG_KALLSYMS_ALL=y CONFIG_SYSVIPC=y CONFIG_IPC_NS=y CONFIG_PID_NS=y CONFIG_ARM64_4K_PAGES=y"
[ "${FLAVOR:-stable}" = susfs ] && want="$want CONFIG_KSU_SUSFS=y"
for want in $want; do
  grep -qx "$want" "$CONFIG_FILE" || die "$want missing from final .config"
done
grep -E '^#? ?CONFIG_KSU' "$CONFIG_FILE" || true

IMG=bazel-bin/common/kernel_aarch64/Image
[ -f "$IMG" ] || die "no Image at $IMG"
mkdir -p "$WORKSPACE/out"
cp "$IMG" "$WORKSPACE/out/Image"
ok "Image built: $(stat -c %s "$WORKSPACE/out/Image") bytes"
