# 应用设置保存（持久化）设计

> 状态：**草案，待 review**。本文只描述现状与目标设计，不含代码改动。
> 适用：HarmonyOS 端（`harmonyos/ets-source`）+ 共用 Qt 引擎（`src/`）。

## 1. 背景与目标

Stellarium 在桌面端把设置写在 `config.ini`，由用户显式点击「保存设置」或退出程序时落盘。HarmonyOS 端引入了两层新环境：

- 应用可能被系统随时冻结/回收，没有可靠的“退出时保存”时机；
- ArkUI 侧另有一批界面状态与用户数据（观测点、收藏、观测列表、搜索历史等）。其中**夜间模式、赤道仪/地平仪本质是引擎行为**，当前却被 ArkUI 当作 UI 状态保存，这是本文要纠正的核心偏差之一。

现状是**三套独立存储通道并存**，各自为政：部分设置退后台才写盘，部分设置从不写盘，部分设置存在两份且启动时互相覆盖。本文的目标是给出一个可 review 的统一设计：

- 每个设置项有**唯一权威存储位置**；
- 每个设置项有**明确的写入时机**（立即 / 防抖 / 生命周期 / 显式）；
- 重启后**可预期地恢复**，并且失败可观测；
- 为后续新增设置提供统一接入方式，避免继续堆特例。

### 非目标

- 不重构引擎内部的 QSettings 读写实现（`StelIniParser` 保持不变）。
- 不改变桌面端行为（桌面端仍以「保存设置」/退出保存为主）。
- 不新增设置项。

## 2. 存储介质与术语

| 介质 | 位置 | 生命周期 | 当前使用者 |
|---|---|---|---|
| A. 引擎配置 `config.ini` | `StelFileMgr::getUserDir()`，OHOS 下为 `filesDir/stellarium_userdir`（`STEL_USERDIR`） | 永久，随应用卸载清除 | 绝大多数引擎设置（`viewing/*`、`astro/*`、`navigation/*`、`projection/*`、`video/*`、`gui/*`、`localization/*`、`color/*` 等），**含夜间模式、赤道仪/地平仪、语言** |
| B. ArkTS Preferences | 应用沙箱 Preferences，按 store 名分库 | 永久，随应用卸载清除 | 观测点、收藏、观测列表、搜索历史、快捷面板、详情呈现轴、桌面卡片；夜间模式**首帧缓存**（非权威） |
| C. AppStorage（内存） | 进程内 `AppStorage` | **进程存活期**，进程结束即丢 | `stellariumSettings` JSON（音乐、单位、星历页签等）、`stellariumNightMode`、赤道仪开关等镜像 |

术语：

- **写入内存**：setter 改运行时属性，或 `QSettings::setValue`（此时仍在内存，未落盘）。
- **落盘（flush）**：`QSettings::sync()` 写 `config.ini`；`Preferences.put + flush()` 写沙箱。
- **立即保存（immediate）**：每次变更即落盘，不等生命周期事件。
- **脏标记（dirty）**：记录“有未落盘变更”，用于批量 flush。

## 3. 现状（as-is）

### 3.1 三条通道

```
┌─ ArkUI 面板 ──────────────────────────────────────────────┐
│  store 字段 ──► AppStorage['stellariumSettings'] (内存)   │  ← 不落盘
│  nightMode  ──► Preferences 'night_mode_store'（仅首帧缓存）│
│  其他域      ──► Preferences 'stellarium_*' (落盘)        │
└───────────────┬───────────────────────────────────────────┘
                │ 桥命令（aa want / NAPI）
┌───────────────▼───────────────────────────────────────────┐
│  C++ setter ──► QSettings::setValue (内存)                │
│             └─► StelApp::immediateSave (受开关门控)        │
│  退后台 / 手动保存 / exportConfig ──► QSettings::sync()    │
└───────────────────────────────────────────────────────────┘
```

### 3.2 写入时机（现状）

