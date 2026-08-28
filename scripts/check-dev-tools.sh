#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=dev-env.sh
source "$SCRIPT_DIR/dev-env.sh"

missing=0

check_tool() {
  local name="$1"
  local required="$2"
  local resolved
  resolved="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    printf 'OK       %-12s %s\n' "$name" "$resolved"
  elif [[ "$required" == "required" ]]; then
    printf 'MISSING  %-12s required\n' "$name"
    missing=$((missing + 1))
  else
    printf 'OPTIONAL %-12s not installed\n' "$name"
  fi
}

check_file() {
  local name="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    printf 'OK       %-12s %s\n' "$name" "$path"
  else
    printf 'MISSING  %-12s %s\n' "$name" "$path"
    missing=$((missing + 1))
  fi
}

echo "Development tool resolution"
echo "PATH=$PATH"
echo

for tool in brew node npm cmake ninja ffmpeg ffprobe git; do
  check_tool "$tool" required
done

for tool in gh unar cliclick deveco devecocli; do
  check_tool "$tool" optional
done

check_file "DevEco" "$DEVECO_HOME"
check_file "Harmony SDK" "$OHOS_BASE_SDK_HOME"
check_file "hdc" "$HDC_BIN"
check_file "hvigor" "$HVIGORW_JS"

echo
if [[ "$missing" -ne 0 ]]; then
  echo "$missing required tool(s) are missing. Run scripts/bootstrap-dev-tools.sh." >&2
  exit 1
fi

echo "All required development tools resolved."
