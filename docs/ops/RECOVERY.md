# 星象仪 · 灾备恢复手册

> 适用：ECS 实例丢失、系统盘损坏、误删关键目录、需要迁移到新服务器。
> 不适用：单页内容被改（用 `skyinstrument-rollback`）、页面被拦截（用 `skyinstrument-incident --rollback`）。

---

## 0. 先判断：真需要重建吗

| 现象 | 走哪条路 |
|---|---|
| 某个页面内容不对 | `skyinstrument-rollback <版本目录>` |
| 某页返回 503 | `skyinstrument-incident --rollback <时间戳>` |
| 证书过期 | `systemctl start skyinstrument-renew-certificate` |
| 磁盘满 | 清理 `/srv/backup` 旧包、`/srv/skyinstrument/incidents` |
| **机器没了 / 系统盘坏了** | **本手册** |

---

## 1. 资产清单：从哪来

| 资产 | 来源 | 备注 |
|---|---|---|
| 站点文件 | `/srv/backup/site-YYYYMMDD.tar.gz` | 需先从旧机或异地取回 |
| nginx 主配置 | 同上备份包（`nginx.conf`） | 也有一份在 git `deploy/server/nginx/` |
| 拦截规则 | 同上备份包（`conf.d/incident.conf`） | 通常可为空 |
| systemd 单元 | 同上备份包（`etc/systemd/system/`） | 也在 git `deploy/server/` |
| 运维脚本 | git `deploy/server/` | 14 个脚本 |
| 夜窗 API | git `deploy/server/nightwindow-api/server.js` | 原最大单点，已入库 |
| 源码（我们的改动） | Gitee `yang-jiexuan000/stellarium-ohos-source` | 36 MB 快照，GitHub Actions 自动推送 |
| 安全记录 | Gitee `yang-jiexuan000/skyinstrument-ops-records`（私有） | 每日 08:30 自动推送 |
| TLS 证书 | 重新签发（acme.sh） | 需 DNS 正常 |
| **密钥（必须手工重填）** | 见第 6 节 | 刻意不入备份、不入 git |

---

## 2. 新建实例

控制台操作，无命令：

1. 同地域（cn-shanghai）、同规格（2 vCPU / 1.8 GiB）或更大
2. 系统盘 40 GiB 以上
3. 安全组照抄旧规则：

```
443/443   0.0.0.0/0         HTTPS
80/80     0.0.0.0/0         HTTP（跳转用）
22/22     100.104.0.0/16    仅 Workbench 内网
ICMP      -1/-1
```

4. 绑定弹性公网 IP（沿用原 IP 可避免改 DNS）

---

## 3. 基础环境

```bash
# 3.1 系统包
yum install -y nginx git python3 tar gzip openssl

# 3.2 目录骨架
mkdir -p /srv/skyinstrument/{website/releases,security-records,incidents,records-repo,edits-archive}
mkdir -p /srv/backup /var/lib/skyinstrument /etc/skyinstrument
chown -R nginx:nginx /srv/skyinstrument/website

# 3.3 验证
nginx -v && git --version && python3 -V
```

---

## 4. 恢复站点

```bash
# 4.1 取回备份包（从旧机 / 本地 / 对象存储）
scp site-YYYYMMDD.tar.gz root@新机:/tmp/

# 4.2 解包到版本目录
cd /tmp && mkdir -p restore && tar xzf site-YYYYMMDD.tar.gz -C restore

# 4.3 文件就位
cp -a restore/current/. /srv/skyinstrument/website/releases/$(date +%Y%m%d)-restored/
ln -sfn releases/$(date +%Y%m%d)-restored /srv/skyinstrument/website/current

# 4.4 配置就位
cp restore/nginx.conf            /etc/skyinstrument-website/nginx.conf
mkdir -p /etc/skyinstrument-website/conf.d
cp -a restore/conf.d/.           /etc/skyinstrument-website/conf.d/
cp restore/etc/systemd/system/skyinstrument-*.service /etc/systemd/system/
cp restore/etc/systemd/system/skyinstrument-*.timer   /etc/systemd/system/

# 4.5 清理解包带回来的临时文件
rm -f /srv/skyinstrument/website/current/*.bak-*

# 4.6 语法检查（必须带 -c）
nginx -t -c /etc/skyinstrument-website/nginx.conf
```

