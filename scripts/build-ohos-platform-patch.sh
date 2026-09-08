#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QT_PREFIX="${QT_OHOS_PREFIX:-$HOME/Qt/6.12.0/harmonyos_arm64_v8a}"
QT_HOST="${QT_HOST_PATH:-$HOME/Qt/6.12.0/macos}"
SDK_NATIVE="${OHOS_NATIVE_ROOT:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
ADDITIONAL="${OHOS_ADDITIONAL_PKGS:-$HOME/.local/opt/ohos/additional-packages}"
REVISION=97575d35c0cecdc0fb4e12fc3575afaa9fd9d3f1
ARCHIVE_SHA=e0c75f8a39ec73723691086b9fcd96f9af2121cc54552387147daf8d238b69ed
ROOT="$REPO_ROOT/build/qt-platform-patch"
ARCHIVE="${QTBASE_ARCHIVE:-$ROOT/qtbase.tar.gz}"
SOURCE="$ROOT/source/qtbase-$REVISION"
mkdir -p "$ROOT/source"
if [ ! -f "$ARCHIVE" ]; then
  curl --proto '=https' --tlsv1.2 -fL --retry 2 "https://codeload.github.com/qt/qtbase/tar.gz/$REVISION" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$ARCHIVE_SHA" "$ARCHIVE" | shasum -a 256 -c -
node - "$QT_PREFIX" "$REVISION" <<'JS'
const fs = require('fs');
const [prefix, revision] = process.argv.slice(2);
const sbom = JSON.parse(fs.readFileSync(`${prefix}/sbom/qtbase-6.12.0.spdx.json`, 'utf8'));
if (!sbom.packages.some(entry => entry.downloadLocation?.endsWith(`@${revision}`))) {
  throw Error('Qt SDK source revision mismatch; do not reuse this private-API patch');
}
JS
if [ ! -f "$SOURCE/src/plugins/platforms/ohos/qohosclipboardobject.cpp" ]; then
  tar -xzf "$ARCHIVE" -C "$ROOT/source"
fi
PATCH="$REPO_ROOT/harmonyos/qt-platform-patch/clipboard-notification.patch"
if git -C "$SOURCE" apply --check "$PATCH"; then
  git -C "$SOURCE" apply "$PATCH"
else
  git -C "$SOURCE" apply --reverse --check "$PATCH"
fi
"$QT_PREFIX/bin/qt-cmake" -S "$REPO_ROOT/harmonyos/qt-platform-patch" -B "$ROOT/compiled" -G Ninja \
  -DQTBASE_SOURCE="$SOURCE" -DQT_HOST_PATH="$QT_HOST" \
  -DQT_CHAINLOAD_TOOLCHAIN_FILE="$SDK_NATIVE/build/cmake/ohos.toolchain.cmake" \
  "-DQT_ADDITIONAL_PACKAGES_PREFIX_PATH=$SDK_NATIVE;$ADDITIONAL" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$ROOT/install" -DCMAKE_STAGING_PREFIX="$ROOT/install"
cmake --build "$ROOT/compiled" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-6}" --target QOhosPlatformIntegrationPlugin
node - "$REPO_ROOT" "$QT_PREFIX" "$REVISION" <<'JS'
const fs = require('fs');
const crypto = require('crypto');
const [root, prefix, revision] = process.argv.slice(2);
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const manifest = { revision, patch: 'clipboard-notification-20260908',
  patchSha256: hash(`${root}/harmonyos/qt-platform-patch/clipboard-notification.patch`),
  librarySha256: hash(`${root}/build/qt-platform-patch/compiled/plugins/platforms/libqohos.so`),
  sdkLibraries: Object.fromEntries(['libQt6Core.so', 'libQt6Gui.so', 'libQt6OpenGL.so'].map(name => [name, hash(`${prefix}/lib/${name}`)])) };
fs.writeFileSync(`${root}/build/qt-platform-patch/manifest.json`, JSON.stringify(manifest, null, 2) + '\n');
console.log('Patched Qt platform built; global SDK and signing unchanged.');
JS
node "$REPO_ROOT/scripts/check-ohos-platform-patch.mjs" --sync