| 触发 | 行为 | 证据 |
|---|---|---|
| 用户改一项设置 | 多数 `setXxx` 只改内存；部分调用 `StelApp::immediateSave` | `src/core/modules/*`、`src/core/StelCore.cpp` |
| `immediateSave` 被调用 | **仅当 `flagImmediateSave == true` 才 `setValue`**；默认 `false` | `StelApp.cpp:1411-1415`、`StelApp.cpp:314/489`、`default_cfg.ini` 无 `gui/immediate_save_details` |
| 应用退后台 | `QAbility.onBackground` → `setApplicationForeground 0` → `emit configurationDataSaved` + `settings->sync()` | `QAbility.ets:1095-1112`、`StelMainView.cpp:18183-18195` |
| 手动「保存设置」 | ArkTS 写 `AppStorage` JSON + 桥命令 `saveAllSettings` → **仅 `sync()`** | `MainWindowNativeNode.ets:3298-3325`、`StelMainView.cpp:10401-10406` |
| 启动 | C++ 从 `config.ini` 读（**引擎权威**）；ArkTS 早期读 `night_mode_store` 仅作首帧缓存，再从 `AppStorage['stellariumSettings']` 恢复 UI 镜像；最终以引擎回读为准 | `StelApp.cpp:475-740`、`QAbility.ets:995-1003`、`StartupBridge.ets:160-194` |
| 配置导出 | `exportConfig`：先 `sync()` 再读 `config.ini` 全文 | `StelMainView.cpp:14294-14312` |
| 配置导入 | `importConfig`：逐条 `setValue` 后 `sync()` | `StelMainView.cpp:14313+` |
| 恢复默认 | 写 `main/restore_defaults=true` + `sync()`，重启时覆盖配置 | `StelMainView.cpp:10408-10415`、`main.cpp:345-350` |

### 3.3 现状归属矩阵

| 设置域 | 权威位置 | 写入时机 | 重启恢复 | 备注 |
|---|---|---|---|---|
| 图层/网格/星座/星云/流星等开关与样式 | `config.ini` `viewing/*`、`astro/*` | 退后台 / 手动保存；部分 `immediateSave`（默认无效） | ✅ | 依赖 setter 是否 `setValue` |
| 投影、时间、导航、定位、语言 | `config.ini` 对应分组 | 退后台 / 手动保存 | ⚠️ 语言不写盘（见 P3） | `setLanguage` 未 `setValue` |
| 颜色（天体/星座线等） | `config.ini` `color/*` | 部分 `immediateSave`（默认无效） | ⚠️ | 见 `StelMainView.cpp:11129+` |
| 夜间模式（**引擎行为**） | **应为** `config.ini` `viewing/flag_night`；当前 Preferences `night_mode_store` 被当成权威 | UI 切换时写 Preferences；引擎属性随退后台 sync | ⚠️ 双源竞争，权威方向错误 | 见 P4 |
| 赤道仪/地平仪（**引擎行为**） | **应为** `config.ini` `navigation/viewing_mode`（`equator` / `horizon`）；当前只存 `AppStorage` | 切换时只改引擎内存 + 写 UI 内存 | ❌ 不落盘 | 见 P4b |
| 音乐开关 / 单位 / 详情呈现轴 / 星历页签等 | `AppStorage['stellariumSettings']` | 切换时写内存 | ❌ 不落盘 | 见 P2 |
| 观测点 | Preferences `stellarium_observer_location` | 选择/保存时 `put+flush` | ✅ | |
| 收藏 | Preferences `stellarium_bookmarks` | 增删时 `put+flush` | ✅ | |
| 观测列表 | Preferences `stellarium_observing_list` | 变更时 `put+flush` | ✅ | |
| 搜索历史 | Preferences `stellarium_search_history` | 变更时 `put+flush` | ✅ | |
| 快捷面板配置 | Preferences `stellarium_quick_panel` | 变更时 `put+flush` | ✅ | |
| 详情呈现轴 | Preferences `stellarium_info_window` | 切换时 `put+flush` | ✅ | 与 `AppStorage` 同名项重复（见 P2） |
| 桌面卡片 | Preferences `sky_instrument_card` | 卡片数据发布时 | ✅ | |

### 3.4 现状问题清单

