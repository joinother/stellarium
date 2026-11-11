# 星象仪网站安全台账

本目录存放星象仪网站的网络安全运行记录，供自查与主管部门核查使用。
记录保存期限不少于三年。

## 目录

| 文件 | 用途 | 填写频率 |
| --- | --- | --- |
| `01-季度自查记录.md` | 系统补丁、文件完整性、日志留存、备份可用性、口令强度 | 每季度一次 |
| `02-应急演练记录.md` | 演练场景、步骤、耗时、发现问题与改进 | 每年至少一次 |
| `03-安全事件处置记录.md` | 事件时间、现象、影响、处置、报告、归档 | 每次事件 |
| `04-备份恢复验证记录.md` | 备份包名、校验和、恢复结果 | 每月一次 |
| `hash-diff-YYYYMMDD.txt` | 每周自动生成的线上文件哈希比对结果 | 系统自动 |

## 自动化任务

| 任务 | 时间 | 产出 |
| --- | --- | --- |
| `skyinstrument-backup.timer` | 每日 03:20 | `/srv/backup/site-YYYYMMDD.tar.gz` 与同名 `manifest-*.sha256`，保留 14 天 |
| `skyinstrument-verify.timer` | 每周日 04:10 | 本目录 `hash-diff-YYYYMMDD.txt` |

查看状态：

```
systemctl list-timers skyinstrument-backup.timer skyinstrument-verify.timer
journalctl -u skyinstrument-backup.service -n 20
```

## 填写要求

记录须如实填写，不得事后补造。发现差异或事件时，先记录事实，再写处置措施，
最后写结论与改进项。涉及个人信息的细节不应写入本目录。
