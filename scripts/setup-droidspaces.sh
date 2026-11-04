#!/usr/bin/env bash
# Droidspaces-OSS support: the SYSVIPC kABI patch for 6.6 plus the GKI-safe config list.
set -euo pipefail
. "$(dirname "$0")/common.sh"
: "${FAMILY:?}"

DS_REPO="${DS_REPO:-https://github.com/ravindu644/Droidspaces-OSS.git}"
DS_REF="${DS_REF:-}"    # optional sha pin; default = main tip
DS_DIR="$WORKSPACE/Droidspaces-OSS"
[ "$FAMILY" = "android15-6.6" ] || die "droidspaces patch selection only wired for android15-6.6"

[ ! -e "$DS_DIR" ] || die "$DS_DIR already exists"
retry git clone --depth=1 "$DS_REPO" "$DS_DIR"
if [ -n "$DS_REF" ]; then
  git -C "$DS_DIR" fetch --depth=1 origin "$DS_REF"
  git -C "$DS_DIR" checkout "$DS_REF"
fi
DS_COMMIT="$(git -C "$DS_DIR" rev-parse HEAD)"

# 5.4..6.6: moves the sysv ipc task_struct fields into ANDROID_KABI padding so
# CONFIG_SYSVIPC/IPC_NS/POSIX_MQUEUE do not shift offsets vendor modules use.
PATCH="$DS_DIR/Documentation/resources/kernel-patches/GKI/below-kernel-6.12/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch"
[ -f "$PATCH" ] || die "missing $PATCH"
cd "$COMMON"
patch -p1 < "$PATCH"

"$REPO_ROOT/scripts/set-kernel-config.sh" "$REPO_ROOT/configs/droidspaces.config"

setenv DROIDSPACES_COMMIT "$DS_COMMIT"
ok "Droidspaces-OSS @ ${DS_COMMIT:0:12} applied"
