# 夜窗 API（/nw/ 代理目标）

> 2026-11-12：本目录 `server.js` 是历史副本，**不得按本文旧步骤重新部署**。
> 正式源码与测试维护在本机 `/Users/jiexuanyang/Documents/nightwindow/server/`。
> 当前生产通过 `nightwindow-api.service` 运行，必须一起部署 `server.js`、`limits.js`、
> `quota.js` 及对应 unit，并配套 nginx 覆盖 XFF、可信 loopback 和预算配置。
> 详细迁移与回退见该项目 `server/README.md` 和本仓库 `docs/ops/COST-SECURITY-REMEDIATION-2026-11-12.md`。
> 下文仅保留旧架构记录，不能覆盖当前非 root、持久预算和并发保护实现。

星象仪 App 使用的在线数据服务，监听 `127.0.0.1:8090`，由 nginx 通过 `/nw/` 反向代理。

## 部署位置

```
/opt/nightwindow-api/server.js      正式运行文件
```

systemd 单元不在本仓库：该服务由手工启动（`/usr/bin/node /opt/nightwindow-api/server.js`），
重建时按下方步骤恢复。

## 依赖

- Node.js（系统自带 `/usr/bin/node`）
- 无需 npm 依赖，全部使用内置模块

## 接口

| 路径 | 说明 |
|---|---|
| `/healthz` | 存活检查 |
| `/v1/grid` | 网格点位 |
| `/v1/week` | 一周数据 |
| `/v1/world` | 全球点位（约 166 KB） |
| `/v1/wx` | 天气点位 |

频率限制：同一 IP 每小时 120 次，超出返回 429。

## 重建步骤

```bash
sudo mkdir -p /opt/nightwindow-api
sudo cp server.js /opt/nightwindow-api/server.js
sudo nohup /usr/bin/node /opt/nightwindow-api/server.js >/var/log/nightwindow-api.log 2>&1 &
curl -s http://127.0.0.1:8090/healthz
```

ngninx 侧需保留 `/nw/` 的 proxy_pass 配置（见 `../nginx/nginx.conf`），否则 App 接口不可达。
