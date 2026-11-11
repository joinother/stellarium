# 服务器与资源管线审计及本地修复

## 范围与状态

2026-11-11 21:39–21:46 UTC+8 的现场检查全部只读，每条远程命令先验证 `id -un = skyops`，实测 uid/gid 1000、无附加组。遵循根 AGENTS 与 SERVER-SECURITY.md。后续仅修改本地镜像抓取器、service、测试和本文；没有在线变更、提权、账号迁移、部署、提交或生产下载测试。共享 CHANGELOG 不由本任务修改。

## 现场证据（历史快照，不是修复后的验收）

| 项目 | 现场结果 |
| --- | --- |
| 容量 | 根盘 40 GiB，已用 5.2 GiB、可用 33 GiB，inode 4%；内存 1870 MiB、available 1404 MiB，无 swap |
| 监听 | wildcard TCP 22/80/443；loopback TCP 8080/8090/37699；不等于外网可达性扫描 |
| staging | resource-server-cli.sh status 返回 active、status=staging、publicService=false，仅代表 8080 |
| 公网资源 | HTTPS /v1/manifest.json 200，56 源、54 ok、2 失败；generatedAt 12:42:45Z，缓存 1800 秒 |
| 错误数据 | gpz.csv / gpz-plus.csv 为 59/69 字节 Invalid query 文本，却在清单标为 ok |
| 过期数据 | active.csv 上游 403，仍公开返回 200，Last-Modified 2026-11-03 18:01:32 GMT（本地 11 月 4 日）；MPC 404 |
| 抽样哈希 | stations.3le SHA-256 1c5b1645ca931c0a0932c095da542a48ba9988b56cd6d531e720f5a0ae190cad，与清单相同 |
| 定时刷新 | 20:42:45–20:46:54、退出 0；下次 23:42:45；部分失败未反映为 unit 失败 |
| 刷新权限 | User/Group 为空，即 root；完整 capabilities；NoNewPrivileges/ProtectSystem 均未启用；无内存上限 |
| 其他服务 | 网站 nginx 为受限 nginx 用户；nightwindow-api 默认 root，虽启用 ProtectSystem/NoNewPrivileges 仍保留完整 capabilities；auditd/sshd active，firewalld inactive、SELinux Disabled；kdump 为唯一 failed unit |
| 监控与备份 | certificate/backup/verify/quickcheck 有近期 exit 0；不证明完整恢复能力；镜像 health.conf 的 ExecStartPost 忽略错误，可选通知环境文件不存在 |

远端抓取器 SHA-256 `92722ec6406885941263ef9986fa790adf507dfc61b773a942c84ae194fa3675`、sources.json `0176beae0507feb12bdd3284fe5b88540d5c62f3fcbff783a37f213d4f86535c`、网站 nginx `5a1032774c653a6e3a60fd013d1433b0cd32a1cf2d4b6371139ae66a0e24ae80` 与修改前仓库一致。日志目录容量读取被 skyops 权限拒绝；不能把 du 的 4K 视作真实日志用量。未核验云端 RAM/安全组、当前漏洞补丁清单、外部备份恢复；37699 进程归属不可见。

## 本地实现契约

- `deploy/tle-mirror/fetch-mirror.mjs`：CSV 完整 GP 字段、引号解析、数值与日期边界；TLE 完整三行组、编号、校验和与基本轨道字段；SatNOGS 数组和编号/TLE 一致性；六类 JSON 集合键/版本/最低数量。未知格式拒绝，不请求 MPC 页面。
- 每源 60 秒 deadline，Content-Length 预检与实际响应流 16 MiB 双限制，严格 UTF-8。任何选中源失败返回 1，同时保留其他成功源。
- 公开清单去掉 root、上游 URL 和原始异常；固定公共路由与错误码白名单。`available`/`stale`/`status` 与 `lastAttemptAt`/`lastSuccessAt` 分离；只广告经过重新验证的旧文件，已知哈希不匹配时不冒充 last-good；无可信成功时间时为 null。
- 旧清单迁移不传播未知字段或旧异常，`--only` 保留未选中源。`.refresh.lock` 拒绝重叠刷新。资源和 manifest 使用 root 内临时文件（公开 /v1 外）、文件 fsync 与 rename；失败清理临时文件并保留旧目标。
- `tle-mirror.service`：专用 User/Group、空 capabilities、NoNewPrivileges、严格系统只读、受限持久写目录、私有临时目录/设备、192/256 MiB 内存限制、50% CPU、32 tasks、256 descriptors。专用账号和权限调整只是迁移方案，未在服务器执行。
- 迁移步骤、健康检查 drop-in 的失败语义变化、静态旧文件处理和锁恢复边界详见 `deploy/tle-mirror/README.md`。