> 按影响排序。每条给出可核对的锚点，便于 review 时逐项确认。

**P1（高）`immediateSave` 默认不生效。**
`StelApp::immediateSave()` 内部检查 `getFlagImmediateSave()`；该标志由 `gui/immediate_save_details` 初始化，默认 `false`，仓库内 `data/default_cfg.ini` 没有该键，OHOS 构建也未注入。因此近期为星云标注、星云显示、流星、星空文化常用名等 setter 新增的 `immediateSave` 调用，**在真机默认配置下不会写盘**。
锚点：`StelApp.cpp:314`、`StelApp.cpp:489`、`StelApp.cpp:1411-1415`、`src/core/modules/NebulaMgr.hpp:827/872`、`SporadicMeteorMgr.hpp:61`、`StelSkyCultureMgr.cpp:1140-1148`。

**P2（高）ArkTS 的 `stellariumSettings` 只写内存，从不落盘。**
`saveAppSettings()`、`NightModeStore.persistNightMode()`、`TelescopeStore.persistEquatorialMount()`、`AudioStore.persistMusicEnabled()` 都只 `AppStorage.setOrCreate('stellariumSettings', ...)`；全仓没有 `PersistentStorage`，也没有把该键写入 Preferences 的代码。进程重启后该 JSON 为空，`StartupBridge.restoreStartupSettings()` 实际恢复不到音乐、单位、星历页签等。**赤道仪虽然也写在这里，但它属于引擎行为，真正的问题见 P4b。**
锚点：`MainWindowNativeNode.ets:3298-3325`、`NightModeStore.ets:63-73`、`TelescopeStore.ets:261-269`、`AudioStore.ets:39-48`、`StartupBridge.ets:164`。

**P3（高）语言选择不持久化。**
桥命令 `setLanguage` 只调用 `StelLocaleMgr::setAppLanguage()`，该函数只重建翻译器，**不写 `localization/app_locale`**；ArkTS 侧仅更新 `AppStorage`（同样不落盘）。重启后语言回到 `config.ini` 中的旧值（默认 `system`）。
锚点：`StelMainView.cpp:6865-6874`、`StelLocaleMgr.cpp:65-92`、`MainWindowNativeNode.ets:6463-6470`。

**P4（高）夜间模式双源竞争，且权威方向错误。**
夜间模式是**引擎行为**（`StelApp::setVisionModeNight` + `actionShow_Night_Mode`），权威配置键应为 `config.ini: viewing/flag_night`。当前实现把 Preferences（`night_mode_store`）当作权威，启动时 ArkTS 早期读 Preferences 并 `setActionChecked`，C++ `init()` 又按 `config.ini` 设置 `visionModeNight`；两者不一致时，最终状态取决于启动时序与回读覆盖。应改为：**引擎配置为权威，Preferences 只作为首帧缓存**，缓存不得反向覆盖引擎。
锚点：`QAbility.ets:995-1003`、`StartupBridge.ets:168-172`、`StelApp.cpp:716`、`NightModeStore.ets:24-60`。

**P4b（高）赤道仪/地平仪未写回引擎配置。**
赤道仪/地平仪是**引擎行为**（`StelMovementMgr` 的 `MountMode`，影响视图变换与 up 向量），引擎已有权威键 `navigation/viewing_mode`（`equator` / `horizon`）。但 `setMountMode()` / `setEquatorialMount()` 只改成员并 emit，**不写回 `QSettings`**；ArkTS 侧又把开关只存进 `AppStorage`（不落盘）。结果：这是一项引擎行为，却在重启后丢失，且 UI 与引擎可能不一致。
锚点：`StelMovementMgr.cpp:177-189`、`StelMovementMgr.cpp:281-317`、`MainWindowNativeNode.ets:3301`、`StartupBridge.ets:173-176`。

**P5（中）「保存设置」只做 `sync()`。**
`saveAllSettings` 命令不调用各模块的 `saveConfiguration()`，也不遍历属性写回。若某个 setter 从未执行过 `setValue`（只改了成员变量），`sync()` 无法把它写进 `config.ini`。
锚点：`StelMainView.cpp:10401-10406`、`ConfigurationDialog::saveAllSettings()`（桌面端实现未在 OHOS 路径复用）。

