#!/bin/bash
# HarmonyOS 代码提交前检查脚本
# 用法: ./scripts/check-ohos.sh
# 功能: 检查 ETS 同步、ArkTS 反模式、编译是否通过

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dev-env.sh
source "$SCRIPT_DIR/dev-env.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

if ! node "$SCRIPT_DIR/check-ohos-platform-patch.mjs"; then
  echo "Qt platform patch validation failed; run scripts/build-ohos-platform-patch.sh before packaging."
  exit 1
fi

echo "=== HarmonyOS 提交前检查 ==="
echo ""

# 1. 检查 ETS 文件同步
echo "[1/3] 检查 ETS 文件同步..."
SRC="build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets"
DST="harmonyos/ets-source/pages/MainWindowNativeNode.ets"

if [ -f "$SRC" ] && [ -f "$DST" ]; then
  if diff -q "$SRC" "$DST" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✅ ETS 文件已同步${NC}"
  else
    echo -e "${RED}  ❌ ETS 文件不同步！${NC}"
    echo "     源文件: $SRC"
    echo "     备份:   $DST"
    echo "     修复:   cp $SRC $DST"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo -e "${YELLOW}  ⚠️  文件缺失，跳过同步检查${NC}"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 2. 检查 ArkTS 反模式
echo "[2/3] 检查 ArkTS 反模式..."
ETS_FILES=$(find build/libstellarium-harmonyos/entry/src/main/ets harmonyos/ets-source -name "*.ets" 2>/dev/null || true)

for f in $ETS_FILES; do
  # any type
  if grep -n ": any" "$f" > /dev/null 2>&1; then
    echo -e "${RED}  ❌ $f: 发现 'any' 类型（ArkTS 禁止）${NC}"
    ERRORS=$((ERRORS + 1))
  fi

  # ESObject cast
  if grep -n "as ESObject" "$f" > /dev/null 2>&1; then
    echo -e "${RED}  ❌ $f: 发现 'as ESObject'（应使用 interface）${NC}"
    ERRORS=$((ERRORS + 1))
  fi

  # this in setTimeout
  if grep -n "setTimeout.*=>.*this\." "$f" > /dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠️  $f: setTimeout 闭包捕获 this，已由 CompileArkTS 实际编译结果确认可用${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

done

if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}  ✅ 未发现 ArkTS 反模式${NC}"
fi

echo ""

echo "[2.5/3] 检查 JPEG 解码运行库..."
JPEG_PLUGIN="build/libstellarium-harmonyos/entry/libs/arm64-v8a/imageformats/libqjpeg.so"
JPEG_RUNTIME="build/libstellarium-harmonyos/entry/libs/arm64-v8a/libjpeg.so"
if [ -f "$JPEG_PLUGIN" ] && [ -f "$JPEG_RUNTIME" ]; then
  echo -e "${GREEN}  ✅ libqjpeg.so 的 libjpeg.so 依赖已准备${NC}"
elif [ -f "$JPEG_PLUGIN" ]; then
  echo -e "${RED}  ❌ 缺少 libjpeg.so，行星 JPEG 纹理无法解码${NC}"
  echo "     修复: scripts/sync-ohos-build-sources.sh"
  ERRORS=$((ERRORS + 1))
else
  echo -e "${YELLOW}  ⚠️  未找到 libqjpeg.so，跳过 JPEG 依赖检查${NC}"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 2.75. 检查可离线打包的目录资源
echo "[2.75/3] 检查离线目录资源..."
if node "$SCRIPT_DIR/check-ohos-offline-catalogs.mjs"; then
  echo -e "${GREEN}  ✅ 内置目录资源与 QRC 一致${NC}"
else
  echo -e "${RED}  ❌ 离线目录资源检查失败${NC}"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# 3. 尝试编译（可选，如果环境已配置）
echo "[3/3] 尝试编译 HAP..."
NODE_BIN="$DEVECO_HOME/tools/node/bin/node"
HVIGORW_JS="$DEVECO_HOME/tools/hvigor/bin/hvigorw.js"
SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/sdk}"
OHOS_SDK_HOME="${OHOS_BASE_SDK_HOME:-$SDK_HOME/default/openharmony}"

if [ -x "$NODE_BIN" ] && [ -f "$HVIGORW_JS" ]; then
    cd build/libstellarium-harmonyos
    if env NODE_HOME="$DEVECO_HOME/tools/node/bin" \
       JAVA_HOME="$DEVECO_HOME/jbr/Contents/Home" \
       DEVECO_SDK_HOME="$SDK_HOME" \
       OHOS_BASE_SDK_HOME="$OHOS_SDK_HOME" \
       "$NODE_BIN" "$HVIGORW_JS" --mode module -p product=default \
       assembleHap --analyze=normal --parallel --incremental --daemon > /tmp/hvigor-check.log 2>&1; then
      echo -e "${GREEN}  ✅ HAP 编译通过${NC}"
    else
      echo -e "${RED}  ❌ HAP 编译失败${NC}"
      echo "     日志: /tmp/hvigor-check.log"
      tail -20 /tmp/hvigor-check.log
      ERRORS=$((ERRORS + 1))
    fi
    cd - > /dev/null
else
  echo -e "${YELLOW}  ⚠️  DevEco Studio 未安装，跳过编译检查${NC}"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=== 检查结果 ==="
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}全部通过 ($WARNINGS 个警告)${NC}"
  exit 0
else
  echo -e "${RED}发现 $ERRORS 个错误，请修复后再提交${NC}"
  exit 1
fi
