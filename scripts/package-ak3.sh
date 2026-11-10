#!/usr/bin/env bash
# Wrap out/Image into this flavor's AnyKernel3 zip and write its release-notes
# section. The release job concatenates header.md + notes-<flavor>.md.
set -euo pipefail
. "$(dirname "$0")/common.sh"
: "${KERNEL_RELEASE:?}" "${ACK_TAG:?}"
FLAVOR="${FLAVOR:-stable}"

STAMP="${BUILD_STAMP:-$(date -u +%Y%m%d)}"
BASE="${KERNEL_VERSION}.${SUBLEVEL}-${ANDROID_VERSION}-${OS_PATCH_LEVEL}_r${ACK_TAG##*_r}-${STAMP}"
NAME="306kernels-laguna-${FLAVOR}-${BASE}"
RELEASE_TAG="laguna-${BASE}"

STAGE="$WORKSPACE/out/ak3"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$REPO_ROOT/anykernel/." "$STAGE/"
case "$FLAVOR" in
  stable) desc="KernelSU-Next ${KSUN_TAG:-release} + Droidspaces (susfs: manager's guard LKM)" ;;
  susfs)  desc="KernelSU-Next dev-susfs + built-in susfs + Droidspaces" ;;
  *) die "unknown FLAVOR $FLAVOR" ;;
esac
grep -q '^kernel.string=' "$STAGE/anykernel.sh" || die "anykernel.sh has no kernel.string"
sed -i "s|^kernel.string=.*|kernel.string=306kernels GKI (laguna) [${FLAVOR}]: ${desc}|" "$STAGE/anykernel.sh"
cp "$WORKSPACE/out/Image" "$STAGE/Image"
( cd "$STAGE" && zip -r9 -q "$WORKSPACE/out/${NAME}.zip" . -x '.git*' )
( cd "$WORKSPACE/out" && sha256sum "${NAME}.zip" | tee "${NAME}.zip.sha256" )

cat > "$WORKSPACE/out/header.md" <<MD
306kernels laguna: GKI ${KERNEL_RELEASE}

Devices: Pixel 10 (frankel), 10 Pro (blazer), 10 Pro XL (mustang), 10 Pro Fold (rango)
Matches LineageOS/crDroid ${LINEAGE_BRANCH:-lineage-24.0} builds (kernel from Lineage's gs-6.6 manifest).
ACK ${ACK_TAG} (${KERNEL_SOURCE_COMMIT:-?}), Droidspaces-OSS ${DROIDSPACES_COMMIT:-?}.

Flash a zip in recovery or with KernelFlasher. Re-flash after every ROM update.
Pick **one** flavor; each pairs with a different manager build.
MD
# sourced by the release job, so quote
printf "RELEASE_TAG='%s'\nRELEASE_TITLE='%s'\n" "$RELEASE_TAG" "laguna ${KERNEL_RELEASE} (${ACK_TAG})" > "$WORKSPACE/out/release.env"

case "$FLAVOR" in
  stable)
    cat > "$WORKSPACE/out/notes-stable.md" <<MD

## stable: \`${NAME}.zip\`

KernelSU-Next **${KSUN_TAG:-?}** (official release, kernel version ${KSUN_VERSION_CODE:-?}, ${KSUN_COMMIT:-?}).
Manager: the apk attached to that [KernelSU-Next release](https://github.com/KernelSU-Next/KernelSU-Next/releases/tag/${KSUN_TAG:-}).
susfs is not built in: turn on "Enable auto load" in the manager's settings and ksud loads
the release's ${ANDROID_VERSION}-${KERNEL_VERSION} susfs guard module at every boot, before module scripts.
MD
    ;;
  susfs)
    cat > "$WORKSPACE/out/notes-susfs.md" <<MD

## susfs: \`${NAME}.zip\`

KernelSU-Next **${KSUN_DESCRIBE:-?}** from pershoot's \`${KSUN_REF:-dev-susfs}\` (${KSUN_COMMIT:-?}), kernel version ${KSUN_VERSION_CODE:-?},
with susfs4ksu **${SUSFS_VERSION:-?}** (${SUSFS_COMMIT:-?}) built into the kernel.
Manager: upstream's dev CI build, [manager.zip](https://nightly.link/KernelSU-Next/KernelSU-Next/workflows/build-manager-ci/dev/manager.zip)
(spoofed package: [manager-spoofed.zip](https://nightly.link/KernelSU-Next/KernelSU-Next/workflows/build-manager-ci/dev/manager-spoofed.zip)).
No released manager pairs with this flavor. It speaks UAPI ${KSUN_UAPI:-?}, same as upstream dev at ${KSUN_DEV_COMMIT:-?} on build day;
if a later dev manager refuses it, upstream bumped the UAPI and the next weekly build catches up.
Root hiding module: sidex15/susfs4ksu-module.
MD
    ;;
  *) die "unknown FLAVOR $FLAVOR" ;;
esac

setenv ZIP_PATH "$WORKSPACE/out/${NAME}.zip"
setenv ZIP_NAME "${NAME}.zip"
setenv RELEASE_TAG "$RELEASE_TAG"
ok "packaged ${NAME}.zip (release tag $RELEASE_TAG)"
