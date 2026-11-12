#!/usr/bin/env bash
set -euo pipefail
root=/srv/tle-mirror
exec 9>"$root/.runner.lock"
flock -n 9 || exit 75
if [[ -d "$root/.refresh.lock" ]]; then rmdir "$root/.refresh.lock"; fi
exec /usr/bin/node /opt/tle-mirror/fetch-mirror.mjs --root "$root" "$@"
