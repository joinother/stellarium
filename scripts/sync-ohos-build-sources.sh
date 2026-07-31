#!/bin/bash
# Synchronize tracked HarmonyOS source mirrors into the generated hvigor project.
#
# The hvigor project under build/libstellarium-harmonyos is not tracked by Git,
# but it is what assembleHap actually compiles. After rollbacks or agent edits,
# stale generated files can survive there and make Git look clean while the HAP
# still contains old native/ArkUI code.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCES=(
  "harmonyos/AppScope/app.json5:build/libstellarium-harmonyos/AppScope/app.json5"
  "harmonyos/AppScope/resources/base/element/string.json:build/libstellarium-harmonyos/AppScope/resources/base/element/string.json"
  "harmonyos/AppScope/resources/zh_CN/element/string.json:build/libstellarium-harmonyos/AppScope/resources/zh_CN/element/string.json"
  "harmonyos/AppScope/resources/base/media/app_icon.png:build/libstellarium-harmonyos/AppScope/resources/base/media/app_icon.png"
  "harmonyos/cpp-source/hello.cpp:build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp"
  "harmonyos/ets-source/pages/MainWindowNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets"
  "harmonyos/ets-source/pages/StellariumTypes.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/StellariumTypes.ets"
  "harmonyos/ets-source/pages/FloatWindowNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/FloatWindowNativeNode.ets"
  "harmonyos/ets-source/pages/SubWindowNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/SubWindowNativeNode.ets"
  "harmonyos/ets-source/pages/UiExtensionNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/UiExtensionNativeNode.ets"
  "harmonyos/ets-source/pages/I18n.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/I18n.ets"
  "harmonyos/ets-source/qability/QAbility.ets:build/libstellarium-harmonyos/entry/src/main/ets/qability/QAbility.ets"
  "harmonyos/ets-source/qability/StellariumResourceBootstrap.ets:build/libstellarium-harmonyos/entry/src/main/ets/qability/StellariumResourceBootstrap.ets"
  "harmonyos/ets-source/resources/base/media/ic_audio.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_audio.svg"
  "harmonyos/ets-source/resources/base/media/ic_gyro.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_gyro.svg"
  "harmonyos/module.json5:build/libstellarium-harmonyos/entry/src/main/module.json5"
  "harmonyos/resources/base/element/string.json:build/libstellarium-harmonyos/entry/src/main/resources/base/element/string.json"
  "harmonyos/resources/zh_CN/element/string.json:build/libstellarium-harmonyos/entry/src/main/resources/zh_CN/element/string.json"
  "harmonyos/resources/base/media/background.png:build/libstellarium-harmonyos/entry/src/main/resources/base/media/background.png"
  "harmonyos/resources/base/media/foreground.png:build/libstellarium-harmonyos/entry/src/main/resources/base/media/foreground.png"
  "harmonyos/resources/base/media/startIcon.png:build/libstellarium-harmonyos/entry/src/main/resources/base/media/startIcon.png"
)

echo "Synced:"
for item in "${SOURCES[@]}"; do
  SRC="$REPO_ROOT/${item%%:*}"
  DST="$REPO_ROOT/${item#*:}"

  if [ ! -f "$SRC" ]; then
    echo "ERROR: missing tracked source: $SRC" >&2
    exit 1
  fi

  if [ ! -d "$(dirname "$DST")" ]; then
    echo "ERROR: missing hvigor destination dir: $(dirname "$DST")" >&2
    echo "Open/generate the HarmonyOS build project first." >&2
    exit 1
  fi

  cp "$SRC" "$DST"
  echo "  $SRC"
  echo "  -> $DST"
done
