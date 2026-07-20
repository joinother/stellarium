#!/usr/bin/env bash
# =============================================================================
# check_env.sh — Stellarium 鸿蒙移植 · Phase 2 步骤0「环境确认」
# 作者: 包立成（鸿蒙构建与发布专家）
# 用途: best-effort 检测本地前置环境是否齐备，逐项打印 ✅/⚠️/❌
# 约定:
#   ✅ = 已满足
#   ⚠️ = 未能自动确认 / 不达标，需你按提示手动补救（脚本不会因此退出）
#   ❌ = 保留位（当前所有项均为 best-effort，故正常只会出现 ✅/⚠️）
# 退出码恒为 0，方便你反复运行、逐项清零。
# 可覆盖的环境变量:
#   QTDIR        Qt 安装根目录（默认 ~/QtSDK，回退 ~/Qt）
#   OHOS_SDK_ROOT OpenHarmony SDK 自定义根目录（其下应有 openharmony/<api>）
# =============================================================================
set -u

OK="✅"; WARN="⚠️"
pass=0; warn=0

print_item() {
  local mark="$1"; local name="$2"; local msg="$3"
  printf "%s %-26s %s\n" "$mark" "$name" "$msg"
  if [ "$mark" = "$OK" ]; then pass=$((pass+1)); else warn=$((warn+1)); fi
}

# 版本比较: version_ge "$1" "$2" 返回 0 表示 版本1 >= 版本2
version_ge() {
  local a=${1%%-*}; local b=${2%%-*}
  local IFS=.
  local aa=($a); local bb=($b)
  local i an bn
  for ((i=0; i<${#aa[@]} || i<${#bb[@]}; i++)); do
    an=${aa[$i]:-0}; bn=${bb[$i]:-0}
    ((an > bn)) && return 0
    ((an < bn)) && return 1
  done
  return 0
}

# 平台探测
case "$(uname -s)" in
  Darwin*)  PLATFORM=mac;;
  Linux*)   PLATFORM=linux;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM=win;;
  *)        PLATFORM=unknown;;
esac

echo "=============================================================="
echo " Stellarium 鸿蒙移植 — Phase 2 步骤0 环境确认"
echo " 平台: $PLATFORM | 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================================="
echo ""

