#!/usr/bin/env bash
# Pre-build tree edits: version string, dirty-flag cleanup, protected-exports
# removal (we add exported symbols the GKI protected list does not know), and
# the check_defconfig gate (our gki_defconfig deliberately differs from stock).
set -euo pipefail
. "$(dirname "$0")/common.sh"
: "${KERNEL_VERSION:?}" "${SUBLEVEL:?}" "${ANDROID_VERSION:?}" "${KMI_GENERATION:?}"
BRAND="${BRAND:-306kernels}"

cd "$COMMON"

# uname -r: keep the KMI so it reads like a stock GKI (6.6.127-android15-8-306kernels).
# scripts/setlocalversion's last line is the echo of the full release string.
RELEASE="${KERNEL_VERSION}.${SUBLEVEL}-${ANDROID_VERSION}-${KMI_GENERATION}-${BRAND}"
last="$(tail -n1 scripts/setlocalversion)"
case "$last" in
  *'scm_version}"'*|'echo "'*) sed -i '$d' scripts/setlocalversion ;;
  *) die "scripts/setlocalversion shape changed (last line: $last); refusing to brand blindly" ;;
esac
echo "echo \"${RELEASE}\"" >> scripts/setlocalversion
chmod +x scripts/setlocalversion
setenv KERNEL_RELEASE "$RELEASE"

# Kleaf stamps -maybe-dirty outside --config=stamp; drop it and the -dirty tag.
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" "$KERNEL_ROOT/build/kernel/kleaf/impl/stamp.bzl"
sed -i 's/-dirty//' scripts/setlocalversion

# Protected exports / modules lists would reject the symbols KernelSU adds.
rm -rf android/abi_gki_protected_exports_*
if grep -q '"protected_exports_list"' BUILD.bazel; then
  perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' BUILD.bazel
  grep -q '"protected_exports_list"' BUILD.bazel && die "protected_exports_list still referenced in BUILD.bazel"
fi
if grep -q '^protected_modules = ' modules.bzl; then
  sed -i 's/protected_modules = \[.*\]/protected_modules = []/' modules.bzl
fi
if grep -q 'protected_module_names_list' BUILD.bazel; then
  perl -pi -e 's/^\s*protected_module_names_list\s*=\s*":[A-Za-z0-9_]*_protected_module_names",\s*$//;' BUILD.bazel
  grep -q 'protected_module_names_list' BUILD.bazel && die "protected_module_names_list still referenced in BUILD.bazel"
fi

# 6.6 gates on POST_DEFCONFIG_CMDS="check_defconfig" in build.config.gki; newer
# trees also carry a per-target check_defconfig attr (6.12+). Handle both.
sed -i 's/check_defconfig//' build.config.gki
if grep -q 'name = "kernel_aarch64",' BUILD.bazel; then
  sed -i '/name = "kernel_aarch64",/a\    check_defconfig = "disabled",' BUILD.bazel
fi

# Commit so the tree is not dirty during the build.
git config user.name  "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add -A
git commit -q -m "306kernels: KernelSU-Next + Droidspaces on ${ACK_TAG:-unknown}" || true
ok "release string $RELEASE"