## 未解决且不能宣称已完成

单文件原子替换不保证跨资源/清单的一致快照，不保证目录项断电持久性；固定 URL 的缓存代际问题仍在。`fresh` 不是轨道历元有效性承诺，缺少签名、反回滚、不可变版本地址和客户端事务激活；本轮不实现 signed v2。TLE/CSV 校验不代替全部科学语义验证；JSON 不逐一验证各科学字段。

旧损坏文件不会被新清单广告，但仍可能通过原静态 URL 读取，需迁移时审查并处理；服务数据树必须可信、不可含跨树符号链接。强杀可能留下锁，不能自动删除不明活跃锁。

客户端修复进展：Dirac 已在本轮本地 `plugins/Satellites/src/Satellites.cpp` diff 中加入全部源完整性门禁、保留缺失卫星、QSaveFile 原子保存，以及候选数据成功提交后再修改现有对象/成功时间。此前“部分失败仍删除”和“先删除后写入”描述属于审计时旧代码，不再代表当前本地实现；仍待 parent 完整 native 构建、故障注入与设备验证，未部署。

独立只读 review：`node --test scripts/test-ohos-satellite-refresh-safety.mjs` 14/14 通过。保存失败前未发现现有对象/成功时间的提前修改，部分源失败不会进入更新；但测试以 JS 转写保存/包装器及源码顺序断言为主，没有执行真实 CSV/TLE 解析器或 Qt 文件系统事务。发现 CSV 仍直接按逗号 split（合法引号逗号名称导致整批拒绝），以及新增无标题 2LE 路径首条记录的 `TleData lastData;` 未初始化 status。离线复现模板/校验和条件：随包 3134 对 TLE 中 166 对校验和正确却被严格模板拒绝，例如 NORAD 3889 第一行第 34 列为 `0`，对应模板只接受空格/正负号；这是既有输入兼容回归证据，不声称这些写法均符合最严格上游规范。CSV fixture 的 17 列被简单 split 成 18 列。以上交 Dirac/parent 修复验证，本任务未修改 native/build。

仍需后续处理：客户端下载不验 manifest；`scripts/update-ohos-astronomy-data.mjs` 默认 verify-only 未比较清单哈希；`src/StelMainView.cpp` 健康状态信任 verified 元数据；`StellariumResourceBootstrap.ets` 启动覆盖随包 manifest。备份范围缺镜像数据/脚本/unit、API root 身份和线上监控盲区同样未修复。

## 离线验收

环境：本机 macOS，Node v26.7.0。所有抓取测试通过注入的 mock fetch 或 ReadableStream，完全不访问生产/上游；使用临时目录、固定 TLE/CSV/SatNOGS fixtures 及六份仓库已有 JSON。临时目录由测试清理。

测试命令：`node --test deploy/tle-mirror/test/fetch-mirror.test.mjs`。23 项测试覆盖：有效/错误 CSV、TLE 对和校验和、SatNOGS、JSON schema/最低数量及六份真实随包 JSON、未知格式不联网、原始字节与 UTF-8、声明/实际流超限、fetch/body 超时、成功元数据、重复失败 last-good、初次失败、路径/异常脱敏、旧版清单迁移、无可信时间回退、坏文件/哈希不符、部分失败、only/dry-run、非法路径/重复注册、原子替换失败、资源/清单发布失败及并发刷新。

结果：23/23 通过，0 失败、0 跳过，退出 0；`node --check deploy/tle-mirror/fetch-mirror.mjs` 通过；`git diff --check -- deploy/tle-mirror docs/harmonyos/server/SERVER-RESOURCE-AUDIT-2026-11-11.md` 无空白错误。测试首轮发现数字字符串版本兼容问题及本地 fixture 引用路径问题，已修正后通过。`systemd-analyze` 在本机不可用，未将静态 service 检查冒充 Linux unit 加载或沙箱运行验收；迁移前仍须在目标维护环境验证。
