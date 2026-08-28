#!/bin/bash
# sync-ohos-resources.sh
#
# Populates the HarmonyOS app's rawfile resource tree with the Stellarium
# data files the C++ core needs at runtime.
#
# WHY THIS EXISTS
# ---------------
# On OHOS, the C++ core (StelFileMgr) cannot read the HAP's rawfile directly.
# At startup, StellariumResourceBootstrap.ets walks the rawfile tree and copies
# every file under `rawfile/stellarium/` into the app's sandbox filesDir, then
# points STELLARIUM_DATA_ROOT at that directory. Whatever is NOT in rawfile is
# simply never available on the device.
#
# The hvigor project does NOT copy these automatically — the rawfile tree is
# assembled manually at build time. This script makes that step reproducible.
# It MUST include `skycultures/` or constellation lines / art will never render
# even though the toggle actions report success.
#
# USAGE
# -----
#   scripts/sync-ohos-resources.sh            # sync into the default build dir
#   OUT=/path/to/rawfile/stellarium scripts/sync-ohos-resources.sh
#
set -euo pipefail

# Repo root = parent of the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Destination: the hvigor project's rawfile source tree.
DEFAULT_DST="$REPO_ROOT/build/libstellarium-harmonyos/entry/src/main/resources/rawfile/stellarium"
DST="${OUT:-$DEFAULT_DST}"

if [ ! -d "$REPO_ROOT/data" ]; then
  echo "ERROR: cannot find Stellarium source data at $REPO_ROOT/data" >&2
  exit 1
fi

mkdir -p "$DST"

# Compile the upstream Qt catalogs first. The rawfile mirror must contain the
# same official translations that the native core loads at runtime.
node "$SCRIPT_DIR/build-ohos-official-translations.mjs"
node "$SCRIPT_DIR/build-ohos-multilingual-search-index.mjs"

# Top-level data directories the core expects under its install root.
# `scripts` holds Stellarium's .ssc sky-tour scripts. It also happens to hold this
# repo's own build shell scripts, so it gets an allow-list filter below — without
# it, StelScriptMgr::getScriptList() finds nothing and the Scripts panel is empty.
DIRS=(data textures landscapes nebulae stars translations skycultures scenery3d scripts)

# Non-culture files living directly inside skycultures/ (CMake scaffolding).
# They must not be copied into the rawfile (they would be treated as junk).
SKYCULTURE_EXCLUDES=(
  --exclude='/CMakeLists.txt'
  --exclude='/CMakeLists.txt.template'
  --exclude='/TODO.txt'
  --exclude='*.py'
)

# Deep-sky data is a resource collection, not source code. Keep the catalogue
# indexes and image files, while excluding the CMake metadata in this source
# directory. `--delete` plus a full copy is intentional: rawfile is generated
# output and must not keep stale zero-byte files from an older build.
NEBULAE_INCLUDES=(
  --include='*/'
  --include='*.dat'
  --include='*.json'
  --include='*.png'
  --exclude='*'
)

# Only Stellarium script assets may enter rawfile. Shell/Python/Swift build
# helpers that share this directory would be flagged by hvigor as stray source.
SCRIPT_INCLUDES=(
  --include='*.ssc'
  --include='*.inc'
  --exclude='*'
)

for d in "${DIRS[@]}"; do
  SRC="$REPO_ROOT/$d"
  [ -d "$SRC" ] || { echo "SKIP (missing): $SRC"; continue; }
  echo "==> syncing $d -> $DST/$d"
  if [ "$d" = "skycultures" ]; then
    rsync -a --delete --delete-excluded "${SKYCULTURE_EXCLUDES[@]}" "$SRC/" "$DST/$d/"
  elif [ "$d" = "nebulae" ]; then
    rsync -a --delete --delete-excluded "${NEBULAE_INCLUDES[@]}" "$SRC/" "$DST/$d/"
  elif [ "$d" = "scripts" ]; then
    rsync -a --delete --delete-excluded --no-r --dirs "${SCRIPT_INCLUDES[@]}" "$SRC/" "$DST/$d/"
  else
    rsync -a --delete "$SRC/" "$DST/$d/"
  fi
done

echo
echo "Done. rawfile tree size:"
du -sh "$DST"
echo "Skyculture count: $(ls -1 "$DST/skycultures" 2>/dev/null | wc -l)"
echo "Script count:     $(ls -1 "$DST/scripts"/*.ssc 2>/dev/null | wc -l)"
