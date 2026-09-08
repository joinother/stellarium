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

node "$SCRIPT_DIR/check-ohos-platform-patch.mjs" --sync

SOURCES=(
  # DevEco owns build-profile.json5 and its local signing credentials; never sync it here.
  "harmonyos/AppScope/app.json5:build/libstellarium-harmonyos/AppScope/app.json5"
  "harmonyos/AppScope/resources/base/element/string.json:build/libstellarium-harmonyos/AppScope/resources/base/element/string.json"
  "harmonyos/AppScope/resources/zh_CN/element/string.json:build/libstellarium-harmonyos/AppScope/resources/zh_CN/element/string.json"
  "harmonyos/AppScope/resources/base/media/app_icon.png:build/libstellarium-harmonyos/AppScope/resources/base/media/app_icon.png"
  "harmonyos/AppScope/resources/base/media/app_icon.png:build/libstellarium-harmonyos/entry/src/main/resources/base/media/app_icon.png"
  "harmonyos/cpp-source/hello.cpp:build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp"
  "harmonyos/cpp-source/PresentationGeometry.h:build/libstellarium-harmonyos/entry/src/main/cpp/PresentationGeometry.h"
  "harmonyos/ets-source/common/QtAppConstants.ets:build/libstellarium-harmonyos/entry/src/main/ets/common/QtAppConstants.ets"
  "harmonyos/ets-source/qability/ClipboardService.ets:build/libstellarium-harmonyos/entry/src/main/ets/qability/ClipboardService.ets"
  "harmonyos/ets-source/common/StellariumLifecycle.ets:build/libstellarium-harmonyos/entry/src/main/ets/common/StellariumLifecycle.ets"
  "harmonyos/ets-source/pages/PrivacyBootstrap.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/PrivacyBootstrap.ets"
  "harmonyos/ets-source/pages/MainWindowNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets"
  "harmonyos/ets-source/pages/AstronomyGuide.ts:build/libstellarium-harmonyos/entry/src/main/ets/pages/AstronomyGuide.ts"
  "harmonyos/ets-source/pages/location_hierarchy.ts:build/libstellarium-harmonyos/entry/src/main/ets/pages/location_hierarchy.ts"
  "harmonyos/ets-source/pages/location_countries.ts:build/libstellarium-harmonyos/entry/src/main/ets/pages/location_countries.ts"
  "harmonyos/ets-source/pages/location_names_zh.ts:build/libstellarium-harmonyos/entry/src/main/ets/pages/location_names_zh.ts"
  "harmonyos/ets-source/pages/StellariumAudio.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/StellariumAudio.ets"
  "harmonyos/ets-source/pages/StellariumTypes.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/StellariumTypes.ets"
  "harmonyos/ets-source/pages/DetailModelGeometry.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/DetailModelGeometry.ets"
  "harmonyos/ets-source/pages/ProceduralDetailModel.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/ProceduralDetailModel.ets"
  "harmonyos/ets-source/pages/DetailModelRenderTypes.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/DetailModelRenderTypes.ets"
  "harmonyos/ets-source/pages/DetailModelRasterizer.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/DetailModelRasterizer.ets"
  "harmonyos/ets-source/pages/DetailModelWorker.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/DetailModelWorker.ets"
  "harmonyos/ets-source/pages/DetailModelRenderClient.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/DetailModelRenderClient.ets"
  "harmonyos/ets-source/pages/FloatWindowNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/FloatWindowNativeNode.ets"
  "harmonyos/ets-source/pages/SubWindowNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/SubWindowNativeNode.ets"
  "harmonyos/ets-source/pages/UiExtensionNativeNode.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/UiExtensionNativeNode.ets"
  "harmonyos/ets-source/pages/I18n.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/I18n.ets"
  "harmonyos/ets-source/qability/QAbility.ets:build/libstellarium-harmonyos/entry/src/main/ets/qability/QAbility.ets"
  "harmonyos/ets-source/qability/QtWindowStageAdapter.ets:build/libstellarium-harmonyos/entry/src/main/ets/qability/QtWindowStageAdapter.ets"
  "harmonyos/ets-source/common/PrivacyStartup.ets:build/libstellarium-harmonyos/entry/src/main/ets/common/PrivacyStartup.ets"
  "harmonyos/ets-source/pages/ApplicationRoot.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/ApplicationRoot.ets"
  "harmonyos/ets-source/pages/StartupSky.ets:build/libstellarium-harmonyos/entry/src/main/ets/pages/StartupSky.ets"
  "harmonyos/ets-source/pages/StartupStarGeometry.ts:build/libstellarium-harmonyos/entry/src/main/ets/pages/StartupStarGeometry.ts"
  "harmonyos/ets-source/qabilitystage/QAbilityStage.ets:build/libstellarium-harmonyos/entry/src/main/ets/qabilitystage/QAbilityStage.ets"
  "harmonyos/ets-source/qability/PrivacyConsent.ets:build/libstellarium-harmonyos/entry/src/main/ets/qability/PrivacyConsent.ets"
  "harmonyos/ets-source/qability/StellariumResourceBootstrap.ets:build/libstellarium-harmonyos/entry/src/main/ets/qability/StellariumResourceBootstrap.ets"
  "harmonyos/ets-source/resources/base/media/ic_audio.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_audio.svg"
  "harmonyos/ets-source/resources/base/media/ic_back.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_back.svg"
  "harmonyos/ets-source/resources/base/media/ic_chevron_right.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_chevron_right.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_planet.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_planet.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_moon.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_moon.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_star.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_star.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_variable_star.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_variable_star.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_comet.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_comet.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_asteroid.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_asteroid.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_constellation.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_constellation.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_galaxy.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_galaxy.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_cluster.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_cluster.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_nebula.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_nebula.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_messier.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_messier.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_satellite.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_satellite.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_exoplanet.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_exoplanet.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_pulsar.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_pulsar.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_nova.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_nova.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_supernova.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_supernova.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_quasar.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_quasar.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_aircraft.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_aircraft.svg"
  "harmonyos/ets-source/resources/base/media/ic_catalog_plugin.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_catalog_plugin.svg"
  "harmonyos/ets-source/resources/base/media/ic_gyro.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_gyro.svg"
  "harmonyos/ets-source/resources/base/media/ic_oculars.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_oculars.svg"
  "harmonyos/ets-source/resources/base/media/ic_polar_scope.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_polar_scope.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_conjunction.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_conjunction.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_opposition.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_opposition.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_quadrature_east.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_quadrature_east.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_quadrature_west.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_quadrature_west.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_elongation_east.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_elongation_east.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_elongation_west.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_elongation_west.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_perihelion.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_perihelion.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_aphelion.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_aphelion.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_station.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_station.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_station_direct.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_station_direct.svg"
  "harmonyos/ets-source/resources/base/media/ic_phenomenon_station_retrograde.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_phenomenon_station_retrograde.svg"
  "harmonyos/ets-source/resources/base/media/ic_time_resume.svg:build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_time_resume.svg"
  "harmonyos/module.json5:build/libstellarium-harmonyos/entry/src/main/module.json5"
  "harmonyos/resources/base/profile/main_pages.json:build/libstellarium-harmonyos/entry/src/main/resources/base/profile/main_pages.json"
  "harmonyos/resources/base/profile/easy_go.json:build/libstellarium-harmonyos/entry/src/main/resources/base/profile/easy_go.json"
  "harmonyos/resources/base/element/string.json:build/libstellarium-harmonyos/entry/src/main/resources/base/element/string.json"
  "harmonyos/resources/zh_CN/element/string.json:build/libstellarium-harmonyos/entry/src/main/resources/zh_CN/element/string.json"
  "harmonyos/resources/base/media/background.png:build/libstellarium-harmonyos/entry/src/main/resources/base/media/background.png"
  "harmonyos/resources/base/media/foreground.png:build/libstellarium-harmonyos/entry/src/main/resources/base/media/foreground.png"
  "harmonyos/resources/base/media/startIcon.png:build/libstellarium-harmonyos/entry/src/main/resources/base/media/startIcon.png"
)