**P6（中）退后台落盘依赖 Qt 队列，存在时序窗口。**
`setApplicationForeground 0` 通过 `QMetaObject::invokeMethod(..., Qt::QueuedConnection)` 投递到 Qt 线程；若进程随即被冻结，`sync()` 可能来不及执行。当前没有“落盘完成”确认回执。
锚点：`StelMainView.cpp:4664-4667`、`StelMainView.cpp:18189-18195`。

**P7（中）无 schema 版本与迁移。**
Preferences 各 store 没有版本号；`config.ini` 仅有 `main/version` 且用于整包覆盖判断。字段改名/类型变化时没有迁移策略，只能靠默认值兜底。
锚点：`main.cpp:352+`、各 `*Store` 的读取分支。

**P8（中）失败不可观测。**
Preferences 写失败多数只 `hilog.warn`；`QSettings::sync()` 的返回值/状态未检查。用户看到“已保存”提示但无法确认是否真的落盘。
锚点：`MainWindowNativeNode.ets:4837-4846`、`StelMainView.cpp:10401-10406`。

**P9（低）导出/导入不完整。**
`exportConfig`/`importConfig` 只覆盖 `config.ini`，不包含 Preferences 中的用户数据（收藏、观测列表、搜索历史、观测点、快捷面板）。夜间模式与赤道仪在修正后属于 `config.ini`，会被覆盖；当前若仍以 Preferences 为准，则导出会漏掉它们。
锚点：`StelMainView.cpp:14294+`。

**P10（低）恢复默认不清理 ArkTS 数据。**
`restoreDefaultSettings` 只重置 `config.ini`，Preferences 中的观测点/收藏/观测列表等保留，语义上“恢复默认”不完整。
锚点：`StelMainView.cpp:10408-10415`。

## 4. 目标设计（to-be）

### 4.1 设计原则

1. **单一权威源**：一个设置项只允许一个权威存储位置；其他位置只能是缓存/镜像，且必须由权威源单向派生。
2. **写入时机显式化**：每个设置项声明保存策略（S0–S3），禁止“碰巧被某次 sync 带走”。
3. **恢复顺序确定**：启动恢复有固定阶段，后阶段可覆盖前阶段，且覆盖关系写进文档。
4. **失败可见**：落盘失败必须能反馈到 UI（至少一次提示 + 日志），不能静默。
5. **可迁移**：Preferences 带 `schemaVersion`，`config.ini` 带迁移钩子。
6. **桌面端不回归**：新增机制只在 OHOS 路径启用，桌面端行为保持不变。

### 4.2 存储边界

| 类别 | 权威存储 | 判定标准 |
|---|---|---|
| 引擎行为设置 | `config.ini` | 影响渲染、计算、星表、插件、坐标、时间、投影、**观测模式（赤道仪/地平仪）**、**夜间模式（暗适应视觉模式）**、语言等引擎状态 |
| 用户数据 | Preferences | 收藏、观测列表、搜索历史、观测点、快捷面板布局、桌面卡片 |
| 纯 UI 偏好 | Preferences（统一 `stellarium_ui`） | 单位、详情呈现轴、面板页签、面板展开状态等“只影响界面组织、不改变引擎行为”的偏好 |
| 运行期镜像/缓存 | AppStorage / Preferences `night_mode_store` | 只做 UI 订阅与首帧显示，**不作为权威源**；不得反向覆盖引擎 |

> 判定口径：**切换后是否需要引擎重新计算/重绘以改变天文呈现**。需要 → 引擎行为（`config.ini`）；只改变界面文字/布局 → UI 偏好（Preferences）。
>
> 关键变化：`AppStorage['stellariumSettings']` 从“伪持久化”降级为**纯内存镜像**；其内容由 Preferences 的 `stellarium_ui` 加载后填充，写入时同步回 Preferences。夜间模式与赤道仪/地平仪不再进入 `stellarium_ui`，而是走引擎权威键。

### 4.3 保存策略分级

