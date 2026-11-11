#!/bin/bash
# 生成源码快照并推送到 Gitee（在本地 Mac 上运行，不在服务器跑）。
#
# 用途：Gitee 免费仓库容量有限，无法镜像 6.8 GB 的完整历史。
#       这里只镜像我们实际改动过的目录：harmonyos / deploy / docs / scripts。
#
# 注意：日常已由 GitHub Actions 自动同步（.github/workflows/gitee-mirror.yml），
#       本脚本用于手动补推（Actions 失败、或需要立即同步时）。
#
# 用法：bash deploy/server/gitee-mirror.sh
# 前置：环境变量 GITEE_TOKEN（Gitee 私人令牌，projects 权限）
set -euo pipefail

REPO_SRC="$(cd "$(dirname "$0")/../.." && pwd)"
SNAP=/tmp/gitee-snapshot
GITEE_REPO=${GITEE_REPO:-https://gitee.com/yang-jiexuan000/stellarium-ohos-source.git}
: "${GITEE_TOKEN:?请先导出 GITEE_TOKEN}"

echo "源仓库：$REPO_SRC"
rm -rf "$SNAP"
mkdir -p "$SNAP"
for d in harmonyos deploy docs scripts; do
    cp -a "$REPO_SRC/$d" "$SNAP/"
done

# 记录对应提交
{
    git -C "$REPO_SRC" rev-parse --short HEAD
    git -C "$REPO_SRC" log -1 --format='%H%n%ad%n%s'
} > "$SNAP/UPSTREAM_COMMIT.txt"

cd "$SNAP"
git init -q -b master
git config user.name "skyinstrument-mirror"
git config user.email "mirror@skyinstrument.cn"
git add -A
git commit -q -m "snapshot: 源码快照（对应 $(head -1 UPSTREAM_COMMIT.txt)）"

printf 'https://yang-jiexuan000:%s@gitee.com\n' "$GITEE_TOKEN" > .git-credentials
chmod 600 .git-credentials

git remote add origin "$GITEE_REPO" 2>/dev/null || git remote set-url origin "$GITEE_REPO"
git -c credential.helper="store --file=$SNAP/.git-credentials" push -f origin master

rm -f .git-credentials
echo "已推送：$(git log --oneline -1)"
