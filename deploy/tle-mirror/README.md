# 星象仪在线数据镜像（TLE + 目录）

把国外的星历/目录源（CelesTrak、SatNOGS、Stellarium 各插件目录）在**自己的 ECS** 上抓一份，
再以静态站点对外提供。App 端用 `--source-mode mirror --mirror-base-url https://<域名>` 构建，
就只依赖自家域名，不再直连国外。

## 目录内容

| 文件 | 作用 |
|---|---|
| `sources.json` | 要镜像的源清单（由仓库 `data/ohos/network-sources.json` 导出，含 `mirrorPath`） |
| `fetch-mirror.mjs` | 抓取脚本：原子落盘 + 格式校验 + 失败保留上一版 + 写 `manifest.json` |
| `nginx-tle-mirror.conf` | 只读静态站点（`/v1/catalogs/...`） |
| `tle-mirror.service` / `tle-mirror.timer` | systemd，每 3 小时刷新一次 |

当前镜像的路径约定：

```
/v1/catalogs/satellites/stations.3le
/v1/catalogs/satellites/visual.3le
/v1/catalogs/satellites/active.3le
/v1/catalogs/satellites/satnogs.json
/v1/catalogs/exoplanets.json
/v1/catalogs/meteor-showers.json
/v1/catalogs/novae.json
/v1/catalogs/supernovae.json
/v1/catalogs/pulsars.json
/v1/catalogs/quasars.json
/v1/manifest.json
```

## 部署（ECS，Ubuntu/Debian 为例）

```bash
# 1. 运行环境
apt-get update && apt-get install -y nginx curl
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs
node -v   # 需要 >= 18（内置 fetch）

# 2. 放脚本
mkdir -p /opt/tle-mirror /srv/tle-mirror
# 把 sources.json / fetch-mirror.mjs 传到 /opt/tle-mirror/
scp sources.json fetch-mirror.mjs root@<ecs>:/opt/tle-mirror/

# 3. 先手动跑一次，确认能出数据
cd /opt/tle-mirror && node fetch-mirror.mjs --root /srv/tle-mirror

# 4. 定时刷新
cp tle-mirror.service tle-mirror.timer /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now tle-mirror.timer
systemctl list-timers tle-mirror.timer

# 5. nginx（把 server_name 改成已备案域名）
cp nginx-tle-mirror.conf /etc/nginx/conf.d/
nginx -t && systemctl reload nginx

# 6. 验证
curl -I https://<域名>/v1/catalogs/satellites/stations.3le
curl -s https://<域名>/v1/manifest.json | head -20
```

内网/无公网 IP 的实例：用 `workbench exec` + `workbench upload` 部署，
对外暴露靠 SLB/反向代理；或直接用 `workbench` 的端口转发做联调。

## 抓取失败的两种已知情况

- `satellites.tle.active` 常返回 **HTTP 403**：CelesTrak 对 `GROUP=active` 这类大分组限制自动抓取。
  脚本会保留上一版文件；首次部署时可用仓库里已构建的 `satellites.json` 兜底，或降低刷新频率到每天一次。
- `catalog.mpc` 返回的不是预期格式（页面变动/需要不同参数）：脚本按“格式不符”拒收，不会写坏文件。

## App 侧怎么接

```bash
# 用镜像构建（替换 upstream）
node scripts/update-ohos-astronomy-data.mjs --all \
  --source-mode mirror \
  --mirror-base-url https://<域名>
```

镜像地址与 `data/ohos/network-sources.json` 里的 `mirrorPath` 一一对应，改域名只改 `--mirror-base-url`。

## 已部署实例（2026-11-03）

| 项 | 值 |
|---|---|
| 实例 | `i-uf68vk358s8l58afzswt`（cn-shanghai，2 vCPU / 1.8 GiB / 40 GiB，Alibaba Cloud Linux 3） |
| 脚本 | `/opt/tle-mirror/`（`fetch-mirror.mjs` + `sources.json`） |
| 数据 | `/srv/tle-mirror/`（约 7.7 MB） |
| 对外 | `https://skyinstrument.cn/v1/...`（挂在既有站点的 apex server 块里） |
| 刷新 | `tle-mirror.timer`，每 3 小时；`systemctl list-timers tle-mirror.timer` |
| 配置备份 | `/etc/skyinstrument-website/nginx.conf.bak-20261103015512` |

注意这台机器上跑了**两个** nginx 实例，pid 文件不同，别混：

- `/etc/skyinstrument-website/nginx.conf` → 80/443，site（`skyinstrument.cn`），镜像就挂在这里
- `/etc/skyinstrument/nginx.conf` → 仅 127.0.0.1:8080

改完配置只重载站点那个：

```bash
nginx -t -c /etc/skyinstrument-website/nginx.conf && \
  nginx -s reload -c /etc/skyinstrument-website/nginx.conf
```

回滚：把 `.bak-*` 覆盖回去再 reload 即可（`/v1/` 那一块是唯一改动）。

已知：`catalog.mpc` 一直格式不符被拒；CelesTrak 的 `active` 分组在短时间内重复抓取会返回 403（3 小时间隔不会触发），失败时保留上一版。
