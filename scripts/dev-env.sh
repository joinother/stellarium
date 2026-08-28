#!/usr/bin/env bash
# Shared development environment for interactive shells, DevEco terminals and scripts.

if [[ -x /opt/homebrew/bin/brew ]]; then
  STELLARIUM_HOMEBREW_PREFIX=/opt/homebrew
elif [[ -x /usr/local/bin/brew ]]; then
  STELLARIUM_HOMEBREW_PREFIX=/usr/local
else
  STELLARIUM_HOMEBREW_PREFIX=""
fi

stellarium_prepend_path() {
  local directory="$1"
  local current
  local rebuilt=""
  local old_ifs="$IFS"
  [[ -d "$directory" ]] || return 0
  IFS=:
  for current in ${PATH:-}; do
    [[ -z "$current" || "$current" == "$directory" ]] && continue
    rebuilt="${rebuilt:+$rebuilt:}$current"
  done
  IFS="$old_ifs"
  PATH="$directory${rebuilt:+:$rebuilt}"
}

if [[ -n "$STELLARIUM_HOMEBREW_PREFIX" ]]; then
  export HOMEBREW_PREFIX="$STELLARIUM_HOMEBREW_PREFIX"
  export HOMEBREW_CELLAR="$STELLARIUM_HOMEBREW_PREFIX/Cellar"
  export HOMEBREW_REPOSITORY="$STELLARIUM_HOMEBREW_PREFIX"
  stellarium_prepend_path "$STELLARIUM_HOMEBREW_PREFIX/sbin"
  stellarium_prepend_path "$STELLARIUM_HOMEBREW_PREFIX/bin"
fi

export DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/sdk}"

if [[ -z "${OHOS_BASE_SDK_HOME:-}" ]]; then
  if [[ -d "$HOME/Library/OpenHarmony/Sdk" ]]; then
    export OHOS_BASE_SDK_HOME="$HOME/Library/OpenHarmony/Sdk"
  else
    export OHOS_BASE_SDK_HOME="$DEVECO_SDK_HOME/default/openharmony"
  fi
fi

export HDC_BIN="${HDC_BIN:-$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc}"
export HVIGORW_JS="${HVIGORW_JS:-$DEVECO_HOME/tools/hvigor/bin/hvigorw.js}"

unset -f stellarium_prepend_path
