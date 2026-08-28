#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
source "$SCRIPT_DIR/dev-env.sh"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install it from https://brew.sh first." >&2
  exit 1
fi

echo "Installing Homebrew dependencies from $REPO_ROOT/Brewfile"
brew bundle --file "$REPO_ROOT/Brewfile"

echo "Installing global npm CLIs"
while IFS= read -r package_spec; do
  [[ -z "$package_spec" || "$package_spec" == \#* ]] && continue
  npm install --global "$package_spec"
done < "$SCRIPT_DIR/dev-tools/npm-global-packages.txt"

exec "$SCRIPT_DIR/check-dev-tools.sh"
