# 镜像校验器上线与卫星联调 · 2026-11-12

## 已上线

上海 ECS `i-uf68vk358s8l58afzswt`，现有 HTTPS 域名及静态 `/v1/`，未购买服务、开放端口或增加 RAM 权限。依用户授权临时使用并核验 root 维护身份；日常诊断仍用 skyops。

- 12:39:57 UTC 完成迁移。上传包 SHA-256：`3e5ebcca78b251946fca6409076bf13beff9c535e6b1b6affda2967be6dabecb`。
- 同机备份 `/var/backups/skyinstrument/tle-hardening-20261112T123957Z`，0700；含原脚本、unit/drop-in、数据、网站 nginx 配置、迁移日志。未下载备份或秘密。
- 抓取器使用专用 `tle-mirror` 用户/组，无登录 shell、无附加组；脚本 root:root 0644，包装器 0755。抓取器不可改程序或网站配置，也不可读取天气和原通知环境文件。
- effective unit：NoNewPrivileges、ProtectSystem=strict、空 capabilities、数据目录以外持久只读、192/256 MiB 内存软/硬限制、CPU 50%、TasksMax 32。一次运行采样内存约 61 MiB，不是峰值保证。
- 旧 root `health.conf` 通知 hook 移入备份；抓取器不接触通知凭据。新增无网络权限状态服务，每 5 分钟只读本地清单并原子写状态，不调用天气、AI 或 Push。
- 每源最多 16 MiB/60 秒；批次网络预算 600 秒、服务限时 900 秒；包装器 flock 防并发并安全回收自身崩溃遗留目录锁。实际锁竞争测试返回 75，未发起重复抓取。
- 补齐 TLE 一阶导数、二阶导数、BSTAR 固定字段校验，校验和正确但传播字段损坏的输入同样拒收。

## 迁移与公开状态

`--validate-only` 不访问上游。迁移发现 GPZ CSV、GPZ-plus CSV、SatNOGS JSON 不满足校验，3 份文件移至 `/srv/tle-mirror/.quarantine`（0700，非公开目录），保留证据。三个原 URL 经公网验证均 404。逐项核对公开目录，没有未登记的额外目录文件。

首轮正式刷新：**51 fresh / 1 stale / 4 unavailable**，可用文件共 52 份，逐份 SHA-256/字节数与清单一致。

| 来源 | 状态 | 原因与处理 |
| --- | --- | --- |
| active.csv | stale | 上游 HTTP 403；保留通过校验的旧文件，不伪造成功时间 |
| SatNOGS JSON | unavailable | 新旧响应均未通过内容校验；不降低标准冒充成功 |
| GPZ / GPZ-plus CSV | unavailable | 上游非有效轨道 CSV；旧文件已隔离 |
| MPC | unavailable | 当前注册格式尚不支持，不发起无意义下载 |

部分失败导致抓取 unit 退出 1 是预期事实，未设置 SuccessExitStatus 隐藏失败。3 小时 timer 继续有效；独立 status timer 不依赖抓取退出成功。

