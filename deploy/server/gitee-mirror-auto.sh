#!/bin/bash
# launchd 调用的包装脚本：从 600 权限文件读令牌，然后调用 gitee-mirror.sh。
set -uo pipefail

TOKEN_FILE="$HOME/.config/skyinstrument/gitee.token"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$HOME/Library/Logs/skyinstrument-gitee-mirror.log"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

if [ ! -f "$TOKEN_FILE" ]; then
    log "缺少令牌文件 $TOKEN_FILE，跳过"
    exit 1
fi

TOKEN=$(sed -n 's/^gitee-token=//p' "$TOKEN_FILE" | head -1)
if [ -z "$TOKEN" ]; then
    log "令牌文件里没有 gitee-token=，跳过"
    exit 1
fi

# 没有新提交就不推（避免每分钟都造一个快照提交）
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAST=$(cat "$HOME/.config/skyinstrument/gitee-last-commit" 2>/dev/null || echo "")
HEAD=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "")
if [ -n "$LAST" ] && [ "$LAST" = "$HEAD" ]; then
    log "无新提交（$HEAD），跳过"
    exit 0
fi

log "开始同步 $HEAD"
if GITEE_TOKEN="$TOKEN" bash "$SCRIPT_DIR/gitee-mirror.sh" >> "$LOG" 2>&1; then
    echo "$HEAD" > "$HOME/.config/skyinstrument/gitee-last-commit"
    log "同步成功"
else
    log "同步失败，详见上方输出"
    exit 1
fi
