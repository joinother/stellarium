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

SRC="$REPO_ROOT/harmonyos/cpp-source/hello.cpp"
DST="$REPO_ROOT/build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp"

if [ ! -f "$SRC" ]; then
  echo "ERROR: missing tracked source: $SRC" >&2
  exit 1
fi

if [ ! -d "$(dirname "$DST")" ]; then
  echo "ERROR: missing hvigor cpp source dir: $(dirname "$DST")" >&2
  echo "Open/generate the HarmonyOS build project first." >&2
  exit 1
fi

cp "$SRC" "$DST"

echo "Synced:"
echo "  $SRC"
echo "  -> $DST"