| 策略 | 语义 | 适用 | 实现 |
|---|---|---|---|
| **S0 立即** | 每次变更即落盘 | 低频但关键、且丢失代价高的项：语言、夜间模式、赤道仪/地平仪、观测点、收藏/观测列表增删 | C++：`immediateSaveNow()`（绕过 `flagImmediateSave`）；ArkTS：`put + flush` |
| **S1 防抖合批** | 变更后 300–500 ms 合并落盘 | 高频连续变更：滑杆（星等上限、字体大小、透明度）、面板页签 | 统一 `SettingsFlusher` 定时器 |
| **S2 生命周期** | 退后台 / 页面隐藏时落盘 | 大部分引擎开关与样式 | `onBackground` → `flushAll('background')`，完成后回执 |
| **S3 显式** | 仅用户点击「保存设置」/ 导出时落盘 | 实验性/批量配置、导入导出 | `saveAllSettings` → `flushAll('manual', { force: true })` |

默认策略：**引擎开关 = S2**，**引擎连续量 = S1**，**用户数据 = S0**，**UI 偏好 = S0 或 S1**。

### 4.4 统一 flush 协议（C++ 侧）

新增（或改造）以下能力：

1. `StelApp::markSettingsDirty(scope)`：标记未落盘；`scope` 取 `engine` / `ui` / `all`。
2. `StelApp::flushSettings(reason)`：`reason ∈ { background, manual, export, shutdown }`；内部：
   - 遍历已注册的 `ISettingsParticipant::saveConfiguration()`（把成员变量写回 `QSettings`）；
   - `QSettings::sync()`；
   - 返回 `FlushResult { ok, configPath, writtenKeys, error }`。
3. `StelApp::immediateSave()` 语义拆分：
   - 保留现有门控版本供桌面端与“细节设置”使用；
   - 新增 `immediateSaveNow(key, value)`，**始终** `setValue + sync`（或 `setValue + markDirty(S0)`，由 flusher 立即 flush）。
4. `setLanguage` 补齐 `localization/app_locale` 写入，并按 S0 落盘。
5. 夜间模式与赤道仪/地平仪统一：**以 `config.ini` 为权威**（`viewing/flag_night`、`navigation/viewing_mode`）。Preferences 中的 `night_mode_store` 仅作为冷启动首帧缓存，用于在引擎就绪前避免主题闪白；缓存**不得**反向覆盖引擎值。引擎 setter（`setVisionModeNight`、`setMountMode`）必须写回配置并按 S0 落盘。

### 4.5 统一持久化层（ArkTS 侧）

新增 `state/SettingsRepository.ets`（或等价模块），职责：

- 单一 Preferences store：`stellarium_ui`（替代散落的 `stellariumSettings` 内存写法）；
- 定义 `UiSettings` 接口 + `SETTINGS_SCHEMA_VERSION`；
- `load(): Promise<UiSettings>`：启动时一次性加载，带默认值与迁移；
- `patch(partial)`：写入 + 防抖 flush；
- `flush(reason)`：显式落盘，返回结果；
- 各 `*Store` 不再直接写 `AppStorage['stellariumSettings']`，改为注入 `SettingsRepository`。

保留现有按域拆分的 Preferences（观测点/收藏/观测列表/搜索历史/快捷面板/卡片），因为它们的数据量大且更新频率不同；但统一通过 `SettingsRepository` 的命名规范与版本号管理。

### 4.6 启动恢复顺序

```
1. QAbility.readEarlyNightMode()      // Preferences 缓存：仅用于首帧主题，不作权威
2. C++ StelApp::init(config.ini)      // 夜间模式/赤道仪等引擎权威值在此生效
3. StartupBridge.restoreStartupSettings()
   ├─ SettingsRepository.load()       // Preferences: stellarium_ui（纯 UI 偏好）
   ├─ 应用 UI 偏好（单位/页签/音乐…）
   └─ 引擎镜像只读对齐（夜间模式/赤道仪以引擎值刷新 UI，不反向下发）
4. 各域 store 加载（观测点/收藏/观测列表/搜索历史/快捷面板）
5. 首帧渲染
```

