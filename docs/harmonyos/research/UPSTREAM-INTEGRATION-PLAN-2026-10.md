# 上游代码差距与引进计划

更新时间：2026-10-01
审计对象：HarmonyOS 定制分支 `HEAD=d288af25a3`
上游快照：`origin/master=630fa8272f`（Stellarium 26.3 发布后）

## 1. 审计结论

当前仓库不是从 `origin/master` 直接分支出来的普通工作树：

- `git merge-base HEAD origin/master` 没有共同祖先；`git rev-list --left-right --count origin/master...HEAD` 的 `1139/330` 不能当作“缺少 1139 个提交”或“新增 330 个提交”。这是历史重写、定制快照和上游桌面仓库之间的结构差异。
- 当前功能分支只与 `myfork/fix/api22-privacy-v2` 在 `9797d13f2b` 对齐，当前 `HEAD` 仅在其上追加了开发检查点。不能对 `origin/master` 做整树 merge，也不能把整批上游提交直接 cherry-pick 到 HarmonyOS 分支。
- 直接快照比较涉及 `src` 107 个路径、`plugins` 123 个路径、`data` 17 个路径，统计约 247 个路径、97812 行增加和 148089 行删除。这个数字主要包含 Qt 桌面 GUI、HarmonyOS 壳层、历史重写和生成工程差异，不等于真实功能缺口。

因此，本项目与上游的正确关系是：**上游负责 Stellarium 核心、插件逻辑、数据和翻译；本仓库负责 HarmonyOS 适配层、CLI、ArkUI、隐私/联网边界和移动端资源装载。按文件和功能选择性引进，不做整树同步。**

## 2. 当前已经有、但上游没有的定制部分

下面这些不是“落后代码”，而是本项目的产品层，不能用上游桌面代码覆盖：

| 范围 | 当前实现 | 处理原则 |
|---|---|---|
| HarmonyOS 工程 | `harmonyos/`、`build/libstellarium-harmonyos/` | 以 `harmonyos/ets-source` 为源，生成工程只由同步脚本更新 |
| ArkUI 交互 | 手机/平板/PC 响应式布局、Dock、详情卡片、模型 Worker、隐私门禁 | 不从 Qt Widgets/QML 复制 UI；上游逻辑通过命令桥接入 |
| CLI | `src/StelMainView.cpp`、`src/StelOhosCommandCatalog.hpp`、`scripts/stellarium-cli.mjs` | 保持命令稳定；新上游能力先增加原生查询/动作，再接 ArkUI |
| 离线与联网边界 | `data/ohos/network-*.json`、网络台账、镜像构建流程 | 上游联网插件不能自动变成运行时联网；必须有主动触发、失败回退和隐私字段清单 |
| 本地化编辑层 | 天区文化编辑说明、官方 PO/QM、中文地理术语审计 | 保留上游作者、来源、许可证和原始史料；应用层说明不得覆盖原始资料 |
| 网站与服务器 | `website/`、服务端部署与资源镜像方案 | 与上游桌面发行流程隔离，不把服务器配置回灌上游 |

## 3. 应优先引进的上游内容

### P0：数据和翻译，先引进再验证

这类改动不改变 HarmonyOS 交互，适合按文件导入；导入后必须重新生成 rawfile、更新清单并做离线审计。

| 上游提交 | 内容 | 引进方式 | 注意事项 |
|---|---|---|---|
| `630fa8272f` | 深空天体名称 `nebulae/default/names.dat` 与翻译模板 | 只导入名称数据和对应翻译，检查搜索别名 | 不覆盖本地多语言搜索别名和中文审核结果 |
| `a249c4a814` | 行星地貌命名数据 `nomenclature.dat/.fab` | 导入二进制/索引及配套翻译 | 与 `NomenclatureMgr` 未来地貌详情接口一起验收 |
| `66b657b2fc`、`8b4f4e8892` | 默认地点列表与压缩索引 | 选较新的完整版本导入，不重复导入两个版本 | 复核中国地名规范、地区字段和本地搜索索引 |
| `2d64cc0cdd` | 彗星发现情况资料 | 导入 `comet_discovery.fab` | 保留来源、时间精度和缺失值说明 |
| `d1e24a2f36` | 系外行星目录更新 | 导入 JSON 后做体积、字段和搜索性能测试 | 不把目录更新误当成运行时联网 |
| `48a84b38f0` | 行星特征/地貌目录和翻译模板 | 导入数据与 PO，重新编译 QM | 中文名称按术语表复核，不批量覆盖人工译文 |
| `07768d6b31` | Potawatomi 天区文化及插图 | 按许可证、来源、文化表述和 43 语言策略审核后导入 | 追加应用层文化呈现说明，不改写原作者史料 |
| 2026-09/10 的 `stellarium*.po` 更新 | 天体、天区文化、地貌、脚本、远程控制翻译 | 通过现有翻译构建脚本导入 | 中文及重点语言人工抽查，保留未翻译回退机制 |