> ⚠️ 坑：本机 nginx 使用独立配置 `/etc/skyinstrument-website/nginx.conf`，
> **所有 nginx 命令都必须带 `-c`**，否则会去读 `/etc/nginx/nginx.conf` 并报错。

---

## 5. 恢复脚本与服务

```bash
# 5.1 运维脚本（14 个）
cd /tmp && git clone https://github.com/joinother/stellarium.git repo
install -m 755 repo/deploy/server/skyinstrument-* /usr/local/sbin/

# 5.2 夜窗 API
mkdir -p /opt/nightwindow-api
cp repo/deploy/server/nightwindow-api/server.js /opt/nightwindow-api/
nohup /usr/bin/node /opt/nightwindow-api/server.js >/var/log/nightwindow-api.log 2>&1 &
curl -s http://127.0.0.1:8090/healthz    # 期望 {"ok":true,...}

# 5.3 单元与定时器
systemctl daemon-reload
systemctl enable --now skyinstrument-website.service
systemctl enable --now skyinstrument-backup.timer skyinstrument-verify.timer \
    skyinstrument-certificate.timer skyinstrument-healthcheck.timer \
    skyinstrument-content-audit.timer skyinstrument-fullscan.timer \
    skyinstrument-daily-report.timer skyinstrument-quickcheck.timer \
    skyinstrument-git-sync.timer skyinstrument-lexicon-update.timer
systemctl list-timers 'skyinstrument-*' --no-pager
```

---

## 6. 重填密钥（**不做这步，告警发不出去**）

以下文件刻意**不在备份、不在 git**：

| 文件 | 内容 | 从哪里拿 |
|---|---|---|
| `/etc/skyinstrument/notify.conf` | SMTP 授权码 | 你自己的邮箱后台重新生成 |
| `/etc/skyinstrument/audit.conf` | DeepSeek API Key | DeepSeek 控制台 |
| `/etc/skyinstrument/git-credentials` | Gitee 令牌 | Gitee 设置（90 天到期） |
| `/etc/skyinstrument/remediate.conf` | `APPLY=0/1` | 直接写，建议先 `0` |

```bash
umask 077
cat > /etc/skyinstrument/notify.conf <<'CONF'
CHANNELS=email
CRITICAL_COOLDOWN_MIN=0
[email]
SMTP_HOST=smtp.qq.com
SMTP_PORT=465
SMTP_USER=你的邮箱
SMTP_PASS=授权码
MAIL_TO=你的邮箱
FROM_NAME=星象仪
CONF
chmod 600 /etc/skyinstrument/notify.conf

printf 'APPLY=0\n' > /etc/skyinstrument/remediate.conf
chmod 600 /etc/skyinstrument/remediate.conf

# 验证发信
echo '恢复测试' > /tmp/t.txt
/usr/local/sbin/skyinstrument-notify --level daily --subject '[恢复] 通道测试' --text-file /tmp/t.txt
```

---

## 7. 证书

```bash
# 7.1 安装 acme.sh 并签发（首次）
curl https://get.acme.sh | sh -s email=你的邮箱
/root/.skyinstrument-acme/acme.sh --issue -d skyinstrument.cn -d www.skyinstrument.cn --webroot /srv/skyinstrument/website/current

# 7.2 或复用已有 acme 目录（从旧机带过来）
#    /root/.skyinstrument-acme/  整个目录拷贝到新机

# 7.3 安装到站点目录
mkdir -p /etc/skyinstrument-website/tls/current
/root/.skyinstrument-acme/acme.sh --install-cert -d skyinstrument.cn \
  --key-file       /etc/skyinstrument-website/tls/current/privkey.pem \
  --fullchain-file /etc/skyinstrument-website/tls/current/fullchain.pem \
  --reloadcmd      "systemctl reload skyinstrument-website"

# 7.4 验证
echo | openssl s_client -connect 127.0.0.1:443 -servername skyinstrument.cn 2>/dev/null | openssl x509 -noout -dates
```

