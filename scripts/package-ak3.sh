#!/usr/bin/env bash
# Wrap out/Image into the AnyKernel3 zip and write the release notes.
set -euo pipefail
. "$(dirname "$0")/common.sh"
: "${KERNEL_RELEASE:?}" "${ACK_TAG:?}"

STAMP="${BUILD_STAMP:-$(date -u +%Y%m%d)}"
NAME="306kernels-laguna-${KERNEL_VERSION}.${SUBLEVEL}-${ANDROID_VERSION}-${OS_PATCH_LEVEL}_r${ACK_TAG##*_r}-${STAMP}"
RELEASE_TAG="laguna-${KERNEL_VERSION}.${SUBLEVEL}-${ANDROID_VERSION}-${OS_PATCH_LEVEL}_r${ACK_TAG##*_r}-${STAMP}"

STAGE="$WORKSPACE/out/ak3"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$REPO_ROOT/anykernel/." "$STAGE/"
cp "$WORKSPACE/out/Image" "$STAGE/Image"
( cd "$STAGE" && zip -r9 -q "$WORKSPACE/out/${NAME}.zip" . -x '.git*' )
sha256sum "$WORKSPACE/out/${NAME}.zip" | tee "$WORKSPACE/out/${NAME}.zip.sha256"

cat > "$WORKSPACE/out/release-notes.md" <<MD
306kernels laguna: GKI ${KERNEL_RELEASE}

Devices: Pixel 10 (frankel), 10 Pro (blazer), 10 Pro XL (mustang), 10 Pro Fold (rango)
Matches LineageOS/crDroid ${LINEAGE_BRANCH:-lineage-24.0} builds (kernel from Lineage's gs-6.6 manifest).

| Component | Ref |
| --- | --- |
| ACK | ${ACK_TAG} (${KERNEL_SOURCE_COMMIT:-?}) |
| KernelSU-Next | ${KSUN_DESCRIBE:-?} / ${KSUN_COMMIT:-?} (version ${KSUN_VERSION_CODE:-?}) |
| susfs4ksu | ${SUSFS_VERSION:-?} / ${SUSFS_COMMIT:-?} |
| Droidspaces-OSS | ${DROIDSPACES_COMMIT:-?} |

Flash the zip in recovery or with KernelFlasher. Re-flash after every ROM update.
Manager: official KernelSU-Next release. susfs module: sidex15/susfs4ksu-module.
MD

setenv ZIP_PATH "$WORKSPACE/out/${NAME}.zip"
setenv ZIP_NAME "${NAME}.zip"
setenv RELEASE_TAG "$RELEASE_TAG"
ok "packaged ${NAME}.zip (release tag $RELEASE_TAG)"
