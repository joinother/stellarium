# 站点服务器运维脚本（星象仪 skyinstrument.cn）

这些文件部署在阿里云 ECS `i-uf68vk358s8l58afzswt`（cn-shanghai）上，
用于满足《网络安全工作规划和实施方案》中"每日自动备份""定期比对哈希"
"季度自查与应急演练有记录"等条款。

## 部署位置

| 仓库文件 | 服务器路径 | 权限 |
| --- | --- | --- |
| `skyinstrument-backup` | `/usr/local/sbin/skyinstrument-backup` | 755 root |
| `skyinstrument-verify` | `/usr/local/sbin/skyinstrument-verify` | 755 root |
| `skyinstrument-backup.service/.timer` | `/etc/systemd/system/` | 644 root |
| `skyinstrument-verify.service/.timer` | `/etc/systemd/system/` | 644 root |
| `security-records/0*.md` | `/srv/skyinstrument/security-records/` | 640 root |

## 定时

| 任务 | 时间 | 产出 |
| --- | --- | --- |
| 备份 | 每日 03:20（随机延迟 ≤5 分钟） | `/srv/backup/site-YYYYMMDD.tar.gz` + `manifest-YYYYMMDD.sha256`，保留 14 天 |
| 哈希比对 | 每周日 04:10（随机延迟 ≤10 分钟） | `/srv/skyinstrument/security-records/hash-diff-YYYYMMDD.txt` |

## 备份内容

- `/srv/skyinstrument/website/current/`（站点发布目录，软链已解引用）
- `/etc/skyinstrument-website/nginx.conf`（站点 nginx 配置）
- `/opt/tle-mirror/sources.json`（TLE 镜像源清单）

## 恢复步骤

```
T=$(mktemp -d)
tar xzf /srv/backup/site-YYYYMMDD.tar.gz -C $T
cd $T && sha256sum -c /srv/backup/manifest-YYYYMMDD.sha256
rsync -a --delete $T/current/ /srv/skyinstrument/website/releases/restore-YYYYMMDD/
ln -sfn releases/restore-YYYYMMDD /srv/skyinstrument/website/current
nginx -t -c /etc/skyinstrument-website/nginx.conf && nginx -s reload -c /etc/skyinstrument-website/nginx.conf
```

## 注意

- 服务器上有两个 nginx 实例，站点那个必须带 `-c /etc/skyinstrument-website/nginx.conf`。
- 备份包与生产同机存放，仍属"同介质"；异地兜底依赖阿里云 ECS 自动快照（控制台配置，按天，保留 7 天）。