P0 不需要把整个 `data/` 目录替换掉。每次只引入一个逻辑资源组，并记录版本、字节数、SHA-256、许可证、来源和上游提交。

### P1：纯核心修复和数据解析，选择性移植

| 上游提交 | 价值 | 当前差距 | 建议 |
|---|---|---|---|
| `1ca17032b2` + `8df92a2970` | Satellites 支持 Alpha-5 TLE 编号 | 当前卫星插件已有离线源、用户导入和自定义 UI，不能覆盖整个 `Satellites.cpp` | 只移植 Alpha-5 解析/序列化函数，补 `Starlink`/Alpha-5/JSON 回归；保留现有源模式和隐私边界 |
| `7d6fbcaba6` | Phobos/Deimos 3D 模型轴向旋转修复 | 当前有自定义 3D 详情渲染器 | 先替换模型资源，再检查同一坐标约定；不复制桌面模型窗口 |
| `75587abf82` | 天体标签可读性和截图文字改进 | 移动端标签、ArkUI 详情和 Qt 绘制是两套路径 | 只挑核心 `StelObject`/标签计算中不依赖 QWidget 的修复，真机比较字号、重叠和帧率 |
| `2b60bf355b` | 警告文案修正 | 通用 | 可直接人工核对并移植，不改错误码语义 |
| `e005013def` | 天区文化年份滑块边界修复 | 当前已有文化年份控制 | 移植年份边界判断，补文化切换和时间滚轮测试 |
| `6b0fb9fb0b`、`bd52ff14a0`、`698472c161` | AstroCalc 位置返回、日食/凌日特定时刻跳转 | 当前 AstroCalc 已有平滑过渡和自定义命令 | 只移植计算语义和目标时刻，不覆盖 ArkUI 动画/时间桥接 |
| `7e13f78348` | 飞机斜距、地面距离字段 | Planes 运行时数据仍有外部来源边界 | 若恢复飞机本地目录，再把字段接入详情；不自动开放 ADS-B |

### P2：需要适配层后再移植

- `e8a3b85a03`、`7e0597b213`：`StelTexture::StelTextureParams` 改名和 API 收敛。当前源码仍有多处旧名称，涉及 `StelTexture.hpp`、`StelTextureMgr`、`Planet`、`Landscape`、`StelHips`、`Scenery3d`、`Oculars`、`SkyCultureMaker` 等。应先在临时分支批量改名并构建桌面核心，再同步 OHOS `.so`；不能只替换头文件。
- `f97ad9cadf`：Object Visibility 的 Twilight limits 新页。鸿蒙不直接移植 Qt 对话框，应将计算和字段抽成 CLI/ArkUI 数据模型，复用现有“可观测性”宿主。
- `cb924edfa8`：Sky Culture Maker loader。当前制作器已有自己的版本化草稿和 ZIP 导入导出，需先比较格式和校验规则，再决定是否兼容上游加载器。
- `01ddcd64f9`、`1741b017b3`、`6916e4957c`：RemoteControl OpenAPI、Scenery3D 端点和本地化。只有在明确打开本机/局域网服务、认证、CORS、端口和审计后，才移植协议描述；不把 HTTP 监听默认带入发行包。
- `f76c30ed4f` 等纯翻译提交：可以导入 PO，但必须重新生成 QM，并运行 `scripts/check-ohos-i18n.mjs`；ArkUI 自有文案仍由 `I18n.ets` 管理。

### P3：暂不引入

- Qt Widgets、Qt Designer `.ui`、桌面菜单、桌面快捷键编辑器、AppImage、WebEngine 和桌面安装/打包脚本。它们解决的是桌面壳层问题，与 ArkUI 不同，不是缺失功能的直接补丁。
- `RemoteControl`、`RemoteSync`、`OnlineQueries`、`Planes` 的默认公网行为。备案不等于可以无条件外发位置、查询词、设备或账号信息；这些能力必须继续按联网台账逐项开启。
- 完整 `TelescopeControl` 桌面设备生命周期。当前 LX200/本机与局域网桥、星闪预研接口是独立适配器，后续串口、INDI、ASCOM、RTS2、星闪应分别做协议适配，不把桌面插件整块搬进 ArkUI。

