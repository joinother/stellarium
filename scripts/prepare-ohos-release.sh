#!/bin/bash
# Restore the generated DevEco project to the exact AppGallery release identity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/sync-ohos-build-sources.sh"

echo "Release identity prepared: 星象仪 (com.joinother.skyinstrument); signing and build mode unchanged, no package built. See docs/harmonyos/RELEASE-PACKAGING.md."