公网 [清单](https://skyinstrument.cn/v1/manifest.json) 与 [状态](https://skyinstrument.cn/v1/status.json) 返回 200，缓存 `public, max-age=60, must-revalidate`。状态为 degraded，不把部分成功说成全部健康；清单超过 12 小时自动失去 fresh 状态。网站及 `/nw/healthz` 均 200，健康验证不产生天气业务请求。

`fresh` 是抓取与内容校验成功，**不等于轨道历元最新或预测精度保证**。镜像文件、安装目录与轨道年龄分别判断。

## 客户端接收契约

- 每轮正式镜像更新先发一次清单 GET，15 秒总时限、1 MiB 上限，禁止重定向/附带 Cookie，清单有效期 12 小时；面板每 5 秒读取的仍是本地状态，不联网。
- fresh/stale 文件必须在解析前满足大小及 SHA-256；stale 可用但报告部分成功。unavailable、缺失/冲突条目、过期清单或哈希不符的正式来源跳过，保留原有轨道。自定义来源仍独立运行原校验。
- `getSatelliteSources.settings` 保存 `mirrorStatus`、`mirrorCheckedAt`、`mirrorStaleSources` 与 `mirrorUnavailableSources`。后两项为来源 URL 数组；详情显示数量。
- 失败/跳过均计入批次完成，不会永久停在更新中；失败重试冷却及用户自动更新选择保留。
- v1 的 HTTPS + 哈希是完整性校验，**没有独立发布签名**。固定 URL 更新期间可能与旧清单跨代，客户端拒收并保留已安装数据，不能称为跨文件原子更新。

离线验证：服务端 29 项、Store 4 项、现有安全测试 11 项，共 44 项通过；真实 C++ 更新流程 18 个场景及元数据异常用例通过。使用项目实际 `StelIniParser.cpp` 读写验证列表持久化，包括多项和 URL 片段；标准 Qt INI 测试不能代替项目自定义格式。原生交叉编译、HAP 构建和 UI 契约检查通过。

首轮 Pad 正式联调完成：46 个配置来源，服务器同分钟日志仅 1 次清单和 42 次镜像文件请求，隔离的 GPZ 两项均 0 次请求；另 2 个原有外部来源保留原路径。目录 18,168 颗，详情显示 1 个旧缓存、2 个不可用；新状态截图可读且未截断。首次重启发现 QStringList 多值被自定义 INI 丢弃，改为 JSON 文本存储（转义 `#` 避免被当作注释），不能只凭更新后内存状态宣称保存成功。

最终包再次构建并覆盖安装 Pad；12:59:34 UTC 正式更新完成，随后强停重启，自动开关、镜像状态、镜像检查时间、旧缓存数组、不可用数组、最近检查时间和最近结果 **7/7** 与退出前一致。没有新轨道时检查时间前进、轨道变更时间仍为 12:48:48 UTC；重启后未重复刷新。详情和主页面最终截图均已检查，未出现占位符或裁切。

## 星链来源和精度边界

当前星链镜像来自 `gp.php?GROUP=starlink&FORMAT=CSV`，为 CelesTrak 普通 GP CSV，非 SpaceX 原始星历，也非 SupGP。格式转换不会自动提升精度。

12:44 UTC 抽样：11,195 条，历元中位年龄约 9.92 小时；347 条超过 24 小时、1 条超过 72 小时、无超过 7 天；最旧历元为 11 月 9 日 11:33 UTC，最新为 11 月 12 日 08:00 UTC。这个样本是当时下载内容，不代表每轮刷新都达到同一时效。

[CelesTrak Supplemental GP 官方说明](https://celestrak.org/NORAD/elements/supplemental/)列明 Starlink SupGP 从 [SpaceX 公开星历](https://api.starlink.com/public-files/ephemerides/MANIFEST.txt)拟合，可继续使用兼容的 SGP4。公开 RMS 是相对输入星历的拟合残差，不是定位真值误差或整段预测保证，不能直接拿来宣传本应用精度。

下一步按独立来源引入 SupGP：先验证格式、编号/对象映射、覆盖率、SGP4 版本和有效时间窗，按同一卫星同一 UTC 时刻比较空间及观测角误差；明确普通 GP 回退策略后接入。不能仅按下载时间覆盖较合适轨道。SpaceX 原始时序星历另需坐标系、时间标准、插值和机动处理，不能塞入现有 TLE 解析器。

## 后续部署与回退

- v2 不可变哈希 URL、独立签名、客户端信任根和原子激活仍为下一阶段；`deploy/content-service` 的契约不是可上线的完整服务。本次没有虚构这些端点上线。
- 天气/AI 的预算、缓存和并发整改已在此前成本专项部署；本次只验证零费用健康端点，不重新部署旧副本。专题内容和 Push 订阅接口仍待完整认证、退订/删除、限流与客户端验收，未发送任何远程通知。
- 回退先停刷新 timer，确认 MainPID=0，保留故障现场；可恢复上一个**已验证有效**资源，不得把隔离坏文件重新公开。代码回退优先保持新低权限 unit；旧 root 单元和通知 hook 不自动恢复。更换 nginx 配置前先 `nginx -t -c /etc/skyinstrument-website/nginx.conf`，仅重载该实例。
- 同机备份不是异机灾备；本次未购买备份、CDN 或 OSS 服务。Workbench 维护凭据依然可以申请 root 会话，低权限抓取账号不等于云运维身份已完全隔离。
- root 维护会话已关闭，全新 skyops 会话身份及只读诊断通过。新增 `scripts/resource-server-cli.sh mirror` 检查正式公开镜像；既有 `status` 仅检查旧本机 8080 staging 服务。
