#!/bin/bash
# Prepare the generated DevEco project as an installable development build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/build/libstellarium-harmonyos"
DEV_VERSION_CODE=1000100
DEV_VERSION_NAME="1.0.0-dev.20260729"

"$SCRIPT_DIR/sync-ohos-build-sources.sh"

replace_value() {
  local file="$1"
  local old="$2"
  local new="$3"
  perl -0pi -e "s/\\Q$old\\E/$new/g" "$file"
}

replace_value "$PROJECT/AppScope/resources/base/element/string.json" '"Stellarium"' '"Stellarium Dev"'
replace_value "$PROJECT/AppScope/resources/zh_CN/element/string.json" '"星象仪"' '"星象仪·开发版"'
replace_value "$PROJECT/entry/src/main/resources/base/element/string.json" '"Stellarium"' '"Stellarium Dev"'
replace_value "$PROJECT/AppScope/app.json5" '"versionCode": 1000000' "\"versionCode\": $DEV_VERSION_CODE"
replace_value "$PROJECT/AppScope/app.json5" '"versionName": "1.0.0"' "\"versionName\": \"$DEV_VERSION_NAME\""
perl -0pi -e 's/("name": "QAbility_label",\\s*"value": ")[^"]+/$1\\u661f\\u8c61\\u4eea\\u00b7\\u5f00\\u53d1\\u7248/' \
  "$PROJECT/entry/src/main/resources/zh_CN/element/string.json"

for asset in \
  "$PROJECT/AppScope/resources/base/media/app_icon.png" \
  "$PROJECT/entry/src/main/resources/base/media/foreground.png" \
  "$PROJECT/entry/src/main/resources/base/media/startIcon.png"; do
  /usr/bin/swift "$SCRIPT_DIR/make-ohos-dev-icon.swift" "$asset" "$asset"
done

echo "Development identity prepared: 星象仪·开发版 $DEV_VERSION_NAME ($DEV_VERSION_CODE; reuses the release bundle name for signing)"