---

## 8. 记录与镜像数据

```bash
# 8.1 拉回安全记录（含历史清单与台账）
git clone https://gitee.com/yang-jiexuan000/skyinstrument-ops-records.git /srv/skyinstrument/records-repo
cp /srv/skyinstrument/records-repo/records/*.md /srv/skyinstrument/security-records/ 2>/dev/null

# 8.2 TLE 镜像：等定时任务自愈（每 3 小时）
systemctl list-timers 'tle-mirror*' --no-pager
# 或手动立即刷新
ls /etc/systemd/system/ | grep tle-mirror

# 8.3 词库：等周一 04:30，或手动
/usr/local/sbin/skyinstrument-lexicon-update
```

---

## 9. 恢复后验证（10 项）

```bash
# 1 首页
curl -s -o /dev/null -w '%{http_code}\n' https://skyinstrument.cn/
# 2 隐私页
curl -s -o /dev/null -w '%{http_code}\n' https://skyinstrument.cn/privacy
# 3 安全头
curl -sI https://skyinstrument.cn/ | grep -E 'x-frame-options|content-security-policy|cache-control'
# 4 证书有效期
echo | openssl s_client -connect 127.0.0.1:443 -servername skyinstrument.cn 2>/dev/null | openssl x509 -noout -dates
# 5 站点服务
systemctl is-active skyinstrument-website
# 6 定时器
systemctl list-timers 'skyinstrument-*' --no-pager | wc -l
# 7 巡检可跑
/usr/local/sbin/skyinstrument-content-audit; echo "exit=$?"
# 8 自检可跑
/usr/local/sbin/skyinstrument-healthcheck; echo "exit=$?"
# 9 告警通道
/usr/local/sbin/skyinstrument-daily-report
# 10 记录同步
/usr/local/sbin/skyinstrument-git-sync
```

全部通过后，**在台账 `04-备份恢复验证记录.md` 记一条**：恢复时间、来源包、耗时、发现的问题。

---

## 10. 常见坑

| 坑 | 现象 | 处理 |
|---|---|---|
| nginx 命令没带 `-c` | `unknown directive` 或读了错误配置 | 所有 nginx 命令加 `-c /etc/skyinstrument-website/nginx.conf` |
| 忘了 `conf.d` include | 拦截规则不生效 | 检查 nginx.conf 里有 `include /etc/skyinstrument-website/conf.d/*.conf;` |
| 解包带回 `.bak-*` | 旧页面被公开访问 | `rm -f current/*.bak-*` |
| 没重填 notify.conf | 所有告警静默 | 第 6 节 + 发一封测试 |
| 没装 nightwindow-api | App 接口 404 | 第 5.2 节 + `/healthz` 验证 |
| 词库为空 | 巡检只靠内置 36 词 | 跑一次 `skyinstrument-lexicon-update` |
| Python 版本 | 语法不兼容 | 脚本已按 3.6 兼容写法（服务器为 3.6） |
| 安全组 22 开放 | 暴露风险 | 只允许 `100.104.0.0/16` |

---

## 11. 时间估算（实测口径）

| 阶段 | 耗时 |
|---|---|
| 新建实例 + 安全组 | 15 分 |
| 基础环境 + 目录 | 10 分 |
| 解包站点 + 配置 + 单元 | 15 分 |
| 夜窗 API | 5 分 |
| 密钥重填 | 10 分 |
| 证书签发 | 10 分 |
| 验证 10 项 | 10 分 |
| **合计** | **约 75 分钟** |

TLE 镜像自愈另需最多 3 小时，不影响站点可用。

---

## 12. 演练建议

每半年做一次**不触碰生产**的演练：

1. 在本机用备份包解出一个站点目录
2. 用 `python3 -m http.server` 起临时服务验证页面完整
3. 核对备份包里的 `nginx.conf` 与线上一致（`diff`）
4. 在台账记录演练日期与结论

演练不要求真的重建 ECS——**目标是验证"备份包里的东西足够重建"，而不是练习装系统**。