规则：**引擎配置始终优先**；第 1 步的缓存只影响引擎就绪前的首帧外观，第 3 步必须用引擎回读值刷新 UI（`syncNightModeFromEngine`、`equatorialMountChanged`），禁止把缓存值再写回引擎。

### 4.7 版本与迁移

- Preferences：每个 store 存 `schemaVersion: int`；`load()` 时按版本执行迁移函数链；迁移失败回退默认值并保留原始 JSON（`_legacy` 键）供诊断。
- `config.ini`：沿用 `main/version`；在 `StelApp::init()` 后增加 `migrateConfig(fromVersion)` 钩子，处理已知键改名（如夜间模式键）。
- 迁移必须幂等、可重入，且在写盘前完成。

### 4.8 失败处理与可观测性

- 所有 flush 返回结构化结果；`saveAllSettings` 回包携带 `ok`、`writtenKeys`、`error`。
- 失败时 UI 提示一次（`flashHint`），并写 `[settings]` 前缀日志（含 reason、路径、错误码）。
- 连续失败（≥3 次）时降级为只读模式提示，避免用户误以为已保存。

### 4.9 导出 / 导入 / 恢复默认

| 动作 | 目标语义 |
|---|---|
| 导出 | 单个 JSON 包：`{ schemaVersion, configIni, uiSettings, userData: { bookmarks, observingList, searchHistory, locations, quickPanel } }`；保留纯 `config.ini` 导出作为兼容选项 |
| 导入 | 按 `schemaVersion` 迁移后分通道写入；失败项汇总返回，不中断其他项 |
| 恢复默认 | 引擎配置重置 + UI 偏好重置 + 用户数据**默认保留**（提供“同时清除用户数据”二次确认） |

实现状态（2026-10-21）：

- **恢复默认**：已接入「设置 → 主设置」第一条目「恢复默认设置」（胶囊「重置」按钮 + 二次确认）；成功后重置 `stellarium_ui` 并**自动退出应用**，下次启动时引擎按 `main/restore_defaults` 覆盖配置；用户数据（收藏/观测列表/观测点/搜索历史/快捷面板）保留。
- **导出/导入**：仍为纯 `config.ini` 文本（P9），JSON 全量包尚未实现。

## 5. 设置归属明细（评审用）

### 5.1 引擎 `config.ini`

| 分组 | 代表键 | 策略 | 备注 |
|---|---|---|---|
| `viewing/*` | `flag_constellation_drawing`、`flag_nebula`、`flag_meteor`、`flag_night` | S2（连续量为 S1）；`flag_night` 为 **S0** | `flag_night` 是夜间模式**权威键** |
| `astro/*` | `flag_nebula_name`、`flag_nutation`、`flag_aberration` | S2 | |
| `navigation/*` | `viewing_mode`、`startup_time_mode`、`preset_sky_time`、`today_time` | `viewing_mode` 为 **S0**，其余 S2 | `viewing_mode` = `equator` / `horizon`，是赤道仪/地平仪**权威键** |
| `projection/*` | `type`、`flip_horz`、`flip_vert`、`viewport` | S2 | |
| `video/*` | `fullscreen`、`screen_w/h`、`viewport_effect`、`dithering_mode` | S2 | 屏幕尺寸类可考虑 S0 |
| `gui/*` | `selected_object_info`、`flag_show_decimal_degrees`、`screen_font_size` | S2 | 字体大小类 S1 |
| `localization/*` | `app_locale`、`time_display_format`、`date_display_format` | **S0** | 当前 `app_locale` 未写入（P3） |
| `color/*` | `const_lines_color`、`object_trails_color` 等 | S2 | 颜色选择器关闭时 flush |
| `landscape/*`、`stars/*`、插件分组 | 各模块配置 | S2 | |
| `main/restore_defaults` | 布尔 | 一次性 | 重启消费后清除 |

### 5.2 Preferences

