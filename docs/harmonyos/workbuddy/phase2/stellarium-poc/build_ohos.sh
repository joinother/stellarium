#!/usr/bin/env bash
# =============================================================================
# build_ohos.sh —— Stellarium HarmonyOS 最小 PoC 构建脚本
#
# 流程：qt-cmake 配置 → cmake --build → harmonydeployqt 打包
# 目标：harmonyos_arm64_v8a, Qt 6.12.0 Beta2, DevEco 6.1 + SDK API 23
#
# 重要：沙箱内无法真编译。请在用户本地具备以下环境的机器上运行本脚本：
#   1) Qt 6.12.0 Beta2 for HarmonyOS（含 qt-cmake、harmonydeployqt）
#   2) DevEco Studio 6.1.0 + HarmonyOS SDK API 23
# =============================================================================
set -euo pipefail

# ----------------------------------------------------------------------------
# 路径变量（⚠️ 按你本地环境修改以下占位路径）
# ----------------------------------------------------------------------------
# Qt 6.12 HarmonyOS 安装根（包含 bin/qt-cmake、bin/harmonydeployqt）
QT_OHOS_DIR="${QT_OHOS_DIR:-$HOME/Qt/6.12.0/harmonyos_arm64_v8a}"

# DevEco Studio 安装位置（harmonydeployqt 需要调用其 hvigorw）
DEVECO_DIR="${DEVECO_DIR:-/Applications/DevEco-Studio.app/Contents}"

# Qt for HarmonyOS 额外包（Qt Sensors 底层 libohsensor 等）查找根
OHOS_ADDITIONAL_PKGS="${OHOS_ADDITIONAL_PKGS:-$HOME/.local/opt/ohos/additional-packages}"

# 目标架构（Qt for HarmonyOS 约定）
export QT_HARMONYOS_TARGET_ARCHS="${QT_HARMONYOS_TARGET_ARCHS:-arm64-v8a}"

# ----------------------------------------------------------------------------
# 0) 基本校验
# ----------------------------------------------------------------------------
if [ ! -x "${QT_OHOS_DIR}/bin/qt-cmake" ]; then
  echo "[ERR] 找不到 qt-cmake，请修改 QT_OHOS_DIR（当前=${QT_OHOS_DIR}）"
  exit 1
fi
if [ ! -x "${DEVECO_DIR}/tools/hvigor/bin/hvigorw" ]; then
  echo "[ERR] 找不到 hvigorw，请修改 DEVECO_DIR（当前=${DEVECO_DIR}）"
  exit 1
fi

QT_CMAKE="${QT_OHOS_DIR}/bin/qt-cmake"
HARMONYDEPLOYQT="${QT_OHOS_DIR}/bin/harmonydeployqt"

# ----------------------------------------------------------------------------
# 1) 配置（qt-cmake 会自动注入 CMAKE_TOOLCHAIN_FILE 等鸿蒙交叉变量）
# ----------------------------------------------------------------------------
BUILD_DIR="${BUILD_DIR:-$(pwd)/build-ohos}"
mkdir -p "${BUILD_DIR}"

"${QT_CMAKE}" -S "$(pwd)" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_FIND_ROOT_PATH="${OHOS_ADDITIONAL_PKGS}" \
  -DQT_HARMONYOS_TARGET_ARCHS="${QT_HARMONYOS_TARGET_ARCHS}"

# ----------------------------------------------------------------------------
# 2) 编译（并行）
# ----------------------------------------------------------------------------
cmake --build "${BUILD_DIR}" --parallel "$(nproc 2>/dev/null || echo 4)"

# ----------------------------------------------------------------------------
# 3) 打包：harmonydeployqt 调用 DevEco 的 hvigorw 产出 .hap
#    <target>-harmony-deployment-settings.json 由 qt-cmake 配置阶段生成
# ----------------------------------------------------------------------------
DEPLOY_JSON="${BUILD_DIR}/stellarium_poc-harmony-deployment-settings.json"
if [ ! -f "${DEPLOY_JSON}" ]; then
  echo "[ERR] 找不到 deployment settings：${DEPLOY_JSON}"
  echo "       qt-cmake 配置应生成该文件；请检查 CMake 输出。"
  exit 1
fi

"${HARMONYDEPLOYQT}" --verbose \
  --hvigor "${DEVECO_DIR}/tools/hvigor/bin/hvigorw" \
  --input "${DEPLOY_JSON}"

echo ""
echo "[OK] 构建与打包完成。产物 .hap 位于 ${BUILD_DIR} 下。"
echo "     在 DevEco Studio 中打开 ${BUILD_DIR} 目录即可签名/运行到模拟器或真机。"