echo "Synced:"
node "$REPO_ROOT/scripts/configure-ohos-model-worker.mjs"
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

# The native Stellarium library is produced by the cross-compiled CMake build.
# Keep the generated hvigor project from silently packaging an older .so after
# the C++ source was rebuilt.
NATIVE_SOURCE="$REPO_ROOT/build/src/libstellarium.so"
NATIVE_TARGET="$REPO_ROOT/build/libstellarium-harmonyos/entry/libs/arm64-v8a/libstellarium.so"
if [ -f "$NATIVE_SOURCE" ]; then
  if [ ! -d "$(dirname "$NATIVE_TARGET")" ]; then
    echo "ERROR: missing native library destination dir: $(dirname "$NATIVE_TARGET")" >&2
    exit 1
  fi
  cp "$NATIVE_SOURCE" "$NATIVE_TARGET"
  echo "  $NATIVE_SOURCE"
  echo "  -> $NATIVE_TARGET"
else
  echo "WARNING: missing cross-compiled libstellarium.so at $NATIVE_SOURCE; generated HAP may contain an older native library" >&2
fi

# Keep every localized system label in the generated project. Resource
# directories are created here because a newly added locale may not exist in
# the generated build tree yet.
for tree in AppScope/resources resources; do
  while IFS= read -r src; do
    rel="${src#${REPO_ROOT}/harmonyos/}"
    dst="$REPO_ROOT/build/libstellarium-harmonyos/$rel"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  $src"
    echo "  -> $dst"
  done < <(find "$REPO_ROOT/harmonyos/$tree" -type f -path '*/element/string.json' -print | sort)
done

OHOS_ADDITIONAL_PKGS="${OHOS_ADDITIONAL_PKGS:-$HOME/.local/opt/ohos/additional-packages}"
JPEG_SOURCE="$OHOS_ADDITIONAL_PKGS/lib/libjpeg.so"
JPEG_TARGET="$REPO_ROOT/build/libstellarium-harmonyos/entry/libs/arm64-v8a/libjpeg.so"
if [ -f "$JPEG_SOURCE" ]; then
  mkdir -p "$(dirname "$JPEG_TARGET")"
  cp "$JPEG_SOURCE" "$JPEG_TARGET"
  echo "  $JPEG_SOURCE"
  echo "  -> $JPEG_TARGET"
else
  echo "WARNING: missing HarmonyOS libjpeg.so at $JPEG_SOURCE; JPEG textures will not load" >&2
fi
