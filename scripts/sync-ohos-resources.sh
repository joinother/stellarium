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

FFMPEG_BIN="${FFMPEG:-}"
if [ -z "$FFMPEG_BIN" ]; then
  FFMPEG_BIN="$(command -v ffmpeg || true)"
fi
if [ -n "$FFMPEG_BIN" ]; then
  converted=0
  while IFS= read -r -d '' texture; do
    description="$(file -b "$texture")"
    case "$description" in
      *"16-bit"*)
        compatible="${texture}.compat.png"
        "$FFMPEG_BIN" -hide_banner -loglevel error -y -i "$texture" \
          -vf format=rgba -frames:v 1 "$compatible"
        mv "$compatible" "$texture"
        converted=$((converted + 1))
        echo "  normalized 16-bit texture: ${texture#$DST/}"
        ;;
    esac
  done < <(find "$DST/textures" -type f -iname '*.png' -print0)
  echo "Texture compatibility pass: converted $converted 16-bit PNG(s)"
  remaining_16bit="$(file -b "$DST"/textures/*.png | awk '/16-bit/ { count++ } END { print count + 0 }')"
  if [ "$remaining_16bit" -ne 0 ]; then
    echo "ERROR: rawfile still contains $remaining_16bit 16-bit PNG(s) after compatibility pass" >&2
    exit 1
  fi

  MODEL_TEXTURES=(
    sun.png mercury.png venus.png earth_cmap.png moon.png mars.png jupiter.png saturn.png uranus.png neptune.png
    pluto.png charon.png ceres.png vesta.png eros.png bennu.png gaspra.png ida.png sedna.png eris.png haumea.png
    dysnomia.png 2007OR10.png phobos.png deimos.png io.png europa.png ganymede.png callisto.png amalthea.png
    mimas.png enceladus.png tethys.png dione.png rhea.png titan.png hyperion.png iapetus.png phoebe.png janus.png
    epimetheus.png prometheus.png ariel.png umbriel.png titania.png oberon.png miranda.png triton.png nereid.png proteus.png
  )
  model_texture_count=0
  for model_texture in "${MODEL_TEXTURES[@]}"; do
    texture_path="$DST/textures/$model_texture"
    [ -f "$texture_path" ] || continue
    "$FFMPEG_BIN" -hide_banner -loglevel error -y -i "$texture_path" \
      -vf 'scale=512:256:flags=lanczos,format=rgba' -frames:v 1 -pix_fmt rgba -f rawvideo \
      "${texture_path}.model.rgba"
    model_texture_count=$((model_texture_count + 1))
  done
  echo "Detail-model CPU textures: generated $model_texture_count RGBA sidecar file(s)"

  RING_TEXTURES=(saturn_rings_radial.png uranus_rings.png neptune_rings.png)
  ring_texture_count=0
  for ring_texture in "${RING_TEXTURES[@]}"; do
    texture_path="$DST/textures/$ring_texture"
    [ -f "$texture_path" ] || continue
    "$FFMPEG_BIN" -hide_banner -loglevel error -y -i "$texture_path" \
      -vf 'scale=512:2:flags=lanczos,format=rgba' -frames:v 1 -pix_fmt rgba -f rawvideo \
      "${texture_path}.model.rgba"
    ring_texture_count=$((ring_texture_count + 1))
  done
  echo "Detail-model ring textures: generated $ring_texture_count RGBA sidecar file(s)"

  # ArkUI ImageKit on the target API rejects the grayscale and indexed PNG
  # encodings used by many upstream constellation illustrations. Normalize
  # only the generated HAP copy; the upstream sky-culture files stay intact.
  art_converted=0
  while IFS= read -r -d '' illustration; do
    description="$(file -b "$illustration")"
    case "$description" in
      *"grayscale"*|*"colormap"*)
        compatible="${illustration}.compat.png"
        "$FFMPEG_BIN" -hide_banner -loglevel error -y -i "$illustration" \
          -vf format=rgba -frames:v 1 "$compatible"
        mv "$compatible" "$illustration"
        art_converted=$((art_converted + 1))
        ;;
    esac
  done < <(find "$DST/skycultures" -type f -path '*/illustrations/*' -iname '*.png' -print0)
  echo "Sky-culture illustration compatibility pass: converted $art_converted grayscale/indexed PNG(s)"
else
  echo "WARNING: ffmpeg not found; 16-bit texture previews may fail on some devices" >&2
fi

echo
echo "Done. rawfile tree size:"
du -sh "$DST"
echo "Skyculture count: $(ls -1 "$DST/skycultures" 2>/dev/null | wc -l)"
echo "Script count:     $(ls -1 "$DST/scripts"/*.ssc 2>/dev/null | wc -l)"