## 4. 与桌面上游的真实功能差距

当前最大的差距不是“核心代码不存在”，而是**桌面 Qt UI 能力尚未转换为 CLI + ArkUI 数据模型**：

1. `AstroCalc`、`ObjectVisibility`、`Oculars`、`Satellites`、`SkyCultureMaker`、`Scenery3d`、`TelescopeControl` 仍有桌面字段或交互没有完整进入移动端。
2. 远程控制和插件脚本在上游以 Qt 窗口、HTTP 服务或键盘事件为中心；鸿蒙端已经有集中路由，但新增上游能力必须补命令、状态、错误、取消和加载状态，不能只加一个按钮。
3. 上游新增数据通常可以复用；上游新增 GUI 通常不能直接复用；上游新增网络能力必须重新做隐私、备案、镜像和离线回退评估。
4. 上游的天区文化、作者说明、许可证和译文属于资源资产；应用层的中国地理术语与文化呈现说明属于本项目本地化层，二者要叠加，不要互相覆盖。

## 5. 推荐的上游处理流程

### 5.1 每次同步前

```text
git fetch origin --prune
记录 origin/master 的完整 SHA 和日期
确认当前工作区没有待覆盖的用户修改
按“数据 / 核心 / 插件 / 桌面 GUI / 联网”分类候选提交
```

由于当前没有共同祖先，禁止直接执行 `git merge origin/master`。候选提交应在临时工作树或临时分支中处理：

```text
git worktree add /tmp/stellarium-upstream-audit origin/master
git show <commit> -- <path>       # 先看逻辑补丁
git diff <local-file> /tmp/stellarium-upstream-audit/<path>
```

数据文件可按“上游文件 → 本地审核 → 生成索引/QM → 同步 rawfile”的流程进入；代码文件必须手工移植并保留本项目命令桥、隐私门禁和联网边界。

### 5.2 每次引进后

1. 运行 `git diff --check`，检查没有覆盖本地改动或生成敏感配置。
2. 核对来源、许可证、版本、SHA-256、文件大小和是否需要重新生成索引。
3. C++ 核心变更运行 `cmake --build build --parallel --target stellarium`。
4. ArkTS/资源变更运行 `scripts/sync-ohos-build-sources.sh`、`scripts/check-ohos.sh`、`CompileArkTS` 和 `assembleHap`。
5. 用 CLI 验证搜索、详情、插件路由、数据版本和失败回退；需要硬件的能力再在 Pad/PC 真机验收。
6. 把上游提交、移植文件、冲突处理、验证结果追加到 `docs/harmonyos/CHANGELOG.md`，不要只记录“已同步”。

### 5.3 冲突处理原则

- 上游核心算法优先保留；HarmonyOS 命令桥、线程/Worker、ArkUI 布局和隐私边界优先保留本地实现。
- 生成工程不手工编辑；改 `harmonyos/ets-source` 后运行同步脚本。
- 不把 `build/` 里的临时产物、HAP、签名、Profile 或服务器密钥当作上游代码。
- 上游翻译不覆盖本地人工审核的中文地名、民族名称和文化呈现说明；保留未翻译回退和来源署名。
- 上游网络请求不自动进入应用；每一个 URL、外发字段、缓存、权限和关闭入口先登记到 `NETWORK-INVENTORY.md`。

## 6. 下一轮实际顺序

1. **数据批次**：先引入 DSO 名称、地貌命名、地点、彗星、系外行星、Potawatomi 天区文化和翻译更新，做资源清单与中文审计。
2. **卫星批次**：移植 Alpha-5 TLE 解析，保留现有来源管理、离线快照、用户导入和本地化界面。
3. **模型批次**：更新 Phobos/Deimos 资源，验证三维模型轴向和晨昏线，不改变详情卡布局。
4. **计算批次**：选择性移植 AstroCalc/Object Visibility 的纯计算字段，统一通过 CLI 和 ArkUI 展示。
5. **核心批次**：单独评估 `StelTextureParams` API 改名；先桌面构建，再 OHOS 交叉编译，不与数据同步混做。
6. **网络/设备批次**：RemoteControl、RemoteSync、OnlineQueries、ADS-B、实时巡天、望远镜协议和通知服务逐项联调，默认不开启。

这样处理可以持续吸收上游数据和 bug 修复，同时避免上游桌面 UI、网络行为或构建配置破坏已经验收的 HarmonyOS 版本。
