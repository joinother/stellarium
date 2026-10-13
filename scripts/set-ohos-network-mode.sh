#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${OHOS_BUILD_DIR:-$root_dir/build}"
module_file="$root_dir/harmonyos/module.json5"
# OFFLINE_APPGALLERY_BUILD now lives in the shared types module (post-refactor),
# not in the page shell.
arkui_types_file="$root_dir/harmonyos/ets-source/common/types/MainWindowModels.ets"

usage() {
  cat <<'EOF'
Usage: scripts/set-ohos-network-mode.sh <offline|online|status>

offline  Remove the public INTERNET permission and compile the native offline guards.
online   Keep INTERNET permission and compile the explicitly user-triggered network paths.
status   Report the source permission and the current CMake cache mode.
EOF
}

read_cache_mode() {
  if [[ -f "$build_dir/CMakeCache.txt" ]]; then
    sed -n 's/^STELLARIUM_OHOS_OFFLINE:BOOL=//p' "$build_dir/CMakeCache.txt" | tail -n 1
  fi
}

read_arkui_mode() {
  perl -ne 'if (/const OFFLINE_APPGALLERY_BUILD: boolean = (true|false)/) { print "$1\n"; exit }' "$arkui_types_file"
}

set_arkui_mode() {
  local offline="$1"
  perl -0pi -e "s/const OFFLINE_APPGALLERY_BUILD: boolean = (true|false)/const OFFLINE_APPGALLERY_BUILD: boolean = ${offline}/" "$arkui_types_file"
}

has_internet_permission() {
  rg -q '"name": "ohos\.permission\.INTERNET"' "$module_file"
}

write_internet_permission() {
  if ! has_internet_permission; then
    perl -0pi -e 's/("requestPermissions": \[\n)/$1      {\n        "name": "ohos.permission.INTERNET"\n      },\n/' "$module_file"
  fi
}

remove_internet_permission() {
  perl -0pi -e 's/\n      \{\n        "name": "ohos\.permission\.INTERNET"\n      \},//' "$module_file"
}

mode="${1:-status}"
case "$mode" in
  status)
    if has_internet_permission; then
      source_permission="present"
    else
      source_permission="absent"
    fi
    cache_mode="$(read_cache_mode)"
    arkui_mode="$(read_arkui_mode)"
    printf 'source INTERNET permission: %s\n' "$source_permission"
    printf 'CMake STELLARIUM_OHOS_OFFLINE: %s\n' "${cache_mode:-not-configured}"
    printf 'ArkUI OFFLINE_APPGALLERY_BUILD: %s\n' "${arkui_mode:-not-found}"
    if [[ "$cache_mode" == "OFF" && "$source_permission" == "present" && "$arkui_mode" == "false" ]]; then
      printf 'effective development mode: online\n'
    elif [[ "$cache_mode" == "ON" && "$source_permission" == "absent" && "$arkui_mode" == "true" ]]; then
      printf 'effective development mode: offline\n'
    else
      printf 'effective development mode: mixed or incomplete\n'
    fi
    ;;
  offline|online)
    if [[ "$mode" == "online" ]]; then
      write_internet_permission
      set_arkui_mode false
      offline_value="OFF"
    else
      remove_internet_permission
      set_arkui_mode true
      offline_value="ON"
    fi
    cmake -S "$root_dir" -B "$build_dir" -DSTELLARIUM_OHOS_OFFLINE="$offline_value"
    bash "$root_dir/scripts/sync-ohos-build-sources.sh"
    printf 'selected HarmonyOS network mode: %s\n' "$mode"
    printf 'next: cmake --build %s --parallel --target stellarium\n' "$build_dir"
    printf 'next: build the HAP only after checking AGC permissions, Profile capabilities, privacy text and fallback behavior\n'
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
