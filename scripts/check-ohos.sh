#!/bin/bash
# HarmonyOS 代码提交前检查脚本
# 用法: ./scripts/check-ohos.sh
# 功能: 检查 ETS 同步、ArkTS 反模式、编译是否通过

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

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
    echo -e "${RED}  ❌ $f: 发现 setTimeout 中使用 this（ArkTS 禁止）${NC}"
    ERRORS=$((ERRORS + 1))
  fi

done

if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}  ✅ 未发现 ArkTS 反模式${NC}"
fi

echo ""

# 3. 尝试编译（可选，如果环境已配置）
echo "[3/3] 尝试编译 HAP..."
if command -v hvigorw >/dev/null 2>&1 || [ -f "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" ]; then
  HVIORW="/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw"
  if [ -f "$HVIORW" ]; then
    cd build/libstellarium-harmonyos
    if env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
       JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
       OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
       "$HVIORW" assembleHap --no-daemon > /tmp/hvigor-check.log 2>&1; then
      echo -e "${GREEN}  ✅ HAP 编译通过${NC}"
    else
      echo -e "${RED}  ❌ HAP 编译失败${NC}"
      echo "     日志: /tmp/hvigor-check.log"
      tail -20 /tmp/hvigor-check.log
      ERRORS=$((ERRORS + 1))
    fi
    cd - > /dev/null
  else
    echo -e "${YELLOW}  ⚠️  未找到 hvigorw，跳过编译检查${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
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