# -----------------------------------------------------------------------------
# a) DevEco Studio >= 6.1.0
# -----------------------------------------------------------------------------
check_deveco() {
  local required="6.1.0"
  local found="" path=""
  if [ "$PLATFORM" = "mac" ]; then
    local p="/Applications/DevEco-Studio.app"
    if [ -d "$p" ]; then
      path="$p"
      local json="$p/Contents/Resources/product-info.json"
      if [ -f "$json" ]; then
        found=$(grep -o '"version"[^,]*' "$json" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/')
      fi
      [ -z "$found" ] && [ -f "$p/Contents/Resources/build.txt" ] && found=$(head -1 "$p/Contents/Resources/build.txt")
    fi
  else
    local candidates=(
      "/c/Program Files/Huawei/DevEco Studio"
      "/c/Program Files (x86)/Huawei/DevEco Studio"
      "$LOCALAPPDATA/Huawei/DevEco Studio"
      "/Applications/DevEco-Studio.app"
    )
    for c in "${candidates[@]}"; do
      if [ -d "$c" ]; then
        path="$c"
        local json="$c/resources/product-info.json"
        if [ -f "$json" ]; then
          found=$(grep -o '"version"[^,]*' "$json" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/')
        fi
        break
      fi
    done
  fi

  if [ -n "$found" ]; then
    if version_ge "$found" "$required"; then
      print_item "$OK"   "DevEco Studio" "版本 $found (>= $required) @ $path"
    else
      print_item "$WARN" "DevEco Studio" "版本 $found < $required，需升级到 6.1.0 Release @ $path"
    fi
  else
    print_item "$WARN" "DevEco Studio" "未自动检测到(探测路径:$path)。请手动确认已装 DevEco Studio 6.1.0 (Release)。"
  fi
}

# -----------------------------------------------------------------------------
# b) HarmonyOS SDK API level >= 23
# -----------------------------------------------------------------------------
check_sdk() {
  local required=23
  local api="" sdk_path=""
  local candidates=()
  [ -n "${OHOS_SDK_ROOT:-}" ] && candidates+=("$OHOS_SDK_ROOT/openharmony")
  if [ "$PLATFORM" = "mac" ]; then
    candidates+=(
      "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony"
      "$HOME/Library/OpenHarmony/Sdk/openharmony"
      "$HOME/OpenHarmony/Sdk/openharmony"
    )
  else
    candidates+=(
      "$LOCALAPPDATA/OpenHarmony/Sdk/openharmony"
      "/c/Users/$USER/AppData/Local/OpenHarmony/Sdk/openharmony"
      "/c/Huawei/ohos-sdk/openharmony"
    )
  fi
  for c in "${candidates[@]}"; do
    [ -d "$c" ] || continue
    for d in "$c"/*; do
      [ -d "$d" ] || continue
      local base; base=$(basename "$d")
      case "$base" in
        ''|*[!0-9]*) continue;;
      esac
      if [ -z "$api" ] || [ "$base" -gt "$api" ]; then api="$base"; fi
    done
    if [ -n "$api" ]; then sdk_path="$c"; break; fi
  done

  if [ -n "$api" ]; then
    if [ "$api" -ge "$required" ]; then
      print_item "$OK"   "HarmonyOS SDK API" "API level $api (>= $required) @ $sdk_path"
    else
      print_item "$WARN" "HarmonyOS SDK API" "API level $api < $required，请在 SDK Manager 安装 API 23 @ $sdk_path"
    fi
  else
    print_item "$WARN" "HarmonyOS SDK API" "未检测到 OpenHarmony SDK(OHOS_SDK_ROOT=${OHOS_SDK_ROOT:-未设置})。请用 DevEco SDK Manager 安装 API 23。"
  fi
}

# -----------------------------------------------------------------------------
# c) Qt 6.12.0 Beta2 含 harmonyos_arm64_v8a 组件
# -----------------------------------------------------------------------------
check_qt() {
  local qtroot="${QTDIR:-$HOME/QtSDK}"
  local found_dir=""
  for base in "$qtroot" "$HOME/Qt"; do
    local d="$base/6.12.0/harmonyos_arm64_v8a"
    if [ -d "$d" ]; then found_dir="$d"; break; fi
  done
  if [ -n "$found_dir" ]; then
    if [ -e "$found_dir/bin/qmake" ]; then
      print_item "$OK"   "Qt 6.12.0 HarmonyOS" "harmonyos_arm64_v8a 组件完整 @ $found_dir"
    else
      print_item "$WARN" "Qt 6.12.0 HarmonyOS" "组件目录存在但缺 qmake，可能未完整安装 @ $found_dir"
    fi
  else
    print_item "$WARN" "Qt 6.12.0 HarmonyOS" "未在 $qtroot/6.12.0/harmonyos_arm64_v8a 找到组件。请用 Qt 在线安装器勾选 6.12.0 Beta2 的 HarmonyOS 组件。"
  fi
}

# -----------------------------------------------------------------------------
# d) harmonydeployqt 可执行存在
# -----------------------------------------------------------------------------
check_deployqt() {
  local qtroot="${QTDIR:-$HOME/QtSDK}"
  local candidates=(
    "$qtroot/6.12.0/macos/bin/harmonydeployqt"
    "$qtroot/6.12.0/macos/bin/harmonydeployqt.exe"
    "$HOME/Qt/6.12.0/macos/bin/harmonydeployqt"
  )
  if [ "$PLATFORM" = "win" ]; then
    candidates+=(
      "/c/Qt/6.12.0/mingw_64/bin/harmonydeployqt.exe"
      "$qtroot/6.12.0/mingw_64/bin/harmonydeployqt.exe"
    )
  fi
  local found=""
  for c in "${candidates[@]}"; do
    if [ -e "$c" ]; then found="$c"; break; fi
  done
  if [ -n "$found" ]; then
    print_item "$OK" "harmonydeployqt" "存在 @ $found"
  else
    print_item "$WARN" "harmonydeployqt" "未找到(探测: $qtroot/6.12.0/macos/bin/harmonydeployqt)。应位于 Qt 6.12 macos 宿主构建 bin 下。"
  fi
}

# -----------------------------------------------------------------------------
# e) ohos-additional-packages 就位
# -----------------------------------------------------------------------------
check_pkgs() {
  local pkg_dir="$HOME/.local/opt/ohos/additional-packages"
  local present=0
  if [ -d "$pkg_dir" ]; then
    local cnt
    cnt=$(ls -1 "$pkg_dir" 2>/dev/null | wc -l | tr -d ' ')
    if [ -n "$cnt" ] && [ "$cnt" -gt 0 ]; then
      present=1
      print_item "$OK" "ohos-additional-packages" "已就位(${cnt} 项) @ ${pkg_dir}"
    fi
  fi
  if [ "$present" -eq 0 ]; then
    print_item "$WARN" "ohos-additional-packages" "未就位(需非空)。请放置到 ${pkg_dir}，见 README 下载链接。"
  fi
}

# ---- 执行 ----
check_deveco
check_sdk
check_qt
check_deployqt
check_pkgs

echo ""
echo "--------------------------------------------------------------"
echo " 结果: ✅ $pass   ⚠️ $warn"
echo " 说明: ⚠️ 表示需手动确认/补救，脚本不因此退出，可反复运行。"
echo "--------------------------------------------------------------"
exit 0