| store | 键 | 策略 | 说明 |
|---|---|---|---|
| `night_mode_store` | `nightMode` | 缓存 | **仅首帧缓存**；权威为 `config.ini: viewing/flag_night`，缓存不得反写引擎 |
| `stellarium_ui`（新增） | `musicEnabled`、`useMetricUnits`、`viewCoordinates*`、`objectDetailConnectorVisible`、`astroTab/Group/...`、`ephemeris*`、`schemaVersion` | S0/S1 | 承接现 `stellariumSettings` 中**纯 UI 偏好**内容；不含夜间模式与赤道仪 |
| `stellarium_observer_location` | 观测点记录 | S0 | |
| `stellarium_bookmarks` | 收藏列表 | S0 | |
| `stellarium_observing_list` | 观测记录 | S0 | |
| `stellarium_search_history` | 搜索历史 | S1 | 高频写入，防抖 |
| `stellarium_quick_panel` | 面板布局 | S0 | |
| `stellarium_info_window` | `detailDisplayMode` | S0 | 与 `stellarium_ui` 去重 |
| `sky_instrument_card` | 卡片数据 | S1 | 由服务发布 |

## 6. 关键流程

### 6.1 前台修改（S0）

```
UI 事件 → store 更新 → SettingsRepository.patch()
        → Preferences.put + flush（失败：提示 + 日志）
        →（若需引擎镜像）桥命令 → C++ setter → immediateSaveNow → sync
```

**引擎行为的 S0 例外**：夜间模式、赤道仪/地平仪、语言不经过 `SettingsRepository`，直接走
`桥命令 → C++ setter → 写回 config.ini → sync`，并以引擎回执刷新 UI 镜像。

### 6.2 前台修改（S2）

```
UI 事件 → 桥命令 → C++ setter → setValue + markDirty
        →（退后台）flushSettings('background')
        → saveConfiguration()* → QSettings::sync() → 回执
```

### 6.3 手动保存

```
「保存设置」→ saveAppSettings()（SettingsRepository.flush('manual')）
            → 桥命令 saveAllSettings
            → flushSettings('manual', force)
            → 返回 { ok, writtenKeys, error } → flashHint
```

### 6.4 冷启动

见 §4.6。

## 7. 兼容性与迁移

| 场景 | 处理 |
|---|---|
| 已安装用户的 `config.ini` 无新键 | 使用默认值；不强制重写 |
| `stellariumSettings` 旧内存数据 | 无法跨进程恢复（本来也没落盘），首次新版本启动按默认值初始化 `stellarium_ui` |
| 夜间模式两份数据不一致 | **以 `config.ini` 的 `viewing/flag_night` 为准**；启动后刷新 Preferences 缓存，禁止反向覆盖 |
| 赤道仪/地平仪旧数据 | 旧版本无持久化（仅 AppStorage），无法恢复；首次启动按 `navigation/viewing_mode` 默认 `horizon`，之后由 setter 正常写回 |
| 语言 | 首次启动把当前系统/界面语言写入 `localization/app_locale`；之后以 `config.ini` 为准 |
| 回滚 | 新 Preferences store 与旧键并存；回滚版本忽略 `stellarium_ui`，不影响旧路径 |

## 8. 测试矩阵

| 用例 | 步骤 | 预期 |
|---|---|---|
| T1 引擎开关持久化 | 改星座连线 → 退后台 → 杀进程 → 重启 | 状态保持 |
| T2 星云/流星持久化 | 改星云标注/流星 → 退后台 → 重启 | 状态保持（验证 P1 修复） |
| T3 夜间模式 | 切换夜间 → 杀进程 → 重启 | 直接夜间主题，无双源回弹 |
| T4 语言 | 切换语言 → 杀进程 → 重启 | 语言保持（验证 P3 修复） |
| T5 UI 偏好 | 改单位/音乐/星历页签 → 杀进程 → 重启 | 全部保持（验证 P2 修复） |
| T5b 赤道仪/地平仪 | 切换赤道仪 → 杀进程 → 重启 | 引擎与 UI 均为赤道仪，无回弹（验证 P4b 修复） |
| T6 手动保存 | 改多项 → 点「保存设置」→ 强杀 | 全部保持，且有成功回执 |
| T7 导出/导入 | 导出 → 重置 → 导入 | 引擎 + UI + 用户数据完整恢复 |
| T8 恢复默认 | 执行恢复默认 | 引擎/UI 重置；用户数据按选择保留 |
| T9 写失败 | 模拟 Preferences/config 不可写 | UI 提示失败 + 日志，不静默 |
| T10 迁移 | 构造旧版数据 → 启动 | 迁移成功，无丢失；失败回退默认并保留 `_legacy` |
| T11 桌面端回归 | 桌面端改设置 → 保存/退出 | 行为与改动前一致 |

