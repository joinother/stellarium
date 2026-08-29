#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dev-env.sh
source "$SCRIPT_DIR/dev-env.sh"

DEVICE_ID=${1:-${OHOS_TEST_DEVICE:-}}
ACTION=${2:-prepare}

if [[ -z "$DEVICE_ID" ]]; then
	DEVICE_ID=$("$HDC_BIN" list targets | awk 'NF && $0 !~ /^\[Info\]/ {print $1}')
	if [[ -z "$DEVICE_ID" || "$DEVICE_ID" == *$'\n'* ]]; then
		echo "用法: $0 <设备ID> [prepare|restore]" >&2
		exit 2
	fi
fi

if [[ "$DEVICE_ID" == *:* ]]; then
	"$HDC_BIN" tconn "$DEVICE_ID"
fi

case "$ACTION" in
	prepare)
		# Keep the test device awake for 24 hours and wake it before installation.
		"$HDC_BIN" -t "$DEVICE_ID" shell power-shell timeout -o 86400000
		"$HDC_BIN" -t "$DEVICE_ID" shell power-shell wakeup
		# HarmonyOS exposes brightness through the minimum brightness key event.
		"$HDC_BIN" -t "$DEVICE_ID" shell uinput -K -d 2724 -u 2724
		"$HDC_BIN" -t "$DEVICE_ID" shell hidumper -s DisplayPowerManagerService
		;;
	restore)
		"$HDC_BIN" -t "$DEVICE_ID" shell power-shell timeout -r
		"$HDC_BIN" -t "$DEVICE_ID" shell hidumper -s DisplayPowerManagerService
		;;
	*)
		echo "未知操作: $ACTION（可用 prepare 或 restore）" >&2
		exit 2
		;;
esac