## 9. 实施切片（建议）

| 切片 | 内容 | 依赖 |
|---|---|---|
| **S1 基建** | `SettingsRepository` + `stellarium_ui` store + `schemaVersion`；`flushSettings(reason)` 与回执 | 无 |
| **S2 修复 P1/P5** | `immediateSaveNow`；`saveAllSettings` 调用 `saveConfiguration()` + dirty flush；OHOS 默认策略 | S1 |
| **S3 修复 P2/P3** | 迁移 `stellariumSettings` 消费者到 `SettingsRepository`；语言写入 `app_locale` | S1 |
| **S4 修复 P4/P4b** | 夜间模式、赤道仪/地平仪回归 `config.ini` 权威；setter 写回 + S0 落盘；Preferences 仅保留首帧缓存 | S1/S3 |
| **S5 收口** | 导出/导入扩展、恢复默认语义、失败可观测、迁移钩子 | S1–S4 |

## 10. 待决策问题（review 重点）

1. `config.ini` 与 Preferences 的边界是否认可？当前按「夜间模式、赤道仪/地平仪、语言属于引擎行为，权威在 `config.ini`」处理。
2. S0/S1/S2/S3 的分级是否符合使用习惯？是否有需要提升为 S0 的高频项？
3. `immediateSaveNow` 采用“每次 sync”还是“setValue + 立即 flush”？（前者简单，后者可合批）
4. 是否接受新增 `stellarium_ui` store，还是复用现有 `night_mode_store` 扩展为通用 UI store？
5. 导出包是否包含用户数据（收藏/观测列表）？隐私与体积如何权衡？
6. 恢复默认是否需要提供“同时清除用户数据”选项？
7. 语言权威位置：按本文设计为 `config.ini: localization/app_locale`（与桌面端一致）；是否认可？
8. 迁移失败时的兜底：保留 `_legacy` 键是否足够，还是需要导出诊断包？

---

## 附录 A：现状证据索引

| 主题 | 文件:行 |
|---|---|
| `immediateSave` 门控 | `src/core/StelApp.cpp:1411-1415`；`StelApp.cpp:314`；`StelApp.cpp:489` |
| 退后台 sync | `src/StelMainView.cpp:18183-18195`；`harmonyos/ets-source/qability/QAbility.ets:1095-1112` |
| 手动保存命令 | `src/StelMainView.cpp:10401-10406`；`harmonyos/ets-source/state/ToolsStore.ets:197-207` |
| AppStorage 设置写入 | `harmonyos/ets-source/pages/MainWindowNativeNode.ets:3298-3325` |
| 夜间模式持久化 | `harmonyos/ets-source/state/NightModeStore.ets:63-73`；`MainWindowNativeNode.ets:4837-4846`；`QAbility.ets:995-1003` |
| 赤道仪/地平仪 | `src/core/StelMovementMgr.cpp:177-189`（读取 `navigation/viewing_mode`）；`StelMovementMgr.cpp:281-317`（setter 未写回）；`src/core/StelMovementMgr.hpp`（`MountMode`） |
| 启动恢复 | `harmonyos/ets-source/capability/StartupBridge.ets:160-194` |
| 语言 | `src/StelMainView.cpp:6865-6874`；`src/core/StelLocaleMgr.cpp:65-92` |
| 导出/导入 | `src/StelMainView.cpp:14294+` |
| 恢复默认 | `src/StelMainView.cpp:10408-10415`；`src/main.cpp:345-350` |
| Preferences store 名 | `harmonyos/ets-source/common/types/MainWindowModels.ets:434-442` |
