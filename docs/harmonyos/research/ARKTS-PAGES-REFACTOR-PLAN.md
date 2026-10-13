# pages/ 代码库重构方案（ArkTS / ArkUI）

- **状态：** 待评审。本文只做规划，**未改动任何源码**。
- **日期：** 2026-09-30
- **范围：** `harmonyos/ets-source/pages/**`，主对象 `pages/MainWindowNativeNode.ets`（32,774 行）。
- **正确性来源：** 本文所有数字与结构均由第 9 节命令在当前代码上实测得到，非估计值。
- **与既有规划的关系：** 产品级的面板归属、导航规则、收口规则服从
  `research/PANEL-PLUGIN-ARCHITECTURE-ROADMAP.md`；本文只解决**代码结构**问题，不改变面板的产品定义。

---

## 1. 现状取证

### 1.1 体量

| 文件 | 行数 | 说明 |
|---|---:|---|
| `pages/MainWindowNativeNode.ets` | **32,774** | 唯一主界面实现，占业务 ArkTS 的 **80.8%** |
| `pages/location_hierarchy.ts` | 74,611 | 数据表（行政区划），不参与重构；**M2 已迁 `common/location/hierarchy.ts`**，见 §15.12.17 |
| `pages/location_names_zh.ts` | 7,350 | 数据表；**M2 已迁 `common/location/names_zh.ts`** |
| `pages/I18n.ets` | 2,354 | 翻译表 + 语言切换 |
| `pages/StellariumTypes.ets` | 1,122 | 桥接协议类型集合；**M5 已迁 `common/types/StellariumTypes.ets`**（旧路径留一行式 barrel），见 §15.12.21 |
| `qability/StellariumResourceBootstrap.ets` | 943 | 资源预热 |
| `pages/StellariumAudio.ets` | 927 | 音频；**M3 已迁 `capability/AudioEngine.ets`**（§15.7 规则 1 NAPI 判定，非 `common/media/`），见 §15.12.18 |
| `qability/QAbility.ets` | 694 | UIAbility（启动链、隐私门控） |
| 其余 20 余个文件 | < 250 各自 | |
| **业务代码合计（不含 `location_*` 数据表）** | **40,548** | 其中主文件占 80.8% |

### 1.2 单体内部结构（主文件）

| 指标 | 实测值 |
|---|---:|
| `@Component` 结构体 | **1**（`export struct WindowNativeNode`，L806） |
| `@State` 字段 | **1,047**（原始类型 948 / 数组 37 / 自定义类 13） |
| `@Builder` 方法 | **145** |
| `private` 方法 | ≈**1,109** |
| `callInteractive` 调用点 | **203**（定义 1 处，L4081） |
| `setInterval` | **20** |
| 定时器字段 | ≈**38** |
| `ForEach` | **169** |
| `.id()` 锚点 | **41** |
| `activePanel` 取值 | **33** |
| `AppStorage` 引用 | 28 |
| `@Watch` | 2 |

### 1.3 最大的 Builder（拆分靶点，前 12，**2026-10-01 重测**）

> **更正说明：** 本文初版此表用"下一个 `\n  }\n`"启发式测量，该启发式会越过 builder 的真实收尾、把紧随其后的
> 普通方法也算进去，导致**严重高估**（如 `searchFilterMenu` 初版记 3,441 行，实测仅 **48 行**）。
> 下表改用"首个 `^  }$` 收尾"重测；全文件共 **118 个 `@Builder`，合计 9,475 行**。

| 行数 | 起始行 | 名称 |
|---:|---:|---|
| **4,707** | L22128 | `panelContent`（33 个面板的 if/else 分发，**占全部 builder 代码的 50%**） |
| 446 | L26837 | `toolsPanel` |
| 209 | L17151 | `scriptFocusShell` |
| 183 | L18603 | `unifiedObjectDetailCard` |
| 179 | L19683 | `tabletInspectorMedia` |
| 150 | L17588 | `expandedShell` |
| 130 | L21407 | `compactMoreDrawer` |
| 125 | L9786 | （首行为 `if` 的匿名 builder） |
| 109 | L27500 | `cityChipsRow` |
| 99 | L21162 | `gyroCalibPanel` |
| 93 | L21912 | `skyCultureMakerConstellationEditor` |
| 87 | L17740 | `compactShell` |

**推论（影响策略）：** 本文件的 UI **并不分散在众多超大 builder 里**，而是集中在 **`panelContent`（4,707 行）**；
其余 builder 多为几十到几百行。因此 Phase 4 的主战场是**把 `panelContent` 的 33 个面板分支逐个抽成组件**
（每个分支通常只有几十行），而不是先啃若干"巨型 builder"。

### 1.4 状态字段的领域分布（按名称聚类）

| 领域 | 字段数 |
|---|---:|
| 天文计算（astro/wut/phenomenon/eclipse/transit/season/almanac…） | 164 |
| 星空文化（skyCulture/sc*） | 130 |
| 对象与详情（object/selected/detail/inspector…） | 93 |
| 天空与视图（sky/view/grid/line/label/star/constellation…） | 79 |
| 图层开关（equatorialGrid/eclipticGrid/cardinalPoints/asterismLines…） | ≈60 |
| 搜索与分类（search*/category*） | ≈60 |
| 目镜（ocular/eyepiece） | 50 |
| 工具（angle/archaeo/nav/mosaic/pointer/coordinate） | 51 |
| 卫星（sat*） | ≈40 |
| 壳层与面板（panel/dock/chip/shell/layout） | 40 |
| 脚本与自动化 | 26 |
| 望远镜（lx200/telescope） | 24 |
| 时间（time/jd/scrub/clock/rate） | 21 |
| 传感器（gyro/compass/orient/attitude） | 13 |
| 视频与录屏 | 10 |
| 设置（config/settings/option） | 10 |
| 位置（place/city/savedLocations/locSearch*） | 8 |
| 星云 / 极轴镜 / 书签 / 音频 / 流星 / i18n | 6 / 6 / 4 / 3 / 3 / 1 |

### 1.5 跨文件状态与存储（全应用）

| 文件 | AppStorage | `@StorageLink/Prop` | LocalStorage | `@Watch` |
|---|---:|---:|---:|---:|
| `pages/MainWindowNativeNode.ets` | 28 | 5 | 1 | 2 |
| `qability/QAbility.ets` | 26 | 0 | 2 | 0 |
| `pages/ApplicationRoot.ets` | 1 | 6 | 0 | 3 |
| `pages/StartupSky.ets` | 1 | 3 | 0 | 2 |
| `pages/PrivacyBootstrap.ets` | 1 | 1 | 0 | 1 |
| `pages/I18n.ets` | 2 | 1 | 0 | 0 |
| `qability/ClipboardService.ets` | 1 | 0 | 0 | 0 |
| `qability/QtWindowStageAdapter.ets` | 1 | 0 | 9 | 0 |
| `qability/QtUtils.ets` / `LocalStorageTsModule.ets` | 0 | 0 | 4 / 6 | 0 |
| 其余 3 个独立窗口页 | 0 | 0 | 各 1 | 0 |
| **AppStorage 唯一 key 总数** | **17** | | | |

**关键区分：** `LocalStorage` 在本工程**不是应用状态**，而是 Qt/QML 互操作桥面
（`windowStage.loadContent(path, storage)` 把 storage 交给 Qt 内容；
`LocalStorageTsModule.makeNewLocalStorage` 经 `QtUtils.getModulesFactoriesMapForQt()` 暴露给 C++）。
这部分属于 C++/Qt 契约，**不在重构范围内**。

### 1.6 同步链路与测试契约

- `scripts/sync-ohos-build-sources.sh` 用 `find "$src_dir" -type f` **整树递归镜像**
  `harmonyos/ets-source/**` → `build/libstellarium-harmonyos/entry/src/main/ets/**`。
  → **新增子目录无需改脚本**，会被自动同步。
- `main_pages.json` 注册 4 个 `@Entry`：主窗口 `ApplicationRoot` + `FloatWindowNativeNode`
  / `SubWindowNativeNode` / `UiExtensionNativeNode`（三个独立窗口）。新增的组件文件**不需要注册**。
- 依赖 UI 内部标识的测试：`scripts/test-ohos-model-scroll.mjs`（`.id()` 1 处）、
  `scripts/test-ohos-search-browser.mjs`（`.id()` 2 处）；
  `test-ohos-guide-pad.mjs` / `test-ohos-polar-scope-pad.mjs` 走 uitest + dumpLayout。
  其余 `test-ohos-*`（52 个）主要走语义 CLI 与 C++ 层。

---

## 2. 根因分析（为什么会长成这样）

1. **唯一 struct = 唯一组件 = 全局刷新。**
   1,047 个 `@State` 集中在同一个 `struct` 实例上，任何一个变更都在同一棵渲染树上求值。
   代码内 L16156 附近的注释已经自证这个坑：*高频刷新路径不得触碰其他 `@State`，否则触发全局重排、
   拖动星图卡顿*——这正是"状态过度集中"的症状，而不是原因。

2. **`@Builder` 的参数按值捕获，堵死了状态下沉。**
   ArkUI V1 的 `@Builder` 简单类型参数是值拷贝、不回传、不参与变更通知；
   因此所有 builder 只能通过 `this.xxx` 直读宿主状态。
   结果：**状态被物理锁定在唯一宿主里**，无法随 UI 一起下沉到子组件。

3. **推论：单纯按行数切文件无效。**
   切完仍是同一个 `struct`、同一个 `this`、同一棵子树——既没有减少刷新范围，
   也没有减少耦合，只是把 32,774 行变成 10 个互相 `this` 依赖的文件。
   必须同时引入**组件边界**与**状态所有权**。

4. **次生问题：**
   `panelContent()` 5,138 行用 if/else 分发 33 个面板（无表驱动、无懒加载边界）；
   38 个定时器全挂在宿主生命周期上（启动/前台/后台/销毁四处逐个接线）；
   `callInteractive` 203 个裸调用点直接依赖 `libentry.so` 导出。

---

## 3. 目标架构

```
harmonyos/ets-source/
├── pages/                    ← 只留页面入口、类型/资源表
│   ├── ApplicationRoot.ets          @Entry 主窗口（不变）
│   ├── I18n.ets  StellariumTypes.ets  StellariumAudio.ets
│   ├── location_*.ts  *Geometry.ts  *Client.ets  DetailModel*.ets
│   └── FloatWindow/SubWindow/UiExtensionNativeNode.ets（独立窗口，不动）
├── window/                   ← 新增：窗口与壳层
│   ├── WindowNativeNode.ets         原结构名保留（ApplicationRoot 直接引用），瘦身为根容器
│   ├── shell/      ExpandedShell.ets  CompactShell.ets  HoverShell.ets  BottomDock.ets
│   └── overlay/    InfoWindow.ets  UnifiedObjectDetailCard.ets  TimeWheel.ets
│                   DockClock.ets  StartupOverlay.ets
├── panels/                   ← 新增：33 个面板，一文件一组件
│   ├── PanelHost.ets                原 panelContent 的 if/else → 表驱动 + 懒加载
│   ├── time/       TimePanel.ets  TimeScrubberSlider.ets  TimeSpeedChips.ets
│   ├── search/     SearchPanel.ets  SearchBar.ets  SearchFilterMenu.ets
│   ├── astro/      AstroPanel.ets  WutTargetCard.ets  ContinuationSection.ets
│   ├── layers/     LayersPanel.ets  LayerPresetBar.ets  HierColumn.ets
│   ├── object/     ObjectPanel.ets  ObjectInspector.ets  ObjectActionBar.ets
│   ├── skyCulture/ Satellite/ Ocular/ Telescope/ Script/ Settings/ Tools/
│   └── Place/ Observers/ Help/ Catalogs/ Commands/ Bookmarks/ Meteors/
├── state/                    ← 新增：@Observed 领域 store（V1）
│   ├── TimeStore.ets  PanelStore.ets  SearchStore.ets  AstroStore.ets
│   ├── SkyViewStore.ets  ObjectStore.ets  SkyCultureStore.ets  SatelliteStore.ets
│   ├── SensorStore.ets  ScriptStore.ets  TelescopeStore.ets  SessionStore.ets
│   └── ToolStore.ets（angle/archaeo/nav/mosaic/pointer/coordinate）
├── bridge/
│   ├── BridgeClient.ets              `libentry.so` 命令桥的唯一出口（封装 callInteractive）
│   └── (后续) time.ts  astro.ts  …    按域的类型化命令方法
├── common/                   ← 已有：PrivacyStartup / StellariumLifecycle / QtAppConstants
│   └── ui/         UiTokens.ets(UI_RADIUS_* / UI_OPTION_ANIMATION_MS)
│                   IconButton.ets  DockButton.ets  SwitchRow.ets  ChipRow.ets  PanelHost 骨架
└── qability/  process/  qabilitystage/   （不动；QAbility、Qt 桥、隐私门控）
```

要点：

- 新增目录由 sync 脚本自动递归镜像，**无需改 `scripts/sync-ohos-build-sources.sh`，无需改 `main_pages.json`**。
- 目录划分依据是第 1.4 节的状态聚类与第 1.3 节的 Builder 体积，不是凭感觉切分。
- `window/` 与 `panels/` 的边界 = 壳层（跨面板常驻）与面板（一次只显示一个）。

---

## 4. 状态策略：V1 `@Observed` store + 子组件

**继续使用 V1，不迁移 V2**（理由见第 8 节）。

### 4.1 基本形态

```ts
// state/TimeStore.ets —— 纯数据 + 纯方法，不 import 任何 UI
@Observed
export class TimeStore {
  observationTimeText: string = ''
  timeRateText: string = ''
  scrubberJd: number = 0
  // …原 @State 字段整体迁入
}
```

```ts
// panels/time/TimePanel.ets —— 只订阅自己需要的 store
@Component
export struct TimePanel {
  @ObjectLink timeStore: TimeStore      // 变更只刷新本组件
  build() { /* 原 time 分支的 builder 内容 */ }
}
```

```ts
// 根容器持有并向子组件传引用（V1 的 @ObjectLink 初始化规则）
// WindowNativeNode 内：
Comp({ timeStore: this.timeStore })
```

### 4.2 规则

1. **一个 store = 一个领域**，与第 3 节 `state/` 目录一一对应；字段名保持不变，便于对照回滚。
2. store 内**不放 UI 代码**，不 import ArkUI 组件，只做数据与纯逻辑（可被单测覆盖）。
3. **刷新范围必须是"订阅者"**：只有 `@ObjectLink` 了该 store 的子组件才重建；
   这是本方案唯一的性能论据来源。
4. **高频链优先隔离**：1 s / 125 ms 时间链、惯性、传感器分别独立成 store，
   与 `panelVisible` 之类的壳层状态彻底分离（对应 L16156 的既有告警）。
5. **不使用 `@Provide/@Consume` 泛化**（当前为 0，保持）；跨层仅在确有主题/常量需求时逐一评估。
6. **过渡手段（已修订，见 §11 修订 1）**：字段搬入 store 后，根 struct **不能**用同名 getter 委托
   —— V1 的 `@Component` 不允许 getter 访问器（ArkTS 转换会丢弃它们，存在运行期崩溃风险）。
   可行做法只有两条：① 调用点机械替换为 `this.timeStore.xxx`（读写都改，编译器全程把关）；
   ② 把该域的 UI 与 store **同步**抽成子组件（`@ObjectLink` 订阅），一步到位。
   由于未加装饰器的 store 字段在 V1 中不会触发宿主重渲染，**单独搬 store 会在搬完那一刻丢失该域的刷新**，
   因此 Phase 3 必须与 Phase 4 的对应面板同步进行，不能先全量搬 store 再补组件。
7. **定时器随域迁移**：每个 store 自带 `start()/stop()`，
   在现有四个生命周期挂点（初始化 / 前台恢复 / 后台 / `aboutToDisappear`）统一收口，
   不再逐个手动接线。

---

## 5. 分阶段迁移计划（绞杀者模式）

原则：每阶段**独立可编译、可装机、可回滚**；纯搬移与功能改动**不混在同一次提交**。

| Phase | 内容 | 规模 | 验收 |
|---|---|---|---|
| **0 基线** | 固化回归契约：33 个 `activePanel`、41 个 `.id()` 锚点、CLI 冒烟清单、构建/装机基线快照，落成可复跑脚本 | 1 天 | 基线快照入库（不入代码库则放 `docs/harmonyos/json/`） |
| **1 纯叶子** | `UI_RADIUS_*` / `UI_OPTION_ANIMATION_MS` → `common/ui/UiTokens.ets`；无状态 builder（iconButton、dockButton、switchRow、chip、面板骨架）→ `common/ui/*.ets` | 3–5 天 | `arkts_check` + 构建 + 装机 + CLI 冒烟 |
| **2 命令桥** | `bridge/BridgeClient.ets` 封装 `callInteractive`（保留同名薄委托），203 个调用点不动 | 2–3 天 | 同上；重点回归命令回包/错误码 |
| **3 状态 store** | **必须与 Phase 4 的对应面板同步进行**（见 §11 修订 1）：逐域把状态与该域 UI 一起抽成 store + 子组件，`TimeStore`+时间面板先行，再 `PanelStore` → `SearchStore` → `AstroStore` → `SkyViewStore` → `ObjectStore` → `SkyCultureStore` → `SatelliteStore` → `SensorStore` → `ScriptStore` → `TelescopeStore` → `SessionStore` → `ToolStore` | 每域 1–3 天，合计 ≈3 周 | **每域 1 次提交**；重点回归该域面板的交互与刷新 |
| **4 面板组件化** | 按 Builder 体积**从大到小**逐面板抽取为 `@Component`；`panelContent` 改 `PanelHost` 表驱动 + 懒加载 | 每面板 0.5–2 天，合计 ≈3–4 周 | **每面板 1 次提交**；回归该面板全部交互 + 平板/手机断点 |
| **5 Overlay** | 信息窗、详情卡、时间轮、Dock 时钟 → `window/overlay/` | 1 周 | 叠放顺序 / zIndex / HitTestMode 回归（按 `specs/UI-ARCHITECTURE.md` §3 §6） |
| **6 壳层** | expanded / compact / hover 三壳 + bottomDock → `window/shell/` | 1–2 周 | 断点切换（短边 520 / 700 / 900×520）、折叠半折角、220 ms 转场回归 |
| **7 收口** | 删除过渡 getter 与死代码；更新 `specs/UI-ARCHITECTURE.md` 与根 `AGENTS.md`（记录 pages/ 重构后的 UI 结构约定） | 1 周 | 全量回归 + 文档校准 |

**总估时：约 9–12 周**（按每阶段完成后向用户汇报、批准后提交的节奏）。

### 5.1 每阶段统一验收矩阵

| 检查 | 手段 | 通过标准 |
|---|---|---|
| ArkTS 静态 | `arkts_check` | 无 error |
| 编译 | `devecocli build` | BUILD SUCCESSFUL |
| 装机 | install + start | 均成功 |
| 交互冒烟 | 语义 CLI（按 `DEVELOPMENT-MCP-WORKFLOW.md`，**不用坐标点击**） | 关键命令返回正常 |
| 契约 | 33 panel id / 41 个 `.id()` 锚点比对 | 完全一致 |
| 视觉 | 仅在改布局时按 `AGENTS.md` §7.9 | 构建+安装+启动成功即为通过 |
| 回滚 | 每阶段一个提交点 | `git revert` 单次即可回退 |

---

## 6. 不变式与约束（硬性）

1. **行为零变更。** 重构阶段不改任何用户可见行为；发现的问题单独提 issue，不顺手修。
2. **`.id()` 字符串保持稳定**（uitest 依赖：`test-ohos-model-scroll.mjs`、`test-ohos-search-browser.mjs`）。
3. **CLI 命令面不变**（`CLI.md` 契约）；`callInteractive` 的 payload / 返回结构不变。
4. **`main_pages.json` 不变**；`ApplicationRoot` 仍是主窗口唯一 `@Entry`。
5. **保持 V1，禁止 V1/V2 混用**（避免双重代理）。
6. **`LocalStorage` 不动**——它是 Qt 互操作桥面（第 1.5 节），迁移即破坏 C++ 契约。
7. **38 个定时器**的启动/停止时机与现状一致；迁移后用 store 的 `start/stop` 收口并逐一核对生命周期。
8. **产品级面板归属与导航**服从 `PANEL-PLUGIN-ARCHITECTURE-ROADMAP.md` 的收口规则。
9. 注释沿用项目既有中文风格；不新增无关注释。

---

## 7. 风险登记

| 风险 | 影响 | 对策 |
|---|---|---|
| V1 `@Observed` 只观测第一层属性，嵌套对象深层修改不刷新 | 面板局部不刷新（**静默 bug**） | 实测本仓库 `this.X.y =`（状态字段上的就地属性赋值）**为 0 处**，3,259 处赋值里 1,028 个字段全是整体替换 → 风险本就极低；仍需对 37 个数组型 + 13 个自定义类型字段逐个确认 |
| `@ObjectLink` 不能在子组件内重新赋值；父传子需传引用 | 编译报错 / 运行期行为异常 | 统一"父持有 store，子 `@ObjectLink` 只读引用，修改回落 store 方法" |
| 定时器迁移漏 stop | 后台耗电 / 定时器叠加 | store 自带 `start/stop`；四个生命周期挂点统一收口；装机后核对前台/后台往返 |
| 41 个 `.id()` 锚点被误改 | uitest 失效 | Phase 0 固化锚点快照，每阶段比对 |
| 面板体积大（如 `searchFilterMenu` 3,441 行）抽取期间产生大量 diff | 评审困难、回滚粒度粗 | 一面板一提交；纯搬移不掺功能改动 |
| `AppStorage` 17 个 key 在 5 个文件间共享（含 `QAbility` 启动链） | 迁移期状态不同步 | 本方案**不动 AppStorage**（保持 V1）；仅在将来迁 V2 时统一处理（见第 8 节） |
| `specs/UI-ARCHITECTURE.md` 内大量 `文件:行号` 引用 | 重构后文档失真 | Phase 7 统一校正；期间在 CHANGELOG 注明行号漂移 |

---

## 8. 备选方案与否决理由

### 8.1 大爆炸重写（否决）

一次性重写 32,774 行，回归面覆盖 33 个面板 + 4 个 `@Entry` + C++ 桥接 + 隐私启动链，
无法提供可编译的中间态，失败即全量回滚。**否决。**

### 8.2 迁移到状态管理 V2（当前否决）

按官方 `V1-V2迁移概述` 的能力对照表，对本仓库逐项实测：

| 迁移项 | 官方映射 | 本仓库实测 | 成本 |
|---|---|---|---|
| `@Component` → `@ComponentV2` | 1:1 | 全应用 **8 个** `@Component`，**0 个** `@ComponentV2` | 小 |
| `@State` → `@Local` | 1:1 | **1,047 个**，其中 948 个是 `number/string/boolean` | 小（近似纯改名） |
| `@Link` → `@Param`+`@Event` | 官方最大痛点 | **0 个** | 不存在 |
| `@Prop` / `@Provide` / `@Consume` / `@Observed` / `@ObjectLink` / `@Track` | 各有映射 | **全为 0** | 不存在 |
| `$$` / `@BuilderParam` / `LazyForEach` | — | **全为 0** | 不存在 |
| `@Watch` → `@Monitor` | 语义有差异（V2 一次事件内多次变化只触发一次；`@Monitor` 可取变化前后值） | 全应用 8 个（主文件 2 个） | 小，需行为回归 |
| `AppStorage` → `AppStorageV2` | **两套独立存储**，互不相通 | 17 个 key 散在 5 个文件（含 `QAbility` 写入方与 `ApplicationRoot` 启动门控） | **中等，主要风险点** |
| `LocalStorage` → `@ObservedV2/@Trace` | — | 本工程为 **Qt 互操作桥面**（`loadContent(path, storage)`、`makeNewLocalStorage`） | **不可迁移** |
| `ForEach` → `Repeat` | 推荐非强制 | 169 处，V2 下 `ForEach` 仍可用 | 0（可选优化） |

**有利事实（实测）：**
- 状态字段上 `this.X.y =`（就地修改对象属性）为 **0 处**；3,259 处赋值中 **1,028 个字段**为整体替换。
  V2 最典型的坑（深层属性修改不触发刷新，需补 `@ObservedV2`+`@Trace`）在本仓库**不存在**。
- 90.5% 的状态字段是原始类型，`@State` → `@Local` 语义等价。

**否决理由（按权重排序）：**
1. **一个 struct 不能一半 V1 一半 V2**（编译报错）。32,774 行里的 1,047 个状态**只能同时翻代**，
   没有可编译中间态；这是唯一的、也是最大的风险，与"改名便宜"无关。
2. **迁 V2 不减少一行代码**：文件仍是 32,774 行、仍是 1 个组件、仍是全量重排。
   它解决的是"深层观测 / 属性级更新"，而本仓库这两点恰好都没在用。
3. **`AppStorage` ↔ `AppStorageV2` 互不相通**，而 `QAbility`（Ability，无装饰器）
   与 `ApplicationRoot` 共享这些 key，过渡期必须引入 `enableV2Compatibility` /
   `makeV1Observed` 临时胶水。
4. 官方指引：*"对于已使用 V1 的应用，如果 V1 的功能和性能满足需求，无需立即切换至 V2。"*

**估时对比：** 直接迁 V2 ≈ **2–3 周**（2–4 天翻代 + 2–3 天存储迁移 + 3–7 天数组/类字段审计 + 3–5 天全量回归），
且为**一次不可分割的大提交**。

**正确顺序：** 先按本方案拆分（保持 V1），再按模块逐个翻 V2。
拆分后每个面板/壳层是独立文件、独立组件，可单文件翻代、单次提交、单独回归，
把"2–3 周不可分割的大爆炸"变成十几次几分钟的小提交。**若现在先迁 V2，等于在单 struct 上做原子手术，
收益为零、风险最大。**

### 8.3 纯文件切分 / 仅拆 `@Builder` 函数（否决）

见第 2 节第 3、4 条：切完仍是同一 `struct`、同一 `this`、同一棵子树；
`@Builder` 参数按值捕获，拆函数不产生组件边界，也不缩小刷新范围。
**无收益，否决。**

---

## 9. 附录：复现命令

```powershell
# 体量
(Get-Content harmonyos\ets-source\pages\MainWindowNativeNode.ets).Count

# 装饰器与结构统计（主文件）
$c = Get-Content harmonyos\ets-source\pages\MainWindowNativeNode.ets -Raw
([regex]::Matches($c,'@State\s+(?:private\s+)?\w+\s*:')).Count     # 1047
([regex]::Matches($c,'(?m)^  @Builder\s*$')).Count                 # 145
([regex]::Matches($c,'@Observed|@ObjectLink|@Link|@Prop\b')).Count # 0
([regex]::Matches($c,'this\.\w+\.\w+\s*=(?!=)')).Count             # 3（命中状态字段 0）
([regex]::Matches($c,'this\.\w+\s*=(?!=)')).Count                  # 3259

# 面板清单
[regex]::Matches($c,"activePanel\s*===?\s*'(\w+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

# 跨文件存储分布
Get-ChildItem harmonyos\ets-source -Recurse -File -Include *.ets,*.ts |
  ForEach-Object { $t = Get-Content $_.FullName -Raw
    "{0}: AppStorage={1} StorageLink={2} LocalStorage={3}" -f $_.Name,
      ([regex]::Matches($t,'AppStorage\.')).Count,
      ([regex]::Matches($t,'@Storage(Link|Prop)')).Count,
      ([regex]::Matches($t,'LocalStorage')).Count }

# 同步脚本行为（整树递归镜像）
Select-String -Path scripts\sync-ohos-build-sources.sh -Pattern 'find .* -type f'
```

---

## 10. 下一步

1. 用户评审本文；确认范围、阶段划分与是否接受"不做 V2 迁移"。
2. 评审通过后执行 Phase 0（固化回归契约），再从 Phase 1 开始逐阶段推进。
3. 每阶段完成后汇报，**按 `AGENTS.md` §2.6 由用户明确要求后才提交**。

---

## 11. 执行记录与修订（2026-09-30）

用户授权无人值守推进后，已按计划完成以下切片，每片均经 `arkts_check` + 构建 + 模拟器安装启动 + 契约校验后独立提交：

| 切片 | 内容 | 提交 |
|---|---|---|
| Phase 0 | `scripts/check-ohos-ui-contract.mjs` + `docs/harmonyos/json/ui-contract-baseline.json`（33 面板 / 22 静态 id / 17 动态前缀 / 41 锚点） | `405666e626` |
| Phase 1a | `common/ui/UiTokens.ets`（5 个视觉常量，856 处引用不变） | `f65357f8fa` |
| Phase 1b | `common/ui/ShellIcons.ets`（纯函数 `getIcon`，61 处调用点去掉 `this.`） | `5b97eb9b07` |
| Phase 2 | `bridge/BridgeClient.ets`（`request`/`send`/`requestWhenReady`/`requestInteractive`，单体只留薄委托，`libentry.so` 导入移出单体） | `307108f331` |
| Phase 1c | `pages/MainWindowModels.ets`（93 个文件作用域类型/常量，764 行） | `f56751e66e` |

单体行数：**32,705 → 31,961**（净减 744 行；新增 4 个职责单一的文件）。

### 修订 1（重要，推翻原 §4.2 第 6 条）：V1 的 `@Component` 不能用 getter 委托

原方案设想「字段搬入 store 后，根 struct 用同名 getter 委托，调用点零改动」。实测不可行：
V1 `@Component` **不允许 getter 访问器**（ArkTS 转换会丢弃，存在运行期崩溃风险）。同时，
未加装饰器的 store 字段不会触发宿主重渲染，因此**单独搬 store 会让该域失去刷新**。
→ Phase 3 必须与 Phase 4 的对应面板**同步**进行；或采用「调用点机械替换为 `this.store.xxx`」，
由编译器全程把关。§4.2 第 6 条与 §5 表格已按此修订。

### 修订 2：Phase 1 的"无状态 builder"实测多为有状态

`dockButton` 依赖 `isExpandedLayout`、`compactDockIconSize()`、`dockActionActive()`、
`handleDockTouch()`、`activateDockAction()`；`switchRow` 依赖 `actionId`/`cmd` 与宿主回调；
`iconButton` 仅 1 处调用、28 行。三者均不属于无状态叶子，其组件化并入 Phase 4/6，
避免先生成一次会被 store 化推翻的组件。Phase 1 以 UiTokens / ShellIcons / MainWindowModels 三个纯叶子切片收口。

### 修订 3：验收矩阵需要补真机

x86_64 模拟器的 UI-only 通道（见 CHANGELOG 2026-09-30 条目）能验证布局、文案、面板开关与交互，
但**星图与引擎相关状态全部不可验**（`libstellarium.so`/`libQt6*.so` 无 x86_64 构建，时间面板显示 `--`）。
因此 store 与面板阶段的验收矩阵必须包含**真机（Mate 80 Pro）复验**，模拟器只作为快速结构回归。

### 修订 6：系统性死代码普查（39 个不可达方法，约 469 行）与"疑似漏接线"清单

Phase 3h/3i 做了两轮死代码清理，方法可复现：本 struct 的方法**全为 `private`**，因此"文件内零引用 = 不可达"。
对 1,090 个 `private` 方法统计 `this.<name>(`、裸引用 `this.<name>`、字符串 `'<name>'` 三种形式，
排除框架生命周期方法与两个 `@Watch` 按名调用的方法后，**39 个方法三种引用全为 0**（删除后 −498 行，含空行）。
可复现命令见 CHANGELOG 2026-09-30 的 Phase 3h/3i 条目。

**需要产品复核的"疑似漏接线"项**（删除不改变行为，但可能掩盖了未接的意图——若本应接线，应作为**功能缺陷**单独处理）：

| 组 | 方法 | 推测的原意 |
|---|---|---|
| 陀螺仪（7 个，约 197 行） | `onRotationVectorData`(119) / `gyroForwardFromGravityAndMagnetic` / `gyroSlerpUnitVector` / `alignGyroToMagneticNorth` / `gyroParallelTransportUp` / `calibrateGyroscopeQuaternionUnused` / `gyroEffectiveAzOffset` | 传感器回调未注册 |
| 对象卡片定位（4 个，约 103 行） | `placeObjectCardAwayFromTarget`(53) / `easeSelectedObjectTo`(36) / `placeSelectedObjectInCompactSafeArea` / `placeSelectedObjectInExpandedSafeArea` | 卡片避让/缓动未接 |
| 功能入口（4 个） | `pauseScript` / `resumeScript` / `toggleTracking` / `triggerAutoLocate` | 入口未接 |
| 时间相关（3 个） | `advanceTimeWheel` / `setTimeNow` / `adjustTime` | 被时间轮/快捷行取代 |
| 其余（21 个） | 抽屉/信息窗几何、`nm`、`tickPercent`、`skyCulture*FilterIndex`、`defaultSkyCultureMakerDraft` 等 | 多为被后续实现取代的旧版本 |

**探查工具（可复用，已扩展到四类判据）：** 本轮的判据 + 三形式引用统计，可作为**每个 Phase 4 面板切片的前置自检**，
先把该面板区域内的死代码清掉再搬迁，避免把死代码带进新结构。四类判据与实测产出：

| 判据 | 做法 | 本轮产出 |
|---|---|---|
| 不可达方法 | `private` 方法在文件内 `this.<name>(`、裸 `this.<name>`、字符串 `'<name>'` 三种引用全 0（排除生命周期与 `@Watch` 目标） | 48 个（首轮 39 + 级联 9），约 500 行 |
| 零调用 `@Builder` | `this.<name>(` 调用点为 0，并核对标识符全文件出现次数以排除同名前缀干扰 | 13 个（含 `tabletObjectInspector`、`railShell`、`padExploreHome` 等旧抽屉/平板布局变体），约 519 行 |
| 零引用字段 | `this.<name>` 引用全 0（含未写未读） | 31 个（FPS 残留、旧陀螺仪锚定量、旧面板开关等） |
| 级联复扫 | 每轮删除后重扫，直到无新增 | 3 轮收敛；暴露出"按步进推进时间"整条支路（`advanceTimeWheel` → `startTimeWheelTransition`）在清理前已不可达 |

**两条删除脚本的硬性要求（都已踩过）：**
① **单行方法必须特判**（`private f(): T { return x }`），否则以"下一个 `\n  }\n`"为结束标记会越过边界、连带删除相邻成员（首轮误删 `drawerWidth` / `onRailTap`，被构建报错捕获）；
② **删字段必须连同其上方独立装饰器行一起删**（否则留下孤立 `@StorageLink(...)` 叠加到下一个属性，报 `cannot have multiple state management decorators`）。
两者都必须由 `arkts_check` + 构建兜底。

### 修订 5：时间轮的"交互控制器"留在宿主是刻意取舍，后续按注入式拆分

> **状态更新（2026-09-30，Phase 3m）：已完成拆分。** 下文描述的方案已落地为 `state/TimeWheelController.ets`
> （普通类，非 `@Observed`；14 个手势草稿字段 + 1 个惯性定时器 + `start/stop`）。
> 三个注入点按计划实现：`onSeek(jd)`（宿主 `callNativeFire('setTimeToJD')`）、`onStopSpeed()`（宿主 `stopTimeWheelSpeed()`，写速度域）、
> `getUtcOffsetHours()`（宿主只读 getter）。宿主只剩 `wheel()` 懒初始化 + 5 处调用转发 + 3 个生命周期 `stop()` 收口。
> 顺带删除：**从未被启动**的过渡定时器与 `timeWheelTargetMs`、`finishTimeWheelTransition()`（其唯一启动者 `advanceTimeWheel` 已在 Phase 3j 作为死代码删除）。
> 同批完成的速度域迁移见下方"速度/速率域"。

Phase 3g 把时间转轴/时间轮的**状态与视图**迁出（`TimeWheelStore` + `TimeWheelScrubber`），
但把**交互逻辑整体留在宿主**，位置与规模（实测）：

- 方法 13 个，`pages/MainWindowNativeNode.ets` **L11910–L12149，约 228 行**：
  `selectTimeWheelUnit` / `applyTimeWheelDate` / `setTimeWheelStopped` / `startTimeWheelTransition` /
  `finishTimeWheelTransition` / `stopTimeWheelInertia` / `startTimeWheelInertia` / `advanceTimeWheel` /
  `timeWheelVelocityMultiplier` / `rebaseTimeWheelTrack` / `rebaseTimeWheelTrackAtCenter` /
  `handleTimeWheelTouch` / `syncTimeWheelFromSimulation`。
- 配套**普通（非 `@State`）字段 16 个 + 2 个定时器句柄**，L324–L339（手势草稿量、惯性/过渡状态、定时器）。

**为什么这次必须留在宿主（4 条实证理由）：**

1. **跨域写入**：`setTimeWheelStopped()` 写速度域（`timeStore.timeSpeedIndex` / `pendingTimeRate` / `timeRateText`）→ 搬它需先搬速度域。
2. **触碰引擎**：`applyTimeWheelDate()` 调 `callNativeFire('setTimeToJD', …)` 且依赖宿主 `utcOffsetHours`；桥是宿主职责（单一出口 `BridgeClient`），store 不应碰 NAPI。
3. **定时器需生命周期托管**：12 ms 过渡 + 16 ms 惯性两个 `setInterval`，今天搭在宿主既有的「面板关闭 / 后台 / `aboutToDisappear`」收口上；搬走需新增 `start()/stop()` 并重挂这些点，**漏停会导致后台仍在跑定时器并向引擎推时间**。
4. **草稿量不该可观测**：那 16 个字段每个触摸采样都在变；放进 `@Observed` 会让**每次采样触发通知与重渲染**（性能与语义都不对）。因此"可观测数据在 store、不可观测草稿与行为在宿主"是正确的切分。

**后续拆分方案（推荐在速度域迁移之后执行，作为独立切片）：**

```
state/TimeWheelStore.ets          ← 只留可观测数据 + 纯计算（现状已达成）
state/TimeWheelController.ets     ← 新增：普通类（非 @Observed），持有 16 个草稿字段
                                     + 2 个定时器 + 上述 13 个方法 + start()/stop()
panels/time/TimeWheelScrubber.ets ← 视图（现状已达成）
```

三个注入点（把跨域依赖从宿主剥出，store 与控制器都不碰引擎）：

| 依赖 | 注入方式 | 今天的落点 |
|---|---|---|
| 引擎推送 | `onSeek(jd: number): void` | 宿主 `callNativeFire('setTimeToJD')` |
| 暂停速度 | `onStopSpeed(): void` | 宿主 `setTimeWheelStopped()` |
| UTC 偏移 | `utcOffsetHours` 只读传入 / getter | 宿主字段 |

**验收要求**：拖动 + 惯性 + 过渡照旧；面板关闭后无残留定时器；切后台/回前台不丢同步（真机日志确认 `setTimeToJD` 推送已停）。
**估时/风险**：1 片（约半天），风险集中在定时器生命周期，**不改任何交互逻辑**。

### 修订 4（已由真机实验定论）：真正的冻结根因是"参数化 @Builder 按值捕获"，`@ObjectLink`/`@Prop` 实时更新正常

2026-09-30 在**真机 Mate 80 Pro（引擎存活）**上做了三版对照实验，同一交互（打开时间面板 → 点「快进」）：

| 版本 | 副标题 | 「快进」chip 标签 | 结论 |
|---|---|---|---|
| 原生实现（`@State` + 参数化 `@Builder speedChip(...)`） | `2x` / `10x` | 始终「快进」，未高亮 | **既有 bug**（重开面板才更新） |
| `TimeStore` + `TimeSpeedChips`，chip 仍走参数化 `@Builder` | `2x` / `10x` | 始终「快进」 | 与原生**行为等价**（继承同一 bug） |
| `TimeStore` + `TimeSpeedChips`，**chip 内容内联、直接读 store** | `2x` → `10x` | **「快进 2x」→「快进 10x」实时更新且高亮** | **修复 bug**，且证明 store 通路正确 |

结论：

1. **根因**：`@Builder speedChip(id, label, icon, active)` 的简单类型参数**按值捕获**，其子树首帧后即冻结，
   状态变化不会触发该子树更新（与 §2 根因分析一致）。这与"组件是否创建在 `@Builder` 体内"无关。
2. **修正此前（同一轮内）的推断**：曾据模拟器实验怀疑"`panelContent()` 体内创建的子组件拿不到更新"，
   真机三版对照已推翻该推断——`@ObjectLink`（store 字段变化）与 `@Prop`（`rateText` 由父更新）
   **都能实时驱动子组件重渲染**；此前两版"不更新"完全由内层参数化 `@Builder` 冻结造成。
3. **对方案的影响**：
   - (b) 方案（store + 组件）成立，**且能顺带修掉既有冻结 bug**；
   - Phase 3 不必等 Phase 4 的 `PanelHost`；
   - **但每个被搬迁的 builder 都必须去掉"参数化 @Builder 冻结"这一模式**：要么内联直接读状态，
     要么改为子组件（`@Prop`），不能保留原来的参数化 `@Builder` 包一层。
   - 这条要写进后续每个切片的自检项：搬迁后必须实测"点击后是否实时更新"，而不只看布局是否一致。
4. 该实验同时证明：**UI-only 模拟器不适合裁决此类刷新问题**（无引擎数据、定时器不产生写入，
   原生与重构版都会呈现"不刷新"），刷新类验收必须在真机做。

---

## 12. 附录：本轮死代码清理逐项清单（2026-09-30，三次提交）

数据由 `git diff --unified=0 <rev>^ <rev> -- harmonyos/ets-source/pages/MainWindowNativeNode.ets` 提取；
"原行号"为删除前文件中的行号。相邻条目在 diff 中会被合并计为一个区块（下表按区块列出，备注已标注合并项）。
**用户已确认：其中相当一部分是用户本人有意删除的历史代码**，因此下表仅作为"已移除内容"的存档，不再作为缺陷线索。

### 12.1 Phase 3h —— 旧转轴（滑杆）死子系统（提交 `e2f0c6f7e9`，−126 行）

| 区块原行号 | 行数 | 内容 |
|---|---|---|
| L307 | 2 | `scrubberValue` / `scrubberLabel`（均为 `@State`，只写不读） |
| L311 | 5 | `scrubberReferenceJd` / `scrubberPendingOffset` / `scrubberAnchorPending` / `scrubberLastSendMs` / `scrubberInteracting` |
| L323 | 1 | `timeMarkLoading` 由 `@State` 降为普通字段（仅重入守卫，不参与渲染） |
| L11799 | 111 | `updateScrubberLabel` / `beginScrubberInteraction` / `sendScrubberTime` / `applyScrubber` / `syncScrubberToSimulation` / `resetScrubberToRealtime`（入口 `applyScrubber` 无任何调用者） |

> 附带性能收益：两个被删 `@State` 原由 `syncScrubberToSimulation` 在每次模拟时间刷新时写入 → 每次写都扩大重渲染范围。

### 12.2 Phase 3i —— 39 个零引用 `private` 方法（提交 `3301201ef0`，−498 行）

| 原行号 | 行数 | 名称 | 类别 |
|---|---|---|---|
| L1590 | 1 | `drawerLeft`（单行方法） | 抽屉几何 |
| L2386 | 7 | `triggerAutoLocate` | 功能入口 |
| L3197 | 6 | `runOnTouchUp` | 触摸工具 |
| L4143 | 8 | `pauseScript` + `resumeScript`（合并计） | 脚本 |
| L4979 | 3 | `cycleOcular` | 目镜 |
| L5941 | 16 | `adjustTime`（+ `setTimeNow` 合并计） | 时间 |
| L9001 | 4 | `skyCultureRangeModeIndex` | 星空文化 |
| L9045 | 6 | `skyCultureClassificationFilterIndex` | 星空文化 |
| L9066 | 11 | `skyCultureRegionFilterIndex` | 星空文化 |
| L10018 | 18 | `defaultSkyCultureMakerDraft` | 星空文化编辑 |
| L10639 | 4 | `pluginFeaturePanel` | 插件 |
| L11719 | 4 | `tickPercent` | 工具 |
| L11904 | 22 | `advanceTimeWheel` | 时间轮 |
| L13288 | 22 | `gyroSlerpUnitVector` | 陀螺仪旧数学 |
| L13313 | 11 | `gyroParallelTransportUp`（+ `alignGyroToMagneticNorth` 合并计） | 陀螺仪旧数学 |
| L13339 | 11 | `calibrateGyroscopeQuaternionUnused` | 陀螺仪旧数学 |
| L13443 | 23 | `gyroForwardFromGravityAndMagnetic` | 陀螺仪旧数学 |
| L13528 | 17 | `gyroEffectiveAzOffset` | 陀螺仪旧数学 |
| L13671 | 119 | `onRotationVectorData`（旧版旋转回调） | 陀螺仪旧路径 |
| L13861 | 5 | `isConstellationSelection` | 命中判断 |
| L14081 | 54 | `placeObjectCardAwayFromTarget` | 对象卡片布局 |
| L14583 | 8 | `placeSelectedObjectInCompactSafeArea`（+ `placeSelectedObjectInExpandedSafeArea` 合并计） | 对象卡片布局 |
| L14608 | 45 | `easeSelectedObjectTo` | 对象卡片动效 |
| L17172 | 9 | `handleFloatingPanelTouch` | 面板触摸 |
| L18764 | 13 | `infoWinLeft`（+ `infoWinWidth` 合并计） | 信息窗几何 |
| L18818 | 4 | `toggleTracking` | 功能入口 |
| L18948 | 8 | `bottomCardSwiperHeight`（+ `bottomCardHitHeight` 合并计） | 卡片几何 |
| L19101 | 7 | `isTabletObjectInspectorPoint` | 命中判断 |
| L19292 | 20 | `isCompactDrawerPoint`（+ `handleCompactMoreTap` 合并计） | 命中判断 |
| L19892 | 5 | `objectInspectorFileUri` | 文件路径 |
| L21537 | 3 | `nm` | 旧配色助手 |
| L21603 | 4 | `trackStatusZh` | 文案 |

> 活路径对照（用户已验证功能正常）：陀螺仪走 `gyroRotationCallback` / `gyroGravityCallback` / `gyroMagneticCallback` / `onOrientationData`（L12605–L12702）。

### 12.3 Phase 3j —— 13 个零调用 `@Builder` + 31 个零引用字段 + 级联 9 方法（提交 `f82b483d2e`，−650 行）

**A. 零调用 `@Builder`（11 个区块合并计 13 个方法，约 519 行）**

| 原行号 | 行数 | 名称 |
|---|---|---|
| L18157 | 43 | `compactObjectPeek`（+ `compactQuickControls` 合并计） |
| L18604 | 19 | `objectActionBar` |
| L19232 | 39 | `expandedObjectSummary` |
| L19273 | 119 | `tabletObjectInspector` |
| L20776 | 93 | `objInfoFloat`（+ `observerBadge` 合并计） |
| L20939 | 36 | `railShell` |
| L21804 | 29 | `collapseButton` |
| L22363 | 39 | `padExploreHome` |
| L22552 | 25 | `smallRoundButton` |
| L28979 | 24 | `detailInfoRow` |
| L29028 | 53 | `configurationSkyDisplaySettings` |

**B. 零引用字段（31 个，多为 1 行）**

| 原行号 | 行数 | 内容 |
|---|---|---|
| L73 | 2 | `startupPreparing`（含其独立 `@StorageLink(...)` 装饰器行） |
| L285 | 4 | `fpsDisplay` / `fpsFrameCount` / `fpsLastTime` / `fpsVisible` |
| L342 | 1 | `autoLocateStarted` |
| L1050 | 1 | `scriptPanelScroller` |
| L1392 | 1 | `expandedTargetPlacementTimer` |
| L1453 | 1 | `gyroLastDiagnosticMs` |
| L12801 | 5 | `gyroReferenceAz` / `gyroReferenceAlt` / `gyroReferenceViewAz` / `gyroReferenceViewAlt`（+1） |
| L12820 | 4 | `gyroAnchorQuat` / `gyroAnchorUp` / `gyroAnchorFwd` / `gyroAnchorValid` |
| — | 各 1 | `visibleConstellations` / `infoTextExpanded` / `centerSearchText` / `tonightPlanets` / `lightPollution` / `asteroidLines` / `asteroidLabels` / `nightViewTab` / `showConfigPanel` / `showAstroPanel` / `showHelpPanel` / `timeScale` / `railCollapsed` / `gyroHeadingSyncInFlight` |

**C. 级联不可达方法（3 轮收敛，9 个）**

| 原行号 | 行数 | 名称 |
|---|---|---|
| L11734 | 27 | `startTimeWheelTransition`（唯一调用者是同批已删的 `advanceTimeWheel`） |
| L13122 | 6 | `gyroAltAzVector` |
| L13187 | 3 | `gyroEnuFromBridge` |
| L13200 | 40 | `syncGyroAnchor` |
| L13657 | 5 | `rectsOverlap` |
| L14713 | 9 | `pad2` |
| L18330 | 3 | `infoWinDetailH` |
| L19396 | 6 | `objectInspectorSubtitle` |

### 12.4 汇总

| 提交 | 删除行数 | 方法 | Builder | 字段 |
|---|---|---|---|---|
| `e2f0c6f7e9`（3h） | 126 | 6 | 0 | 7（+1 降级） |
| `3301201ef0`（3i） | 498 | 39 | 0 | 0 |
| `f82b483d2e`（3j） | 650 | 9（级联） | 13 | 31（+1 孤立装饰器行） |
| **合计** | **1,274** | **54** | **13** | **39** |

单体行数 32,705 → 30,229。

### 12.5 附：被移除功能块的来龙去脉（git 考古）

方法：`git log -S <标识符> -- harmonyos/ets-source/pages/MainWindowNativeNode.ets` 会列出**该标识符出现次数发生变化的每一次提交**；
序列的**最后一个**（我方的删除提交之外）就是它**失去调用点（失活）**的时刻，其提交信息通常说明了替代者。

#### 模式一：出生即死（引入提交本身就没接线）

| 标识符 | 引入 | 引入提交主题 |
|---|---|---|
| `updateScrubberLabel` | 2026-07-31 | `aa2b2b384f` refine offline HarmonyOS observation controls |
| `easeSelectedObjectTo` | 2026-07-31 | 同上 |
| `syncGyroAnchor` | 2026-07-31 | 同上 |
| `onRotationVectorData` | 2026-07-31 | 同上 |
| `detailInfoRow` | 2026-07-28 | `cb7bf253c6` checkpoint offline HarmonyOS candidate |
| `compactQuickControls` | 2026-07-28 | 同上 |
| `advanceTimeWheel` | 2026-08-11 | `969cd1b33d` stabilize AstroCalc selection flows（连同 `startTimeWheelTransition` 一起，故"按步进推进时间"整条支路从未可用） |

#### 模式二：短命试验（引入后 1–3 天即被替换）

| 标识符 | 引入 | 失活 | 存活 |
|---|---|---|---|
| `objInfoFloat`（选中天体浮动详情窗，93 行） | 2026-07-25 `e1f06f17de` | 2026-07-26 `4d4ae41768` | **1 天** |
| `infoWinLeft`/`infoWinWidth`（浮窗几何） | 2026-07-25 | 2026-07-27 `ba34693f4e` | 2 天 |
| `objectActionBar`（19 行） | 2026-08-29 `9ffed5f759` | 2026-08-30 `eabe2f1c5d` | **1 天** |
| `configurationSkyDisplaySettings`（53 行） | 2026-08-30 `eabe2f1c5d` | 2026-08-31 `626cefea53` | **1 天** |
| `collapseButton`（29 行） | 2026-07-25 `6733da1103` | 2026-07-27 `ba34693f4e` | 2 天 |
| `observerBadge` / `smallRoundButton` | 2026-07-21 `947a1892f3` | 2026-07-28 `cb7bf253c6` | ~7 天 |
| `setTimeNow` / `adjustTime` | 2026-07-22 `0e89bd5ca5` | 2026-07-31 `aa2b2b384f` | ~9 天 |
| `pauseScript` / `resumeScript` | 2026-07-27 `ba34693f4e` | 2026-08-28 `68f9a05be3`（"compact script controls"） | ~1 月 |
| `triggerAutoLocate` | 2026-07-25 `b8dc048eff`（本功能提交） | 2026-08-21 `9a8dd78731` | ~1 月 |

#### 模式三：整代 UI 被替换（替代者可在"失活提交"里定位）

| 家族 | 引入 | 失活（=替代者登场） | 替代者 |
|---|---|---|---|
| **对象详情**（`tabletObjectInspector` 119 行 / `objInfoFloat` 93 / `compactObjectPeek` 43 / `expandedObjectSummary` 39 / `objectActionBar` 19 / `isTabletObjectInspectorPoint` 7 / `toggleTracking` 4） | 08-27 `8cb728a488`（引入平板检查器 + `structuredObjectDetails`/`tabletInspectorMedia`）→ 08-29 `9ffed5f759`（加 peek/动作条 + `selectedLiveInfoRows`） | **08-30 `eabe2f1c5d`**（complete CLI regression and UX audit） | 同一次提交引入 **`unifiedObjectDetailCard`** —— 四套详情变体一同失去调用者 |
| **时间控制**（旧滑杆子系统：`applyScrubber`/`beginScrubberInteraction`/`sendScrubberTime`/`syncScrubberToSimulation`/`resetScrubberToRealtime` 等 117 行 + `scrubberReferenceJd` 等 7 字段） | 07-30 `f87310fbc0`（complete time control redesign — Sky Guide style，同批引入 `timeScrubberSlider`） | 08-11 `969cd1b33d` | `timeScrubberSlider`（字段行 + 刻度轮），即今天的 `TimeWheelScrubber` |
| **左栏 / 抽屉**（`railShell` 36 行） | 07-23 `a9349c9a8e`（星表下载 ArkTS 界面） | 08-22 `ad2a423575` | `expandedShell` 内的常驻侧栏 |
| 抽屉/卡片几何（`drawerLeft`、`drawerWidth` 旁系等） | 07-28 `cb7bf253c6` | 08-28 `68f9a05be3` | 同上 |
| **平板探索首页**（`padExploreHome` 39 行） | 08-22 `ad2a423575` | 09-06 `6245c85b07`（offload detail model rendering…） | 统一后的对象详情/检查器路径 |
| **星空文化筛选索引**（`skyCultureRangeModeIndex`/`ClassificationFilterIndex`/`RegionFilterIndex`） | 08-21 `9a8dd78731`（complete sky culture filtering） | 08-22 `ad2a423575` | 新的筛选状态字段与面板 |
| **配色助手 `nm()`** | 07-21 `947a1892f3` 起被 84 次提交广泛使用 | **由本方案自己的迁移 3d–3g 逐步抽走调用点**（搬进组件后改用 `nmText()`/`@Prop` 传色），最后由 3j 删除 | `nmText()`/`nmSub()`/`nmAccent()` + 组件 `@Prop` 颜色 |

#### 结论与三条可执行改进

1. **堆积的成因：** 本项目 UI 迭代极快（7/21–9/06 期间对象详情就换了三代），每次改版只改"接线"，旧的 `@Builder`/方法留在原地并连同其设计注释一起变成"注释还在、代码已死"的僵尸块。
2. **`nm()` 的教训值得记：** 它在很长一段时间里是**活代码**，是被本方案的迁移抽空了调用者才变成死代码 —— 说明"死代码"是动态状态，**迁移/重构本身也会制造新的死代码**，因此每片迁移后必须复扫（这也是 3j 采用"级联复扫直到收敛"的原因）。
3. **流程建议（已可落地）：** ① 每个改动面板的功能提交里，顺手删掉被替换的旧 builder（改动者最清楚替代关系）；② 本方案 Phase 4 的"每面板前置死代码自检"（§11 修订 6 的四类判据）正好兜住这类堆积；③ 删除时**连同其设计注释一起删**，需要保留的设计意图应移入文档而不是留在代码里。

---

## 13. 续作操作手册（任何后续会话/Agent 都可照此独立推进）

本节把本轮全部**实测结论**固化为可执行规则，避免续作时重新踩坑。

### 13.1 六条已验证的硬规则（违反其一即产生回归）

| # | 规则 | 依据 |
|---|---|---|
| 1 | **`@ObjectLink` 的宿主源必须是 `@State` 持有的实例**；写成普通 `private` 字段会被编译器拒绝 | Phase 3a 报错原文 |
| 2 | **组件成员名不得与 `CustomComponent` 基类属性方法同名** —— 已踩：`borderColor`、`scale`、`onTouch`、`background`（报 `Property 'background' ... is not assignable to the same property in base type 'CustomComponent'`；`background` 与 `backgroundColor` 都中招，因为基类有 `.background()` 属性方法） | 四次编译失败 |
| 3 | **迁移后的 UI 不得保留参数化 `@Builder`**（简单类型参数按值捕获 → 子树首帧后冻结，切档/开关不刷新）。改法：内联直接读 store，或改成子组件用 `@Prop` | 真机三版对照实验 |
| 4 | **宿主改 `@State` 持有的 `@Observed` 实例属性 → 宿主自身也会重绘**（所以让宿主读 store 是安全的） | 夜视模式实测（全应用变红） |
| 5 | **state 与读取它的 UI 必须同片搬迁**：只搬字段不搬读取方 → 宿主观测不到 store → 退化成不刷新 | 恒星时行的处理 |
| 6 | **跨域 / 桥 / 定时器依赖用注入解决，不硬搬**（如 `TimeWheelController` 的 `onSeek` / `onStopSpeed` / `getUtcOffsetHours`） | Phase 3m |
| 7 | **`@Component` 的 `build()` 只能有唯一容器根节点**。原 `@Builder` 允许并列多根（如 `tabletInspectorFallbackVisual` 的 `Stack` + `Text`），下沉成组件后必须包进一个容器：用**与原调用点外层容器相同的 `space`**（该例外层是 `Column({ space: 8 })`），否则间距会变 | Phase 3v 编译报 `build method can have only one root node` |
| 8 | **搬迁会打断"按文本切片单体"的测试脚本**：仓库里 23 个 `scripts/*.mjs` 用 `source.indexOf(...)`/`slice`/正则读 `MainWindowNativeNode.ets`，字段改 `this.store.X`、UI 改组件后它们会成片失败。每片必须跑一次受影响脚本并同步（切到组件文件、注入 `objectDetailStore` 之类的假宿主）。**存量失败（先于本会话、与本轮无关）见 §13.6** | Phase 3v 一次暴露 20+ 处 |
| 9 | **不要把宿主的 `@Builder` 经 `@BuilderParam` 传进子组件**：真机实测**渲染该页即整个应用退出**（hilog 无 ArkTS 报错、`pidof` 直接为空，且 `arkts_check` 与构建均通过，属运行期）。正解是先把该 builder 改写成**组件**，由宿主把数据与回调传进去（Phase 3aa 的"观测/坐标"两页为对照组：同样用 `@ObjectLink` + 回调注入，正常）。 | Phase 3aa 真机 A/B |

### 13.2 每片协议（八步，缺一不可）

> **0（前置，最高优先级）：自动续作，不在片间停。** 用户已授权本队列"全流程自动执行"。一片做完（含构建、真机、测试、CHANGELOG、提交）后，**必须在同一轮内直接开始下一片**，不得输出"本片已完成，下一步打算做 X"这类检查点汇报，也不得请求确认。进度写进 CHANGELOG 与本节 §13.5 队列，而不是写成给用户的片间状态消息。仅在以下情况停：(a) 需要用户才能做的决策；(b) 报阻塞；(c) 队列全部完成。此规则同时写入仓库根 `AGENTS.md`。

1. **量化**：统计该域字段与引用数（`this.<name>`），据此挑最小可自包含的片。
2. **建 store**（`state/*Store.ets`，`@Observed`，只放数据 + 纯计算，不 import UI/NAPI）。
3. **建组件**（`panels/...ets` 或 `common/ui/...ets`）：`@ObjectLink` + `@Prop` + 回调；**不用参数化 `@Builder`**。分支多而每支入参少时（如媒体区八分支），**保留宿主的无参 `@Builder` 做分支判定，每支下沉成小组件**（每个 2–7 个入参），比"一个大组件传十几个 `@Prop`"更稳。
4. **单体手术**：字段 → `@State` store 字段；引用改写；UI 区 → 组件调用；删除已搬走的 builder/方法。
5. **`arkts_check` → `devecocli build`（项目脚本）→ `node scripts/check-ohos-ui-contract.mjs`**。
6. **跑受影响的切片测试**（`node scripts/test-ohos-*.mjs` / `verify-ohos-*.mjs`，见 §13.1 规则 8）并同步。
7. **真机实测**（`192.168.3.95:40565`，IP 可能变，先用 `hdc list targets`）：安装 → 启动 → **逐项交互验证"点按后是否实时更新"**，不要只看布局是否一致；**测试若改了持久化设置，必须测后恢复**。回调链路可用 `hdc shell hilog -x` 过滤日志实证（如点"重试"后应出现 `[detail-media] retry request=...`）。
8. **CHANGELOG + 提交**：CHANGELOG 用 **CRLF 安全脚本**追加（见 13.4）。**不需要**再单独同步 `build/...` 的生成副本 —— 自 §13.7 起 `build/` 下的副本已全部取消跟踪，由构建脚本按需生成。

### 13.3 已知陷阱（都付出过代价）

- **单行方法**：`private f(): T { return x }`。删除脚本若以"下一个 `\n  }\n`"为方法结束标记，会越过其边界并连带删除相邻成员（曾误删 `drawerWidth`/`onRailTap`）→ **必须特判单行方法，并由编译器兜底**。
- **删字段必须连同其独立装饰器行一起删**（否则留下孤立 `@StorageLink(...)`，报 `cannot have multiple state management decorators`）。
- **PowerShell here-string 是 LF 而源码是 CRLF**：用于匹配的 here-string 必须先 `-replace "(?<!`r)`n","`r`n"` 归一，否则匹配失败。
- **超大文档（>100 KB）不要用通用编辑工具插入**：CHANGELOG（687 KB）曾被静默截断到 64 KB 并提交；改用脚本追加并**立即核对字节数/行数/裸 LF 数**。
- **`deveco ui layout` 是简化树，且 TextInput 值可能不显示**；需要视觉确认时用 `snapshot_display` + 读图。
- **面板本身可被拖动**：在面板上滑可能移动面板而非滚动内容；滚动要在 `Scroll` 区域内（先 dump 拿到其 bounds）。
- **列表内滑动**可能被判为点选 → 用 `ui drag`（按压—移动—释放）。
- **替换"外层有条件包裹的块"时必须保留/补回 `if (...) {` 那一行**：若起始标记落在条件语句内部、而替换文本只写了新内容，会把 `if` 的开括号一起删掉，其闭合 `}` 变成孤儿 → 文件括号深度失衡 → 数千行之后爆出上百条 `UI component ... cannot be used in this place` / `Cannot find name 'width'`。**定位法**：脚本扫描全文件括号净深度（与 HEAD 对比应为 0），再逐 diff hunk 统计 `{`/`}` 净差额，锁定"删了一个 `{` 未补回"的 hunk。
- **`arkts_check` 会漏掉结构失衡，绝不可替代构建**：曾出现 `arkts_check` 对四个文件全部报 "No errors"、而 `devecocli build` 立即失败的情况（括号深度 −1）。§13.2 第 5 步的"必须跑构建"因此是硬性要求。
- **"某页一渲染应用就退出"的排查法（A/B + 二分）**：`git stash -u` 回到**上一个已验证提交**重新构建安装，重走完全相同的点击序列 —— 旧构建正常、新构建退出，即锁定为新改动；再把新改动按"最小可删单元"二分（Phase 3aa 保留三页中的两页即恢复正常，从而把差异锁到 `@BuilderParam` 这一处）。运行期退出在 hilog 里可能**没有任何 ArkTS 报错**，所以只能靠 `pidof <本机调试包名>` 判存活 + A/B 复现，不要浪费时间抓日志。
- **面板内的嵌套滚动会吞掉手势**：如搜索面板"目录天体"网格自身可滚动且占满可视区，`dumpLayout` 下无法把外层滚动拖到网格下方的块（星座 chips / 坐标输入曾因此无法交互验证）→ 需要交互验证尾部内容时，可先切到对象很少的分类让网格变短。
- **批量改引用时必须同时补宿主 store 字段声明**：只把 `this.X` 改成 `this.store.X` 而忘了 `@State private store: XStore = new XStore()`，会让**所有**该引用推断为 `any`，构建报 `arkts-no-any-unknown`，且报错行号散落在毫不相关的业务方法里（13066/13948/18815…），极难一眼定位。**这两步必须成对执行。**
- **类型导入要找对模块**：Phase 1c 的 `pages/MainWindowModels.ets` **只包含原单体序言区**的声明；`ObjectDetailField` / `ObjectDetailModel` / `SatellitePass` / `SkyCultureDescriptionBlock` 等类型的导出仍在 **`pages/StellariumTypes.ets`**。导入错模块会报 `declares 'X' locally, but it is not exported`。
- **真机上同时装着两个 `QAbility` 包，且"看前台"与"跑 CLI"默认不是同一个**（2026-10-01）：仓库 `harmonyos/AppScope/app.json5` 的 `bundleName` 是发布配置 `com.joinother.skyinstrument`（versionCode 1000050），而 Windows 构建脚本的 `-Install` 会 `force-stop`/`aa start` **本机签名配置的包名**（由 DevEco 自动签名决定，脚本从 `pack.info` 读取）；`devecocli ui *` 作用于**前台窗口**，而 `scripts/stellarium-cli.mjs` 的 `DEFAULT_BUNDLE` 是 `com.joinother.skyinstrument` —— 一句 `openUiPanel` 就会把 skyinstrument 拉到前台，随后所有 `devecocli ui` 点击都落到它身上（曾整段误测到另一个版本）。**验收/复现一律以本机安装的包名为准：CLI 显式带 `--bundle <本机调试包名>`（或设 `STELLARIUM_BUNDLE`），并在关键步骤后用 `aa dump -l` 复核 `state #FOREGROUND`。**
- **`devecocli ui layout` 的 `Toggle` 节点不暴露 `checked`**：开关的真实状态只能靠截图 —— 把 ~3MB 全屏图**裁成小区域**（几十~一百 KB）再读，直接读全屏图会撑爆上下文。

### 13.4 常用命令

```powershell
# 构建（默认 debug，含 x86_64；-SkipEngine 表示不重编 C++）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-ohos-hap-windows.ps1 -SkipEngine -SkipDeploy -SkipResources
# 契约校验（33 面板 / 22 静态 id / 17 动态前缀 / 41 锚点）
node scripts\check-ohos-ui-contract.mjs
# 安装 / 启动
& $hdc -t 192.168.3.95:40565 install -r build\libstellarium-harmonyos\entry\build\default\outputs\default\entry-default-signed.hap
& $hdc -t 192.168.3.95:40565 shell aa start -b <本机调试包名> -a QAbility
# UI 交互（语义化，优先于坐标点击）
devecocli ui layout --device 192.168.3.95:40565
devecocli ui click/drag/text --device 192.168.3.95:40565 ...
```

**CHANGELOG 追加（CRLF 安全）**：把条目写入临时文件后用脚本前置插入，并核对 `裸LF = 0`（见本轮各次提交的实际命令）。

### 13.6 存量失败（先于本轮重构，续作不要误判为自己引入）

| 脚本 | 现象 | 性质 |
|---|---|---|
| `test-ohos-privacy-startup.mjs` | 11 处 `Cannot use import statement outside a module`，抛自 `new Function(...)`（脚本 L24 夹具 `plain()` 未能剥离 `qability/PrivacyConsent.ets` 的 import） | **夹具缺陷**；`PrivacyConsent.ets` / `QAbility.ets` 最后修改于 `101acf6cd3`，早于本会话 |
| `test-ohos-satellite-panel.mjs` test 7 | `computeOrbitPoints()` 的 `if (!validSample()) return;` 计数期望 3、实际不符 | **纯 C++ 断言**，与 ArkTS 无关 |
| `verify-ohos-location-search.mjs` | 直接 `ENOENT`：路径拼成 `E:\E:\code\...` | **脚本自身路径 bug**，断言都未执行到 |
| `test-ohos-clipboard-pad.mjs` / `test-ohos-guide-pad.mjs` / `test-ohos-mist-horizon-pad.mjs` / `test-ohos-polar-scope-pad.mjs` | 断言抛错（`actual: undefined`）：四个 `-pad` 用例要求显式 `--device`，未传时拿不到设备 | **用例需设备参数**；Phase 3aq 用 `git worktree` 检出 HEAD 复核，基线同样失败 |
| `test-ohos-mist-performance.mjs` | 同上，需在连接设备时运行 | **需设备**，先于本片 |
| `verify-ohos-search.mjs` | 走 macOS hdc 默认路径，Windows 上取不到设备 | **脚本平台假设**，先于本片 |

> **Phase 3aq 复核**：在 HEAD（`fea7652791`）用 `git worktree add --detach` 检出后逐个运行，上表 7 个脚本（含原有 3 个中的 `verify-ohos-location-search.mjs`）**在基线即失败**；`test-ohos-privacy-startup.mjs` 与 `test-ohos-satellite-panel.mjs` 在 HEAD 已不再失败。

> Phase 3v 已顺带清掉 Phase 3t 遗留的 5 处失败（`test-ohos-detail-live-values.mjs` 的假宿主缺 `objectDetailStore`）。
> 其余切片测试在 Phase 3v 结束时全绿：`audit-ohos-resource-coverage`、`test-ohos-astro-motion`、`-detail-image-layout`、`-detail-live-values`、`-detail-model-geometry`、`-distance-ui`、`-guide`、`-information-policy`、`-mist-horizon`、`-model-scroll`、`-plugin-panel-state`、`-polar-scope`、`-procedural-model`、`-search-browser`、`-settings-choice-motion`、`-skyculture-text`、`-startup-stars`、`-wut-layout`、`verify-ohos-julian-date`、`verify-ohos-object-details`。

### 13.7 `build/` 生成物取消跟踪（2026-10-01）

**现象：** 每改一次源码，`git status` 就多出 `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets` 等改动，因此每片都要额外做一次“同步生成副本”的提交。

**根因：** git 的 `.gitignore` **只对未跟踪文件生效**。根 `.gitignore` 里确实有 `build` 一行，但这 11 个文件在规则生效前（2026-07-26 的 `3a1bad1e3a` / `0566439884` 等提交）就已被 `git add`，于是一直被跟踪。构建脚本 `scripts/sync-ohos-build-sources.sh` 会把 `harmonyos/ets-source/**` 复制到 `build/.../entry/src/main/ets/**`，所以源码一动、被跟踪的副本就脏。

**核查（取消跟踪前）：** 11 个文件**全部**能在仓内找到被跟踪的源，取消跟踪不丢任何内容 ——

| 类别 | 数量 | 源（均已跟踪） | 关系 |
|---|---:|---|---|
| ArkTS 页面 | 4 | `harmonyos/ets-source/**` | **byte 完全一致**（纯拷贝） |
| 资源 | 5 | `harmonyos/{AppScope,resources,ets-source}/resources/**` | 一致 |
| 数据 | 2 | `stars/hip_gaia3/**`（含 53.2 MB 星表） | 一致 |

**处理：** `git rm --cached` 上述 11 个（文件留在磁盘），`build` 继续被忽略；构建脚本在编译前完成同步，因此新克隆只需跑一次构建。`verify-ohos-object-details.mjs` 的“生成镜像是否过期”检查照常有效（它只要求文件在磁盘上存在）。

**注意：** 仓内还有约 20 个“被忽略但被跟踪”的**上游素材**（`textures/*.tif`、`guide/*.pdf`、`data/*.dat`、`scripts/tests/media/*.mp4` 等），它们是被 `*.tif`/`*.pdf` 这类宽泛规则误伤的真实内容、且**没有别的副本**，属于另一类别，**不要**顺手删除。

### 13.5 剩余队列（按体积，供续作选择；**2026-10-01 用实测行数修正**）

> 初版此表沿用 §1.3 的错误测法，行数普遍高估 10–70 倍（如 `searchFilterMenu` 3,441 → 实测 48）。
> 下表为"首个 `^  }$` 收尾"重测值。**真正的 UI 体量集中在 `panelContent`（4,707 行）**，
> 故 Phase 4 的主线始终是"把 `panelContent` 的 33 个分支逐个抽成组件"。

| 序 | 域 | 实测规模 | 备注 |
|---|---|---|---|
| 1 | **search 筛选器** | `searchFilterMenu` **48** + `searchFilterChips` **30** + `catalogFilterRow`（参数化 UI 函数，需改子组件）；`searchFilterPage` 15 / `searchCategory` 19 / `searchVisibilityFilter` 5 / `searchInstrumentFilter` 6 | 一片可完成 |
| 2 | search 分类浏览 | `category*` 10 字段 / 64 处 | |
| 3 | **object / detail** | ~~`tabletInspectorMedia` 179~~ **已完成（Phase 3v / 3ab，现为 `TabletInspectorMediaGroup` 组件）**；~~`objectDataRow`/`structuredObjectDetailRow`/`tabletInspectorSection`~~ **已完成（Phase 3u）**；~~`objectDataTile`/`objectMetric`/`objectScheduleTile`/`objectDetailTab`/`objectCompactMetric`~~ **已完成（Phase 3x）**；~~`objectDistanceNotice`/`selectedLiveInfoRows`/`selectedCoordinateRow(s)`~~ **已完成（Phase 3y）**；~~`structuredObjectDetails` + 五个段落助手~~ **已完成（Phase 3z）**；~~`satellitePassesDetails`/`satellitePassCard`/`satellitePassTimelineRow` + 四个助手~~ **已完成（Phase 3z2a）**；~~`selectedConstellationCultureDescriptionView` + `skyCultureDescriptionBlockView`~~ **已完成（Phase 3z2b）**；~~卡片"观测/坐标"两页~~ **已完成（Phase 3aa）**。**剩余：** （1）~~先搬"资料"页~~ —— **顺序已调整（Phase 3ad 结论）**：先搬资料页要向 `ObjectDetailDataTab` 转发 26 个入参（媒体区 12 个派生值 + 4 回调），而先把**外壳**组件化后资料页分支将随外壳内收、媒体参数在外壳内部就地计算。已完成的 ``ObjectDetailCardHeader`` / ``ObjectDetailCardTabs`` 即此路径第一步；~~下一步是 ``unifiedObjectDetailCard`` 剩余部分（Scroll + 四个分支）整体内收为 ``UnifiedObjectDetailCard`` 组件~~ **已完成（Phase 3ap：`panels/object/UnifiedObjectDetailCard.ets`，46 个成员——2 个 `@ObjectLink` + 25 个 `@Prop` + 1 个 `Scroller` 成员 + 17 个回调 + 1 个 `distanceSummaryText`；四个页组件的调用点已全部在组件内；`objectInspectorModelRendering` / `objectInspectorModelTexturePixels` 仍留宿主、以 `@Prop` 传入）**。**详情卡域至此收尾。**（2）``objectInspectorModelRendering`` / ``objectInspectorModelTexturePixels`` **刻意不并入 @Observed store**：它们由渲染管线**逐帧写入**，放进被观察的 store 会造成重渲染风暴；保持为宿主字段、以 ``@Prop`` 传入（``modelRendering`` / ``hasModelTexture``）。（3）~~``objectDetailConnector*``(9) 叠层字段簇~~ **已完成（Phase 3an：指向线几何 9 字段按"逐帧写入不入被观察 store"留在宿主、以 ``@Prop`` 传入 ``panels/overlay/ObjectDetailConnectorLayer.ets``；只有开关 ``objectDetailConnectorVisible`` 入 ``state/OverlayStore.ets``）**；``objectInspectorModel*``(5) 仍留宿主。**Phase 3aq**：`tabletInspectorAction`(8) / `tabletInspectorRow`(9) / `expandedSummaryMetric`(8) / `expandedSummaryLine`(8) 经零引用扫描确认为死代码（四类判据全 0），已删除。**Phase 3ad 回归修复（`fix(harmonyos)`，2026-10-02，真机 A/B 定位）**：`ObjectDetailCardHeader` 的三枚摘要（星等/星座/距离）原只经普通成员回调 `resolve`/`distanceSummary` 求值，抽成组件后局部刷新不为该元素登记依赖 → 切换天体时摘要冻结在上一颗天体；已改为直接读 `@ObjectLink store`（距离经带实参的回调，实参即 store 字段）—— 结论：**组件内动态值必须以表达式直读装饰变量**。 | 与 tablet/compact 两壳耦合 |
| 4 | **astro** | ~~`phenomenonRelationMark` 29 / `astroSelectionGuide` 15~~ **已完成（Phase 3af，`panels/astro/AstroGuides.ets`）**；~~`wutTargetCard` 21~~ **已完成（Phase 3ah，`panels/astro/WutTargetCard.ets`）**；~~`continuationSection` 31~~ **已完成（Phase 3ag，`panels/astro/ContinuationSection.ets`）**；**Phase 3aq**：`graphLoadingRow` / `rtsSelectionGuide` / `graphSelectionGuide` **已完成（`panels/astro/GraphGuides.ets`，3 组件 61 行，14 处调用点）**；~~`observerPlanetSection` 24 / `pointingTestSection` 28 / `watchGyroSection` 34 / `tonightEventsSection` 23 / `tonightCard` 16~~ **已完成（Phase 3as：`state/SessionToolStore.ets` + `panels/astro/SessionToolSections.ets`，5 组件 189 行，宿主 80 处 store 引用改写）**；~~`gyroTargetGuide` 19~~ **已完成（Phase 3as：`panels/astro/GyroTargetGuide.ets`）**；≈164 字段（注：前四段在当前构建被 `OFFLINE_APPGALLERY_BUILD = true` 跳过，须在非 appgallery 构建真机走查） **Phase 4l（已完成，2026-10-02）**：`astro` 面板分支（1,980 行）整体下沉 —— `state/AstroStore.ets`（140 字段）+ `panels/astro/AstroPanel.ets`（2,255 行；`@ObjectLink` store/wutStore/objectDetailStore + 5 个颜色 `@Prop` + 普通 `Scroller` 成员 + 114 个注入回调 `AstroPanelHost`），宿主加载/导出/路由/持久化方法保留并改写为 `this.astroStore.X`；单体 21,303 → 19,314 行 | 多为展示 |
| 5 | **layers** | ~~`hierColumn` 75~~ **已完成（Phase 3aj，`panels/common/HierColumn.ets`，通用组件，位置面板四列与图层面板共用）**；~~`layerPresetBar` 19 + `viewTabs` 26 + 参数化 `switchRow` + 图层开关字段簇~~ **已完成（Phase 3ak：`state/LayerStore.ets`（94 字段）+ `panels/layers/LayerSwitchRow.ets` + `LayerPresetBar.ets` + `LayerTabs.ets`，103 处 switchRow 调用点全部改组件）** | 实测 **94 字段 / 103 个 switchRow**（原表「≈60 字段 / 21 个」低估）；7 个视图标签页 `viewXxxTab` builder 留给 Phase 4。**Phase 4f/4g/4h 已完成**：6 个 `view*Tab` → `panels/layers/LayerViewTabs.ets`、`viewSkyCultureTab` → `panels/skyculture/SkyCultureViewTab.ets`、整个 `layers` 分支 → `panels/panels/LayersPanel.ets`（252 行） |
| 6 | **tools** | ~~`toolsPanel` 446~~ **已完成（Phase 3ao：`state/ToolsStore.ets`（25 字段）+ `panels/tools/ToolsPanel.ets`·`RecordingControlBar.ets`·`RecordingFocusShell.ets`，宿主 153 处引用改写）**。实测纠正：原表「446」是把 `toolsPanel` 随后的 `lockRow`/`languageRow`/`gyroscopeRow`/… 一并计入的测量错误，`toolsPanel` 本体仅 **76 行**；本域实测引用约 **190 处**（改写 153）。`recordCount` 与录制引擎字段按"高频写入不入被观察 store"留在宿主；`skyTextureStatus` 状态条 UI 属 Phase 6 壳层，本片只改其字段引用 | |
| 7 | **skyCulture** | ~~`skyCultureMakerConstellationEditor` 93 + `skyCultureMakerArtworkEditor` 63 + maker 向导字段簇 29 字段~~ **已完成（Phase 3am：`state/SkyCultureMakerStore.ets` + `state/SkyCultureViewStore.ets` + `panels/skyculture/SkyCultureMakerFields`·`Tabs`·`Overview`·`ArtworkEditor`·`ConstellationEditor`·`ValidationPanel`，分两个提交 `783593b4da` / `5013516cb6`）**。实测 maker **29 字段 / 247 处引用**（原表「≈130 字段」把整个 skyCulture 域都算进来了）；只读详情视图另拆 **17 字段 / 123 处引用**。**剩余（下一个 skyCulture 切片）**：文化列表/当前选择（`skyCultureList`/`skyCultureListLoading`/`skyCultures`/`currentSkyCulture`/`currentSkyCultureId`，被领地地图与默认文化设置交叉使用）、领地地图簇、面板设置/筛选/标签模式/颜色约 90 字段，以及 `viewSkyCultureTab` 的组装 UI —— 与 `panelContent` 的设置宿主同片（Phase 4）。**Phase 3as**：~~`skyCultureMakerPanel` 68~~ **已完成（`panels/skyculture/SkyCultureMakerPanel.ets`，复用既有 `SkyCultureMakerStore`，19 个桥/定时器回调解入）**。进度驱动的 `skyCultureArtStates`/`skyCultureArtThumbnailPixelMaps`/`skyCultureArtPreviewPixelMap` 刻意不入 store。**Phase 4d 已完成**：叶件 `skyCultureSectionHeader`/`skyCultureMetaItem`/`skyCultureLabelSettingCard`/`skyCultureLabelModePicker`/`skyCultureFilterPicker`/`skyCultureFilterOption` 已下沉 `panels/skyculture/SkyCultureViewParts.ets`（`skyCultureArtPreviewOverlay` 属 Phase 5 叠层，未动）；`satelliteGroupSelector` → `panels/satellite/SatelliteGroupSelector.ets` |
| 8 | **sensors/gyro** | `gyroCalibPanel` 99；13 字段 | 活路径是 `gyroRotationCallback` 等，勿动 |
| 9 | satellite / script / telescope / session / 其余设置标签页 | ~~`scriptFocusShell` 209~~ **已完成（Phase 6a：`panels/shell/ScriptFocusShell.ets`，251 行；`guideState.active` 分发留在宿主调用点，宿主 19,098 → 18,913）** / ~~`compactMoreDrawer` 130~~（**Phase 3aq 零引用扫描确认为死代码，已删除；同批 `actionDrawer` 70 / `verticalRail` 66 / `iconButton` 31 / `moreButton` 32 / `musicButton` 25 / `gyroButton` 28 / `lockRow` 18 / `timeSpeedChips` 6 也一并删除**） / ~~`cityChipsRow` 109~~ **已完成（Phase 3ai）** / ~~`locationSearchPanel` 77~~ **已完成（Phase 3ai）**；~~`locationPickerPanel` 153（含参数化 `@Builder hierColumn` 75 与方法/字段簇）~~ **已完成（Phase 3aj：`panels/location/LocationPickerPanel.ets` + `LocationPickerStore` + `panels/common/HierColumn.ets`，分两个提交）**；~~telescope（`lx200Panel` 214 / `lx200ObjectControls` 60 / 参数化 `ocularSelector` 45 / 参数化 `ocularMetric` 7 + 81 个 `ocular*`·`lx200*`·`equatorialMount` 字段，实测 450 处引用）~~ **已完成（Phase 3al：`state/TelescopeStore.ets` + `panels/telescope/Lx200Panel.ets`·`OcularSelector.ets`·`OcularMetric.ets`·`Lx200ObjectControls.ets`，单片一提交；`oculars` 分支的内联 UI 留给 Phase 4）**；**Phase 3as**：~~参数化 `guideButton` 10（12 调用点） / 参数化 `scriptKeyButton` 12（6 调用点）~~ **已完成（`panels/guide/GuideButton.ets` + `panels/tools/ScriptKeyButton.ets`，可用态由 `phase`/`index`/`action` 在组件内推导）** | |
| 10 | **Phase 4 面板宿主** | `panelContent` **4,707** → 表驱动 `PanelHost` | 主线；逐分支抽组件。**Phase 3aq 先摘走它体内的设置行**：`infoRow`（55 调用点）/ `ephemerisRow` / `informationModeButton` / `informationSwitchRow` / `navigationSwitchRow` / `mosaicCameraMetric` / `languageRow` / `gyroscopeRow` / `deviceAndPrivacySettings` 共 9 个 builder → `common/ui/InfoRow.ets` + `panels/settings/SettingsRows.ets` + `panels/settings/DeviceAndLanguageRows.ets`（合计 313 行）。**Phase 3as 又摘走它体内的 13 个 `@Builder`**（会话工具 5 + 星文化制作器 1 + 面板壳件 4 + 陀螺仪指引 1 + 脚本键 1 + 导览键 1），并删死代码 `padExploreCard`(27)；单体 25,434 → 25,098。**Phase 3at 又摘走它体内的 `guideLibrary`（14 行 → `panels/guide/GuideLibrary.ets`）**；单体 25,098 → 25,063。**Phase 4a（已完成）**：`panelContent` 首批 4 个最小分支抽组件 —— `catalogs` → `panels/panels/CatalogsPanel.ets`、`angleMeasure` → `AngleMeasurePanel.ets`（复用 `ToolsStore` 的 `@ObjectLink`）、`audio` → `AudioPanel.ets`、`scenery3d` → `Scenery3dPanel.ets`（后两者 `@Prop` + 回调注入，`AudioEngine`/`resourceText` 按规则 6 回注）；单体 25,059 → 24,945 行。**Phase 4b（已完成，2026-10-01）**：第二批 5 个次小分支 —— `place` → `PlacePanel.ets`（3 个 `@ObjectLink` + 回调组装既有 7 子组件）、`commands` → `CommandsPanel.ets`、`navStars` → `NavStarsPanel.ets`、`archaeoLines` → `ArchaeoLinesPanel.ets`、`mosaicCamera` → `MosaicCameraPanel.ets`；随 UI 下沉 3 个纯助手（`navStarsSetLabel`/`filteredCommandCatalog`/`mosaicCameraValue`）；单体 24,945 → 24,796 行。**Phase 4c（已完成，2026-10-02）**：重扫剩余分支、排除薄调用 hub 类与 `layers`/`floatingPanel`/`compactPanel` 后，取**最小的 5 个分支** —— `more`(62) → `MorePanel.ets`、`nebulaTextures`(69) → `NebulaTexturesPanel.ets`、`time`(71) → `TimePanel.ets`（装配 5 store + 7 个既有时间子组件）、`meteorshowers`(87) → `MeteorShowersPanel.ets`、`help`(95) → `HelpPanel.ets`；随 UI 下沉 2 个纯助手（`fmtIso`/`nebulaTextureStatusLabel`）；单体 24,796 → 24,497 行。**Phase 4d（已完成，2026-10-02）**：先搬挡着 `skyCultureMaker`/`layers` 分支的 7 个 skyCulture/satellite 叶件 —— 新增 `panels/skyculture/SkyCultureViewParts.ets`（`SkyCultureSectionHeader`/`SkyCultureMetaItem`/`SkyCultureLabelSettingCard`（合并原 `skyCultureLabelModePicker`）/`SkyCultureFilterOption`/`SkyCultureFilterPicker`）+ `panels/satellite/SatelliteGroupSelector.ets`，删死助手 `satGroupZh`/`skyCultureFilterOptionSelected`，22 处调用点改组件；真机验标签模式/筛选器/卫星分组的点按实时刷新；单体 24,497 → 24,440 行。**Phase 4e（已完成，2026-10-02）**：按 §6.2 口径重扫后取剩下最小的 4 个实分支 —— `search`(110) → `panels/panels/SearchPanel.ets`、`observing`(112) → `ObservingPanel.ets`、`object`(145) → `ObjectPanel.ets`、`satellites`(179) → `SatellitesPanel.ets`（复用既有 store 的 `@ObjectLink` 与 `@Prop` 快照，不新建 store）；`layers` 因体内 7 个 `view*Tab` 仍是宿主 `@Builder` 而**跳过**。单体 24,440 → 24,098 行。**Phase 4f（已完成 1/2，2026-10-02）**：先解决 `layers` 的前置 —— 6 个 `view*Tab` 宿主 `@Builder`（`viewSkyTab`/`viewSSOTab`/`viewDSOTab`/`viewMarkingsTab`/`viewLandscapeTab`/`viewSurveysTab`）下沉为 `panels/layers/LayerViewTabs.ets`，并新增 `state/LayerViewStore.ets`（31 个数值/展开态设置，宿主引用全部改写）；单体 24,098 → 23,632 行。`layers` 分支仍未抽出（超出 ≤400 行同片预算）。**Phase 4g（已完成，2026-10-02）**：第 7 个标签页 `viewSkyCultureTab`（819 行）下沉为 `panels/skyculture/SkyCultureViewTab.ets`（940 行，24 个 bridge/定时器/解码回调回注），并新建 `state/SkyCultureSettingsStore.ets`（503 行，82 个设置字段 + 纯计算助手；`currentSkyCulture`/`skyCultureList`/`selectedSkyCultureId`/解码 PixelMap/Canvas 上下文按口径不硬搬）；单体 **23,632 → 22,451 行**，分两个提交（store 与组件）各自全绿；真机已验证该页签渲染、store 实时刷新与引擎 `setSkyCultureLabelStyle` 往返。**Phase 4h（已完成，2026-10-02）**：`layers` 分支整体下沉为 `panels/panels/LayersPanel.ets`（252 行；4 个 `@ObjectLink` store + 25 个 `@Prop`/普通成员 + 43 个回调），判定条件留宿主；单体 **22,451 → 22,380 行**。同时收尾 `floatingPanel`/`compactPanel`：二者体内只是 `this.panelContent()`，组件化必用 `@BuilderParam`（规则 9 真机退出），**保留为宿主薄 `@Builder`**，不影响「分支 ≤8 行单调用」口径（该口径只针对 `panelContent` 的分支）。逐一核对 33 个分支：**26 个已达标**（纯单组件分发）；**Phase 4i（已完成，2026-10-02）**：`telescope`(23) / `settings_quick_legacy`(180) / `oculars`(278) 三个分支下沉为 `panels/panels/TelescopePanel.ets`（60 行）/ `SettingsQuickLegacyPanel.ets`（238 行）/ `OcularsPanel.ets`（316 行），判定条件留宿主；单体 **22,380 → 21,983 行**；真机已验证 `telescope` / `oculars` 渲染与点按后实时刷新（`settings_quick_legacy` 无 UI 入口，临时放开 CLI 白名单取得运行期证据后已还原）。**Phase 4j（已完成，2026-10-02）**：`settings`(406) 下沉为 `panels/panels/SettingsPanel.ets`（548 行；4 个 `@ObjectLink` store + 44 个 `@Prop` + 46 回调 + 1 `Scroller`，8 个子标签页内联 UI 逐字下沉），末尾 `else`（`config` 回退页，219 行；**正常导航不可达** —— `setPanel()` 已把 `config`/`pluginManager` 归一为 `settings`，CLI `isCliPanelName` 白名单亦不含未知名）下沉为 `ConfigFallbackPanel.ets`（277 行；4 store + 8 `@Prop` + 14 回调），判定条件留宿主；单体 **21,983 → 21,485 行**；真机已验证设置面板渲染、逐标签切换与「附加 > 投影」点按后同一 `Text` 文案即时刷新（极射→鱼眼→极射，恢复测前值）。**仍未达标**：`astro`(≈2,000 行) 与 `scripts`(248 行) —— 本片全链复核：29 个分支中**唯此二者仍含内联 UI**，其余全部退化为单次组件调用；4h/4i 清单本就含 `scripts`。**Phase 4k（已完成，2026-10-02）**：`scripts`(248) 下沉为 `panels/panels/ScriptsPanel.ets`（310 行；1 个 `@ObjectLink tools` + 27 个 `@Prop` + 20 个回注回调 + 4 个函数成员（`scriptZh`/`scriptDesc`/`scriptMetaLine`/`scriptSourceLine`，因设置页共用仍留宿主），根为单个 `Scroll`），判定条件留宿主；单体 **21,485 → 21,303 行**；真机已验证面板渲染、脚本列表的 `scriptZh`/`scriptSourceLine` 链路，以及录制名 `TextInput` 点按键入 + 切换面板（组件销毁重建）后值仍由宿主 `@State` 再注入。**剩余**：`astro`(≈2,000 行) —— 29 个分支中**仅此一个仍含内联 UI**。**Phase 4l（已完成，2026-10-02）**：`astro` 分支（1,980 行）下沉为 `state/AstroStore.ets`（140 字段）+ `panels/astro/AstroPanel.ets`（2,255 行；`@ObjectLink` ×3 + 颜色 `@Prop` ×5 + 普通 `Scroller` + 114 个注入回调 `AstroPanelHost`）；宿主方法与持久化仍留宿主，引用改写为 `this.astroStore.X`（140 字段），单体 **21,303 → 19,314 行**；`test-ohos-astro-motion` / `test-ohos-wut-layout` 已同步改读组件文件。**全链达标复核（Phase 4 收口）**：`panelContent` 的全部具名分支除 `floatingPanel`/`compactPanel`（4h 定论：体内即 `this.panelContent()` 的宿主薄 `@Builder`，不迁）外，**全部**已退化为单个组件调用；实测该区段 `Text(`/`Row(`/`Button(`/`ForEach(`/`Toggle(` 构造均为 **0**，无内联 UI 残留。 |
| 11 | **Phase 5 overlay / Phase 6 壳层** | ~~`scriptFocusShell` 209~~ **已完成（Phase 6a：`panels/shell/ScriptFocusShell.ets`，251 行）**；~~`compactShell` 165~~ **已完成（Phase 6b：`panels/shell/CompactShell.ets`，268 行；壳内 `this.compactPanel()` 上移宿主调用点——流程见 Phase 6b CHANGELOG；单体 18,913 → 18,823）**；~~`harmonyShell` 90~~ **已完成（Phase 6b：`panels/shell/HarmonyShell.ets`，90 行；三壳布局分发与顶层 Dock 命中靶上移宿主调用点，组件只承载坐标叠层 / 陀螺仪指引 / 点击反馈气泡）**；~~`hoverObservatoryShell` 142~~ **已完成（Phase 6c：`panels/shell/HoverObservatoryShell.ets`，242 行；壳内 `this.compactPanel()` 上移宿主调用点——流程见 Phase 6c CHANGELOG）**；~~`expandedShell` 128~~ **已完成（Phase 6c：`panels/shell/ExpandedShell.ets`，232 行；`expandedUiAllowed()` 结果以 `@Prop` 入组件、壳内 `this.floatingPanel()` 上移宿主调用点；单体 18,823 → 18,751）**；~~`interactiveGuideShell` 78~~ **已完成（Phase 6d：`panels/shell/InteractiveGuideShell.ets`，116 行；导览按钮已是既有 `GuideButton` 组件、壳内无宿主 @Builder 调用，故无需上移调用点；导览阶段/步序文案由宿主从 `guideState` 与 `currentGuide()/currentGuideStep()` 算好后以 @Prop 下发，卡片几何 `guideCardWidth/Height/X/Y()` 由宿主算好传入；`.id('guide-stop')`/`.id('guide-content')`、`hitTestBehavior` 与过渡逐字保留；单体 18,751 → 18,689）**；~~`viewCenterCoordinateOverlay` 50 / `objectDetailConnectorLayer` 51 / `viewCoordinateSettings` 59 / `pointerCoordinatesPanel` 54 + 参数化 `pointerCoordinateToggle` + 该域 14 个设置字段~~ **已完成（Phase 3an：`state/OverlayStore.ets` + `panels/view/PointerCoordinateToggle.ets`·`PointerCoordinatesPanel.ets`·`ViewCoordinateSettings.ets` + `panels/overlay/ViewCenterCoordinateOverlay.ets`·`ObjectDetailConnectorLayer.ets`，提交 `9cac82c847`）** | ~~`panelHeader` chrome~~ **已完成（Phase 3ap：`panels/shell/PanelHeader.ets`，70 行；`observationTimeText`/`timeRateText` 未搬——仍由宿主 `panelTitle()`/`panelSubtitle()` 算好后以 `@Prop` 传给组件）。同片顺带完成 `dockButton`（`panels/shell/DockButton.ets`，33 行）与 `hubActionList`（`panels/shell/HubActionList.ets`，38 行）**。**Dock 交互修复（已完成，2026-10-02）**：Phase 3at 的普通成员闭包使 `BottomDock` 高亮冻结、`7202d0e1b1` 把激活态并入 `ForEach` 键又让激活入口销毁重建；现改为**稳定键 + `state/DockStore.ets` 经 `@ObjectLink` 注入**（`@Prop` 加 `@Watch` 同步），高亮实时跟随且开/关面板不重建入口（`BottomDock.ets` 79 / `DockButton.ets` 62 / `DockStore.ets` 8）。**Phase 3aq 已删掉本域的三条死壳路径**：`verticalRail` 66 + `actionDrawer` 70 + `compactMoreDrawer` 96，及其 4 个子按钮（`iconButton`/`moreButton`/`musicButton`/`gyroButton`）与 11 个 rail/drawer 辅助成员（`pinnedActions`/`drawerActions`/`compactDrawerActions`/`railHeight`/`drawerWidth`/`onRailTap`/`RAIL_*`×5/`railPinned`/`drawerOpen`）。**Phase 3as**：~~`dockClockChip` 16 / `dockClockLayer` 13 / `panelHandle` 22 / `padPanelHandle` 10~~ **已完成（`panels/shell/PanelChromeExtras.ets`，4 组件 100 行）**。**Phase 3at**：~~`bottomDock` 31~~ **已完成（`panels/shell/BottomDock.ets`，复用 `DockButton`；3 处调用点改组件）**；**同日回归修复（2026-10-01，见 CHANGELOG）**：点按后激活高亮不显示 —— 该组件化把激活判定改成宿主回注的普通闭包，组件因此观测不到 `activePanel`，`ForEach`（键不含 active）也不重建子项，`@Prop active` 冻结；已改为数据化的 `@Prop activePanel` + 组件内 `dockItemActive()`，并把激活态纳入 `ForEach` 键（`BottomDock.ets` 58 → 67 行；宿主 3 处调用点改写、删 `dockActionActive`，25,063 → 25,059 行）。**已 A/B 坐实为 3at 引入的回归**（`d7a2bc9768^` 构建点「位置」后 place 采样 max(B−R)=134，修复前 HEAD=3，修复后=143）；~~`compactTopQuickControls` 20 + 参数化 `compactQuickButton` 25~~ **已完成（`panels/shell/CompactTopQuickControls.ets` + `CompactQuickButton.ets`；参数化 `@Builder` 去除，动作本体回注宿主）**。**仍留宿主（Phase 4h 已定论）**：`floatingPanel` 55 **与 `compactPanel` 46** —— 二者体内都调用宿主 `this.panelContent()`，而 `panelContent` 是 §6.1 要求长期留在宿主的 `activePanel` 分发链；ArkUI 无按名实例化能力，组件化必须用 `@BuilderParam`，违反 §13.1 规则 9（真机退出）。故**保留为宿主薄 `@Builder`**，待 `panelContent` 剩余实分支全部下沉、整体组件化后二者才能随之下沉；**该保留不影响「分支 ≤8 行单调用」达标口径**（口径只针对 `panelContent` 的 `if/else if` 分支）。**Phase 3at 结论**：Phase 3 自身的"非 `private` 域 builder"队列已清空（仅剩上两件待 Phase 4）；但单体仍有 **11 个 `private` builder**（`satelliteGroupSelector` 25、`skyCultureSectionHeader`/`skyCultureMetaItem`/`skyCultureLabelSettingCard`/`skyCultureLabelModePicker`/`skyCultureFilterOption`/`skyCultureFilterPicker` 合计 150、`polarScopeOverlay` 126、`skyCultureArtPreviewOverlay` 60、`objectInspectorMediaPreviewOverlay` 66、`objectInspectorModelOverlay` 45）与 **7 个 `view*Tab`**，经零引用扫描全部为活代码，调用点落在 `panelContent` / `viewSkyCultureTab` / `build()`，归属 Phase 4（面板宿主 + 视图标签页）与 Phase 5（overlay），非 Phase 3 遗留。**Phase 5a（已完成，2026-10-02）**：`polarScopeOverlay`（127 行）→ `panels/overlay/PolarScopeOverlay.ets`（147 行），几何与手工命中路由留宿主机、以 `@Prop` + 回调注入，四个 `polar-scope-*` id 原样保留，单体 19,314 → 19,230 行。**Phase 5b（已完成，2026-10-02）**：~~`objectInspectorMediaPreviewOverlay`（66 行）~~ → `panels/overlay/ObjectInspectorMediaPreviewOverlay.ets`（88 行），可见性判定留宿主、标题/顶部安全区以 `@Prop`（titleText/topInset）传入、媒体数据经 `@ObjectLink objectMediaStore`、四个动作回注宿主（成员名与宿主方法一致），`ImageFit.Contain` 等语义逐字保留，单体 19,230 → 19,173 行。**Phase 5c（已完成，2026-10-02）**：~~`skyCultureArtPreviewOverlay`（60 行）~~ → `panels/overlay/SkyCultureArtPreviewOverlay.ets`（88 行）：可见性判定留宿主、主题色与顶部安全区以 `@Prop` 传入、预览三态与解码结果 `artPreviewPixelMap` 经 `@ObjectLink skyCultureViewStore` 引用语义读取（该 PixelMap 从宿主 `@State` 收进 store —— 真机实测 `@Prop` 会深拷贝 PixelMap 致 `Image.onError`）、关闭/加载完成/失败/重试四个动作回注宿主（新增宿主方法 `retrySkyCultureArtPreview`），单体 19,173 → 19,134 行。**Phase 5d（已完成，2026-10-02）**：~~`objectInspectorModelOverlay`（45 行）~~ → `panels/overlay/ObjectInspectorModelOverlay.ets`（80 行）：可见性判定留宿主、模型数据（PixelMap / proceduralKind / opacity）经 `@ObjectLink objectMediaStore` 引用语义读取（跨组件传 PixelMap 禁止 `@Prop`，见 5c）、标题/模式提示/顶部安全区以 `@Prop`（titleText/noticeText/topInset）传入、关闭/重置/舞台手势三动作回注宿主，`object-model-close` / `object-model-stage` 锚点与 `BLOCK_HIERARCHY` 逐字保留；本片未连真机（改模拟器 UI-only，模型叠层本体待真机走查）。**模型叠层本体已于 2026-10-02 补做真机走查（同一诊断片修复了行星模型"本地资源解码失败"后）：`devecocli ui click` 打开 `object-model-stage` → `drag` 旋转（前后截图表征位移）→ 关闭回 `object-model-inline-stage`，进程存活；双指缩放未走查（`devecocli ui` 无多点触控）**，单体 19,134 → 19,098 行。**Phase 5 收口（2026-10-02）**：4 个 overlay（`polarScopeOverlay` / `objectInspectorMediaPreviewOverlay` / `skyCultureArtPreviewOverlay` / `objectInspectorModelOverlay`）**全部组件化、无遗留**，宿主 `build()` 只剩 `if (可见性) { <Component>({...}) }`，无参数化 `@Builder`、无 `@BuilderParam`。**下一步 Phase 6 六个壳层**：~~`scriptFocusShell`~~（6a）/ ~~`compactShell`~~ / ~~`harmonyShell`~~（6b）已抽出；剩余 `hoverObservatoryShell` 142 / `expandedShell` 128 / `interactiveGuideShell` 78。**构建侧收口（2026-10-02）**：Windows 资源同步脚本 `sync-ohos-resources-windows.ps1` 已用 `System.Drawing` 生成 `.model.rgba` 侧车（50×512×256 + 3×512×2，共 53 个），行星模型恢复“侧车优先”快速路径（应用内 PNG 回退保留为兜底），见 CHANGELOG。 |
| 12 | **Phase 7 收口** | **已完成（Phase 7：删 8 个零引用 `private` 方法 + 2 个零引用字段（含 `TimeTick` 接口与导入）+ 1 处陈旧注释；`observationTimeText` 收入 `TimeStore`；单体 18,689 → 18,593，−42.9% → −43.1%；校正 `UI-ARCHITECTURE.md`、根 `AGENTS.md`；真机开合时间面板验证通过；**队列已空** —— 收口结论见下）** | |
| 13 | **Phase RA 资源覆盖审计（非 UI 切片）** | **已完成（Phase RA：修正 `scripts/audit-ohos-resource-coverage.mjs` 的 skycultures 期望集与陈旧结论、纳入 `scenery3d` 并新增"未随包家族与原因"；以签名 HAP + 真机 `getDeepSkyImageStatus` 逐族核对。结论：**所有应随包的运行时资源均已进包**；FOV 横幅的 N 是视口内纹理**加载中**数量而非缺失（`missingCount=0`、`referenced=onDisk=674`）；仅 `models/`（17.8 MiB）与 `atmosphere/`（58.7 MiB）按默认关闭的配置项启用，属**待决策**不擅自打包。详见 CHANGELOG [2026-10-02] 与 `docs/harmonyos/archive/audits/RESOURCE-COVERAGE-AUDIT-2026-08-24.md`）** | 审计报告已随包提交 |


#### Prop 风格域转 Store 追加队列（review §2.7，2026-10-04）

- **已完成（第三批，2026-10-04）**：`archaeo`（`ArchaeoStore` 18 字段 + `ArchaeoLinesPanel`）、`navStars`（`NavStarsStore` 14 字段 + `NavStarsPanel`）、`polarScope`（`PolarScopeStore` 6 字段 + `PolarScopeOverlay`）三域由 Prop 风格转 Store 风格；宿主 `@State` 266 → 231。
- **viewCoordinate 经核查无字段可迁，不改**：`viewCoordinatePrimaryText/SecondaryText`（50ms 定时器回填）与 `viewCoordinateOffsetX/Y`（拖拽逐帧写）按规则"高频字段不入被观察 store"留宿主；`ViewCoordinateSettings` 早已用 `OverlayStore`，`ViewCenterCoordinateOverlay` 以 `@Prop` 接收读数 —— 故不新建 `ViewCoordinateStore`。
- **已完成（前序，2026-10-04）**：`satellites`（`SatelliteStore`，28 字段）、`script/recording/video`（`ScriptStore`）、`scenery3d`/`catalogs`/`meteorShowers`/`commandConsole`（四簇同批，共 24 字段）。
- **已完成（第四批，2026-10-04）**：`mosaicCamera`（`MosaicStore` 10 字段 + `MosaicCameraPanel`）、`observingList` 残留（`ObservingListStore` 2 字段 + `ObservingPanel`/`ObjectPanel`/`ConfigFallbackPanel` 改 `@ObjectLink`）、`audio`（`AudioStore` 2 字段 + `AudioPanel`）、`eclipse` 起始日期（并入既有 `AstroStore` 3 字段，宿主自用）。宿主 `@State` 238 → 224。`test-ohos-satellite-panel.mjs` / `test-ohos-plugin-panel-state.mjs` 假宿主已随 store 同步，卫星脚本存量失败清除。
- **已完成（第五批，2026-10-04）**：两簇**残留字段并入既有 store**（不新建）—— ① 星空文化列表 / 当前选择：`skyCultures` / `skyCultureList` / `skyCultureListLoading` / `currentSkyCulture` / `currentSkyCultureId`（5 字段）并入 `SkyCultureViewStore`，消费方 `LayersPanel` / `SkyCultureViewTab` / `SettingsQuickLegacyPanel` / `ConfigFallbackPanel` 由 `@Prop` 改 `@ObjectLink`；`skyCultureArtStates` / `skyCultureArtThumbnailPixelMaps` 按"分块/防抖渐进写入＝高频不入 store"仍留宿主。② 脚本播放引擎 / 回放 / 视频导出（16 字段）并入既有 `ScriptStore`，`ScriptFocusShell` 改 `@ObjectLink`（播放/回放四态直接读 store，文案/几何仍宿主算好 `@Prop` 下发）；`recordBuffer` 按"追加型工作缓冲"留宿主。宿主 `@State` 217 → 196；`test-ohos-privacy-startup.mjs` 第 13 项夹具补齐 `fileSize` 形参后 19/19 全绿。
- **已完成（第六批，2026-10-04）**：三簇 Prop 风格域转 Store（均**新建**独立 store）—— ① `ephemeris`（11 字段）→ `state/EphemerisStore.ets`（DE430/431/440/441 的 Available/Active + `ephemerisStartYear/Month/Day`）；因 `AstroStore` 已有同名前缀但语义无关的星历表字段族，故独立不并入；`SettingsPanel` 8 个 DE `@Prop` → 1 个 `@ObjectLink`。② `nebulaTexture`（5 字段）→ `state/NebulaTextureStore.ets`；`NebulaTexturesPanel` 11 个派生 `@Prop` → 1 个 `@ObjectLink`（就地读 `nebulaTextureStatus`）。③ `pluginList`（2 字段）→ `state/PluginStore.ets`；`SettingsPanel` 2 个 `@Prop` → 1 个 `@ObjectLink`。宿主 `@State` 196 → 181。**`dso` 计数（`dsoTotalCount`/`dsoGalaxies`/`dsoClusters`/`dsoNebulae`）经普查确认零读取、`loadDSOCounts` 零调用，属写后即弃死状态，未并入 `LayerViewStore`、留宿主**。`test-ohos-plugin-panel-state.mjs` 假宿主已随 store 同步（4/4 全绿）。
- **已完成（第七批，2026-10-04）**：三簇 Prop 风格域转 Store + dso 死代码清理 —— ① `navigation` 设置（9 字段：mouse/zoom/keys/gravityLabels/startup Fov·Azimuth·Altitude/maxFov）→ 新建 `state/NavigationSettingsStore.ets`；`SettingsPanel` 9 个 `@Prop` → 1 个 `@ObjectLink`。② 视图交互偏好（5 字段：`autoZoomResets`/`useMetricUnits`/`viewLock`/`verticalClamp`/`flatHorizon`）→ 新建 `state/ViewSettingsStore.ets`；`SettingsPanel`（3）/`SettingsQuickLegacyPanel`（4）/`ConfigFallbackPanel`（1）共 8 个 `@Prop` → 3 个 `@ObjectLink`；`viewLock` 深链（壳层 → `UnifiedObjectDetailCard`）沿用宿主读 store + `@Prop` 下发。③ 大气观测辅助（4 字段：`atmoPressure`/`atmoTemperature`/`atmoExtinction`/`refractionOn`）→ 新建 `state/AtmosphereStore.ets`；`TimePanel` 4 个 `@Prop` → 1 个 `@ObjectLink`。④ `dso` 死代码（4 `@State` + `private loadDSOCounts()` + `StellariumBridgeResponse.dsoCounts`）确认零调用/零读取后删除（独立 `chore(harmonyos)` 提交）。宿主 `@State` 181 → 162。真机走查：设置「视角与导航」渲染 store 值、点按「地平线自动重置」开关 `getNavigationSettings` 回读 `false→true`（写回）并复原；时间面板大气块渲染 `1013 mbar / 15 °C / 0.13`。
- **已完成（第八批，2026-10-04）**：残留字段**并入既有 store**（不新建）+ 死字段清理 —— ① 时间/历法残留（12 字段）：`manualYear/Month/Day/Hour/Minute`（5）并入 `state/TimeStore.ets`（同属时间面板域，`TimePanel`→`ManualTimeBlock` 经 `@Prop` 消费）；`presetSkyTime`（1）并入 `state/TimeSettingsStore.ets`（与启动时间/格式设置同域）；`rtsCalendarStartYear/Month/Day` + `graphStartYear/Month/Day`（6）并入 `state/AstroStore.ets`（RTS 日历 / 年度高度图起始日期，`AstroPanel` 经 host 回调消费）。② 目录残留（2 字段）：`starCatalogHealth`（`SettingsQuickLegacyPanel` `@Prop`）与 `objectCatalogCategories`（经 `searchAllCategoryOptions()` 进 `SearchPanel` `@Prop categories`）并入 `state/CatalogStore.ets`；`catalogHealthLoaded`/`catalogManifestPresent` 仍留宿主（与卫星面板共用）。消费面板的 `@Prop` 数量不变（来源改为 `this.<store>.<field>`），故无面板文件改动。③ 死字段 `pickedTime`（0 处 `this.` 引用、`panels/scripts/qability` 无消费）删除（独立 `chore(harmonyos)` 提交）；`pickedDate`（8 处，RTS/星历/图表/日食共用）保留。宿主 `@State` 162 → 147。真机走查：时间面板手工时间块渲染 store 值，选择并确认 10 时 → 按钮 `23:00→22:00`；「同步星图当前时间」→ `22:00→05:43`（store 写回实时刷新）。`AstroPanel` RTS 起始日期控件因需先选中天体且视口未渲染，未走查（见 CHANGELOG）。
- **已完成（第九批，2026-10-04）**：四簇 14 字段（先普查后只搬白名单）——① 信息窗 6 字段（`infoWinVisible`/`infoWinExpanded`/`informationMode`/`informationCustomMask`/`informationSettingPending`/`infoLevel`）→ 新建 `state/InfoWindowStore.ets`；消费方（三壳层 `infoWinVisible`、`SettingsPanel` `informationMode`/`informationSettingPending`）仍以 @Prop 快照接收、宿主下发点读 store。② 会话残留 3 字段（`sessionJson`/`sessionExportSig`/`sessionHint`）并入 `state/SessionToolStore.ets`（`ToolsStore` L17 已明确排除；`PlacePanel` 早已 `@ObjectLink sessionToolStore`）——`PlacePanel` 的 `@Prop sessionHint`/`sessionJson` 已移除，`ContinuationSection` 就地读 store。③ 语言 2 字段（`selectedLanguage`/`languageRevision`）→ 新建 `state/LanguageStore.ets`；`languageRevision` 为语言刷新锚点，消费方（14 文件）保持 @Prop 多层串接、宿主下发点读 store，刷新链路逐字不变。④ 杂项：`configDitheringMode` 与 `liveMode` 并入 `state/ViewSettingsStore.ets`（两消费面板都已持有该 store）。**`moduleList` 未搬**（写后即弃：1 处赋值、0 读取、未传任何面板），留宿主。宿主 `@State` **147 → 136**（删 13 字段声明、新增 2 store 持有）。真机走查（192.168.50.108:36717）：信息设置页模式 全部→简短 实时高亮移动、`getInformationSettings` 回读 `all→short`（已复原）；语言 en↔zh_CN 面板文案就地刷新；place 面板冒烟。`test-ohos-distance-ui`/`-information-policy`/`-settings-choice-motion` 假宿主已随 store 同步。

- **已完成（第十批 / 收尾批，2026-10-04）**：4 字段并入既有/新建 store + 死字段清理 + 不迁移清单登记 —— ① 引导/语音（`guideState` 19 处 + `speechStatus` 5 处）→ **新建** `state/GuideStore.ets`（无同义 store；消费方 `InteractiveGuideShell`/详情卡仍 @Prop，宿主改读 store）。② `bottomCardIndex`（9 处）并入 `state/ObjectDetailStore.ets`（详情卡页索引，三壳层 @Prop `activeIndex`）。③ `uiLocked`（3 处）并入 `state/ViewSettingsStore.ets`（与 viewLock 同域；普查确认全工程**零写入**、属失活标志，仍按语义归位）。④ 死字段 `moduleList`（1 赋值 / 0 读取）连同无用的 `getLoadedModuleNames` 启动任务删除（独立 `chore` 提交）。宿主 `@State` **136 → 132**（46 store + 86 裸字段）；不迁移清单登记进 `ARKTS-PAGES-REFACTOR-STATE-REVIEW.md` §2.7.1（86 字段 / 16 类）。真机走查（192.168.50.108:36717）：`startGuide solar-neighbours` → `getGuideState` 返回 active/phase/index、`guideAction next` index 0→1、stop 复原；详情卡切「观测/操作」页实时刷新（`bottomCardIndex` 走 store）；点「朗读文本」后卡片显示 `getObjectSpokenText` 文本；`getAtmosphereFlags` 复原、`pidof` 存活。`test-ohos-guide` / `test-ohos-detail-live-values` 全绿；全量脚本仅 §13.6 的 7 个环境类失败。

**每个 Phase 4 面板切片前**建议先跑一次第 13.2 步 1 的"零引用扫描"，把死代码清掉再搬迁（§11 修订 6 的四类判据）。

#### Phase 6 收口结论（2026-10-02，Phase 6d 后）

六个壳层全部组件化：`ScriptFocusShell`（6a，251）/ `CompactShell`（6b，268）/ `HarmonyShell`（6b，90）/ `HoverObservatoryShell`（6c，242）/ `ExpandedShell`（6c，232）/ `InteractiveGuideShell`（6d，116）。宿主 `build()` 现只剩五类结构：

1. **顶层 `Stack`**：语言刷新锚点 `Text(i18nLang)`、gl-probe `XComponent`、隐私放行后挂载的 `qohos` NODE `XComponent`、两处触摸反馈 `Row`、全屏触摸承接 `Stack`（`handleOverlayTouch`）。
2. **布局三选一分发**：`if (!scriptPlaybackVisible() && !recording && !polarScopeVisible)` → `Stack { if isFoldHoverLayout → HoverObservatoryShell else if isExpandedLayout → ExpandedShell else → CompactShell }`；每个壳之后的 `if (panelVisible) { Stack { this.compactPanel() / this.floatingPanel() } }` 面板包裹仍在宿主（跨组件不能调用宿主 @Builder，规则 9）。
3. **脚本/导览焦点层**：`if (scriptPlaybackVisible()) { if (guideState.active) InteractiveGuideShell else ScriptFocusShell }` + `RecordingFocusShell`。
4. **Dock 命中区**：Dock 顶层命中靶 `Stack` + `HarmonyShell`（坐标叠层 / 陀螺仪指引 / 点击反馈气泡）。
5. **浮层与状态条**：`RecordingControlBar` + `PolarScopeOverlay` + 三个 Phase 5 Overlay（星空文化美术预览 / 详情媒体全屏 / 详情模型沉浸）+ `skyTextureStatus` 状态条。

#### Phase 7 收口结论（2026-10-02，队列收尾）

> 本节原为"下一片待办"，现已全部执行，队列**清空**。

- **文档校准（已完成）**：`docs/harmonyos/specs/UI-ARCHITECTURE.md` 全量改写 —— §2 行数改为 18,593，删除 §3/§4/§4.4/§5 中**所有易失真的 `文件:行号` 引用**，改为组件名 + `panels/shell/*.ets` 路径；§4.4 由"三种壳层 Builder"改为"壳层组件表"；§6 命中分布改为宿主单体实测并注明其余在 `panels/**`；§10 核对方法补 `check-ohos-ui-contract.mjs`。根 `AGENTS.md` 新增 UI 结构约定条目（`panels/panels/**`、`panels/shell/**`、`state/*Store.ets`、V1-only、`.id()` 契约）。
- **宿主转发层复核（已完成，无需改代码）**：`return this.<store>.<x>` 型纯转发 getter **0 处**（唯一形似者是 `selectedDisplayValue()` 的 `switch` 分派表，不是转发层）。`observationTimeText` **已收入 `state/TimeStore.ets`**（`timeRateText` 早已在其中）；`nmText()`/`nmSub()`/`nmAccent()`/`nmBg()` 等夜视色助手是 `nightMode` 的纯函数，**技术上可并入 `NightModeStore`**，但全部调用点都在宿主（消费方经 `@Prop` 拿颜色），下沉不减少行数；改用它们需让已持有 `nightModeStore` 的组件（`TimePanel`/`ConfigFallbackPanel`/`NightModeToggleRow` 等）就地取色，属**后续可选优化**，本片不做。`floatingPanel`/`compactPanel` 保留定论**仍成立**（体内 `this.panelContent()`，见 §13.1 规则 9），已在源码注释与本文件标注。
- **死代码扫描（已完成）**：用 §11 修订 6 四类判据重扫，确认并删除 **8 个零引用 `private` 方法**（`toggleDrawer` / `orbitColorStyleIndex` / `toggleSkyCultureLabelPicker` / `applySkyCultureCustomColor` / `setSkyCultureFilterValue` / `toggleSkyCultureFilter` / `formatDegrees` / `morePanelActive`，后三个与 `LocationStore`、`LayerViewTabs` 中的同名活实现无关）、**2 个零引用字段**（`gyroSensitivity`、`timeTicks`）及其连带的 `TimeTick` 接口与导入；级联复扫一次收敛，无新增。

#### 终态指标与剩余已知问题（2026-10-02）

- **单体行数**：32,705 → **18,593**（−43.1%）；本轮各提交末态见 CHANGELOG。
- **结构文件数**：`state/*Store.ets` **26 个**（+`TimeWheelController`），`panels/**` **119 个** `.ets`。
- **契约**：`check-ohos-ui-contract.mjs` = 33 面板 / 22 静态 id / 17 动态前缀 / 42 锚点 / 183+ `.ets`，全绿。
- **测试现状**：35 个 `scripts/*ohos*.mjs` 全部扫描，仅 §13.6 的 7 个存量环境类失败（4 个 `-pad` 需显式 `--device`、`mist-performance` 需设备、`verify-ohos-location-search.mjs` 路径 bug、`verify-ohos-search.mjs` macOS 假设），与本轮无关。
- **§13 队列**：**已空** —— §13.5 表内 1–12 全部完成。
- **剩余已知问题（非本轮引入，待后续单独处理）**：
  1. 陀螺仪校准面板 `GyroCalibPanel` 在当前 UI 无入口（活路径是 `gyroRotationCallback`，勿误判死代码）。
  2. `settings_quick_legacy`（`SettingsQuickLegacyPanel`）无入口死分支。
  3. `object` 分支在 expanded 构型不可达。
  4. `OFFLINE_APPGALLERY_BUILD` 跳过 astro 面板前四段，需非 appgallery 构建在真机走查。
  5. `nm*` 夜视色助手可按上文评估结果选择性下沉 `NightModeStore`。
  6. **Phase 3ad 引入、已修复**：详情卡页头三枚摘要（星等/星座/距离）切换天体不刷新 —— 见 §13.5 第 3 行与 CHANGELOG `[2026-10-02] 修复：详情卡页头三枚摘要…`。教训已固化：ArkUI V1 局部刷新按元素登记依赖，组件内动态值不得只经普通成员回调求值。



### 13.8 历史重写：从分支起点剔除 `build/` 跟踪与全部同步提交（2026-10-01，**仅本地**）

**目标（用户要求）：** 从 `997c007e3`（本分支基点）起，`build/` 目录**从一开始就**不被跟踪，并从历史中剔掉所有 `chore(harmonyos): sync the tracked generated copy of MainWindowNativeNode.ets` 提交。

**结果：** 区间提交 **80 → 52**（29 个纯 build 同步提交被剪掉，+1 个专门的取消跟踪提交）；区间内触碰 `build/` 的提交**只剩那一个**；`sync` 提交 **0**；**最终 HEAD 的树与重写前逐字节一致**（源码/脚本/文档/插件/C++ 全 0 差异）。

**做法（可复现）：**

1. `git filter-branch --prune-empty --index-filter "git rm -r --cached --ignore-unmatch build" 997c007e3..HEAD`
   —— 每个提交的索引里都删掉 `build/`；29 个"纯 build"提交因此变为空被 `--prune-empty` 剪掉，其余提交保留（树去掉 build/）。
2. 用 plumbing 在**分支起点**插入一个专门的取消跟踪提交（不切工作区）：临时索引 `GIT_INDEX_FILE` + `git read-tree 997c007e3` + 对 **11 个文件逐个** `git rm --cached` + `git write-tree` + `git commit-tree -p 997c007e3`，然后 `git rebase --onto <U2> <旧U> feat/api26-pages-refactor`。
   —— 这样分支的**第一个提交**就是 `chore(git): stop tracking the generated copies under build`。

**踩坑：** 在临时索引里用**目录 pathspec**（`git rm -r --cached build`）会**静默失败**，树里仍留 11 个 `build/` 条目，于是删除动作被记到了下一个不相关的提交上（表现为"Phase 0 提交也碰 build/"）。改为**显式 11 个文件路径**，并在 `commit-tree` 前断言 `git ls-tree -r <tree> -- build` 为 0。

**与远端：** `origin/feat/api26-pages-refactor`（`55f6ce49f1`）是重写前本地 HEAD 的祖先；重写后所有哈希变化，故同步必须
`git push --force-with-lease origin feat/api26-pages-refactor`。**本次未执行推送**；远端内容均已作为改写后的提交保留（例如 `05f0e93341 docs(harmonyos): trace the provenance of every removed block`）。

**备份与清理：** 重写前的 `eea49e386c` 保留在 `refs/heads/backup/pre-build-untrack-rewrite` 与 `refs/original/refs/heads/feat/api26-pages-refactor`。确认无误后可删（删后旧对象才会被回收）：

```powershell
git update-ref -d refs/original/refs/heads/feat/api26-pages-refactor
git branch -D backup/pre-build-untrack-rewrite
git reflog expire --expire=now --all; git gc --prune=now
```

---

## 14. 续作计划二：A/B 类方法下沉（依据 STATE-REVIEW §2.12 / §2.13，2026-10-04 立）

> **前置已完成**：§2.7 的域状态下沉（宿主 `@State` 333 → **132**、`state/` **48** 个 store、§2.7.1 已登记 86 个保留裸字段）。
> 本节把"宿主里本可归组件 / 归 store 的方法"整理为两条**互不依赖**的轨道，可直接作为无人值守队列执行。
> 协议与硬规则沿用 §13.1（九条）/ §13.2（八步）/ §13.3（陷阱）；本节只补 **A/B 专属规则**（§14.8）与切片顺序。

### 14.0 目标与基线（2026-10-04 复测）

| 指标 | 现状（实测） | 终态目标 | 依据 |
|---|---:|---:|---|
| 宿主 `private` 方法 | **942** | ≈ 640 | §2.12（305 可归组件/模块） |
| 宿主 `private load*` | **72** | ≈ 11 | §2.13（B1 24 + B2 35 下沉；B3 11 暂留） |
| 宿主 `@State` | 132 | 132（本计划不动状态） | §2.7.1 |
| 已有基础设施 | `bridge/BridgeClient.ets`、`common/ui/`、48 个域 store | ＋`bridge/CommandPort.ets`、`common/derive/*.ets` | 实测 |

**两类判据（§2.12/§2.13 原文）**
- **A 类（纯派生）**：`private`、非 `void`/非 `Promise` 返回、名字非动作动词、无成员写、无 IO、无桥、无路由、无定时器、无 `AppStorage`/`localStorage`、无 `hilog`。
  - **A1**＝零宿主状态读取（只依赖入参/静态/纯计算）**91 个** → 可直接移出，无需 V2、无需注入。
  - **A2**＝读取宿主字段 **214 个** → 需目标位置能拿到该数据（组件已持有时随组件；否则带显式入参）。
- **B 类（域内加载器 `load*`）**：只做"桥调用 → 解析回包 → 写本域状态"。
  - **B1**＝仅桥＋本域 store → 注入 `CommandPort` 即可搬（**24 个**）。
  - **B2**＝再加本域助手／他域 store 引用／CLI `publish*` → 一并注入（**35 个**；Astro 簇 19 + 其余 16）。
  - **B3**＝还写 §2.7.1 保留的裸宿主字段 → 先把该字段处理（搬 store 或注入），即降为 B1/B2（**11 个**）。

> **数字纪律**：以上取 §2.12/§2.13 的实测值；本复测宿主 `private`=942（原文 940）、`load*`=72（原文 70）。
> **每片开工前必须用附录命令重测该片的判据与清单边界**，以重测为准，不照抄本节表格。

### 14.1 Enabler（轨道 B 硬前置，1 片）：`bridge/CommandPort.ets`

新增 `harmonyos/ets-source/bridge/CommandPort.ets` —— **纯接口，不 import NAPI / UI / libentry.so**（§13.1 规则 6 授权"跨域/桥/定时器依赖用注入解决"，先例 `TimeWheelController` 的 `onSeek`/`onStopSpeed`/`getUtcOffsetHours`）：

```ts
export interface CommandPort {
  request(name: string, payload?: string): StellariumBridgeResponse
  requestInteractive(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure?: (r: StellariumBridgeResponse) => void): void
  requestLongRunning(name: string, payload: string, onOk: (r: StellariumBridgeResponse) => void, onFailure: (r: StellariumBridgeResponse) => void, onProgress: (r: StellariumBridgeResponse) => void, intervalMs: number, cancelled: () => boolean): void
  fire(name: string, payload?: string): void
}
```

**store 侧统一约定**（后续每一片照此）：
- `private port: CommandPort | null = null`
- `private seq: number = 0`（**原宿主的请求序号搬入 store**，禁止宿主与 store 双序号）
- `private onChanged: (() => void) | null = null`（原宿主 `publish*` 注入点）
- `attachPort(port: CommandPort, onChanged: () => void): void`

**宿主侧**：`aboutToAppear` 里做**薄适配器**（不改行为）：
`this.<store>.attachPort({ request: (n, p) => this.callNative(n, p), requestInteractive: (...), requestLongRunning: (...), fire: (...) }, () => this.publishXxx())`
（端口对象用**具名实现**，避免 ArkTS 匿名对象字面量越界；参照既有 `interfaces /*Port*/` 写法。）

**本片验收**：构建 + 契约通过；**先拿最小加载器 `loadAboutInfo`(9 行) 试点**搬入 `ToolsStore` 并真机验证（打开设置/关于，回包渲染正常），确认机制可用后再批量推进 B1。

### 14.2 轨道 A1：91 个零宿主依赖纯函数（7 片）

**落点**：新建 `harmonyos/ets-source/common/derive/<domain>.ets`，**文件级函数**（无 `this`、无状态），具名导出；宿主与组件按名 import（§13.3 已有"类型导入要找准模块"的教训，此处对函数同理）。

**分域清单（依 §2.12 A1 全清单归类；开工前重测）**：

| 片 | 模块 | 函数（§2.12 A1 清单按前缀归类） | 约数 |
|---|---|---|---:|
| A1-1 | `derive/gyro.ets` | `gyroRotateAboutAxis` `gyroMultiplyQuaternions` `gyroFilterDeviceVector` `gyroCross` `gyroRotateAboutVertical` `gyroScreenAxisForDisplay` `shortestGyroAzimuthDelta` `wrapGyroAzimuth` `gyroNormalizeVector` `gyroNormalizeQuaternion` `gyroConjugateQuaternion` `gyroDot` | 12 | **已完成（2026-10-04）** |
| A1-2 | `derive/astro.ets` | `dateToJD` `jdToLocalTimeText` `astroTabItemsForGroup` `astroGroupItems` `astroGroupForTab` `rtsCalendarDurationLabel` `graphModeLabel` `graphStartOptionLabel` `hourOffsetLabel` `planetMetricLabel` `planetMetricUnit` `planetPairBodyName` `planetPairLinearLabel` `hecPointSize` `hecPointAngle` `hecDistanceLabel` `hecPlanetOrbitRadius` `lunarElongationBarHeight` `planetTimeSeriesBarHeight` `planetPairBarHeight` `messierNumberOf` `minorPlanetNumberOf` `fmtDegMin` `clamp` `distance` | 25 | **已完成（2026-10-04；`derive/astro.ets` 215 行 25 个纯函数，宿主 −25 `private`、−188 行，组件直连模块，拆 A1-2a/A1-2b 两提交）** |
| A1-3 | `derive/labels.ets` | `zhNameOf` `zhType` `planetZh` `sensZh` `scriptZh` `scriptDesc` `pluginZh` `pluginDesc` `pluginHostName` `pluginFeatureRoute` `resourceText` `describeDecodeError` | 12 | **已完成（2026-10-04；`common/derive/labels.ets` 279 行 12 个标签/文案纯函数迁出，宿主 −12 `private`、−280 行；5 个面板（Astro/Settings/Scripts/ConfigFallback/Scenery3d）改直连模块、成员与宿主注入同片删除，构建/契约绿，模拟器冒烟，真机文案内容待验）** |
| A1-4 | `derive/skycult.ets` | `isSafeSkyCultureArtPath` `cleanSkyCultureDescription` `cleanSkyCultureNarration` `isCliPanelName` `parseObservingList` `csvCell` `formatRate` `configDitheringLabel` `informationMaskBit` `isRecordable` | 10 | **已完成（2026-10-04；`common/derive/skycult.ets` 135 行 10 个纯函数迁出，宿主 −10 `private`、−119 行，`SettingsPanel` 的 `configDitheringLabel` 注入改直连模块，成员/注入/调用点同片删除，构建/契约绿，模拟器冒烟，真机数值与设置文案待验）** |
| A1-5 | `derive/actions.ets` | `moreActions` `primaryDockActions` `skyDataHubActions` `automationHubActions` `observingHubActions` `telescopeErrorText` `telescopeUpdateTime` `validationFromResponse` `sessionSignature` `getCityPreset` `officialLocationAliases` `normalizeLocationSearchText` | 12 | **已完成（2026-10-04；`common/derive/actions.ets` 143 行 12 个动作表/文案纯函数迁出，宿主 −12 `private`、−120 行；5 个 `*Actions` 实测均构造静态数组、零宿主状态读取，故无剔除项；宿主 36 处调用点改直连模块 + 清理 2 个无用类型 import，调用点数不变，构建/契约绿，模拟器验证 Dock 与 6 个 `#more-action-*` 及 `#hub-action-*`，真机望远镜/会话/位置数值待验）**；**A1-6 已完成（2026-10-04；`common/derive/geometry.ets` 60 行 13 个几何/触摸/布局纯函数迁出，宿主 −13 `private`、−55 行，13 名经复测全部零宿主读取、无剔除项；`AstroPanel` 的 `azBarHeight` 改直连模块、接口/noop/注入同片删除；`test-ohos-model-scroll.mjs` 夹具注入 `touchScreenX/Y`，构建/契约绿，模拟器验证缩放按钮/Dock/面板切换，真机缩放与连接线几何待验）** |
| A1-6 | `derive/geometry.ets` | `pointInsideRect` `pointOverlapsUiObstacle` `touchScreenX` `touchScreenY` `touchWindowX` `touchWindowY` `azBarHeight` `compactTopQuickY` `baseCompactObjectPeekY` `expandedDetailSummaryHeight` `isPhoneDetailPeek` `useTabletObjectInspector` `useExpandedDetailSummary` | 13 | **已完成（2026-10-04；`common/derive/geometry.ets` 60 行 13 个几何/触摸/布局纯函数迁出，宿主 −13 `private`、−55 行；开工复测确认 13 名**全部零宿主读取**（三个构型开关恒 `false`、`230`/`92`/`50` 为常量），无剔除项；`AstroPanel` 的 `azBarHeight` 改直连模块并同片删除接口/noop/注入；`test-ohos-model-scroll.mjs` 夹具改为形参注入 `touchScreenX/Y`，构建/契约绿，模拟器验证缩放按钮 + Dock + 面板切换，真机缩放/连接线几何待验）** |
| A1-7 | `derive/catalog.ets` | `catalogIconForModule` `catalogIconForObjectType` `wutCategoryOptions` `wutCategoryKey` `wutDirectionLabel` `phenomenonCaption` `timezoneDisplayName` | ≤9 | **已完成（2026-10-04；收尾片。开工按 §2.12 判据重测，宿主内余项恰为 7 个，全部零宿主依赖、**剔除到 A2 = 0**；新建 `common/derive/catalog.ets` 86 行 5 个纯函数，`phenomenonCaption` 并入 `derive/astro.ets`、`timezoneDisplayName` 并入 `derive/labels.ets`；宿主 −7 `private`、−135 行，`AstroPanel` 4 个接口成员/noop/宿主注入同片删除并改直连模块，构建/契约绿，`test-ohos-wut-layout` 4/4 + `test-ohos-astro-motion` 9/9，模拟器冒烟打开天文面板无崩溃，真机 WUT/caption/目录图标/时区文案待验）** |

> 合计 ≈ 91。**归属以 §2.12 A1 全清单逐名核对**；"动作数组构造"类（`*Actions`）若读取宿主字段，说明它其实是 A2，本轨道**剔除**，留给 §14.3。
>
> **A1 轨道收尾结论（2026-10-04，A1-7 后）**：§2.12 A1 全清单 **91 = 前 6 片 84 + A1-7 收尾 7 + 残留 0 + 剔除到 A2 0**。7 片产出 6 个 `common/derive/*.ets` 模块（gyro 12 / astro 26 / labels 13 / skycult 10 / actions 12 / geometry 13 / catalog 5）；`AstroPanel` 的 `phenomenonCaption`/`wutCategory*`/`wutDirectionLabel` 改直连模块。复测另发现若干**次生纯函数**（前片迁出其被调宿主方法后才变纯，如 `moreActionStartsSection`/`panelRouteParent`，及 `phenomenaBodyName`/`panelRouteRoot`/`celestialTitle`/`formatObservationTime`/`hecPoint*` 等）——不在 §2.12 的 91 清单内，留待后续补充微片或随 §14.3 A2 处理。

**每片手法（只做剪切 + 导入，禁改函数体）**
1. 从宿主剪切函数体 → 粘入模块（保留逐字语义）。
2. **删 `this.`**：函数内任何 `this.foo()` → `foo()`；残留 `this` 触发 `arkts-no-standalone-this`（§14.8 规则 1）。
3. 宿主删除该 `private` 方法声明；所有调用点 `this.<fn>(` → `<fn>(`（具名 import）。
4. 组件内的调用点同样 import 后去 `this.`。
5. 复核：宿主内 **零残留 `this.<fn>`**、模块内 **零 `this`**、调用点数不变。

**验收**：`arkts_check` → 构建 → 契约 → 相关域测试 → 真机（触及 UI 的域）。纯函数模块**可选加单测**（无 `this`、无 IO，易测）。

### 14.3 轨道 A2：214 个读宿主字段的派生方法（12 片）

**三去向**（按语义，不按体量）：

| 去向 | 判定 | 落点 | 约数 |
|---|---|---|---:|
| **A2-D 文案/命名/查找表** | 读域 store 字段 | 并入该域 store 的方法，或 `derive/<域>.ets` + 显式入参 | ≈60 |
| **A2-G 几何/布局** | 读布局字段且消费方组件本就持有该数据 | 组件文件级函数 + 显式入参（§7.5 Phase A 重叠区） | ≈100 |
| **A2-M 媒体/纹理** | `objectInspector*` 一族（28/21/17/14/11/9 行） | 随媒体管线（`ObjectMediaStore` / 媒体助手） | ≈50 |

**片序**：先做 **§2.12 列出的行数最大 25 个**中的**非热路径**（`objectInspector*` 6 个、`searchCategory*` 4 个、`categoryModuleIdFor`、`pluginFeatureDestination`、`catalogIcon*`）；**热路径放到最后单独成片**：
- `isUiPoint`(84 行，触摸判定，Down/Move/Up 全走)、`skyZoomButtonAt`(9，dock 命中，与 `common/ui/ChromeGeometry.ets` 强耦合)、`dockActionAt`(14)、`compactQuickIdAt`(9)、`expandedSafeTargetPoint`(16)、`inferredPanelRouteDirection`(16)。
- 这些**命中失败不报编译错**，必须"语义逐字不变"+"真机命中 + 截图对照"双验证（§13.2 步 7）。

**约束**：每片 ≤ 15 个方法或 ≤ 350 行；A2 依赖 §2.7（已完成）与 §14.2 的 `derive/` 模块（可复用）。**不得**为省事把 A2 的函数留在宿主"只改调用写法"。

> **A2-1 已完成（Phase A2-1，2026-10-04，单提交）**：`objectInspector*` 媒体族 6 个 —— `objectInspectorMediaWarmupText`(11) → `ObjectMediaStore` 方法（读本 store 字段，零入参）；`objectInspectorPlanetTexturePath`(28) / `objectInspectorPlanetRingSpec`(14) / `objectInspectorDeepSkyImageName`(21) / `objectInspectorFallbackVisualKind`(17) / `objectInspectorStarColor`(9) → **新建 `common/derive/media.ets`**（97 行 5 个纯函数，读 `objectDetailStore` 字段的改为显式入参；`objectInspectorSearchText` 仍留宿主、其值在调用点传入）。函数体逐字搬入，宿主删 6 `private`、改 16 调用点、删 1 个失效类型 import（`ObjectInspectorRingSpec`）；组件 `warmupText`/`fallbackKind`/`starColor` 是数据通道，`@Prop` 保留。宿主 `private` 方法 **730 → 724**、单体 **15636 → 15531**（−105）。构建/契约绿，`test-ohos-procedural-model` 12/12（夹具改读 derive 模块）等 5 个受影响测试全绿，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（Dock「更多功能」面板渲染、`pidof` 存活），详情卡派生值渲染待真机。**A2 进度：6 / 214。**

> **A2-2 已完成（Phase A2-2，2026-10-04，单提交）**：按行数降序取非热路径 **15 个**（开工重测宿主内余项边界）——`gyroMagneticHeadingFromDeviceVectors`(25) 读 §2.7.1 保留裸字段 → `common/derive/gyro.ets` + 显式入参；`archaeoLineSettingValue`(21) → `ArchaeoStore`；`currentSkyCultureMakerDraft`(21) → `SkyCultureMakerStore`；`makeAstroCsv`(19) → `AstroStore`（`fmtDateTime` 经既有 `AstroHostHooks` 注入）；`quickLocationSearchItems`(18) → `LocationPickerStore`；`filteredEclipses`(14) 与 `annualMaxLabel`(12)/`lunarElongationClosestLabel`(12)/`altAzMaxLabel`(11)/`altAzVisibleHours`(11)/`altAzNowLabel`(7)/`rtsCalendarStartOptionLabel`(7)/`eclipseStartOptionLabel`(7)/`graphCustomStartLabel`(4) → `AstroStore`；`telescopeCircleValues`(13) → `TelescopeStore`。**主动停下 2 个**：`currentAstroCsvExport`(76)（读 astro+wut 两域 + 3 宿主标题助手）、`objectDetailConnectorObstacles`(45)（A2-G 几何簇，含 8 几何助手）。函数体逐字搬入，仅改取值方式（`this.<store>.<field>`→`this.<field>`；`AstroPanelHost` 端口 lambda 改指向 store，组件接口/`@Prop` 未删除）；删 2 个失效 import（`csvCell`/`hourOffsetLabel`）；宿主零残留、store 零双写。宿主 `private` **747 → 732**、单体 **15,531 → 15,309**（−222）。构建/契约绿（44 锚点），全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（更多功能/观测工作区/目镜模拟 + 位置面板，`pidof` 全程存活）；astro/考古天文/位置快速搜索的端到端渲染待真机（UI-only 通道 `openUiPanel` 无回包）。**A2 进度：21 / 214。**

> **A2-3 已完成（Phase A2-3，2026-10-04，放宽粒度首片，单提交 `refactor(harmonyos): sink the domain value/label/option helpers (A2-3)`）**：按 §14.3.1 口径重测后取"域取值/标签/选项族" **41 个**（明细见 §14.3.1 表 A2-3 行与 CHANGELOG），停止 0；同片**登记 A-保留组 49 个 / 210 行**（判据见 §14.3.1 与 STATE-REVIEW §2.7.1）。宿主 `private` 710 → 669、单体 15,309 → 15,008（−301）。构建/契约绿，受影响 4 测试全绿，全量仅 §13.6 的 7 个环境类失败，模拟器冒烟（搜索分类/时间/更多面板）存活。**A2 进度：62 / 214。**

> **A2-4 已完成（Phase A2-4，2026-10-04，放宽粒度第 2 片，单提交 `refactor(harmonyos): move the layout and geometry helpers into their consumers (A2-4)`）**：开工 `git log -1` = `104871aa76`。按 §14.3.1 口径重测 A2 余项 **85 个 / 578 行**，排除 6 热路径（留 A2-6）与已登记 A-保留 49 后，取"布局/几何族（A2-G）" **30 个几何/布局方法 → `common/derive/geometry.ets`**（文件级纯函数 + 显式入参）：`railTop` `expandedMainPanelLeft` `panelTop` `panelLeft` `panelRight` `expandedDetailAvailableWidth` `baseExpandedDetailSummaryX/Y` `baseTabletInspectorX/Y` `tabletInspectorHeight` `baseBottomCardX/Y` `expandedDockOccupiedLeft/Width/Left` `dockWidthPixels` `dockLeft` `chromeRowPosXLeft/Right` `guideCardHeight/X/Y` `scriptControlWidth/X/Y` `isPanelBackPoint` `isDockPoint` `objectActionBarY` `isObjectDetailCardPoint`；**2 个 → store**（`panelSubtitle`→`TimeStore`，`scriptControlHeight`→`ScriptStore`）；**1 个转发方法折叠删除**（`chromeRowWidth`→ 调用点直接 `dockWidthPixels`）。函数体逐字搬入（比较边界/取整/回退分支一字未改，仅 `this.X`→形参、`this.f()`→模块 `f()`），宿主调用点同片改（含 6 热路径中 `isUiPoint`/`dockActionAt` 的**调用点**改写，热路径本体未动）。**停下**：`bottomCardX/Y` `detailCardX/Y/Width/Height` `expandedDetailSummaryX/Y` `tabletInspectorX/Y` `objectActionBarX`（A-保留 `clampedObjectCardOffset*` 的薄包装，不复制保留逻辑）、`currentGuide/Step`（`GuideStore` 注释登记保留）；`objectDetailCardY` 同因留下。**补登记 A-保留 +2**：`dockTop`（只读 `isExpandedLayout`+`skyHeight`）、`guideCardWidth`（只读 `skyWidth`），全部读取项 ⊆ §2.7.1 保留集合且零 store。宿主 `private` **669 → 636**、单体 **15,008 → 14,861**（−147）；`derive/geometry.ets` 75 → 309、`ScriptStore` 256 → 261、`TimeStore` 137 → 146。构建/契约绿（44 锚点），`test-ohos-polar-scope` 4/4（夹具改读 geometry 模块），全量扫描仅 §13.6 的 7 个环境类失败，模拟器冒烟（Dock 五项 + 缩放 ± + `panel-close`/`panel-back` 子面板返回 + 时间面板副标题实时渲染，`pidof` 全程存活）。详情卡/对象操作条（依赖引擎选中）与 `isPanelBackPoint` 触摸路径、`isDockPoint` 极轴镜分支**待真机**。**A2 进度：95 / 214。**

> **A2-5 已完成（Phase A2-5，2026-10-04，放宽粒度第 3 片，单提交 `refactor(harmonyos): sink the large and coupled derivation helpers (A2-5)`）**：开工 `git log -1` = `7ccb9a7e3b`。按 §14.3.1 口径重测 A2 余项 **75 个 / 519 行**，排除 6 热路径（留 A2-6）与已登记 A-保留 51 后取 **45 个**：日心黄道点几何簇 10 个（复测确认**零宿主读取**，`derive/astro.ets` 纯函数）、`panelTitle`(101)→`derive/labels.ets` `panelTitleFor(activePanel, configTab, isExpandedLayout, timeText)`、`celestialTitle`+`hecTitle`+`celestialPositionTitle`→`derive/labels.ets`（后两者删）、`currentAstroCsvExport`(76)→`AstroStore.astroCsvExport(wutTargets, wutObservationTime)`、天文图表尺寸/标签 18 个→`AstroStore`、夜视配色 12 个→`NightModeStore`。**停下**：`objectDetailConnectorObstacles`(45)（逐帧连接线组合：读 4 store 可见性 + `selectedObjectUiObstacles` + ~10 A-保留几何助手；17 参数或 ~10 hook 注入会破坏逐字语义，且真机离线不可验渲染）→ 登记宿主控制器逻辑（组合型），留设备可用片；`selectedObjectUiObstacles` 同因留。**补登记 A-保留：无**（`shouldRefresh*`/`canGoBackPanel` 读 `applicationInForeground`/`panelNavigationStack`/`tools`，不满足判据，维持既有注入语义）。宿主单体 **14,860 → 14,456（−404）**、`private` **658 → 613（−45）**；`derive/astro.ets` 245→349、`derive/labels.ets` 342→453、`AstroStore` 1408→1578、`NightModeStore` 13→52。构建/契约绿（44 锚点），全量扫描仅 §13.6 的 7 环境类失败，模拟器冒烟（Dock 五面板 + 三 hub 标题文本对照、天文计算面板，`pidof` 全程存活）。真机（天文图表数值 / CSV 内容 / 夜视 `nm*` 实时刷新）待验。**A2 进度：140 / 214。**

#### 14.3.1 A2 重排（2026-10-04，放宽粒度；覆盖上表"12 片"的余量口径）

**背景**：A2-1/A2-2 两片（各 6/15 个）按"每片 ≤15 个或 ≤350 行"推进，余量约 190 个，按原粒度需再 12+ 片；且大量条目是**布局/命中几何**（改造成本高、收益低、真机离线时不可验）。经实测量化后重排（用户 2026-10-04 指示"加快进度、放宽每片方法与行数"）。

**实测口径**：宿主 `private`、非 `void`/`Promise` 返回、名字非动作动词、无成员写、无 IO/桥/路由/定时器/`AppStorage`/`hilog`、且读 `this.<field>`。按此口径 A2-1/A2-2 之后余量 = **153 个 / 1,131 行**（严于 §2.12 的 214；差额多为判定为动作/写状态的条目 —— **每片开工前仍以重测为准**）。拆两组：

| 组 | 方法数 | 行数 | 判据 | 处置 |
|---|---:|---:|---|---|
| **A-保留组** | **49**（原估 31，见下"重测修正"） | 210 | **仅**读 §2.7.1 保留裸字段，且不读任何 store | **登记为宿主控制器逻辑，永久保留**（与 §2.5"宿主是控制器"一致） |
| **B-下沉组** | **122** | 1,004 | 读 store 字段，或读宿主**非保留** scratch 字段 | 下沉（见下 4 片） |

> **A-保留组重测修正（2026-10-04，A2-3 片）**：原表"31"为占位估值，且其示例清单是从 A2-4 目标表误抄。
> A2-3 开工按判据逐名重测（宿主 `private`、非 void/Promise、非动作动词、无成员写/IO/桥/路由/定时器/
> `AppStorage`/`hilog`，且**全部宿主字段读取项 ⊆ §2.7.1 保留集合、零 store 读取**），实测 **49 个 / 210 行**
>（`this.EDGE_MARGIN` 等**未登记常量**不计入保留集合，故读它的布局方法归 A2-4 而非本组）。全量清单与逐条
> 判据命中说明见 `ARKTS-PAGES-REFACTOR-STATE-REVIEW.md` §2.7.1"宿主控制器逻辑（永久保留）"子类。
> **注**：A2-4/A2-6 表内的 `bottomCardWidth`/`locationMapWidth`/`responsiveFoldAngle`/`compactPanelUsableHeight`/
> `expandedUiAllowed`/`isCompactMorePoint`/`dragFollowAlpha`/`clampedViewCoordinateOffset*`/`objectDetailMarkerSize`/
> `compactQuickIdAt` 等**同时命中本组判据**，续作按"本组永久保留、A2-4/A2-6 只处理非保留读取项（读 `EDGE_MARGIN`/
> `screenSafeTopPixels`/`getUIContext` 者）"的口径收敛，避免重复评估。

**B-下沉组重排为 4 片（每片 ~30–45 个方法 / ~300–500 行）**：

| 片 | 范围（示例，开工以重测为准） | 方法数 | 估行数 | 去向 |
|---|---|---:|---:|---|
| **A2-3** | 域取值/标签/选项族：`searchCategoryOptions` `searchAllCategoryOptions` `searchDynamicCategoryOptions` `searchCategoryLabel` `searchCategoryIcon` `categoryModuleIdFor` `categoryObservationSubtitle` `objectDistanceNoticeText` `hecPointColor` `scriptMetaLine` `sessionHandoff` 等 | ~35 | ~300 | 各域 store 方法 或 `derive/<域>.ets` + 显式入参。**已完成（Phase A2-3，2026-10-04，单提交）：实测取 41 个**（搜索/目录 12 → `CatalogStore`/`SearchStore`；详情卡 12 → `ObjectDetailStore`/`ObjectMediaStore`；信息窗判断 3 → `InfoWindowStore`；脚本/时间文案 8 → `ScriptStore`/`TimeStore`；星历/会话/天文/星空文化 6 → 各域 store，`hecPointColor` → `derive/astro.ets` 显式入参）；宿主 `private` **710 → 669**、单体 **15,309 → 15,008**（−301）；`sessionHandoff` 为 void 动作剔除，`catalogHealthText/Color` 入 A-保留组未动；构建/契约绿，受影响 4 测试全绿，模拟器冒烟（搜索分类/时间/更多面板） |
| **A2-4** | 布局/几何（消费方组件自有数据）：`panelLeft` `bottomCardWidth` `baseBottomCardX/Y` `objectActionBarY` `locationMapWidth` `responsiveFoldAngle` `compactPanelUsableHeight` `expandedUiAllowed` `isCompactMorePoint` `dragFollowAlpha` `clampedViewCoordinateOffset*` `objectDetailMarkerSize` 等 | ~45 | ~350 | **组件文件级函数 + 显式入参**（A2-G）。**已完成（Phase A2-4，2026-10-04，单提交 `refactor(harmonyos): move the layout and geometry helpers into their consumers (A2-4)`）：开工重测 A2 余项 85 个 / 578 行；排除 6 热路径与已登记 A-保留 49 后取 30 个几何/布局 → `common/derive/geometry.ets`（文件级纯函数 + 显式入参，A1-6 模块续建）、2 个 → store（`panelSubtitle`→`TimeStore`、`scriptControlHeight`→`ScriptStore`）、1 个转发方法 `chromeRowWidth` 折叠删除；宿主 `private` 669 → 636（−33）、单体 15,008 → 14,861（−147）。停下：`bottomCardX/Y` 等 `clampedObjectCardOffset*`（A-保留）薄包装、`currentGuide/Step`（GuideStore 注释登记）留待别片。补登记 A-保留 +2（`dockTop`/`guideCardWidth`）。构建/契约绿、`test-ohos-polar-scope` 4/4、全量仅 §13.6 的 7 环境类失败、模拟器冒烟点按 Dock/缩放/面板返回存活** |
| **A2-5** | 大项与耦合项：`panelTitle`(101) `currentAstroCsvExport`(76) `hecLayoutPositions`(56) `objectDetailConnectorObstacles`(45) 等；**A2-4 后余项**：`bottomCardX/Y` `detailCardX/Y/Width/Height` `expandedDetailSummaryX/Y` `tabletInspectorX/Y` `objectActionBarX`（A-保留 `clampedObjectCardOffset*` 薄包装）、Astro 图表 bar 高度族（`altBarHeight` 等）、NightMode 颜色族（`nm*`）等 | ~35 | ~450 | 组件文件级 / 域 store（按读取字段定）。**注：`isDockPoint`/`isPanelBackPoint`/`isObjectDetailCardPoint`/`expandedDock*`/`chromeRowPosXRight`/`panelSubtitle` 已由 A2-4 迁出。** **已完成（Phase A2-5，2026-10-04，单提交 `refactor(harmonyos): sink the large and coupled derivation helpers (A2-5)`）：开工 `git log -1` = `7ccb9a7e3b`；重测 A2 余项 75 个 / 519 行，取 **45 个**——10 个零宿主读取的 hec 几何簇（`hecDistanceToRadius`/`hecOrbitVerticalRadius`/`hecPointDistance`/`hecPointHorizontalRadius`/`hecPointVerticalRadius`/`hecPointX`/`hecPointY`/`hecPointLeft`/`hecPointTop`/`hecLayoutPositions`）→ `common/derive/astro.ets`；`panelTitle`(101) → `derive/labels.ets` `panelTitleFor(...)` 显式入参；`celestialTitle`+`hecTitle`+`celestialPositionTitle` → `derive/labels.ets` `celestialTitle`（后两者删）；`currentAstroCsvExport`(76) → `AstroStore.astroCsvExport(wutTargets, wutObservationTime)`；天文图表尺寸/标签 18 个 → `AstroStore`；夜视配色 12 个 → `NightModeStore`。**停下**：`objectDetailConnectorObstacles`(45)（逐帧连接线组合：读 4 store 可见性 + `selectedObjectUiObstacles` + ~10 A-保留几何助手，下沉需 17 参数或 ~10 hook，且改动落在真机离线不可验的渲染路径）→ 登记为宿主控制器逻辑（组合型），留设备可用时几何合并片；`selectedObjectUiObstacles` 同因留。宿主单体 **14,860 → 14,456（−404）**、`private` **658 → 613（−45）**；`derive/astro.ets` 245→349、`derive/labels.ets` 342→453、`AstroStore` 1408→1578、`NightModeStore` 13→52。构建/契约绿（44 锚点），全量仅 §13.6 的 7 环境类失败，模拟器冒烟（Dock 五面板 + 三 hub 标题对照、天文计算面板，`pidof` 全程存活），真机数值/CSV/夜视刷新待验。**A2 进度：140 / 214。** |
| **A2-6** | **热路径收尾**：`isUiPoint`(84) `skyZoomButtonAt`(26) `dockActionAt`(14) `compactQuickIdAt`(9) `expandedSafeTargetPoint`(16) `inferredPanelRouteDirection`(16) + 残留 | ~12 | ~200 | 组件文件级 + **真机命中/截图对照**（真机离线时记为待验）。**已完成（Phase A2-6，2026-10-04，单提交 `refactor(harmonyos): close the A2 track - sink the residual and triage the hot paths`）：A2 收尾片。重测残留 B 组 **33**（排除 6 热路径与 A-保留 51），下沉 **20** / 登记 **13**。下沉：12 → store（`WutStore.observingDisplayName`、`SearchStore.wutTargetSubtitle`、`ScriptStore.{scriptPlaybackVisible,scriptSessionActive,scriptControlCompact,scriptKeyButtonWidth,replayTimelineMs}`、`ObjectDetailStore.{isObjectDetailCardRendered,objectInspectorModelTransform}`、`ObjectMediaStore.objectInspectorModelReady`、`LocationPickerStore.{locationSearchCountryName,locationResultContext,quickLocationSearch}`，跨 store 一律显式入参）+ 7 → `derive/actions.ets`（`panelRouteRoot`/`panelRouteParent`/`inferredPanelRouteDirection`/`matchesLocationSearch`/`locationSearchMatchScore`）+ 2 → `derive/geometry.ets`（`expandedDetailSummaryWidth`/`canShowExpandedDetailSummary`）。热路径逐个判定：`isUiPoint`/`skyZoomButtonAt`/`dockActionAt`/`expandedSafeTargetPoint` → **(b) 宿主控制器登记**；`compactQuickIdAt` → (b) 已含 A-保留 51；`inferredPanelRouteDirection` → **(a) 下沉**（实测零宿主读取，纯函数，模拟器实测路由正常）。宿主 `private` **613 → 593**、单体 **14,456 → 14,347（−109）**；构建/契约绿，全量仅 §13.6 的 6 环境类失败，模拟器冒烟（缩放 ± / Dock 五项 / 面板开合 / 更多功能→观测工作区→返回）存活。**A2 进度：160 / 214，A2 轨道收尾。** |

**合计**：A2 = 已完成 **160**（A2-1 6 + A2-2 15 + A2-3 41 + A2-4 33 + A2-5 45 + A2-6 20）+ A-保留 **51**（登记，含 A2-4 补登记 2，见下）+ 热路径 (b) 登记 **4**（`isUiPoint`/`skyZoomButtonAt`/`dockActionAt`/`expandedSafeTargetPoint`；`compactQuickIdAt` 已含 51）+ 宿主控制器登记 **13**（`objectDetailConnectorObstacles` + 布局薄包装族 + `skyCultureColorOptions/ActiveColorTarget` + `shouldRefreshPolarScope` + `currentGuide/Step`）+ 未处理 **0**。**A2 轨道至此收尾**（宽口径 214 系 §2.12；严格重测余量见 §14.3.1 注，本片以严格口径判定，余项已穷尽）。

**A2 轨道收尾结论（2026-10-04，A2-6 后）**：A2 六片产出 —— 12 个域 store 方法增量 + `common/derive/{media,geometry,astro,labels,actions}` 五个纯函数模块（media 5 / geometry 15 / astro 35 / labels 15 / actions 17 个函数）。宿主单体自 A2 起点 **15,636 → 14,347（−1,289，−8.2%）**、`private` **942 → 593（−349）**（§14.0 目标 ≈640，**已超额达成**）；宿主 `private load*` 由 72 → **3**（`loadSkyCultureDetails` 登记保留 + `loadFov`/`loadPlanetPositions` 非 A/B 目标；§14.0 目标 ≈11，**达成**）。A2 未处理项 = 0；刻意保留项均为宿主控制器逻辑（命中层/面板路由/逐帧几何），判据与理由见 §2.7.1.1 与本片 CHANGELOG。

**A-保留组登记（进 §2.7.1 的"宿主控制器逻辑（永久保留）"子类；49 个为 A2-3 开工逐名重测全量，非原估 31；A2-4 补登记 +2 = `dockTop` / `guideCardWidth`，合计 51）**：判据固定为"其**全部宿主字段读取项均 ∈ §2.7.1 保留集合**，且**不读任何 store**（`this.EDGE_MARGIN` 等未登记常量不计入保留集合）"。全量 51 名与逐条命中说明写入 `ARKTS-PAGES-REFACTOR-STATE-REVIEW.md` §2.7.1。**不要**改这些方法。

**放宽后的片级约束**：每片 ≤ ~45 个方法、≤ ~500 行变更、≤ ~3 个文件族；其余仍守 §14.8 七条与 §13.1/§13.2/§13.3。

### 14.4 轨道 B1：24 个可直接沉（6 片，最优先）

| 片 | 目标 store | 方法（行数） |
|---|---|---|
| B1-1 | TelescopeStore | `loadOculars`(75) **—— 已完成（Phase B1-1，2026-10-04）** |
| B1-2 | LayerViewStore ＋ ToolsStore | ~~`loadTrailDisplaySettings`(13) `loadOrbitDisplaySettings`(12) `loadLandscapeList`(12) ＋ `loadAngleMeasure`(11) `loadAboutInfo`(9) `loadLog`(7)~~ **已完成（Phase B1-2，2026-10-04；`loadTrailDisplaySettings`/`loadOrbitDisplaySettings`/`loadLandscapeList` → `LayerViewStore`，`loadLog` → `ToolsStore`，复用同一 `HostCommandPort`；`loadAboutInfo` 已在 AB-0 完成；`loadAngleMeasure`(11) **未搬**——其请求序号 `angleMeasureRequestId` 与宿主动作方法 `toggleAngleMeasure` 共享，属 B2/B3，留待同片下沉）** |
| B1-3 | CatalogStore ＋ SearchStore | ~~`loadStarCatalogs`(18) ＋ `loadConstellationNavigation`(27)~~ **已完成（Phase B1-3，2026-10-04；`loadStarCatalogs` → `CatalogStore`，复用同一 `HostCommandPort`；`loadConstellationNavigation`(27) **未搬**——其代际计数器 `languageRefreshSerial` 与宿主 `fetchSuggestions`/`loadObjectCatalogCategories` 及 `setLanguage` 刷新链共享，属 B2/B3，留待与搜索域同片下沉）** |
| B1-4 | MeteorStore / NavStarsStore / ArchaeoStore / MosaicStore | ~~`loadMosaicCamera`(24)~~ → `MosaicStore`、~~`loadArchaeoLines`(30)~~ → `ArchaeoStore` **已完成（Phase B1-4，2026-10-04）**；`loadNavStars`(31)、`loadMeteorShowers`(33) **主动停下**（依赖宿主代际计数器 `navStarsMutationId` / 与 `setMeteorShowersFlag` 共享 `meteorShowersLoadRequestId`，登记 B2/B3） |
| B1-5 | PluginStore / CommandStore / EquationOfTimeStore / NebulaTextureStore | ~~`loadPluginList`(34) `loadCommandCatalog`(28) `loadEquationOfTime`(19) `loadNebulaTextureStatus`(15)~~ **已完成（Phase B1-5，2026-10-04；4 个加载器经逐名复测全为真 B1，无 B2/B3 停下项；`loadPluginList`→`PluginStore`、`loadCommandCatalog`→`CommandStore`、`loadEquationOfTime`→`EquationOfTimeStore`、`loadNebulaTextureStatus`→`NebulaTextureStore`，复用同一 `HostCommandPort`，宿主 −4 `private load*`（59 → 55）、单体 17,459 → 17,364）** |
| B1-6 | Location / SessionTool / Satellite / Script / SkyCultureSettings / ObjectDetail / Overlay | `loadSavedLocations`(20) `loadPlanetList`(11) `loadSatelliteSources`(10) `loadRecordings`(6) `loadSkyCultureConstellationSelectionFlags`(8) `loadObjectInfo`(18) `loadPointerCoordinates`(23) **—— 已完成（Phase B1-6，2026-10-04，B1 收尾）**：7 个加载器逐名复测**全为真 B1、无 B2/B3 停下项**；分别下沉 `LocationStore`/`SessionToolStore`/`SatelliteStore`/`ScriptStore`/`SkyCultureSettingsStore`/`ObjectDetailStore`/`OverlayStore`，复用同一 `HostCommandPort`。`loadSavedLocations` 读 AppStorage（无桥，port 预留）；`loadObjectInfo` 在宿主内**零调用点**（既有死代码，按计划表仍下沉）；其余 5 个为 `callInteractive`/`callNativeWhenReady` 桥加载器（指针坐标重试档 0/100/15 逐字保留）。宿主 −7 `private load*`（56 → 49）、单体 17,364 → 17,277（−87）。**B1 轨道 24 个至此全部结清（20 下沉 + 4 转 B2/B3）。** |

> 行号/行数取 §2.13 实测；开工重测。`loadOculars`(75) 收益最大，**建议作为 B1 首片**（在 §14.1 enabler 试点之后）。

### 14.5 轨道 B2：35 个（Astro 19 一片或两片；其余 16 四片）

- **B2-Astro（19，1–2 片）**：`loadAlmanac` `loadAltAzCurve` `loadAnnualElevation` `loadAstroTab` `loadCelestialPositions` `loadEclipses` `loadEphemeris` `loadHeliocentricPositions` `loadLunarElongation` `loadObservabilityCalendar` `loadPhenomena` `loadPlanetaryTransits` `loadPlanetCalc` `loadPlanetPairDistance` `loadPlanetTimeSeries` `loadRTS` `loadRtsCalendar` `loadTonightAstro` `loadWutTargets`。
  **同片搬域助手**（`updateAstroCalcSnapshot`/`beginGraphLoad`/`finishGraphLoad`/`resolveGraphStartJD`/`clearRtsSelectionResults`/`hasSelectedObject`/`hecLayoutPositions`/`wutCategoryTitle`/`planetPairBodyName`/`updatePlanetPairDistanceRanges`/`updatePlanetTimeSeriesRanges`/`publishAstroPanelState`）——多为域内逻辑；`publishAstroPanelState` 走 `onChanged` 注入。
  **已完成（Phase B2A，2026-10-04；单提交 `refactor(harmonyos): sink the astro cluster loaders into their stores`）**：19 个加载器 **全部下沉、停下 0**——18 个 + 域助手 → `state/AstroStore.ets`（新增 `export interface AstroHostHooks` 11 法：`hasSelectedObject`/`selectedObjectName`/`wutCategory`/`wutObservationTime`/`loadWutTargets`/`ephemerisCustomStartJD`/`fmtDateTime`/`hecLayoutPositions`/`loadPlanetPositions`/`loadMoonPhases`/`loadAstroCalcContext` 经 `attachHooks` 具名注入），`loadWutTargets` + `wutCategoryTitle` → `state/WutStore.ets`。序号/代际随加载器搬入（`rtsRequestSequence`/`rtsCalendarLoadSequence`/`ephemerisLoadSequence`/`planetCalcRequestSequence`/`planetPairDistanceRequestSequence`/`graphLoadSequence`/`eclipseLoadSequence`/`planetaryTransitRequestSequence`/`phenomenaRequestSequence`/`almanacRequestSequence`/`hecPositionsRequestSequence`/`celestialPositionsRequestSequence`/`wutRequestSequence`）；`rtsCalendarLoadSequence` 与 `markRtsCalendarForRegeneration`、`eclipseLoadSequence` 与 `reloadEclipses` 共享，故二者同片搬入 store（规则 3）。宿主 `private load*` **49 → 30**、单体 **17,276 → 16,433**（−843）；`AstroStore` 172 → 1,188 行、`WutStore` 22 → 121 行。构建/契约绿；`test-ohos-astro-motion` 9/9、`test-ohos-wut-layout` 4/4、`verify-ohos-julian-date` 通过；全量扫描仅 §13.6 的 7 个环境类失败；模拟器冒烟（UI-only）三组与全部标签切换无崩溃，桥回包渲染待真机。
- **B2-其余（16，4 片）**
  | 片 | 方法 | 额外注入 |
  |---|---|---|
  | B2R-1 媒体 | `loadObjectInspectorModelRawTexture`(72) | `commit/fail/decode` 媒体助手 | **已完成（Phase B2R-1，2026-10-04）**：真 B2（无桥 / 无 `publish*` / 无 UI 上下文）；因 `fileIo`、`image` 属 NAPI，按 §14.8 规则 2「改为注入职责」下沉 `ObjectMediaStore` —— 新增 `ObjectMediaHostHooks`（4 法：`commit`/`fail`/`decode` + **新增 `readRawSidecar`** 承接内联 fileIo），宿主新增 `private readRawSidecar`；宿主 `private load*` 30 → 29、单体 16,433 → 16,397（−36）；构建/契约绿，5 个媒体测试全绿，模拟器冒烟存活，侧车/解码/渲染链路待真机 |
  | B2R-2 设置 | `loadConfigurationSettings`(49)、`loadObserverInfo`(17)、`loadTimeExtras`(9) | `applySelectedInfoMode`、`applyTimeSettings`、`applyAtmosphereResponse`、`syncNightModeFromEngine`、时区助手 | **已完成（Phase B2R-2，2026-10-04）**：3/3 下沉、停下 0——`loadConfigurationSettings` → `TimeSettingsStore`（跨 5 store：本域时间格式 + `TimeSettingsHostHooks` 19 法，其中 ViewSettings 3 / Navigation 9 / Ephemeris 2 组 / InfoWindow 3 / `applySelectedInfoMode`/`applyTimeSettings` 注入）、`loadObserverInfo` → `LocationPickerStore`（`LocationPickerHostHooks` 2 法）、`loadTimeExtras` → `TimeStore`（`TimeHostHooks` 2 法）；`approximateTimeZoneDisplay` 逐字迁入 `common/derive/labels.ets`（纯函数，宿主与 store 共用）。跨 store 写入不允许 store 互相持有，故按 §14.5「主要归属 store + 其余经 hooks setter」；`syncNightModeFromEngine` 因共享宿主 `pendingNightMode` 待定窗口而保留宿主注入（未登记 B3）。宿主 `private load*` 29 → 26、单体 16,397 → 16,361（−36）；构建/契约绿，5 个受关注测试全绿（settings-choice-motion 4/4 / information-policy 3/3 / distance-ui 5/5 / skyculture-refresh 5/5 / cli-response 4/4），模拟器冒烟存活、设置三页签 + 时间 + 位置面板渲染正常；桥回包真实写入链路待真机 |
  | B2R-3 星空文化 | `loadSkyCultureList`(42)、`loadSkyCultureVisualSettings`(40)、`loadSkyCultureTerritoryMap`(21)、`loadSkyCultureMakerDraft`(21) | `loadSkyCultureDetails`、`skyCultureActiveColorTarget`、`drawSkyCultureTerritoryMap`、`applySkyCultureMakerDraft`、`ensurePluginLoaded`、`skyCultureMakerDraftFromResponse` | **已完成（Phase B2R-3，2026-10-04）**：4/4 下沉、停下 0 —— `loadSkyCultureList` → `SkyCultureViewStore`（+`SkyCultureViewHostHooks` 2 法：`invalidateSkyCultureDetails`/`loadSkyCultureDetails`）、`loadSkyCultureVisualSettings` / `loadSkyCultureTerritoryMap` → `SkyCultureSettingsStore`（+`SkyCultureSettingsHostHooks` 3 法：`skyCultureActiveColorTarget`/`drawSkyCultureTerritoryMap`/普查补出的 `skyCultureCurrentId`）、`loadSkyCultureMakerDraft` → `SkyCultureMakerStore`（+`SkyCultureMakerHostHooks` 3 法）；`loadSkyCultureDetails` **未搬**（保持 §14.6 B3 登记，经 hooks 调用）；序号 `skyCultureListRequestId` 搬入 store；宿主 `private load*` 26 → 22、单体 16,361 → 16,255；构建/契约绿，`test-ohos-skyculture-refresh` 5/5 / `test-ohos-skyculture-text` 4/4，模拟器冒烟存活，桥回包渲染待真机 |
  | B2R-4 存储/检索/望远镜 | `loadObjectCatalogCategories`(32)、`loadObservingListFromStorage`(19)、`loadBookmarks`(15)、`loadBookmarksFromStorage`(13)、`loadRecordingByName`(11)、`loadScriptList`(8)、`loadSelectedSatellitePasses`(5)、`loadTelescopeControlStatus`(13) | `catalogIconForModule`、`loadCategoryObjects`、`publishSearchBrowserState`、`getUIContext`、`parseObservingList`、`saveBookmarksToStorage`、`flashHint`、`setScriptMetadata`、`requestSatellitePasses`、`lx200Payload`、`scheduleTelescopeLivePosition`（**含定时器 → store 需自持 start/stop**） | **已完成（Phase B2R-4，2026-10-04，B2 收尾）**：8 个加载器 **7 下沉 + 1 转 B3** —— `loadObjectCatalogCategories` → `CatalogStore`（+`CatalogHostHooks` 7 法：`languageSerial`/`pendingPluginCatalogId`/`clearPendingPluginCatalogId`/`searchCategory`/`categoryModuleId`/`loadCategoryObjects`/`publishSearchBrowserState`；`catalogIconForModule` 直连 `derive/catalog`，宿主 `languageRefreshSerial` 单序号不搬、调用点显式传入）、`loadObservingListFromStorage` → `ObservingListStore`（+`ObservingListHostHooks` 2 法，Preferences I/O 整体注入，`parseObservingList` 直连模块）、`loadBookmarks` / `loadBookmarksFromStorage` → `BookmarkStore`（+`BookmarkHostHooks` 2 法，新增 `attachPort`）、`loadRecordingByName` / `loadScriptList` → `ScriptStore`（+`ScriptHostHooks.flashHint`；`setScriptMetadata` 同片搬入 store 方法）、`loadSelectedSatellitePasses` → `ObjectDetailStore`（+`ObjectDetailHostHooks` 2 法：`selectedObjectIsArtificialSatellite`/`requestSatellitePasses`）；**`loadTelescopeControlStatus` 主动停下登记 B3**（live-position 定时器簇与 `applicationInForeground`/`panelVisible`/`activePanel` 及 29 处宿主动作站点交织，见 §14.6）。宿主 `private load*` **24 → 17**、单体 **16,255 → 16,207**（−48）；构建/契约绿，13 个受影响测试全绿，模拟器冒烟（观测工作区/脚本/搜索面板开合，`pidof` 全程存活），桥回包与 Preferences 真实读写、定时器收敛待真机 |`

### 14.6 轨道 B3：11 个（先解其保留裸字段，再按 B1 手法下沉）

| 加载器 | 行的保留裸字段 | 处理方向 |
|---|---|---|
| `loadSkyCultureDetails`(69) | `skyCultureArtStates`（渐进写入） | 该字段登记为"高频逐帧"→**保留宿主**，加载器改为经注入回调上报 |
| `loadSatellites`(55) | `satelliteListElapsedMs`/`satelliteLoadTimer`（计时器） | 计时器移入 store（自持 start/stop）或注入 |
| `loadMoreCategoryObjects`(51) / `loadCategoryObjects`(35) | `categoryOffset`（跨页游标）、`satelliteCatalogReady` | **已完成（Phase B3-3，2026-10-04）**：游标 `categoryOffset` + 代际计数 `categoryRequestSerial` + 标志 `satelliteCatalogReady` + 常量 `CATEGORY_PAGE_SIZE` 随两加载器搬入 `SearchStore`（单一持有者）；宿主助手 `categoryModuleIdFor`/`publishSearchBrowserState`/`ensurePluginLoaded`/`celestialTitle`/`celestialSubtitle` 经 `SearchHostHooks` 回注 |
| `loadMoonPhases`(35) / `loadAstroCalcContext`(35) / `loadPolarScopeData`(19) | 请求进度 / 进行中标志 | **已完成（Phase B3-2，2026-10-04）**：请求进度 / 进行中标志与其请求序号一并搬入对应 store —— `loadMoonPhases`+`moonPhaseLoadingDays`/`moonPhaseRequestId` → `AstroStore`；`loadAstroCalcContext`+`astroContextRequestPending`/`astroContextRequestId` → `AstroStore`；`loadPolarScopeData`+`polarScopeRequestPending`/`polarScopeDataRequestId` → `PolarScopeStore`。宿主只留计时器（`astroContextTimer`/`polarScopeTimer`）调用 store 加载器，作废在途请求改由新增 `AstroStore.cancelAstroCalcContext()` / `PolarScopeStore.cancelPolarScopeRequest()` 承接；撤除 `AstroHostHooks.loadMoonPhases`/`loadAstroCalcContext`，新增 `PolarScopeHostHooks.shouldRefreshPolarScope()` |
| `loadVideoRecordingState`(14) | `stopVideoStatePolling`（定时器收口） | 定时器移入 ScriptStore |
| `loadSearchHistoryFromStorage`(13) | `searchHistory`（跨域共用） | **已完成（Phase B3-3，2026-10-04）**：`searchHistory` 单一持有者移入 `SearchStore`（普查：读写点仅宿主 `searchObject()`，无渲染/他 store 读取，故宿主直接写 store、无需 hooks 回注）；Preferences 读写经 `SearchHostHooks.readSearchHistoryStorage`/`writeSearchHistoryStorage` 注入；`saveSearchHistoryToStorage` 同片搬入 |
| `loadScenery3d`(12) | `scenery3dCurrentId`（引擎自用，已登记） | 保持登记；加载器只读/只上报 |
| `loadCatalogHealth`(9) | `catalogHealthLoaded`/`catalogManifestPresent`（跨域共用） | 保持登记；加载器返回值经注入回调 |

| `loadTelescopeControlStatus`(13) | live-position 定时器簇 `lx200LivePositionTimer`/`lx200LivePositionRequestPending`/`lx200LivePositionRequestId` + 宿主 UI 状态 `applicationInForeground`/`panelVisible`/`activePanel` | B2R-4 主动停下：`scheduleTelescopeLivePosition`(12 调用点)/`stopTelescopeLivePosition`(17) 与 `refreshTelescopeLivePosition`/`syncTelescopeLivePosition`/`setTelescopeLivePosition` + `lx200Payload`/`applyTelescopeProfiles`/`applyTelescopeEndpointStatus` 交织 → 定时器整体移入 `TelescopeStore`（自持 start/stop）并注入 `shouldRefreshTelescopePosition` 谓词后再下沉 |

> 每处理完一项即从本表移除；表中"处理方向"若与 §2.7.1 登记冲突，**以 §2.7.1 为准**（那是已验证的保留决定）。

> **B3-1 已完成（Phase B3-1，2026-10-04，单提交）**：结清「B1/B2 因 §14.8 规则 3 主动停下」的 **4 个共享序号簇** —— `loadAngleMeasure`（序号 `angleMeasureRequestId`，配对写方 `toggleAngleMeasure`）→ `ToolsStore`；`loadNavStars`（`navStarsLoadRequestId`/`navStarsMutationId`，配对写方 `setNavStarsSetting` + 助手 `applyNavStarsSetting`）→ `NavStarsStore`；`loadMeteorShowers`（`meteorShowersLoadRequestId`，配对写方 `setMeteorShowersFlag`）→ `MeteorStore`；`loadConstellationNavigation`（代际 `languageRefreshSerial`，配对方 `setLanguage` 刷新链 + 读点 `fetchSuggestions`/`loadObjectCatalogCategories`）→ `SearchStore`，代际字段移入其真正归属 `LanguageStore`（方案 a：单一持有者 + 无第二份副本；跨域读者经只读 hooks / 显式传参）。手法：加载器与配对写方**同片搬入同一 store**，序号/代际随之下沉、宿主零副本零双写；`flashHint` 经 `ToolsHostHooks` 注入、语言代际经 `SearchHostHooks.languageSerial()` 在回包时读实时值。宿主 `private load*` 18 → 14、单体 16,207 → 16,035（−172）。构建/契约绿，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（打开流星雨面板并点按「启用」开关、`pidof` 全程存活）。**B3 剩余**：本表 9 行全部未动（`loadSkyCultureDetails`/`loadSatellites`/`loadMoreCategoryObjects`+`loadCategoryObjects`/`loadMoonPhases`+`loadAstroCalcContext`+`loadPolarScopeData`/`loadVideoRecordingState`/`loadSearchHistoryFromStorage`/`loadScenery3d`/`loadCatalogHealth`/`loadTelescopeControlStatus`）。

> **B3-2 已完成（Phase B3-2，2026-10-04，单提交）**：结清「请求进度 / 进行中标志」组 **3 个加载器** —— `loadMoonPhases`（+`moonPhaseLoadingDays`/`moonPhaseRequestId`）、`loadAstroCalcContext`（+`astroContextRequestPending`/`astroContextRequestId`）→ `AstroStore`；`loadPolarScopeData`（+`polarScopeRequestPending`/`polarScopeDataRequestId`）→ `PolarScopeStore`。手法：逐字段普查确认这些裸字段**仅被加载器与其停止计时器读写**（面板只读既有 store 字段），故按「单一持有者 + 无第二份副本」随加载器搬入归属 store；宿主只留计时器（`astroContextTimer`/`polarScopeTimer`）调用 store 加载器，作废在途请求改由 `AstroStore.cancelAstroCalcContext()`（只递增序号、不复位 pending）/ `PolarScopeStore.cancelPolarScopeRequest()`（复位 pending + 递增序号）承接原停止计时器语义；极轴镜「是否应刷新」谓词（读宿主 `applicationInForeground`）经新增 `PolarScopeHostHooks.shouldRefreshPolarScope()` 注入；撤除 `AstroHostHooks.loadMoonPhases`/`loadAstroCalcContext`（`AstroStore.loadAstroTab` 改 `this.loadXxx()`）。宿主 `private load*` **14 → 11**、单体 **16,035 → 15,944**（−91）；`AstroStore` 1,187 → 1,278、`PolarScopeStore` 31 → 96。构建/契约绿，`test-ohos-astro-motion` 9/9 / `test-ohos-polar-scope` 4/4，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（打开天文计算→月相、极轴镜叠层并点按翻转开关，`pidof` 全程存活）。**B3 剩余**：本表 **8 行**（`loadSkyCultureDetails`/`loadSatellites`/`loadMoreCategoryObjects`+`loadCategoryObjects`/`loadVideoRecordingState`/`loadSearchHistoryFromStorage`/`loadScenery3d`/`loadCatalogHealth`/`loadTelescopeControlStatus`）。

> **B3-3 已完成（Phase B3-3，2026-10-04，单提交）**：结清「搜索 / 分页 / 历史」族 **3 个加载器** —— `loadCategoryObjects`(35) + `loadMoreCategoryObjects`(51)（+ 游标 `categoryOffset`、代际计数 `categoryRequestSerial`、标志 `satelliteCatalogReady`、常量 `CATEGORY_PAGE_SIZE`）、`loadSearchHistoryFromStorage`(13)（+ 同片 `saveSearchHistoryToStorage` 与 `searchHistory`）→ `SearchStore`。跨域字段按「单一持有者 + 无第二份副本」：`searchHistory` 读写点仅宿主 `searchObject()`（无渲染 / 他 store 读取）故宿主直接写 store、无需 hooks 回注；`satelliteCatalogReady` 仅分类加载器读写、卫星域未消费，留 `SearchStore`。新增 `SearchHostHooks` 7 法（`publishSearchBrowserState`/`categoryModuleIdFor`/`ensurePluginLoaded`/`celestialTitle`/`celestialSubtitle`/`readSearchHistoryStorage`/`writeSearchHistoryStorage`），宿主存储助手替换为 `readSearchHistoryStorage`/`writeSearchHistoryStorage` 适配器。宿主 `private load*` **9 → 6**（**校正**：B3-2 记「14 → 11」与 `git show HEAD:` 实测 9 不符，本片以实测为准）、单体 **15,944 → 15,859**（−85）、`SearchStore` 113 → 280。构建/契约绿，`test-ohos-search-browser` 3/3 / `test-ohos-constellation-lookup` 2/2，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（Dock 开搜索面板、选分类「月球/恒星」标签实时刷新、点击分页失败重试，`pidof` 全程存活）。**B3 剩余**：本表 **6 行**（`loadSkyCultureDetails`/`loadSatellites`/`loadVideoRecordingState`/`loadScenery3d`/`loadCatalogHealth`/`loadTelescopeControlStatus`）。

> **B3-4 已完成（Phase B3-4，2026-10-04，单提交）**：结清「定时器族」**3 个加载器** —— `loadSatellites`(55)（+ 请求序号 `satelliteListRequestId`、90ms 去抖 `satelliteLoadTimer`、合并标志 `satelliteLoadIncludeSources`、代际 `satelliteFlagMutationId`、命名耗时 `satelliteListElapsedMs`）→ `SatelliteStore`（`attachPort` 的 `onChanged` 带 `error` 形参，逐字保留 CLI 失败串）；`loadVideoRecordingState`(14)（+ `start/stopVideoStatePolling` + `videoStateTimer`，450ms）→ `ScriptStore`（`ScriptHostHooks` 新增 `stopVideoRecording()`）；`loadTelescopeControlStatus`(13) + live-position 定时器簇（`lx200LivePositionTimer`/`...Pending`/`...Id` + `shouldRefreshTelescopePosition` + `stop/schedule/refresh/sync/setTelescopeLivePosition` + `lx200Payload` + `applyTelescopeProfile(s)` + `applyTelescopeEndpointStatus`）→ `TelescopeStore`（新增 `TelescopeHostHooks.shouldRefreshTelescopePosition()`，宿主保留谓词只读注入）。手法：**定时器句柄/标志/计数随加载器移入 store，store 自持 start/stop**（§14.10），调用点改 `this.<store>.X`；函数体逐字搬入，桥重试档 0/100/15 与 onFailure / 1000/1800/500ms 延迟 / `markStale` / reqId 作废语义逐字保留。宿主 `private load*` **8 → 5**（全量 `private load[A-Za-z0-9_]*(` 口径；本片 −3）、单体 **14,885 → 14,681**（−204）、`SatelliteStore` 93 → 174、`ScriptStore` 150 → 191、`TelescopeStore` 254 → 429。构建/契约绿，`test-ohos-satellite-panel` 7/7，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（Dock→更多功能→天体数据与扩展→卫星面板开合数轮，`pidof` 全程存活、关闭后 hilog 无空转）。**B3 剩余**：本表 **3 行**（`loadSkyCultureDetails` / `loadScenery3d` / `loadCatalogHealth`，均为「保持登记」项）。
> **B3-5 已完成（Phase B3-5，2026-10-04，B3 收尾片，单提交）**：结清本表最后 **3 行** —— `loadScenery3d`(12) → `SceneryStore`（新建 `SceneryHostHooks.setScenery3dCurrentId`，宿主保留 §2.7.1「引擎自用 / 已登记约定」字段 `scenery3dCurrentId`）；`loadCatalogHealth`(9) → `CatalogStore`（`CatalogHostHooks` 新增 `setCatalogHealthLoaded`/`setCatalogManifestPresent`/`setSatelliteCatalogHealth`，宿主保留「跨域共用」字段 `catalogHealthLoaded`/`catalogManifestPresent`）；**`loadSkyCultureDetails`(69) 永久保持登记**——请求序号 `skyCultureDetailsRequestId` 与 `selectSkyCulture`/锚点系统/美术解码管线共享，且调 5 个宿主助手 + 5 处跨 store 方法 + 写「高频逐帧」字段 `skyCultureArtStates`，下沉须连带重写整条管线，故按 (b) 永久保留（现状 store 经 hooks 调用，无代码改动）。手法：函数体逐字搬入，`callNativeWhenReady`→`port.requestWhenReady`、登记字段写入→`hooks.set*` 回注；宿主删 2 方法、改 5 调用点、补 2 处 `attach*`，零双写。宿主 `private load*` **5 → 3**、单体 **14,681 → 14,673**；`SceneryStore` 18 → 66、`CatalogStore` 144 → 172。构建/契约绿，受影响 5 个测试全绿，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（卫星 / 3D地景 + 开关 / 图层文化标签，`pidof` 全程存活）。**B3 总账（16 = §2.13 的 11 + B1 转入 4 + B2 转入 1）：已下沉 15 + 保持登记 1（`loadSkyCultureDetails`）+ 未处理 0；B3 轨道清空。全队列宿主 `private load*` 剩 3（`loadSkyCultureDetails` 登记项 + `loadFov`/`loadPlanetPositions` 非 A/B 目标）。**


### 14.7 队列总表（38 片，建议顺序）

| ID | 轨道 | 内容 | 前置 | 状态 |
|---|---|---|---|---|
| AB-0 | B 前置 | `bridge/CommandPort.ets` + `loadAboutInfo` 试点 | — | **已完成（Phase AB-0，2026-10-04；新增 `bridge/CommandPort.ets` 33 行纯接口 + 具名适配器 `HostCommandPort` 注入；`loadAboutInfo` 迁入 `ToolsStore`，宿主零残留/零双写；构建/契约 intact；模拟器端口链路实证，`about*` 数据渲染待真机）** |
| A1-1…A1-7 | A1 | 91 个纯函数 → `common/derive/*.ets`（7 片） | — | **已完成（2026-10-04，7 片全部收尾；§2.12 的 91 项 84+7 全部迁出、残留 0、剔除到 A2 = 0）**。**A1-1 已完成（2026-10-04；`common/derive/gyro.ets` 12 个陀螺/四元数/向量纯函数迁出，宿主 −12 `private`、−91 行，零残留/零双写，构建/契约绿，模拟器冒烟，真机陀螺待验）**；**A1-2 已完成（2026-10-04；`common/derive/astro.ets` 25 个天文纯函数迁出，宿主 −25 `private`、−188 行，AstroPanel 30 处改直连模块并瘦身接口/noop 各 13 项，拆 A1-2a/A1-2b 两提交，构建/契约绿，模拟器 astro 面板分组/标签实时刷新实证，真机数值待验）**；**A1-3 已完成（2026-10-04；`common/derive/labels.ets` 12 个标签/文案纯函数迁出，宿主 −12 `private`、−280 行，5 个面板改直连模块并同片删除成员与宿主注入，构建/契约绿，模拟器冒烟，真机文案内容待验）**；**A1-4 已完成（2026-10-04；`common/derive/skycult.ets` 135 行 10 个星空文化/杂项纯函数迁出，宿主 −10 `private`、−119 行，`SettingsPanel` 改直连模块、成员与宿主注入同片删除，构建/契约绿，模拟器冒烟，真机数值与设置文案待验）**；**A1-5 已完成（2026-10-04；`common/derive/actions.ets` 143 行 12 个动作表/文案纯函数迁出，宿主 −12 `private`、−120 行，5 个 `*Actions` 实测均静态数组、零宿主状态读取故无剔除项，宿主 36 处调用点改直连模块，构建/契约绿，模拟器验证 Dock + 6 个 `#more-action-*` + `#hub-action-*`，真机望远镜/会话/位置数值待验）**；**A1-6 已完成（2026-10-04；`common/derive/geometry.ets` 60 行 13 个几何/触摸/布局纯函数迁出，宿主 −13 `private`、−55 行，13 名全零宿主读取无剔除项，`AstroPanel` 的 `azBarHeight` 改直连模块，`test-ohos-model-scroll` 夹具改形参注入，构建/契约绿，模拟器验证缩放按钮/Dock/面板切换，真机缩放与连接线几何待验）**；**A1-7 已完成（2026-10-04；收尾片。按 §2.12 判据重测宿主余项恰 7 个且全部零宿主依赖（剔除到 A2 = 0）；新建 `common/derive/catalog.ets` 86 行 5 个纯函数，`phenomenonCaption` 并入 `derive/astro.ets`、`timezoneDisplayName` 并入 `derive/labels.ets`；宿主 −7 `private`、−135 行，`AstroPanel` 4 个接口成员/noop/宿主注入同片删除并改直连模块；构建/契约绿，`test-ohos-wut-layout` 4/4 + `test-ohos-astro-motion` 9/9，模拟器冒烟打开天文面板无崩溃，真机 WUT/caption/目录图标/时区文案待验）** |
| B1-1…B1-6 | B1 | 24 个加载器 → store（6 片） | AB-0 | **B1-1 已完成（2026-10-04；`loadOculars` 迁入 `TelescopeStore`，复用同一 `HostCommandPort` 实例；`CommandPort.requestWhenReady` 追加可选重试参数以逐字保留 0/100/15；宿主 −2 `private`（loadOculars + ocularLoadRequestId）、`load*` 66→65、单体 17643→17571；构建/契约绿，模拟器冒烟存活；getOculars 回包与渲染待真机）**；**B1-2 已完成（Phase B1-2，2026-10-04；`loadLandscapeList`/`loadOrbitDisplaySettings`/`loadTrailDisplaySettings` → `LayerViewStore`、`loadLog` → `ToolsStore`，复用同一 `HostCommandPort`，宿主 −4 `private load*`（67 → 63）、单体 17,570 → 17,526；`loadAngleMeasure` 因请求序号与 `toggleAngleMeasure` 共享而**主动停下**，登记为 B2/B3；构建/契约绿，模拟器冒烟存活且图层「地景」标签路径可达；回包渲染待真机）**；**B1-3 已完成（Phase B1-3，2026-10-04；`loadStarCatalogs` → `CatalogStore`，复用同一 `HostCommandPort`，宿主 −1 `private load*`（63 → 62）、单体 17,525 → 17,510，`CatalogStore` 22 → 75 行；`loadConstellationNavigation` 因代际计数器 `languageRefreshSerial` 与搜索结果域 `fetchSuggestions`/`loadObjectCatalogCategories`、`setLanguage` 刷新链共享而**主动停下**，登记为 B2/B3；构建/契约绿，模拟器冒烟存活且「更多功能 → 天体数据与扩展 → 星表下载」路径可达，`getStarCatalogs` 出站重试实证；回包渲染待真机）**；**B1-4 已完成（Phase B1-4，2026-10-04；`loadMosaicCamera` → `MosaicStore`、`loadArchaeoLines` → `ArchaeoStore`，复用同一 `HostCommandPort`，宿主 −2 `private load*`（62 → 60）、单体 17,509 → 17,458，`MosaicStore` 24 → 87 行、`ArchaeoStore` 37 → 105 行；`loadNavStars` 因代际计数器 `navStarsMutationId` 与宿主动作 `setNavStarsSetting` 共享、`loadMeteorShowers` 因请求序号 `meteorShowersLoadRequestId` 与 `setMeteorShowersFlag` 共享，二者**主动停下**登记 B2/B3；构建/契约绿，模拟器冒烟存活且「流星雨 / 星表下载」路径可达；回包渲染待真机）**；**B1-5 已完成（Phase B1-5，2026-10-04；`loadPluginList`→`PluginStore`、`loadCommandCatalog`→`CommandStore`、`loadEquationOfTime`→`EquationOfTimeStore`、`loadNebulaTextureStatus`→`NebulaTextureStore`，复用同一 `HostCommandPort`；4 个加载器逐名复测**全为真 B1、无停下项**；宿主 −4 `private load*`（59 → 55）、单体 17,459 → 17,364，`PluginStore` 20→88、`CommandStore` 18→82、`EquationOfTimeStore` 12→69、`NebulaTextureStore` 28→79；构建/契约绿，`test-ohos-plugin-panel-state` 4/4，模拟器冒烟存活且「命令控制 / 插件管理 / 时间」路径可达；四域桥回包渲染待真机）**；**B1-6 已完成（Phase B1-6，2026-10-04，B1 收尾；7 个加载器逐名复测全为真 B1、无停下项：`loadSavedLocations`→`LocationStore`、`loadPlanetList`→`SessionToolStore`、`loadSatelliteSources`→`SatelliteStore`、`loadRecordings`→`ScriptStore`、`loadSkyCultureConstellationSelectionFlags`→`SkyCultureSettingsStore`、`loadObjectInfo`→`ObjectDetailStore`、`loadPointerCoordinates`→`OverlayStore`，复用同一 `HostCommandPort`；宿主 −7 `private load*`（56 → 49）、单体 17,364 → 17,277；`SatelliteStore` 的 onChanged 走既有 `publishSatellitePanelState`，其余六域空实现；构建/契约绿，受影响域 13 个测试全绿，模拟器冒烟存活且「位置 / 更多功能」路径可达；桥回包渲染待真机）。B1 轨道 24 = 20 下沉 + 4 转 B2/B3，**已全部结清** |
| B2A-1…B2A-2 | B2 | Astro 簇 19 个（1–2 片） | AB-0、A1-2 | **已完成（Phase B2A，2026-10-04，单提交）**：19/19 下沉、停下 0；18 → `AstroStore`（+`AstroHostHooks` 11 法注入）、`loadWutTargets` → `WutStore`；宿主 `private load*` 49 → 30、单体 17,276 → 16,433；构建/契约绿，astro-motion 9/9 / wut-layout 4/4 / julian 通过，模拟器冒烟无崩溃，桥回包渲染待真机 |
| B2R-1…B2R-4 | B2 | 其余 16 个（4 片） | AB-0 | **B2R-1 已完成（Phase B2R-1，2026-10-04）**：`loadObjectInspectorModelRawTexture` 下沉 `ObjectMediaStore`（`ObjectMediaHostHooks` 4 法注入；新增 `readRawSidecar` 承接 fileIo）；宿主 `private load*` 30 → 29、单体 16,433 → 16,397（−36）；构建/契约绿、5 个媒体测试全绿、模拟器冒烟存活，侧车/解码/渲染链路待真机。**B2R-2 已完成（Phase B2R-2，2026-10-04）**：3/3 下沉、停下 0 —— `loadConfigurationSettings` → `TimeSettingsStore`（`TimeSettingsHostHooks` 19 法：ViewSettings 3 / Navigation 9 / Ephemeris 2 组 / InfoWindow 3 + `applySelectedInfoMode`/`applyTimeSettings`）、`loadObserverInfo` → `LocationPickerStore`（`LocationPickerHostHooks` 2 法）、`loadTimeExtras` → `TimeStore`（`TimeHostHooks` 2 法）；`approximateTimeZoneDisplay` 迁入 `common/derive/labels.ets`；宿主 `private load*` 29 → 26、单体 16,397 → 16,361（−36）；构建/契约绿，settings-choice-motion 4/4 / information-policy 3/3 / distance-ui 5/5 / skyculture-refresh 5/5 / cli-response 4/4，模拟器冒烟存活（设置三页签 + 时间 + 位置面板渲染正常），桥回包真实写入待真机。**B2R-3 已完成（Phase B2R-3，2026-10-04）**：星空文化域 4 个加载器下沉 —— `loadSkyCultureList` → `SkyCultureViewStore`、`loadSkyCultureVisualSettings` / `loadSkyCultureTerritoryMap` → `SkyCultureSettingsStore`、`loadSkyCultureMakerDraft` → `SkyCultureMakerStore`；`loadSkyCultureDetails` 保持 B3 登记经 hooks 调用；宿主 `private load*` 26 → 22、单体 16,361 → 16,255（−106）；构建/契约绿，skyculture-refresh 5/5 / skyculture-text 4/4，模拟器冒烟存活，桥回包渲染待真机。**B2R-4 已完成（Phase B2R-4，2026-10-04，B2 收尾）**：8 个加载器 **7 下沉 + 1 转 B3**（`loadObjectCatalogCategories`→`CatalogStore`、`loadObservingListFromStorage`→`ObservingListStore`、`loadBookmarks`/`loadBookmarksFromStorage`→`BookmarkStore`、`loadRecordingByName`/`loadScriptList`→`ScriptStore`、`loadSelectedSatellitePasses`→`ObjectDetailStore`；`loadTelescopeControlStatus` 主动停下登记 B3）；宿主 `private load*` 24 → 17、单体 16,255 → 16,207；构建/契约绿，13 个受影响测试全绿，模拟器冒烟存活，桥回包/Preferences 真实读写待真机。**B2 轨道收尾总账：§2.13 的 35 个 = 已下沉 34 + 转 B3 1（`loadTelescopeControlStatus`）+ 未处理 0。** |
| A2-1…A2-12 | A2 | 214 个派生方法（12 片；热路径最后） | A1 模块 | **A2-1 已完成（Phase A2-1，2026-10-04）**：`objectInspector*` 媒体族 6 个全部结清 —— `objectInspectorMediaWarmupText` → `ObjectMediaStore` 方法；另外 5 个（`objectInspectorPlanetTexturePath`/`objectInspectorPlanetRingSpec`/`objectInspectorDeepSkyImageName`/`objectInspectorFallbackVisualKind`/`objectInspectorStarColor`）→ 新建 `common/derive/media.ets`（纯函数 + 显式入参）。宿主 `private` 730 → 724、单体 15636 → 15531；构建/契约绿、5 个受影响测试全绿、模拟器冒烟存活，详情卡派生值渲染待真机。**A2 进度 6 / 214。** **A2-2 已完成（Phase A2-2，2026-10-04）**：按行数降序取非热路径 **15 个** —— `gyroMagneticHeadingFromDeviceVectors`(25)→`derive/gyro.ets`+显式入参；`archaeoLineSettingValue`(21)→`ArchaeoStore`；`currentSkyCultureMakerDraft`(21)→`SkyCultureMakerStore`；`makeAstroCsv`(19)→`AstroStore`；`quickLocationSearchItems`(18)→`LocationPickerStore`；`filteredEclipses`(14)+`annualMaxLabel`(12)+`lunarElongationClosestLabel`(12)+`altAzMaxLabel`(11)+`altAzVisibleHours`(11)+`altAzNowLabel`(7)+`rtsCalendarStartOptionLabel`(7)+`eclipseStartOptionLabel`(7)+`graphCustomStartLabel`(4)→`AstroStore`；`telescopeCircleValues`(13)→`TelescopeStore`。主动停下 `currentAstroCsvExport`(76)（两域+3 助手）与 `objectDetailConnectorObstacles`(45)（A2-G 几何簇）。宿主 `private` **747 → 732**、单体 **15,531 → 15,309**；构建/契约绿（44 锚点）、全量脚本仅 §13.6 的 7 个环境类失败、模拟器冒烟存活（更多功能/观测工作区/目镜模拟 + 位置面板），astro/考古天文/位置快速搜索端到端待真机。**A2 进度 21 / 214。** **A2-3 已完成（Phase A2-3，2026-10-04，放宽粒度首片，单提交）**：域取值/标签/选项族 **41 个**（开工按 §14.3.1 口径重测边界）——搜索/目录 12（`catalogLabelForModule`/`searchCategoryOptions`/`searchDynamicCategoryOptions`/`searchAllCategoryOptions`/`searchCategoryIcon`/`categoryModuleIdFor`/`searchCategoryLabel`/`categoryObjectIcon` → `CatalogStore`（后两者读搜索域当前分类，改显式入参）；`searchVisibilityLabel`/`searchInstrumentLabel`/`celestialSubtitle`/`categoryObservationSubtitle` → `SearchStore`；撤除 `SearchHostHooks.celestialSubtitle`）；详情卡 12（`expandedAtmosphereSummary`/`selectedObjectIsConstellation`/`selectedSatelliteTleEpoch`/`objectInspectorIcon`/`objectInspectorSearchText`/`hasSelectedObject`/`selectedObjectIsArtificialSatellite` → `ObjectDetailStore`，`objectDistanceSummary`/`objectDistanceNoticeText` 改显式 `distanceVisible` 入参；`objectInspectorModelNotice`/`defaultObjectInspectorModelRotation`/`objectInspectorImageHeight` → `ObjectMediaStore`；撤除 `ObjectDetailHostHooks.selectedObjectIsArtificialSatellite`）；信息窗判断 3（`informationMaskHas`/`distanceInformationVisible`/`selectedLiveInfoVisible` → `InfoWindowStore`）；脚本/时间文案 8（`scriptMeta`/`scriptMetaLine`/`scriptSourceLine`/`scriptWaitDisplayText`/`visibleScriptCaptions`/`visibleScriptCaptionText` → `ScriptStore`；`timePanelClockText`/`timePanelDateText` → `TimeStore`）；其余 6（`ephemerisStartOptionLabel`→`EphemerisStore`；`isObserverPlanetSelection`→`SessionToolStore`；`astroNeedsSelectedObject`→`AstroStore`；`skyCultureNarrationParagraphs`→`SkyCultureViewStore`；`selectedSkyCultureMakerConstellation`→复用 `SkyCultureMakerStore.selected()`；`hecPointColor`→`derive/astro.ets` 显式 accent 入参）。**停下 0**；`sessionHandoff`（void 动作）与 `catalogHealthText/Color`（A-保留组）剔除。**A-保留组登记 49 个 / 210 行**（判据"全部读取项 ⊆ §2.7.1 保留集合且不读 store"；写入 STATE-REVIEW §2.7.1 新子类）。宿主 `private` **710 → 669**、单体 **15,309 → 15,008**（−301）。构建/契约绿；受影响 4 测试（detail-image-layout 5/5、distance-ui 5/5、information-policy 3/3、search-browser 3/3）全绿，全量脚本仅 §13.6 的 7 个环境类失败；模拟器冒烟（Dock→搜索面板分类 picker、时间面板、更多功能面板，`pidof` 全程存活），详情卡/距离提示真实渲染待真机（UI-only 通道无引擎）。**A2 进度 62 / 214（B-下沉口径：已迁 62 / 153）。** **A2-4 已完成（Phase A2-4，2026-10-04，单提交）**：布局/几何族 30 个 → `common/derive/geometry.ets`、2 个 → store、1 个转发折叠删；停下 `clampedObjectCardOffset*` 薄包装与 `currentGuide/Step`；补登记 A-保留 +2（`dockTop`/`guideCardWidth`）。宿主 `private` 669 → **636**、单体 15,008 → **14,861**（−147）。构建/契约绿（44 锚点），`test-ohos-polar-scope` 4/4，全量仅 §13.6 的 7 环境类失败，模拟器冒烟点按 Dock/缩放/面板返回 + 时间面板副标题实时渲染、`pidof` 存活。**A2-5 已完成（Phase A2-5，2026-10-04，单提交 `refactor(harmonyos): sink the large and coupled derivation helpers (A2-5)`）**：45 个（10 hec 纯函数 → `derive/astro.ets`；`panelTitle` → `derive/labels.ets` `panelTitleFor`；`celestialTitle` 并入 labels、`hecTitle`/`celestialPositionTitle` 删；`currentAstroCsvExport` + 18 天文尺寸/标签 → `AstroStore`；12 夜视配色 → `NightModeStore`）；`objectDetailConnectorObstacles`(45) 停下登记宿主控制器逻辑（组合型，读 4 store + 10 A-保留几何助手、真机离线不可验）。宿主 `private` 658 → **613**、单体 14,860 → **14,456**（−404）。构建/契约绿（44 锚点），全量仅 §13.6 的 7 环境类失败，模拟器冒烟（Dock 五面板 + 三 hub 标题文本对照、天文计算面板，`pidof` 存活）。**A2 进度 140 / 214（B-下沉口径 140 / 153；A-保留组登记 51）。** **A2-6 已完成（Phase A2-6，2026-10-04，单提交 efactor(harmonyos): close the A2 track - sink the residual and triage the hot paths）**：残留 B 组 33 → 下沉 20 / 登记 13；热路径 inferredPanelRouteDirection 下沉 derive/actions.ets、其余 5 个 (b) 宿主控制器登记；宿主 private **613 → 593**、单体 **14,456 → 14,347（−109）**。**A2 轨道收尾：宽口径 214 = 已迁 160 + A-保留 51 + 热路径登记 4 + 控制器登记 13（含既登记）+ 未处理 0；全宿主 private 942 → 593（目标 ≈640，超额达成）、load* 72 → 3（目标 ≈11，达成），A2 轨道清空。** |
| B3-1…B3-6 | B3 | 11 个加载器（先解保留字段） | B1/B2 手法 | **B3-1 已完成（Phase B3-1，2026-10-04，单提交）**：结清「B1/B2 因 §14.8 规则 3 主动停下」的 4 个共享序号簇 —— `loadAngleMeasure`→`ToolsStore`（序号并作 `seq`，配对写方 `toggleAngleMeasure` 同片）、`loadNavStars`→`NavStarsStore`（保留双序号名，配对写方 `setNavStarsSetting`+助手 `applyNavStarsSetting` 同片）、`loadMeteorShowers`→`MeteorStore`（序号并作 `seq`，配对写方 `setMeteorShowersFlag` 同片）、`loadConstellationNavigation`→`SearchStore`（语言代际 `languageRefreshSerial` 按方案 a 移入 `LanguageStore` 单一持有，跨域经 `SearchHostHooks.languageSerial()`/`CatalogHostHooks.languageSerial()` 只读）；宿主 `private load*`   18 → 14、单体 16,207 → 16,035（−172）；构建/契约绿、全量脚本仅 §13.6 的 7 个环境类失败、模拟器冒烟存活，角度测量/航海星面板（插件 + 无引擎）与语言切换待真机。**B3-2 已完成（Phase B3-2，2026-10-04，单提交）**：结清「请求进度 / 进行中标志」组 3 个加载器 —— `loadMoonPhases`（+`moonPhaseLoadingDays`/`moonPhaseRequestId`）、`loadAstroCalcContext`（+`astroContextRequestPending`/`astroContextRequestId`）→ `AstroStore`；`loadPolarScopeData`（+`polarScopeRequestPending`/`polarScopeDataRequestId`）→ `PolarScopeStore`；宿主只留计时器调用 store，作废在途请求改由 `AstroStore.cancelAstroCalcContext()` / `PolarScopeStore.cancelPolarScopeRequest()` 承接；撤除 `AstroHostHooks.loadMoonPhases`/`loadAstroCalcContext`，新增 `PolarScopeHostHooks.shouldRefreshPolarScope()`。宿主 `private load*` 14 → 11、单体 16,035 → 15,944（−91）；构建/契约绿，astro-motion 9/9 / polar-scope 4/4，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（天文计算→月相、极轴镜叠层 + 翻转开关，`pidof` 全程存活）。**B3-3 已完成（Phase B3-3，2026-10-04，单提交）**：搜索/分页/历史族 3 个加载器 —— `loadCategoryObjects`+`loadMoreCategoryObjects`（+游标 `categoryOffset`/代际 `categoryRequestSerial`/标志 `satelliteCatalogReady`/常量 `CATEGORY_PAGE_SIZE`）、`loadSearchHistoryFromStorage`（+`searchHistory` + `saveSearchHistoryToStorage`）→ `SearchStore`（新增 `SearchHostHooks` 7 法）；宿主 `private load*` 9 → 6、单体 15,944 → 15,859（−85）；构建/契约绿，search-browser 3/3 / constellation-lookup 2/2，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（开搜索面板、选分类标签实时刷新、分页失败重试，`pidof` 全程存活）。**B3-4 已完成（Phase B3-4，2026-10-04，单提交）**：定时器族 3 个加载器 —— `loadSatellites`(+`satelliteListRequestId`/`satelliteLoadTimer`/`satelliteLoadIncludeSources`/`satelliteFlagMutationId`/`satelliteListElapsedMs`) → `SatelliteStore`、`loadVideoRecordingState`(+`start/stopVideoStatePolling`/`videoStateTimer`) → `ScriptStore`、`loadTelescopeControlStatus` + live-position 定时器簇(+`stop/schedule/refresh/sync/setTelescopeLivePosition`/`lx200Payload`/`applyTelescopeProfile(s)`/`applyTelescopeEndpointStatus`) → `TelescopeStore`（store 自持 start/stop，新增 `TelescopeHostHooks`/`ScriptHostHooks.stopVideoRecording`）；宿主 `private load*` 8 → 5、单体 14,885 → 14,681（−204）；构建/契约绿，satellite-panel 7/7，全量脚本仅 §13.6 的 7 个环境类失败，模拟器冒烟（卫星面板开合数轮 `pidof` 存活、关闭后 hilog 无空转）。**B3 剩余**：§14.6 表内 **3 行**（`loadSkyCultureDetails` / `loadScenery3d` / `loadCatalogHealth`，均保持登记）。  **B3-5 已完成（B3 收尾）**：`loadScenery3d`→SceneryStore、`loadCatalogHealth`→CatalogStore 下沉；`loadSkyCultureDetails` 永久保持登记。B3 总账 16 = 已下沉 15 + 保持登记 1 + 未处理 0；全队列宿主 `private load*` 5 → 3。|

**建议首序**：`AB-0` → `B1-1`（`loadOculars` 75 行，收益最大）→ `A1-1…A1-7`（零风险、无前置，可整批推进）→ `B1-2…B1-6` → `B2A` → `A2 非热路径` → `B2R` → `B3` → `A2 热路径`。
（A1 与 B1 无相互依赖，可任意交错；A2 热路径放最后，留足真机对照余量。）

### 14.8 A/B 专属硬规则（叠加在 §13.1 之上）

1. **文件级函数禁 `this`**：迁移后残留 `this` 触发 `arkts-no-standalone-this`；把 `this.x` 变为显式入参或模块 import。
2. **store 不得 import NAPI/UI**：`load*` 下沉只依赖 `CommandPort` 接口；`getUIContext` 之类经注入提供（可用假 port 单测）。
3. **请求序号随加载器搬入 store**（`private seq`）；禁止宿主与 store 双序号，禁止共享。
4. **`publish*` → `onChanged` 注入**：store 不直接 `callNative`；刷新语义不变（同一 `@Observed` 实例仍由宿主 `@State` 持有、组件 `@ObjectLink` 消费）。
5. **禁止双写**：加载器/派生方法搬走后，宿主不得保留同名方法副本（灰度期不允许，避免运行期走错分支）。
6. **纯函数模块无状态**：`common/derive/*.ets` 不得 import store、不得持有模块级可变变量。
7. **声明与调用同片搬**：一次只搬一个方法簇，声明与全部调用点在同一片内完成并同片构建（避免中间态）。

### 14.9 度量与验收

- 每片记录三组数字：宿主 `private` 方法数、宿主内 `this.<派生名>` 端口引用数、`load*` 方法数；写入 CHANGELOG。
- 门槛与 §13.2 八步一致：`arkts_check` → 构建（`scripts\build-ohos-hap-windows.ps1 -SkipEngine -SkipDeploy -SkipResources`）→ `node scripts/check-ohos-ui-contract.mjs`（**44 锚点不变**）→ 受影响测试 → 真机（优先语义命令 `openUiPanel`，见 `MainWindowNativeNode.ets:1346`）→ 恢复被改的持久化设置 → CHANGELOG（CRLF 安全、裸 LF=0）→ 提交。
- 累计目标：`private` 942 → ≈640；`load*` 72 → ≈11。

### 14.10 风险与取舍

- **A2 几何/触摸类是运行时回归热点**（命中失效不报编译错）：`isUiPoint`/`skyZoomButtonAt`/`dockActionAt`/`compactQuickIdAt`/`expandedSafeTargetPoint`/`inferredPanelRouteDirection` 单独成片、逐字迁移、真机命中 + 截图对照；其余 A2 也不得"顺手改语义"。
- **B 轨道定时器**：`loadTelescopeControlStatus`、`loadVideoRecordingState`、`loadSatellites` 需 store 自持 start/stop，须测"面板关闭后定时器停止"。
- **与 §7（V1 → V2）的关系**：本计划是 **V1 期瘦身**，其中 A2-G 与 §7.5 Phase A 目标重叠。**建议先做 A1 + B1**（零风险、收益明确、与 V2 无冲突），A2 的几何类可等 §7 的 V2 试点结论再决定"随组件下沉"还是"随 V2 模型下沉"，避免重复劳动。
- **回滚**：每片独立提交；A2 热路径若真机回归，`git revert` 单片即可（不牵动 store 结构）。

---

## 15. 续作计划三：剩余功能模块下沉（依据 STATE-REVIEW §9，2026-10-04 立）

> **前置已完成**：§2.7 域状态下沉（宿主 `@State` 132 = 46 store 实例 + 86 保留登记）、§14 A/B 方法下沉
> （`private` 940 → **593**、`private load*` 70 → **3**、单体 18,582 → **14,347** 行；`bridge/CommandPort.ets`
> 与 `common/derive/*`（8 模块 / 1,769 行）已建成）。
> 本节把 STATE-REVIEW **§9**（A/B 之后剩余功能模块普查）整理为可执行队列。协议与硬规则沿用
> §13.1（硬规则）/§13.2（八步）/§13.3（陷阱）与 **§14.8（A/B 专属规则）**；本节只补 §15 专属规则（§15.7）。

### 15.0 目标与基线（2026-10-04，取自 593-方法文件）

| 指标 | 现状（实测） | 终态目标 | 依据 |
|---|---:|---:|---|
| 宿主行数 | **14,347** | ≈9,000–10,000 | §9.1 可下沉 ≈4,300 行 |
| 宿主 `private` 方法 | **593** | ≈440–470 | §9.2 P1 ≈105 + §9.3 P4 ≈50 + §9.4 P2 ≈10 |
| 宿主裸 `@State` | 86（保留登记） | 86（**不再动**） | §2.7.1 / §9.6 |
| 控制器类（普通类 + 注入端口 + 自持定时器） | 1（`TimeWheelController`） | ＋5 | §9.2 |
| 端口接口（纯接口，不 import NAPI） | 1（`CommandPort`） | ＋3（`MediaPort`/`SensorPort`/`PlatformPort`） | §9.5 |
| `common/` 模块 | `ui/`+`derive/*`(8) | ＋`media/`、`platform/`、`SpeechService` | §9.3 |

**轨道命名**（与 §9 一致）：**P1**＝控制器类（普通类 + 注入端口 + 自持 `start()/stop()`，形如既有 `TimeWheelController`）；
**P2**＝并入既有域 store 的方法；**P4**＝跨域服务（`common/` 或 `capability/`）。
**口径**：所有数字取自 STATE-REVIEW §9.0–§9.4 的普查；**每片开工前必须重测该片的方法/字段/行数边界**，不照抄本节表格。

### 15.1 Enabler：三个新端口（3 片，P1/P4 的硬前置）

A/B 已为"桥"建立 `CommandPort`；剩余子系统依赖**非桥 NAPI**，需同形态端口（§14.8 规则 2）：
纯接口 + 宿主 `aboutToAppear` 具名适配器（同 `HostCommandPort` 先例）。

| 片 | 端口 | 覆盖 NAPI | 供哪些后续片 |
|---|---|---|---|
| **AB2-0a** | `bridge/MediaPort.ets` | `fileIo` / `image` / `picker` / `media` / `photoAccessHelper` | P4-1 `ImageDecoder`、P1-2 `RecordingController`、P4-2 `PlatformServices` |
| **AB2-0b** | `bridge/SensorPort.ets` | `sensor.*`（订阅 / 退订 / 上报） | P1-1 `SensorController` |
| **AB2-0c** | `bridge/PlatformPort.ets` | `systemShare` / pasteboard / TTS | P4-2 `PlatformServices`、P4-3 `SpeechService` |

每片含：**纯接口**（不 import `@ohos.*`）+ 宿主具名适配器 + **最小方法试点**——
`MediaPort` 试点 `releaseDecodedImage`(11)、`SensorPort` 试点 `watchGyro*` 退订、`PlatformPort` 试点 `copyTextToClipboard`(13)——
并跑通 构建 / 契约 / 真机冒烟后，再放量对应控制器。

### 15.2 轨道 P1：控制器类（5 个控制器，8 片，按 §9.7 低→高风险排序）

| 片 | 控制器 | 代表方法（行） | 私有字段 | 定时器 | 落点 | 风险 |
|---|---|---|---:|---|---|---|
| **P1-1a** | `SensorController` ①（订阅与数据回调） | `onRotationVectorDirect`(122) `onOrientationData`(113) `startGyroscope`(121) `stopGyroscope`(56) `watchGyro*` | **48** | — | `capability/SensorController.ets` + 扩充 `state/GyroStore.ets` | 中 |
| **P1-1b** | `SensorController` ②（姿态解算与目标引导） | `updateGyroTargetGuide`(109) `emitGyroPoseProbe` + 姿态解算助手 | （同上） | — | 同上 | 中 |
| **P1-2** | `RecordingController` | `startScreenVideoRecording`(51) `playRecording`(25) `saveCurrentRecording`(22) `replayNextCommand`(22) `startRecording`(21) `finalizeScreenVideo`(21) `stopScreenCapture` / `saveScreenshot` | 13 | `videoStateTimer` / `recordViewCheckpointTimer` | `capability/RecordingController.ets`（`ScriptStore` 已含部分） | 中 |
| **P1-3a** | `ObjectModelRenderer` ①（触摸/光照/请求） | `requestObjectInspectorModelRender`(25) `handleObjectInspectorModelTouch`(57) `refreshObjectInspectorModelLighting`(11) | ~25 | `objectInspectorModelRenderTimer` | `capability/ObjectModelRenderer.ets`（经既有 `DetailModelRenderClient` worker） | 中高 |
| **P1-3b** | `ObjectModelRenderer` ②（渲染/纹理提交） | `renderObjectInspectorModel`(106) `decodeObjectInspectorModelTextureFromPng`(46) `commitObjectInspectorModelTexture`(36) `clearObjectInspectorModelRenderer`(35) | （同上） | — | 同上 | 中高 |
| **P1-4** | `StartupBridge` | `restoreStartupSettings`(65) `runStartupBridgeTasks`(37) `startupBridgeSync`(11) `saveCurrentViewAsStartup`(10) | — | — | `capability/StartupBridge.ets`（`CommandPort` + Preferences） | 低 |
| **P1-5a** | `SkyInputController` ①（鼠标/键盘/轴/惯性） | `handleSkyMouse`(51) `handleSkyKey`(31) `handleSkyAxis`(23) `handleSkyTap`(11) `startSkyInertia` / `stopSkyInertia`(25) | **89** | `skyInertiaTimer` | `capability/SkyInputController.ets` | **高** |
| **P1-5b** | `SkyInputController` ②（触摸主路径） | `handleSkyTouch`(318) `emitFluidDrag`(36) | （同上） | （同上） | 同上 | **高** |

> **P1-5 是当前宿主最大未拆控制器**（独占 89 个字段 + `handleSkyTouch` 318 行）；**必须最后做**，
> 每片"语义逐字 + 真机命中/拖动对照"（命中失效不报编译错）；无法保证逐字等价 → 停下登记保留（§15.6）。
> **P1-1 `SensorController`** 独占 48 字段 + 22 方法，是第二大整块，且**无定时器、边界清晰**，故列为首做。

### 15.3 轨道 P4：跨域服务（5 片）

| 片 | 服务 | 代表方法（行） | 端口 | 落点 |
|---|---|---|---|---|
| **P4-1** | `ImageDecoder` | `decodeLocalImage`(70) `decodeSkyCultureArtThumbnail`(33) `decodeSkyCultureArtPreview`(27) `releaseDecodedImage`(11) | `MediaPort` | `common/media/ImageDecoder.ets` |
| **P4-2** | `PlatformServices` | `shareFile`(22) `copyTextToClipboard`(13) `saveScreenshot`(17) `exportScreenshotToUserStorage`(25) | `PlatformPort` / `MediaPort` | `common/platform/{Share,Clipboard,Screenshot}.ets` |
| **P4-3** | `SpeechService` | `speakSelectedObject`(11) | `PlatformPort`(TTS) | `common/SpeechService.ets`（或并入 `GuideStore`） |
| **P4-4** | `SessionStore` | `sessionApply`(24) `sessionExport`(20) `sessionHandoff`(14) `sessionSummary`(6) | `CommandPort` + AppStorage | `state/SessionStore.ets`（并入 `SessionToolStore` 或新建） |
| **P4-5** | `SelectionService`（**决策片**） | `applySelectedObject`(230) `refreshSelectedObject`(29) `requestSelectedDetails`(28) `navigateSelectedObjectTo`(33) `moveToSelectedObject`(19) `scheduleSelectedObjectForUiChange`(15) | 多个域 store + `CommandPort` | 先**普查**：能整片搬 → `capability/SelectionService.ets`；含热路径/多入口无法逐字等价 → **登记保留**并写明理由（§9.3 已给此选项） |

> P4-5 与 P1-5 同属**高风险**（全应用选中管线、多入口），放最后；"登记保留"是合法结局。
> P4-1/P4-3 行数小、边界清晰，适合在 AB2-0a/0c 之后紧接着做。

### 15.4 轨道 P2：并入既有 store（3 片）

| 片 | 域 | 方法 | 目标 store |
|---|---|---|---|
| **P2-1** | 脚本播放 | `playScriptByName`(44) `continueNativeScript` `toggleReplayPause`(20) `changePlaybackRate` `stopScriptPlayback` `sendScriptKey` | `ScriptStore`（+ `ScriptHostHooks` 注入） |
| **P2-2** | 交互导览 | `executeGuideRequest`(63) + guide 请求/定时器 | `GuideStore`（guide 请求与定时器自持） |
| **P2-3** | 跟踪 | `setTrackingState`(37) `toggleTracking` 相关 | `ViewSettingsStore` 或登记保留 |

### 15.5 队列总表（19 片，建议顺序）

| ID | 轨道 | 内容 | 前置 | 估规模 | 状态 |
|---|---|---|---:|---:|---|
| **AB2-0a/0b/0c** | 端口 | `MediaPort` / `SensorPort` / `PlatformPort`（各含最小试点） | — | 3×~60 行 | 待做 |
| **P1-1a/P1-1b** | P1 | `SensorController`（22 方法 + 48 字段） | AB2-0b | ~700 行 | 待做 |
| **P1-2** | P1 | `RecordingController`（23 方法 + 13 字段 + 2 定时器） | AB2-0a | ~450 行 | 待做 |
| **P4-1** | P4 | `ImageDecoder` | AB2-0a | ~150 行 | 待做 |
| **P4-2** | P4 | `PlatformServices` | AB2-0c | ~80 行 | 待做 |
| **P4-3** | P4 | `SpeechService` | AB2-0c | ~20 行 | 待做 |
| **P1-3a/P1-3b** | P1 | `ObjectModelRenderer`（~29 方法 + ~25 字段） | AB2-0a | ~650 行 | 待做 |
| **P1-4** | P1 | `StartupBridge`（~18 方法 / ~330 行） | — | ~330 行 | 待做 |
| **P4-4** | P4 | `SessionStore` | — | ~70 行 | 待做 |
| **P2-1/P2-2/P2-3** | P2 | 脚本播放 / 导览 / 跟踪 并入 store | — | ~270 行 | 待做 |
| **P1-5a/P1-5b** | P1 | `SkyInputController`（31 方法 + 89 字段，热路径） | — | ~800 行 | 待做（**最后**） |
| **P4-5** | P4 | `SelectionService` 决策片（搬或登记） | — | ~1,200 行 | 待做（**最后**） |

**建议首序**：`AB2-0a/0c/0b` → `P1-2` / `P1-1a` / `P1-1b` → `P4-1` / `P4-2` / `P4-3` → `P1-3a` / `P1-3b` / `P1-4` / `P4-4` → `P2-1` / `P2-2` / `P2-3` → `P1-5a` / `P1-5b` → `P4-5`。

### 15.6 保留项（勿再动；引自 STATE-REVIEW §9.6）

1. **§2.7.1 的 86 个保留裸字段**（机制类 / 高频逐帧 / 跨域共用 / 引擎自用）；
2. A2 的 **51 个 A-保留** + **4 个热路径登记**（`isUiPoint` / `skyZoomButtonAt` / `dockActionAt` / `expandedSafeTargetPoint`）+ **13 个宿主控制器**（`objectDetailConnectorObstacles` 等）；
3. **`loadSkyCultureDetails`**（跨序号线 + 美术管线 + 逐帧字段，永久登记）；
4. **壳层/路由**（`setPanel`/`updateResponsiveLayout`/`closePanel`/`open*` 族；§9.1：壳层 57 方法/734 行）、**刷新/同步/收口**（`publish*`/`schedule*`；25/567）、**生命周期/回调**（10/543）；
5. `floatingPanel` / `compactPanel` / `panelContent` 三个 `@Builder`（§13.1 规则 9）。
6. **`SelectionService` 族（M3-3 登记，2026-10-05）**：`applySelectedObject` / `refreshSelectedObject` / `requestSelectedDetails` / `navigateSelectedObjectTo` / `moveToSelectedObject` / `scheduleSelectedObjectForUiChange` 及其独占机制字段（`dismissedObjectName` / `objectCardPlacementPending` / `objectInspectorMediaRequestPath` / `objectInspectorMediaResolvedRequestPath` / `objectInspectorMediaResolvedPath` / `objectInspectorMediaResolutionComplete` / `detailRefreshing` / `detailRefreshGuard` / `lastSafeNavigationPayload` / `lastSafeNavigationAt` / `skySelectionRequestSerial`）—— 全应用选中/居中管线，**47 个组件/宿主入口** + 三法互调成环 + 写 §15.6-1 保留字段 + 服务层禁 NAPI，**永久保留宿主**（判定与后续路径见 CHANGELOG [2026-10-05] M3-3 与 STATE-REVIEW §9.3）。

### 15.7 P1/P4 专属硬规则（叠加在 §13.1 与 §14.8 之上）

1. **控制器/服务不 import NAPI/UI**：`capability/*` 与 `common/*` 只依赖端口接口（`CommandPort`/`MediaPort`/`SensorPort`/`PlatformPort`）；不得 import `@ohos.*` 设备能力模块。
2. **可观测数据入 `@Observed` store，草稿/逐帧字段留控制器**：手势采样、逐帧写入等**不可观测**字段**不得**放进 store（否则每帧触发刷新）；store 只放组件要消费的数据。
3. **定时器由控制器 `start()/stop()` 自持**，并在宿主生命周期（面板关闭 / 应用后台）收口；每片必须给出 **start/stop 调用点对照表**，并实测"关闭后定时器停止"（参照 §14 B3-4 的 hilog 计数法）。
4. **端口适配器具名实现**（同 `HostCommandPort`）：禁匿名对象字面量越界、禁 `as`。
5. **热路径逐字等价**：`handleSkyTouch`/`isUiPoint` 相关（P1-5）与 `applySelectedObject` 相关（P4-5）只允许"参数化 + 所有权转移"，**不得改比较边界/分支**；须真机命中 + 截图对照；真机不可用时只做构建级并记"待真机验证"。
6. **不搬 §15.6 保留项**：遇到即停下登记（并写明属哪一条）。
7. **端口先行**：任何需要新 NAPI 的片，其端口必须在 AB2-0x 中先落地并在最小方法上试点通过。

### 15.8 度量与验收

- 每片记录四组数字：**宿主行数** / **宿主 `private` 方法数** / **宿主裸 `@State` 数（应恒为 86）** / **新增控制器或服务文件数**；写入 CHANGELOG。
- 门槛同 §14.9：`arkts_check` → 构建（`scripts\build-ohos-hap-windows.ps1 -SkipEngine -SkipDeploy -SkipResources`）→ `node scripts/check-ohos-ui-contract.mjs`（**44 锚点不变**）→ 受影响测试 → 真机（优先语义命令 `openUiPanel` / `stellarium-cli --batch`；`CHANGELOG` 为 LF 索引，改它需与索引一致）→ CHANGELOG → 独立提交。
- 累计目标：宿主 **14,347 → ≈9,000–10,000 行**；`private` **593 → ≈440–470**。

### 15.9 风险与取舍

- **两块高风险放最后**：`SkyInputController`（89 字段 + `handleSkyTouch` 318 行，命中/拖动热路径）与 `SelectionService`（`applySelectedObject` 230 行、多入口选中管线）。**两者"登记保留"都是合法结局**，不得为凑指标强行搬迁。
- **端口先行、单片试点**：`MediaPort`/`SensorPort`/`PlatformPort` 必须先于其控制器落地并用最小方法（`releaseDecodedImage` / `watchGyro*` / `copyTextToClipboard`）验证，避免一次性大改。
- **`SensorController` 的字段最多（48）且与 `GyroStore` 现有 19 行高度相关**：先扩 store 再搬控制器，避免中间态。
- **与 §7（V1→V2）的关系**：本计划仍是 **V1 期瘦身**；控制器/服务内部用**普通类**（非 `@Observed`），与 V2 迁移不冲突（V2 只影响可观测 store 与组件）。
- **回滚**：每片独立提交，且以**新增控制器/服务文件**为主、宿主只做"调用点改指向 + 删方法"，单文件回归面最小；高风险片若真机回归，`git revert` 单片即可。
- **`P1-2 RecordingController` 与 `ScriptStore` 已有部分重叠**（录制/回放状态已在 store）：本片只搬**行为与定时器**，不重复搬状态；若发现状态冗余，先登记再定。


### 15.10 模块级大切片队列（2026-10-04 重排；**中低风险优先 + 功能模块级粒度**）

> **重排依据（用户 2026-10-04 指示）**：① 先聚焦 STATE-REVIEW §9.7 的**中低风险**模块，高风险（`SkyInputController`、`SelectionService`）放最后；
> ② 切片粒度放宽到**功能模块级**——**一个功能模块 = 一片**，**允许数千行的整体拆分**（不再用 §14 的 300–500 行细粒度）。
> 因此把 §15.1–§15.5 的 19 片**合并为 10 片**，分三批：**M1 中低风险（6 片，先做）→ M2 中高（2 片）→ M3 高风险（3 片，最后）**；
> 三个端口合并为 1 片。**§13.2 八步协议与 §14.8/§15.7 硬规则不变**；每片仍独立提交、可单独 `git revert`。

#### 批次 M1：中低风险（先做，6 片）

| 片 | 模块 | 内容（合并自 §15.1–§15.4） | 规模 | 前置 | 风险 |
|---|---|---|---:|---|---|
| **M1-1** | **端口组** | `MediaPort` + `SensorPort` + `PlatformPort` 三个纯接口 + 宿主具名适配器 + 三个最小试点（`releaseDecodedImage` / `watchGyro*` 退订 / `copyTextToClipboard`） | ~300 行 | — | 低 |
| **M1-2** | **传感器/陀螺仪** | `SensorController` 整体：22 方法（`onRotationVectorDirect` 122 / `startGyroscope` 121 / `onOrientationData` 113 / `updateGyroTargetGuide` 109 / `stopGyroscope` 56 / `watchGyro*` / `emitGyroPoseProbe`）+ **48 个字段** + 扩充 `state/GyroStore.ets` 的可观测子集（先扩 store 再搬控制器，避免中间态） | ~700 行 | M1-1 | 中 |
| **M1-3** | **录制/回放/视频/截图** | `RecordingController` 整体：23 方法（`startScreenVideoRecording` 51 / `playRecording` 25 / `saveCurrentRecording` 22 / `replayNextCommand` 22 / `startRecording` 21 / `finalizeScreenVideo` 21 / `stopScreenCapture` / `saveScreenshot` 等）+ 13 字段 + 自持 `videoStateTimer` / `recordViewCheckpointTimer`（只搬**行为与定时器**，状态已在 `ScriptStore`，勿重复搬） | ~450 行 | M1-1 | 中 |
| **M1-4** | **媒体/平台/语音服务** | `common/media/ImageDecoder.ets`（`decodeLocalImage` 70 / `decodeSkyCultureArtThumbnail` 33 / `decodeSkyCultureArtPreview` 27 / `releaseDecodedImage` 11）＋ `common/platform/{Share,Clipboard,Screenshot}.ets`（`shareFile` 22 / `copyTextToClipboard` 13 / `saveScreenshot` 17 / `exportScreenshotToUserStorage` 25）＋ `common/SpeechService.ets`（`speakSelectedObject` 11） | ~250 行 / 3 个新文件族 | M1-1 | 低 |
| **M1-5** | **启动 / 会话 / 平台杂项** | `capability/StartupBridge.ets`（`restoreStartupSettings` 65 / `runStartupBridgeTasks` 37 / `startupBridgeSync` 11 / `saveCurrentViewAsStartup` 10）＋ `state/SessionStore.ets`（`sessionApply` 24 / `sessionExport` 20 / `sessionHandoff` 14 / `sessionSummary` 6）＋ 其余启动/隐私/平台杂项（§9.1 记该模块 ~18 方法 / ~330 行，**开工重测列出全名单**） | ~400 行 | — | 低 |
| **M1-6** | **并入既有 store（P2 三域）** | 脚本播放 → `ScriptStore`（`playScriptByName` 44 / `continueNativeScript` / `toggleReplayPause` 20 / `changePlaybackRate` / `stopScriptPlayback` / `sendScriptKey`；+ `ScriptHostHooks` 注入）；交互导览 → `GuideStore`（`executeGuideRequest` 63 + guide 请求/定时器）；跟踪 → `ViewSettingsStore`（`setTrackingState` 37 / `toggleTracking`） | ~270 行 | — | 中低 |

**M1 预期收益**：宿主 14,347 → **≈12,000 行**、`private` 593 → **≈500**；覆盖 §9.7「低风险高价值」全部 + P2 三域。

#### 批次 M2：中高风险（M1 完成后做）

| 片 | 模块 | 内容 | 规模 | 风险 |
|---|---|---|---:|---|
| **M2-1** | **对象模型渲染 ①** | `ObjectModelRenderer` 的渲染与纹理部分：`renderObjectInspectorModel`(106) / `decodeObjectInspectorModelTextureFromPng`(46) / `commitObjectInspectorModelTexture`(36) / `clearObjectInspectorModelRenderer`(35) / `requestObjectInspectorModelRender`(25) + `ObjectMediaStore` 可观测子集 | ~400 行 | 中高 |
| **M2-2** | **对象模型渲染 ②** | 剩余部分：`handleObjectInspectorModelTouch`(57) / `refreshObjectInspectorModelLighting`(11) / `objectInspectorModelRenderTimer` 自持 + ~25 个 `objectInspectorModel*` 字段 | ~350 行 | 中高 |

> 开工时若实测一片可行（<~500 行），**允许合并为一片 M2**；按实测决定并在 CHANGELOG 说明。

#### 批次 M3：高风险（最后，须真机命中 + 截图对照）

| 片 | 模块 | 内容 | 规模 | 风险 |
|---|---|---|---:|---|
| **M3-1** | **天空输入 ①（骨架）** | `SkyInputController` 骨架：`handleSkyMouse`(51) / `handleSkyKey`(31) / `handleSkyAxis`(23) / `handleSkyTap`(11) / `startSkyInertia`+`stopSkyInertia`(25) + **89 个手势/视图字段**迁入普通类（可观测子集入 `OverlayStore`/`DockStore`） | ~400 行 | 高 |
| **M3-2** | **天空输入 ②（主路径）** | `handleSkyTouch`(318) + `emitFluidDrag`(36) | ~400 行 | 高 |
| **M3-3** | **选中服务（决策片）** | `SelectionService`：**先普查** → 能整片逐字搬则 `capability/SelectionService.ets`；含热路径/多入口无法逐字等价则**登记保留**（§9.3 明确给出的合法选项） | ~1,200 行 **或 0** | 高 |

**M3 许可**：M3-1/2/3 若真机不可用、或无法保证逐字等价，**允许登记保留并写明理由**（§15.6），**不得为凑指标硬搬**。

#### 队列与优先级（重排后：10 片）

| ID | 批次 | 模块 | 前置 | 状态 |
|---|---|---|---|---|
| M1-1 | M1 | 端口组（`MediaPort`/`SensorPort`/`PlatformPort` + 试点） | — | 待做 |
| M1-2 | M1 | `SensorController`（22 方法 + 48 字段） | M1-1 | 待做 |
| M1-3 | M1 | `RecordingController`（23 方法 + 13 字段 + 2 定时器） | M1-1 | 待做 |
| M1-4 | M1 | `ImageDecoder` + `PlatformServices` + `SpeechService` | M1-1 | 待做 |
| M1-5 | M1 | `StartupBridge` + `SessionStore` + 启动杂项 | — | 待做 |
| M1-6 | M1 | 脚本播放 / 导览 / 跟踪 → 既有 store（P2） | — | 待做 |
| M2-1 | M2 | `ObjectModelRenderer` 渲染/纹理（或与 M2-2 合并） | M1-1 | 待做 |
| M2-2 | M2 | `ObjectModelRenderer` 触摸/光照/字段 | M1-1 | 待做 |
| M3-1 | M3 | `SkyInputController` 骨架（89 字段 + 鼠标/键盘/轴/惯性） | — | 待做（最后） |
| M3-2 | M3 | `SkyInputController` 主路径（`handleSkyTouch` 318） | M3-1 | 待做（最后） |
| M3-3 | M3 | `SelectionService` 决策片（搬或登记） | — | 待做（最后） |

**建议首序**：`M1-1` → `M1-2` → `M1-3` → `M1-4` → `M1-5` → `M1-6` → `M2-1` / `M2-2` → `M3-1` / `M3-2` → `M3-3`。

**与 §15.1–§15.5 的关系**：本节**取代** §15.1–§15.5 的 19 片细分（后者保留作模块普查与依赖说明）；**执行以 §15.10 为准**。§15.6 保留项、§15.7 硬规则、§15.8 度量、§15.9 风险**继续有效**。


### 15.11 M1/M2 步长再放大（2026-10-04 二次重排；用户要求"M1 M2 步子再迈大一些"）

> **口径**：M1 由 §15.10 的 6 片并为 **2 片**，M2 由 2 片并为 **1 片**；**M3（高风险）保持 3 片不变**。
> 合并原则：**按模块性质成组**——"端口 + 服务 + 并入"归一片（纯新增/迁移，无状态机），"控制器状态机"归另一片；**不把控制器与纯迁移混在一片**。
> 批次顺序、风险分级与全部硬规则不变。本节**取代 §15.10 的 M1/M2 粒度**（§15.10 保留作依赖与内容说明；M3 定义以 §15.10 为准）。

| 片 | 组成（原 ID） | 内容 | 规模 | 风险 | 前置 |
|---|---|---|---:|---|---|
| **M1-A** | M1-1+M1-4+M1-5+M1-6 | **端口 + 服务层 + P2 并入**：① 三端口 `MediaPort`/`SensorPort`/`PlatformPort`（各含最小试点）；② `common/media/ImageDecoder.ets` ＋ `common/platform/{Share,Clipboard,Screenshot}.ets` ＋ `common/SpeechService.ets`；③ `capability/StartupBridge.ets` ＋ `state/SessionStore.ets` ＋ 启动/隐私杂项（§9.1 该模块 ~18 方法）；④ P2 三域并入既有 store（脚本播放→`ScriptStore`、导览→`GuideStore`、跟踪→`ViewSettingsStore`） | **~1,200 行** | 低–中低 | — |
| **M1-B** | M1-2+M1-3 | **控制器批（两个状态机）**：`SensorController` 整体（22 方法 + **48 字段** + 先扩 `state/GyroStore.ets`）＋ `RecordingController` 整体（23 方法 + 13 字段 + 自持 `videoStateTimer`/`recordViewCheckpointTimer`） | **~1,150 行** | 中 | M1-A（端口） |
| **M2-A** | M2-1+M2-2 | **`ObjectModelRenderer` 整体**：渲染/纹理提交 ＋ 触摸/光照 ＋ ~25 个 `objectInspectorModel*` 字段 ＋ 自持 `objectInspectorModelRenderTimer`；可观测子集入 `ObjectMediaStore` | ~750 行 | 中高 | M1-A |
| **M3-1/2/3** | 不变 | 天空输入骨架（89 字段）／天空输入主路径（`handleSkyTouch` 318）／选中服务决策片（搬或登记保留） | ~400+400+1,200 | 高 | — |

**预期收益**：M1 后宿主 **14,347 → ≈12,000 行**、`private` **593 → ≈500**（与 §15.10 同，仅片数 6 → 2）；M2 后再 − ~29 方法 / ~650 行。

**M1-A 片内顺序建议**：① 三端口（每落地一个即 构建/契约/真机冒烟）→ ② 服务层（`SpeechService` 最小 → `ImageDecoder` → `PlatformServices`）→ ③ `StartupBridge`/`SessionStore` → ④ P2 并入三域（各域独立小节，可与前序交错）。

**M1-B 片内顺序建议**：① 扩 `GyroStore` 可观测子集 → ② `SensorController`（订阅/回调 → 姿态解算/目标引导）→ ③ `RecordingController`（先搬定时器与 `start()/stop()` → 再搬行为）。

**片内提交纪律**：M1-A/M1-B **允许一片内多次提交**（如 ① 端口 ② 服务 ③ 控制器 各一次），但**同片内不停顿、不汇报**；片末在 CHANGELOG 记**总账**并标注 §15.11 队列行。
**回滚粒度**：片子变大后若整片不宜回滚，**以片内每个提交为回滚单位** —— 因此**片内每个提交必须自洽可构建**（构建/契约必须在每个提交点上跑过）。

#### 重排后队列（共 6 片）

| ID | 批次 | 组成 | 前置 | 状态 |
|---|---|---|---|---|
| **M1-A** | M1 | 端口组 + 服务层 + 启动/会话 + P2 并入（原 M1-1/4/5/6） | — | **已完成（2026-10-04）**：新增 3 端口（`MediaPort`/`PlatformPort`/`SensorPort` + 具名适配器）、4 服务（`common/media/ImageDecoder`、`common/platform/{Clipboard,Share,Screenshot}`、`common/SpeechService`）、`capability/StartupBridge`；`SessionToolStore` 并入会话四法；`ScriptStore`（脚本播放四法）/`GuideStore`（导览 + 自持定时器）并入。宿主 **14,357 → 14,161 行**、`private` **594 → 575**、`@State` **132 不变**；4 次提交 `333f51e23d`/`88dab09304`/`c61a693eb5`/`bf5b6b6ede`；登记保留：skyCulture 美术解码二法（§15.6-3）、启动隐私生命周期杂项（§15.6-4）、`toggleReplayPause`/`changePlaybackRate`（归 M1-B）、`setTrackingState`（引擎耦合） |
| **M1-B** | M1 | `SensorController` + `RecordingController`（原 M1-2/3） | M1-A | **已完成（2026-10-04）**：① `capability/SensorController.ets`（21 方法 + 52 私有字段；真传感器经 `SensorPort`（label 化 + 4 类型别名）、桥经 `CommandPort`、`watchGyro*` 实为桥驱动虚拟指星笔；`GyroStore` 可观测子集 M1-A 已齐备；`watchLastSend` 保留字段经 hooks）；② `capability/RecordingController.ets`（21 方法 + 12 私有字段 + 自持 `recordViewCheckpointTimer`/`replayTimer`；状态在 `ScriptStore` 不重复搬；`recordBuffer` 保留字段经 hooks；系统录屏 NAPI 收在扩展后的 `HostMediaPort`/`MediaPort`）；纳入 M1-A 遗留 `toggleReplayPause`/`changePlaybackRate`。宿主 **14,161 → 13,140 行**、`private` **574 → 536**、`@State` **132 不变**；2 次提交 `f452b228bf`/`7355472cfc`；真机三路传感器订阅 + callbacks 1→301 + `stopGyroscope` 归零、视频帧序列桥命令、脚本录制 UI 开关均存活；未走查：回放 UI（内层滚动容器）、系统录屏授权对话框、陀螺引导叠层 |
| **M2-A** | M2 | `ObjectModelRenderer` 整体（原 M2-1/2） | M1-A | **已完成（2026-10-04）**：新增 `capability/ObjectModelRenderer.ets`（540 行；12 方法 —— `renderObjectInspectorModel`(106) / `decodeObjectInspectorModelTextureFromPng`(46) / `commitObjectInspectorModelTexture`(36) / `clearObjectInspectorModelRenderer`(35) / `requestObjectInspectorModelRender`(25) / `handleObjectInspectorModelTouch`(57) / `refreshObjectInspectorModelLighting`(11) 等 + 22 个逐帧/草稿字段）；可观测子集留 `ObjectMediaStore`，逐帧字段留控制器（§15.7 规则 2）；`objectInspectorModelRenderTimer` 为**一次性防抖**（18ms，非周期轮询），控制器 `stop()` 清除、宿主 `aboutToDisappear` 收口；`MediaPort`/`HostMediaPort` 扩展 `createPixelMapFromRgba`/`readPixelMapPixels`（M1-B 式）。宿主 **13,140 → 12,800 行**、`private` 方法 **521 → 510**、`@State` **132 不变**；提交 `ab38bd25a9`；真机 `render pixel map created kind=object-inspector-model bytes=409600` + 触摸拖拽存活；未走查真双指捏合 |
| **M3-1** | M3 | `SkyInputController` 骨架（89 字段 + 鼠标/键盘/轴/惯性） | — | **部分完成（2026-10-05）**：新增 `capability/SkyInputController.ets`（265 行；8 方法 `handleSkyMouse`/`handleSkyKey`/`handleSkyAxis`/`handleSkyTap`/`resetSkyTapSequence`/`isSkyDoubleTap`/`startSkyInertia`/`stopSkyInertia` + 16 字段 + `SkyInputHostHooks` 18 法 + `CommandPort` fire + `NightModeStore` 注入）。宿主 **12,800 → 12,641 行**、`private` **510 → 503**、`@State` **132 不变**；提交 `3d97c8bec5`；真机拖拽（az→352.35°）/点选（η² Hyi）/缩放（fov 60→38.4→48）/惯性（fling 后 alt 继续收敛）逐项数值对照通过。**登记保留（安全 > 完成度）**：① 触屏主路径 `handleSkyTouch`(318)+`emitFluidDrag`(36) → **M3-2**；② §15.6 的 4 个 A2 热路径（`isUiPoint`/`skyZoomButtonAt`/`dockActionAt`/`expandedSafeTargetPoint`）均未动、经 hooks 调宿主；③ `centerSelectedObjectFromKeyboard`（选中管线交织）随 `handleSkyKey` 经 hooks；④ 键盘/鼠标路径无注入通道，**待真机人工** |
| **M3-2** | M3 | `SkyInputController` 主路径（`handleSkyTouch` 318） | M3-1 | **已完成（2026-10-05）**：`dragFollowAlpha`(6) / `emitFluidDrag`(36) / `handleSkyTouch`(318) 三法 + 26 个逐帧/草稿字段下沉 `capability/SkyInputController.ets`；M3-1 暂转移的 5 个共享草稿字段收回私有（宿主 15 处跨边界访问消失）；`SkyInputHostHooks` 18 → 63 法（新增 45，A2 热路径 `skyZoomButtonAt`/`dockActionAt` 经 hooks 回注）。宿主 **12640 → 12309 行**、`private` 方法 **503 → 500**、`@State` **132 不变**；提交 `93ae32db15`。**逐字等价（§15.7 规则 5）**：仅「取值经 hooks + `callNativeFire`→`commandPort.fire` + 所有权转移」，比较边界/分支/取整/事件判定未动，`f712b2e517` 的拖拽归属修复两处逐字保留。真机 8 项数值对照通过（拖拽 az 0.0006→352.31 / 竖直 alt 11.39→1.46、点选 0→1、缩放 60→48→38.4→48、惯性 az 10.35→20.85→21.09 收敛；**归属回归：面板起手拖动 Δ≈1e-12 不转星图、星图起手 21.09→16.26 转动**）。**待真机人工**：双击清除（`devecocli doubleclick` 两次 Down 间隔 2.2s > 800ms，工装无法构造）、触摸反馈点视觉。 |
| **M3-3** | M3 | `SelectionService` 决策片（搬或登记保留） | — | **已完成（登记保留，2026-10-05）**：开工重测宿主 12,309 行 / `private` 500 / `@State private` 132；候选 6 法 ≈360 行（`applySelectedObject` 236 / `navigateSelectedObjectTo` 33 / `refreshSelectedObject` 29 / `requestSelectedDetails` 28 / `moveToSelectedObject` 19 / `scheduleSelectedObjectForUiChange` 15）、**47 个组件/宿主调用点**；判定**不可逐字等价整体搬入 `capability/SelectionService.ets`**，按 §9.3 与 §15.10 M3 许可**登记保留、0 行代码**。障碍：① 写 §15.6-1 两个保留 `@State`（`fullInspectorRequested`/`objectDetailConnectorLength`）+ 6 个媒体机制私有字段，搬入须双写或改保留决定（§14.8 规则 5 / §15.7 规则 6）；② `navigateSelectedObjectTo`/`placeSelectedObjectInSafeArea` 内联 `hilog` 4 处，服务层禁 NAPI（§15.7 规则 1）；③ 三法互调成环 + `refreshSelectedObject` 回环，47 入口散布于 `SkyInputHostHooks`/详情卡 `onCenter`/`onRefresh`/`onReselect` 等组件接口；④ 依赖 §15.6-2 A2 登记热路径 `expandedSafeTargetPoint`；⑤ 钩子面 ≥20、跨域 store 6 个。后续路径：先拆 `requestSelectedDetails` 550ms 主定时器 + `refreshSelectedObject` `detailRefreshGuard` 为独立 `DetailRefreshController`，或待 §7 V1→V2 后重评。验证：预检通过、构建 `BUILD SUCCESSFUL`、契约 44 锚点 intact（0 行文档片，不跑 `arkts_check`/测试/真机）。**M3 批次至此收尾（M3-1 部分 + M3-2 完成 + M3-3 登记保留）。** |

**建议首序**：`M1-A` → `M1-B` → `M2-A` → `M3-1` → `M3-2` → `M3-3`。

**仍未变**：§15.6 保留项、§15.7 硬规则、§15.8 度量与验收、§15.9 风险与取舍、M3 的"登记保留"许可（§15.10）。


### 15.12 位置域行为下沉（2026-10-05，D8；新增切片）

> **背景**：§15.10/§15.11 的 M 批止于 M3-3（SelectionService 登记保留）。本片继续 §15.10 的
> 「先普查 → 判定搬或登记」纪律，处理 STATE-REVIEW §10 的 **D8（位置 / 地图 / GPS）** 簇：
> 原宿主停在 `@Builder` 组件化阶段（Phase 3ai/3aj 只搬了 UI 与纯计算），**动作层仍在宿主**。
> 本片把行为下沉为控制器（P1）+ 并入既有 store（P2），并新增 `LocationPort`（§15.7 规则 7：端口先行）。

#### 15.12.1 开工普查（基线：宿主 12,382 行 / `private` 方法 520 / `@State private` 132）

| 方法 | 行 | 判定 | 去处 / 依赖 |
|---|---:|---|---|
| `useDeviceLocation` | 43 | **搬** | `capability/LocationController`（NAPI→`LocationPort`；隐私门禁→hooks） |
| `applyPickerLocation` | 5 | **搬** | 同上 |
| `setLocation` | 51 | **搬** | 同上（桥→`CommandPort`；头部三 `@State`→hooks；观测星球写→hooks） |
| `setObserverPlanet` | 15 | **搬** | 同上（`CommandPort.requestInteractive`） |
| `saveObserverLocationToStorage` | 17 | **搬** | 同上（preferences→`LocationPort.writeObserverLocation`） |
| `readObserverLocationStorage` | 9 | **搬** | 同上（→`LocationPort.readObserverLocation`） |
| `restoreObserverLocation` | 20 | **搬** | 同上（启动恢复钩子改指向） |
| `locationMapWidth` / `locationMapHeight` | 6+3 | **搬（几何随组件）** | `panels/location/LocationPickerPanel` |
| `updatePickerFromMap` / `handleLocationMapTouch` | 8+26 | **搬（组件内触摸）** | 同上（点选后的 apply 走既有 `onApply` 回调） |
| `setPickerLocation` | 7 | **拆** | `LocationPickerStore.setPickerLocation`（控制器/组件共用纯 setter） |
| `searchLocations` | 31 | **搬（P2）** | `state/LocationStore`（跨域助手经 `LocationStoreHostHooks`） |
| `scanLocationSearchChunk` | 74 | **搬（P2）** | 同上 |
| `selectSearchLocation` | 6 | **搬（P2）** | 同上（`setLocation` 经 hooks） |
| `saveCurrentLocation` | 19 | **搬（P2）** | 同上 |
| `deleteSavedLocation` | 4 | **搬（P2）** | 同上 |
| `persistSavedLocations` | 12 | **搬（P2）** | 同上（**AppStorage 存储方式原样保留**） |
| `selectCityByName` / `selectContinent` / `selectCountry` / `selectRegion` | — | **登记（薄胶水）** | 层级状态写 `LocationPickerStore` + 一次 `locationCtl().setLocation` 调用点 |
| `handleUiTap` 的 GPS 命中区 / `handleChip` 城市 chip | — | **登记保留** | 壳层命中/快捷键分发（§15.6-4） |

#### 15.12.2 端口与适配器

- **`bridge/LocationPort.ets`**（18 行，纯接口）：`requestLocationPermissions` / `getCurrentLocation`（返回具名
  `LocationFix`）/ `readObserverLocation` / `writeObserverLocation`。
- 宿主具名适配器 **`HostLocationPort implements LocationPort`**（§15.7 规则 4）：承载 `abilityAccessCtrl` +
  `ohos.permission.APPROXIMATELY_LOCATION|LOCATION`、`geoLocationManager.getCurrentLocation`（ACCURACY /
  DAILY_LIFE_SERVICE / maxAccuracy 2000 / timeoutMs 5000）、`@ohos.data.preferences`（store `LOCATION_STORE`，
  key `location`）。`aboutToAppear` 里 `configure(getUIContext)`。

#### 15.12.3 完成结论与度量（2026-10-05）

- 新增：`bridge/LocationPort.ets`（18）、`capability/LocationController.ets`（194）。
- 修改：`state/LocationStore.ets` 69 → 267（+198）；`state/LocationPickerStore.ets` +11（`setPickerLocation`
  纯 setter）；`panels/location/LocationPickerPanel.ets` +68（内收地图几何/触摸 + 触摸草稿字段）；
  `panels/panels/PlacePanel.ets` +11（`mapWidth/mapHeight`→`expandedLayout/skyWidth`）。
- 宿主：**12,382 → 12,111 行（−271）**、**`private` 方法 520 → 504（−16）**、`@State private` **132 不变**。
- 验证：`check-ohos-refactor-slice` 通过；`arkts_check` 7 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；
  `test-ohos-privacy-startup` 19/19 全绿（用例改指 `LocationController` + `HostLocationPort`）；全量脚本扫描仅
  §13.6 的 6 个环境类失败。
- 真机（192.168.50.108:36717）：地图点选 → `command received: "setLocation"`（组件内几何/触摸 + 控制器 + 端口全链路）；
  点选后头部坐标实时刷新 `51.75°N / 82.67°W` 且**重启后观测点保持**（`[location] restoring persisted observer location`
  + `setLocation` 重放），`pidof` 存活。
- **未走查（待真机人工）**：GPS 权限弹窗路径（需授予/撤销系统权限）；保存点/删除与城市 chips（嵌套滚动较深）；
  层级城市落地 `selectCityByName`（内层过滤未变，调用点仅改指向控制器）。
- 逐字等价（§15.7 规则 5）：`setLocation` 为高频动作路径，仅「`this.<宿主字段>`→store/hooks/port」，
  比较边界/分支/三步回退（`setLocation`→`setLocationCoords`→`setLocationByName`）未改。


#### 15.12.4 D 轨道 D0/D1 完成结论与度量（2026-10-05）

> **背景**：M3-3 后进入 STATE-REVIEW §10 的 **D 轨道**（行为控制器下沉，17 簇）。首切两片：**D0**（hook 基础设施，
> 解开 §10.3 的 `refreshState` / 面板路由阻塞）与 **D1**（§10.2「详情连接线/刷新定时器」，最干净首切）。

**D0：行为控制器 hook 基础设施**

- 新增 `capability/ControllerHooks.ets`：纯接口 `BehaviorHostHooks { refreshState() / flashHint(text: ResourceStr) / panelChange(panel, visible) }`，不 import NAPI/UI（§15.7 规则 1）；后续 D 轨道控制器接口 `extends BehaviorHostHooks`。
- 宿主新增具名 `behaviorHooks(): BehaviorHostHooks`：`refreshState → this.refreshState()`；`flashHint → this.flashHint`；`panelChange → this.activePanel = panel; this.panelVisible = visible; this.syncDockClockTimer()`（与 §10.3 第 2 条逐字一致）。
- 本段不迁任何簇，构建/契约绿。

**D1：详情连接线 / 详情刷新定时器 → `capability/DetailConnectorController.ets`**

- 新增 `capability/DetailConnectorController.ets`（353 行；`DetailConnectorHostHooks extends BehaviorHostHooks`）。逐字下沉 12 法：`startDetailAutoRefresh` / `stopDetailAutoRefresh` / `pauseDetailRefreshForSkyDrag` / `resumeDetailRefreshAfterSkyDrag` / `startObjectDetailConnectorRefresh` / `stopObjectDetailConnectorRefresh` / `armObjectDetailConnectorTransition` / `refreshObjectDetailConnector` / `clearObjectDetailConnector` / `rayRectIntersection` / `segmentRectEntryFraction` / `objectDetailCardY`。
- **迁出私有字段（9）**：`detailTimer` / `detailRefreshing` / `detailRefreshGuard` / `objectDetailConnectorTimer` / `objectDetailConnectorAnimationTimer` / `objectDetailConnectorLastPanelVisible` / `objectDetailConnectorLastActivePanel` / `objectDetailConnectorLastClippedByUi` / `objectCardPlacementPending`。定时器自持 `start()/stop()`；宿主 `aboutToDisappear` 与清除选中处改调 `stop()`（§15.7 规则 3）。
- **登记保留（实测引用点全在宿主非 D1 方法）**：`objectCardDragging` / `objectCardDragStartX/Y/OffsetX/OffsetY`（唯一引用点 `handleObjectInspectorDragTouch`）、`objectDetailTabTransitionId`（唯一引用点 `selectObjectDetailTab`）——§10.2 字段清单含它们，但「以实测引用点为准」，不在 D1 方法集内故不迁。
- **@State 留宿主、经 hooks 逐帧 get/set（§15.7 规则 2）**：`objectDetailConnectorX/Y/Length/Angle/EndX/EndY/TargetX/TargetY/TargetOnScreen` 9 个 + `objectDetailConnectorAnimateGeometry`；`objectDetailContentOpacity/TranslateX` 未被 D1 引用、原样留宿主。
- **保留宿主、经 hooks 回读**：`objectDetailConnectorObstacles`（A2-5 登记宿主控制器）、`refreshSelectedObject`、`scheduleSkyTextureStatusCheck`、几何派生 `detailCardX/Y/Width/Height`、`bottomCardY`/`hoverBottomCardY`、`skyWidth`/`skyHeight`、`isFoldHoverLayout`、`panelVisible`/`activePanel`/`skyDragging`、`connectorVisible()`。
- **端口说明**：D1 唯一桥调用 `getGyroGuidePosition` 的回包需强转 `GyroGuideProjection` 而控制器禁 `as`，故未注入 `CommandPort`，按 `SensorController.guideProjection` 先例以 hook `gyroGuideProjection()` 由宿主强转后回注（§15.7 规则 4）。
- **逐字等价（§15.7 规则 5）**：`refreshObjectDetailConnector` 仅改取值来源（`this.<宿主字段>` → `this.hooks.*` / 控制器私有字段），比较边界与分支结构未改；宿主保留方法 `refreshSelectedObject` 仅把 `detailRefreshing`/`detailRefreshGuard` 的读写改为控制器 API——二者所有权随 D1 移交控制器（§15.6-6 相应项随之修订，即 M3-3 记录的后续路径）。
- **度量**：宿主 **12,111 → 11,906 行（−205）**、`private` 方法 **502 → 492（−10）**、`@State private` **132 不变**；新增 2 文件。
- **验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 3 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；`test-ohos-detail-live-values.mjs` 7/7 全绿（第 4 用例改读控制器 + hooks 断言）；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。
- **真机（192.168.50.108:36717）**：`Smoke: PASS`；`verify_ui` 走通「搜索 → 选中 Sirius → 详情卡 → 拖动星图」，`pidof` 存活、hilog 无 jscrash。连接线本体未目视确认（天狼在地平线下 −82°，按设计隐藏）；未走查：地平线上目标的连接线跟随与遮挡过渡动画（待真机人工）。


#### 15.12.5 D 轨道 D2/D11/D12/D16 完成结论与度量（2026-10-05）

> **背景**：D0/D1 之后并行推进 STATE-REVIEW §10.2 的四个"低风险"簇：D2 图层/视图标签、D11 SkyTexture
> 状态观察、D12 星云纹理（三簇 P1 控制器），以及 D16 夜视模式/儒略日（P2 并入既有 store，不新建控制器）。
> 三控制器接口沿用 D0 的 `extends BehaviorHostHooks`；本片续做被中断的 staged 文件并补齐 D16。

**新增文件**

- `capability/LayerController.ets`（251 行；10 法 + `viewTabTransitionId`/`configTabTransitionId` 2 字段 + `LayerHostHooks`）。
- `capability/SkyTextureStatusController.ets`（166 行；6 法 + 4 字段 + 3 常量；定时器自持 `start()`/`stop()`）。
- `capability/NebulaTextureController.ets`（113 行；6 法 + `NebulaTextureHostHooks`）。

**修改**

- `bridge/MediaPort.ets` **+9**：新增具名 `MediaImportResult` 与 `pickDocumentToDir`（D12 单文件导入）；宿主 `HostMediaPort` 具名实现（picker/`fileIo` 逐字保留）。
- `state/NightModeStore.ets` **+56**：夜视三法 + `pendingNightMode`/`pendingNightModeUntilMs` + `attachPort`（`request('setNightMode')`）。
- `state/JulianDateStore.ets` **+90**：儒略日三法 + `julianDateApplyInFlight` + `attachPort`/`attachHooks`（`wheel().syncFromSimulation` 与 `refreshSimTimeLight` 回注）。
- `state/TelescopeStore.ets` **+13**：第 7 法 `persistEquatorialMount`（实测归 `equatorialMount` 所在 store）。
- 宿主 `MainWindowNativeNode.ets`：删 29 法 + 6 字段，增 3 控制器惰性构造器、端口/hooks 接线与全部调用点改指向。

**D16 判定**：STATE-REVIEW §10.2 建议并入 `sessionToolStore`/`OverlayStore`，但实测三簇分别只读写
`nightModeStore`/`julianStore`/`telescopeStore`，按"以实测引用点为准"归各自域 store（语义唯一真源）。

**度量**：宿主 **11,906 → 11,370 行（−536）**、`private` 方法 **492 → 466（−26）**、`@State private` **132 不变**；新增 3 文件、扩展 1 端口。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 8 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；`test-ohos-plugin-panel-state` 4/4 / `test-ohos-settings-choice-motion` 4/4 / `test-ohos-startup-stars` 17/17 / `verify-ohos-julian-date` 通过（4 夹具同步改读控制器/store）；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。

**真机（192.168.50.108:36717）**：图层开关（`setLayer`）+ 预设（`setActionStates`）、SkyTexture 轮询（`getDeepSkyImageStatus`）、星云刷新（`refreshNebulaTextures`）+ 开关（`setNebulaTexturesVisible`）、儒略日（`setJulianDate`）、夜视模式（`setNightMode true` → 整界面转红，`false` 复原）逐项经 hilog/截图实证；`pidof` 存活、无 jscrash。

**未走查（待真机人工）**：图层面板「地景/文化」页地景加载（`viewTab===4`）；星云「导入图片」picker 路径；星云条目 `goto`/`remove`；标签切换两段动画的视觉本体。


#### 15.12.6 D 轨道 D9/D15 完成结论与度量（2026-10-05）

> **背景**：D2/D11/D12/D16 之后续做 STATE-REVIEW §10.2 的 **D9（Ocular / 望远镜工具）** 与
> §10.5 的 **D15（目录下载 / 书签）**。D9 为两个 P1 控制器；D15 为 P4，按实测并入既有 store
>（`CatalogStore`/`ObservingListStore`/`BookmarkStore`），**不新建 service**。

**新增文件**

- `capability/OcularController.ets`（180 行；16 法 + `equationOfTimeMutationId`/`archaeoMutationId` 2 草稿字段；注入 `CommandPort` + 4 store）。
- `capability/TelescopeController.ets`（269 行；12 法；注入 `CommandPort` + `TelescopeStore`；定时器仍由 store 自持）。

**修改**

- `state/CatalogStore.ets` **+72**：`startCatalogDownload` / 私有 `pollCatalogStatus`（600ms setInterval 自我收口）+ `CatalogHostHooks.flashHint`。
- `state/ObservingListStore.ets` **+14**：`persistObservingList` + `saveObservingListStorage` hook。
- `state/BookmarkStore.ets` **+55**：`addCurrentBookmark` / `gotoBookmark` / `deleteBookmark` + `flashHint` hook。
- 宿主 `MainWindowNativeNode.ets`：删 34 法 + 2 字段、新增 2 控制器惰性构造器与 3 hook 适配器、全部调用点改指向、清理 8 个未用导入。
- `scripts/test-ohos-plugin-panel-state.mjs`：`setMosaicCamera` 夹具改读 `OcularController`。

**D9 判定**：STATE-REVIEW 记「27 法（Ocular 17 + Telescope 10）」，工作区实测 **Ocular 16 + Telescope 12 = 28 法**（估数偏差 1）。`setPointerCoordinates` 位于目镜区块但写 `overlayStore`、属 D6，未搬。

**D15 判定**：6 法全部并入对应既有 store（无新 service）；`pollCatalogStatus` 的 600ms setInterval 为**自我收口**轮询，随方法留在 store（非 §15.7 规则 3 所指的持续定时器）。

**度量**：宿主 **11,370 → 10,938 行（−432）**、`private` 方法 **466 → 434（−32）**、`@State private` **132 不变**；新增 2 文件、扩展 3 store。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 6 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；`test-ohos-plugin-panel-state` 4/4 全绿；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。

**真机（192.168.50.108:36717）**：目镜开关（`setOcularMode`→`getOculars`）、望远镜保存/测试连接（`saveTelescopeProfile`/`testTelescopeConnection`）、均时差（`setEquationOfTime`）、古天文线（`setArchaeoLineSetting`）、相机拼接（`setMosaicCamera`）、书签增/跳/删（`addBookmark`/`gotoBookmark`/`deleteBookmark`）逐项经 hilog 实证；星表下载入口渲染；`pidof` 存活、无 jscrash；测试改动的持久化设置均复原。

**未走查（待真机人工）**：`startCatalogDownload`/`pollCatalogStatus` 实际下载（当前构建无可用星表项）；望远镜 `readTelescopePosition`/`lx200Goto*`/`lx200Sync*`/`lx200Abort` 按钮（需滚至控制区）；目镜/望远镜滑杆。


#### 15.12.7 D 轨道 D5/D6/D13 完成结论与度量（2026-10-05）

> **背景**：D9/D15 之后续做 STATE-REVIEW §10.2 的三个 P1 簇 —— D5 极轴镜、D6 视图中心坐标叠层、D13 卫星行为。
> 三控制器均 `CommandPort` + 对应 store + 具名 hooks；D5 接口 `extends BehaviorHostHooks`，D6/D13 按实测需要
> 自定义 hook（不含 `refreshState`/`flashHint`/`panelChange`）。

**新增文件**

- `capability/PolarScopeController.ets`（212 行；9 法 + 4 私有字段；定时器自持 `stopPolarScopeTimer()`/`syncPolarScopeTimer()`）。
- `capability/ViewCoordinateController.ets`（162 行；8 法 + 8 草稿字段；定时器自持）。
- `capability/SatelliteController.ets`（152 行；8 法；无定时器）。

**修改**

- 宿主 `MainWindowNativeNode.ets`：删 25 法 + 11 字段声明 + 1 未用导入，增 3 惰性构造器与全部调用点改指向。
- `scripts/test-ohos-satellite-panel.mjs`：2 用例改读控制器 + 宿主动画 hook 断言。

**D5 判定**：实测 9 法（与 STATE-REVIEW 一致）。`polarScopeTopInset`/`ControlWidth`/`FooterHeight` 属 A-保留 51（§15.6-2），留宿主经 hooks 回注。桥回包 flags/location 的 `as Record<...>` 抽取收口宿主 hook（控制器禁 `as`）。

**D6 判定**：STATE-REVIEW 记「16 法 + 10 私有字段」，工作区实测为 **8 行为法 + 5 几何法（A-保留 51，留宿主）+ 8 草稿字段**：`utcOffsetHours` 引用点全在 D6 方法集之外（dock 时钟 / 时间格式化 / TimeWheel 钩子），属跨域共用，按 §15.6-1 留宿主；4 个 @State 属 §2.7.1 G 类逐帧保留裸字段，按 §15.7 规则 2 留宿主、经 hooks 读写。

**D13 判定**：STATE-REVIEW 记「11 法」，实测卫星域 9 个 `private` 方法 = 1 `publish*`（§15.6-4 保留，只迁调用方）+ 8 行为；`requestSatellitePasses` 归选中管线（M3-3）。实测 8 法均不调 `flashHint`；`frameSatellite` 无动画，`animateTo` hook 服务于 `selectSatelliteGroup` 的 180ms 分组过渡。

**度量**：宿主 **10,939 → 10,682 行（−257）**、`private` 方法 **436 → 414（−22）**、`@State private` **132 不变**；新增 3 控制器文件。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 4 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；`test-ohos-satellite-panel` 7/7 全绿；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。

**真机（192.168.50.108:36717）**：D5 `openUiPanel polarScope` → `setPolarScopeOverlay`/`centerPolarScope`/`setFOV 4` + 1s `getPolarScopeData`；水平翻转 → `setActionChecked "actionHorizontal_Flip|1"`（已复原）；关闭 → `applySessionState` 恢复快照。D6 设置开启叠层 → 50ms `getViewCenterCoordinates` 轮询；`ui drag` 叠层 `[216,455]→[313,552]`，拖回并关闭复原。D13 `setSatellitePanelGroup beidou` → `getSatellites "beidou||40"`（已复原）。`pidof` 存活、无 jscrash。

**未走查（待真机人工）**：极轴镜回中按钮；卫星 TLE 导入与「定位卫星」`frameSatellite`（需从今夜天象卡片跳转）；卫星显示开关（经单测覆盖）。






#### 15.12.8 D 轨道 D7/D14 完成结论与度量（2026-10-05）

> **背景**：D5/D6/D13 之后续做 STATE-REVIEW §10.2 的 **D7（AstroCalc 行为）** 与 **D14（插件功能）**。
> 两片均为 P1 控制器；D7 涉天文计算面板全部动作 + CSV 导出 + 上下文定时器，D14 涉插件加载与跨域路由。

**新增文件**

- `capability/AstroCalcController.ets`（429 行；29 行为法 + 7 私有字段；注入 `CommandPort`/`MediaPort` + `astroStore`/`ephemerisStore`/`wutStore`/`searchStore` + `AstroCalcHostHooks`；定时器自持 `syncAstroCalcContextTimer`/`stopAstroCalcContextTimer`）。
- `capability/PluginFeatureController.ets`（183 行；8 行为法 + `pluginFeatureLoading`；注入 `CommandPort` + `pluginStore`/`searchStore`/`astroStore` + `PluginFeatureHostHooks`）。

**修改**

- `bridge/MediaPort.ets` **+3**：新增具名 `saveTextFileAs(text, fileName, suffixLabel, onDone)`；宿主 `HostMediaPort` 逐字承载原 `exportCurrentAstroCsv` 的 `fileIo.writeSync` + picker + `fileIo.copy` 段。
- 宿主 `MainWindowNativeNode.ets`：删 38 法 + 9 字段声明 + 4 未用导入，增 2 惰性构造器（`astroCalcCtl()`/`pluginFeatureCtl()`）与全部调用点改指向。
- `scripts/test-ohos-astro-motion.mjs`：夹具改读 `capability/AstroCalcController.ets`（假 hooks 提供 `animateAstroIn/Out` + `astroPanelOnScreen`）。

**D7 判定**：STATE-REVIEW §10.1 记「32 法」（含 5 个 `chooseXxxStartDate` / 3 个 `openXxxTargetPicker`）；实测 **4 个 choose（无 `chooseWutStartDate`，RTS 的为 `chooseRtsCalendarStartDate`）+ 4 个 picker + 22 个其余 = 30 法 = 29 行为 + 1 `publish*`**。`publishAstroPanelState`（§15.6-4）本体留宿主、只迁调用方，宿主经 `requestedAstroTab()`/`astroTransitionSerial()` 回读 `astroRequestedTab`/`astroTransitionId`。4 个 `fmt*` 留控制器（非 `common/derive/`；理由：AstroStore 已以 `AstroHostHooks.fmtDateTime` 消费同一实现，留此零改动 store 接口）。

**D14 判定**：STATE-REVIEW §10.1 记「10 法」；实测 8 行为法（`pluginZh`/`pluginDesc`/`pluginFeatureRoute` 属 `common/derive/labels` 纯函数，不属行为层）。`openPluginFeatureAfterLoad` **可逐字等价下沉**（`astroStore`/`searchStore` 直注，`viewTab`/`openSubPanel` 经 hooks），非登记保留；原 `ensurePluginLoaded` 两处 hilog 诊断日志按 §15.7 规则 1 不再保留。

**度量**：宿主 **10,682 → 10,288 行（−394）**、`private` 方法 **414 → 378（−36）**、`@State private` **132 → 131（−1，死字段 `pickedDate` 随 choose 迁移后零引用删除）**；新增 2 控制器文件、扩展 1 端口。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 4 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；`test-ohos-astro-motion` 9/9 全绿；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。

**真机（192.168.50.108:36717）**：`Smoke: PASS`；`openUiPanel astro` + `setAstroTab 2`（`transitionId=1`）/ `setAstroGroup 1`（tab→0、`transitionId=2`）/ `setAstroFilter direction|east`（`getAstroPanelState.direction=east`）；`openPluginFeature TelescopeControl`/`Oculars` → hilog `[cli-ui] opened plugin feature=...`（`ensurePluginLoaded` + `openPluginFeatureAfterLoad` 跨域路由存活）；`searchObject Sirius` → `getSelectedObjectInfo found:true`（`searchObject` 经 `astroCalcCtl().*PickerActive()` 回跳分支存活）；`pidof` 存活、无 jscrash；测试后 `setAstroTab 5` 复原持久化 tab。

**未走查（待真机人工）**：目标选择 picker 按钮（`devecocli` 简化树与 `verify_ui` 下均未呈现，需「未选天体且计算报错」态）；`chooseXxxStartDate` 的 DatePickerDialog 弹层；`exportCurrentAstroCsv` 的另存为 picker。


#### 15.12.9 D 轨道 D17/D10/D4 完成结论与度量（2026-10-05）

> **背景**：D7/D14 之后续做 STATE-REVIEW §10.2 的 **D17（对象检查器媒体）**、**D10（脚本录制回放 UI）** 与
> §10.6 队列末位的 **D4（时间操作）**。D4 曾因 `refreshState` 受阻，D0 的 `BehaviorHostHooks` 落地后解锁。

**新增文件**

- `capability/ObjectInspectorMediaController.ets`（约 470 行；15 法 + 11 私有字段；注入 `ObjectMediaStore`/`ObjectDetailStore`/`MediaPort` + `ObjectInspectorMediaHostHooks`；预热/body detail 定时器自持，`stop()` 收口）。
- `capability/ScriptPlaybackController.ets`（约 230 行；9 法 + 8 私有字段；注入 `ScriptStore`/`ToolsStore`/`CommandPort`/`MediaPort` + `ScriptPlaybackHostHooks extends BehaviorHostHooks`；250ms 状态轮询自持 start/stop）。
- `capability/TimeController.ets`（约 320 行；21 法 + 3 私有字段；注入 `TimeStore`/`TimeSettingsStore`/`DeltaTStore`/`CommandPort` + `TimeHostHooks extends BehaviorHostHooks`；时间面板 125ms/3000ms 定时器自持 `startPanelTimers()`/`stopPanelTimers()`）。

**修改**

- `bridge/MediaPort.ets` **+2 方法**：新增 `readRawSidecar(path, expectedBytes, label)`（`HostMediaPort` 逐字承载原宿主 fileIo open/read/close；`ObjectMediaStore` 的 `readRawSidecar` hook 改指端口）与 `importScriptDocument()`（脚本 picker/fileIo + 文件名清洗，`HostMediaPort` 具名实现）。
- 宿主 `MainWindowNativeNode.ets`：删 45 法 + 22 字段声明（含死字段 `scriptStartGraceUntil`）+ 7 个未用导入 + 死常量 `BODY_DETAIL_TEXTURE_PATHS`，增 3 惰性构造器与全部调用点改指向；`ObjectModelRenderer` 三个媒体管线 hook 改指 `objectInspectorMediaCtl()`；`TimeSettingsStore` 的 `applyTimeSettings` hook 与 `JulianDateStore` 的 `refreshSimTimeLight` hook 改指 `timeCtl()`；`ScriptStore` 的脚本 UI hooks 改指 `scriptPlaybackCtl()`。
- `scripts/test-ohos-settings-choice-motion.mjs`（第 4 用例改读 `TimeController` + `hooks.animateOption`）、`scripts/test-ohos-procedural-model.mjs`（第 11 用例改读控制器 + `mediaPort.fileExists`）、`scripts/test-ohos-startup-stars.mjs`（`dismissSplash` 夹具补 `objectInspectorMediaCtl()`）。

**D17 判定**：STATE-REVIEW §10.1 记 20 法；实测 15 行为法 + 11 字段（多出的含已随 M2-A 下沉 `ObjectModelRenderer` 的渲染/纹理法）。`objectInspectorInlineModelSize` 属几何 A-保留（宿主组件调用），未动；`readRawSidecar` 按"只迁宿主实现并改指向"上移 `MediaPort`（控制器不 import fileIo）。

**D10 判定**：STATE-REVIEW §10.1 记 13 法；实测 9 行为法 + 8 字段。`scriptControlSafeTop`（`getUIContext().px2vp` 属 UI 几何）留宿主经 hook；`scriptImportFileName` 随导入上移 `MediaPort`；`changePlaybackRate`/`toggleReplayPause` 已于 M1-B 在 `RecordingController`；死字段 `scriptStartGraceUntil` 删除（唯一真源在 `ScriptStore`）。

**D4 判定**：STATE-REVIEW §10.1 记 20 法；实测 21 法 + 3 字段（`setEquationOfTime` 已于 D9 迁 `OcularController` 不重复；`setConfigurationDateFormat` 留宿主但改调 `timeCtl().saveTimePreference`）。`fpsTimer` 属启动 splash 闪烁非时间域，留宿主；`utcOffsetHours`（§15.6-1）与 `timeSettingsPending`（§15.6-1 @State，SettingsPanel 消费）留宿主经 hook 回注。

**度量**：宿主 **10,288 → 9,512 行（−776）**、`private` 方法 **378 → 336（−42）**、`@State private` **131 不变**；新增 3 控制器文件、扩展 1 端口。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 5 文件 0 error（首轮构建暴露 2 处漏改 `this.applyManualTime`/`this.syncManualTimeFromState`，修后 `BUILD SUCCESSFUL`）；契约 **44 锚点 intact**；`test-ohos-settings-choice-motion` 4/4 / `test-ohos-procedural-model` 12/12 / `test-ohos-startup-stars` 17/17 全绿；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。

**真机（192.168.50.108:36717）**：`Smoke: PASS`。D4：时间面板 chips 点按实时刷新（快进→2x / 实时→1x / 停止→已暂停），面板时钟 125ms 轮询在跑（21:08:17→21:08:33）。D17：搜索 M4 → 详情卡「离线深空资料图像」→ 打开全屏预览，hilog `[detail-media-preview] open/image loaded/close`；D10：「导入脚本」唤起系统 `DocumentViewPicker`（`HostMediaPort.importScriptDocument`）并取消存活；`pidof` 全程存活、无 jscrash；测试后时间恢复「实时 · 1x」。

**未走查（待真机人工）**：脚本控制条拖动/回放速率/录制 UI 开关（需先进入录制会话，入口深于 3 步）；对象媒体预览「重试」（需解码失败态）；手动时间应用 / 日期选择器 / 时间设置写回（会改持久化设置）。


#### 15.12.10 D 轨道 D3 完成结论与 D 轨道收尾（2026-10-05）

> **背景**：D17/D10/D4 之后，STATE-REVIEW §10.6 队列仅剩末位 **D3（SkyCulture 行为，最大簇，估 ~1,126 行）**。
> 按 §15.6-3，`loadSkyCultureDetails` 永久保留宿主；本片把「选择/标签/视觉」「Art 预览」「Maker」三子域拆为
> 两个控制器，全部行为逐字下沉。

**新增文件**

- `capability/SkyCultureController.ets`（700 行；38 行为法 + 12 私有字段；注入 `CommandPort` + `MediaPort` + `SkyCultureViewStore` + `SkyCultureSettingsStore` + `SkyCultureHostHooks extends BehaviorHostHooks`；时间跟随 500ms 轮询与 Art 48ms/32ms 渐进定时器自持）。
- `capability/SkyCultureMakerController.ets`（507 行；24 行为法 + 6 私有字段；注入 `CommandPort` + `MediaPort` + `SkyCultureMakerStore` + `SkyCultureMakerHostHooks`；650ms 自动保存去抖自持 + `flushSkyCultureMakerSave()` 收口）。

**修改**

- `bridge/MediaPort.ets` **+6**：新增 `pickDocumentToDirNamed(dirName, fileSuffixFilters, buildFileName)`（Maker 美术图/文化包导入的 picker + fileIo 段逐字上移；宿主 `HostMediaPort` 具名实现）。
- 宿主 `MainWindowNativeNode.ets`：删 62 法 + 16 字段声明，增 3 私有方法（`correctSkyCultureRowScroll` / `skyCultureCtl()` / `skyCultureMakerCtl()`）与全部调用点改指向；`SkyCultureMakerStore` 两 hook 与 `LayerHostHooks.syncSkyCultureTimeFollowTimer` 改指控制器；CLI `setSkyCulture` 分支与 `aboutToDisappear` maker 定时器收口改指控制器。

**D3 三子域判定（以工作区实测为准）**：① 选择/标签/视觉 22 法 + 时间跟随 3 法 → `SkyCultureController`，薄桥 + store 写，逐字等价；`skyCultureColorOptions` / `skyCultureActiveColorTarget`（§15.6-2 A2 登记宿主控制器）经 hook 回读。② Art 预览 14 法 → `SkyCultureController`；渐进字段按 §15.7 规则 2 判定：`skyCultureArtStates` / `skyCultureArtThumbnailPixelMaps` 属 §2.7.1 L 高频渐进且被 LayersPanel 以宿主 `@State→@Prop` 消费，**字段本体留宿主、经 hooks get/set**（§15.6-1 与 §15.7-2 双重约束）；代际/定时器/pending 等非可观测字段留控制器；`drawSkyCultureTerritoryMap`（持宿主 `CanvasRenderingContext2D` + 画布尺寸，UI 类型）与 `skyCultureMapRenderWidth/Height` 留宿主（§15.7 规则 1）。③ Maker 24 法 → `SkyCultureMakerController`，完整 CRUD + 画布触摸 + 650ms 自动保存定时器自持。**`loadSkyCultureDetails` 回注确认**：本体留宿主（§15.6-3 永久登记），控制器经 `hooks.loadSkyCultureDetails()` 调用；共享序号 `skyCultureDetailsRequestId` 留宿主（§14.8 规则 3），控制器经 `hooks.skyCultureDetailsRequestId()` / `nextSkyCultureDetailsRequestId()` 读写。

**度量**：宿主 **9,513 → 8,646 行（−867）**、`private` 方法 **336 → 277（−59）**、`@State private` **131 不变**；新增 2 控制器文件、扩展 1 端口。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 4 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；`test-ohos-skyculture-refresh` 5/5 / `test-ohos-skyculture-text` 4/4 全绿；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。

**真机（192.168.50.108:36717）**：`Smoke: PASS`。`setSkyCulture tibetan` → `[sky-culture-anchor] id=tibetan delta=-13.3 offset=1878.4` + `[sky-culture-art] thumbnail ready ...` ×24 + `released pixel map kind=sky-culture-art-thumbnail`；`openUiPanel skyCultureMaker` → `新增星座` 渲染 `1 个星座` → `saveSkyCultureMakerDraft` 收到含 `constellation_1` 的草稿 → `校验草稿` → `validateSkyCultureMakerDraft`；`pidof` 全程 33488 存活、无 jscrash；测试后 `setSkyCulture modern` + `resetSkyCultureMakerDraft` 复原。**未走查（待真机人工）**：Art 大图预览叠层开合；领地地图 Canvas 重绘；标签模式 picker 选项弹层与收起动画本体；Maker 美术图导入 / 导出 picker。

**D 轨道收尾结论（17 簇全清）**：D 轨道基线 12,321 行 / 501 `private`；本队列依次完成 D0（`capability/ControllerHooks` 前置）→ D1/D2/D11/D12/D16 → D9/D15 → D5/D6/D13 → D7/D14 → D17/D10/D4 → D8（位置域 `LocationController`，§15.12.3）→ **D3（本片，末位最大簇）**。**17/17 簇全部落地**：迁出为控制器/并入既有 store，`loadSkyCultureDetails` 按 §15.6-3 永久登记、`SelectionService` 族按 §15.6-6 永久登记。宿主降至 **8,646 行**（自 D 轨道基线 **12,321 → 8,646，−3,675 行**，−29.8%）。

#### 15.12.11 E 轨道 E1：删死代码 + 位置层级选择薄胶水下沉（2026-10-05）

> **背景**：D 轨道收尾后进入 **E 轨道（设置/配置行为残余清理 + 薄胶水下沉）**。E1 为清理 + 小迁移片：删除 action bar 死链与零引用 `loadFov`，并把 D8（§15.12.1）登记为「薄胶水」的 `selectContinent` / `selectCountry` / `selectRegion` / `selectCityByName` 迁入既有 `capability/LocationController.ets`。

**删除的死代码（用户已确认；以零引用扫描为准）**

- 宿主 `MainWindowNativeNode.ets`：`showObjectActionBar`（硬编码 `return false`）、`objectActionBarX`、`objectActionBarWidth`、`isObjectActionBarPoint`（4 法，仅互调 + `isUiPoint` 一处恒假分支）、零引用 `loadFov`。
- `isUiPoint` 体内 `if (isObjectDetailCardPoint(...) || this.isObjectActionBarPoint(x, y))` 删恒假第二项，保 `isObjectDetailCardPoint(...)` 首项不变（语义等价）。
- geometry import 移除零引用的 `objectActionBarY`；其函数本体**保留**（`scripts/test-ohos-polar-scope.mjs` 以它为文本切分边界，production 已零引用）。

**位置 4 法迁出判定**：`selectContinent` / `selectCountry` / `selectRegion` / `selectCityByName` **逐字等价**迁入 `capability/LocationController.ets` —— 纯 store 写（`hier*` 取/清）与 `hierCities(...).find(...)` 过滤、`locationPlanet(found)` 判定一字未改；仅 `this.<宿主 store>` → 控制器持有的 `LocationPickerStore` / `SessionToolStore`，`this.locationCtl().setLocation` → 控制器内部 `this.setLocation`。宿主 4 个调用点（`PlacePanel` 回调）改指 `this.locationCtl().selectXxx(...)`。无新文件、无新端口。

**度量（ReadAllLines / UTF-8 口径）**：宿主 **8,646 → 8,587 行（−59）**、`private` 方法 **277 → 268（−9）**、`@State private` **132 不变**；`LocationController.ets` **214 → 245（+31）**。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 2 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；`test-ohos-polar-scope` 4/4、`test-ohos-privacy-startup` 19/19 全绿；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。真机（192.168.50.108:36717）：`Smoke: PASS`；层级选择 亚洲→丹麦→哥本哈根→哥本哈根 → `getObserverInfo` `Copenhagen / 55.6759 / 12.5655 / 14` + hilog `command received: "setLocation" "Copenhagen|55.6759|12.5655|14"`；切大洲「欧洲」验证下级列刷新与地区/城市清空；`pidof` 存活、无 jscrash；测试后经「地图选点 + 应用」复原 `自定义位置 / 21.34°N / 110.38°E / 0 m`。**未走查 / 记录**：层级列无 `--id`，交互用坐标点击（缺语义命令，已记录）；`objectActionBarY` 因测试脚本切片锚点保留。

#### 15.12.12 E 轨道 E2：显示 / 图层设置行为并入 LayerController（2026-10-05）

> **背景**：E1 之后继续清理「设置/配置行为残余」。E2 把宿主残留的 16 个显示 / 图层设置
> 行为并入既有 `capability/LayerController.ets`（D2 控制器；不新建文件，先普查后决定 —— 16 法
> 与 D2 同属「图层 / 显示」域，写同一组 store，`applyLayerSwitch` 本就分发到其中两法）。

**16 法逐条判定（以工作区实测为准）**

| 法 | 目标 | 判定 |
|---|---|---|
| `applyStarMagLimit` | `LayerController` | 逐字等价（`layerViewStore.starMagLimit` + `setLimitMagnitude`） |
| `applyMilkyWayBright` | `LayerController` | 逐字等价（`layerViewStore.milkyWayBright` + `setMilkyWayIntensity`） |
| `applyTrailColor` | `LayerController` | 逐字等价（`flashHint` 经 hooks） |
| `setOrbitDisplayFlag` / `setOrbitDisplayThickness` / `setOrbitColorStyle` | `LayerController` | 逐字等价（`setOrbitDisplaySetting`） |
| `setTrailDisplayFlag` / `setTrailDisplayNumber` | `LayerController` | 逐字等价（`setTrailDisplaySetting`） |
| `setLandscapeFadeWithZoom` / `changeLandscapeTransparency` | `LayerController` | 逐字等价 |
| `selectLandscape` | `LayerController` | 逐字等价（`landscapeDetailOpen` 经 hook `setLandscapeDetailOpen`） |
| `importLandscapeFile` | `LayerController` | picker/fileIo 经新增 `MediaPort.importLandscapeDocument()`；`landscapeImportFileName` 随之上移 `HostMediaPort` |
| `setScenery3dEnabled` / `setScenery3dScene` | `LayerController` | 逐字等价（`sceneryStore`） |
| `setSkyDisplaySetting` / `setBridgeFlag` | `LayerController` | **D2 遗留 hooks 实现迁入并移除 hooks**；`syncBridgeFlagState` 随 `setBridgeFlag` 下沉，`setViewLock` 分支经 hooks 回注宿主 |

**新增 hooks**：`setViewLockState(enabled)`（宿主既有动作，含选中判定 / `trackingText`）、`setLandscapeDetailOpen(value)`；**移除** `setSkyDisplaySetting` / `setBridgeFlag` 两个 D2 遗留 hooks。端口：`MediaPort` +1（`importLandscapeDocument`）。

**度量**：宿主 **8,587 → 8,437 行（−150）**、`private` 方法 **268 → 250（−18）**、`@State private` **131 不变**；`LayerController.ets` **250 → 487 行（+237）**；`MediaPort.ets` **103 → 107 行（+4）**；未新增文件。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 3 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。真机（192.168.50.108:36717）：`Smoke: PASS`；`applyStarMagLimit` 6.5→5.0（`getLimitMagnitude` enabled=true/5）、`applyMilkyWayBright` 3→4（`getMilkyWayIntensity` 1→1.33）、`setOrbitDisplayFlag`（`orbitIsolated` true→false）、`setSkyDisplaySetting`（「星星闪烁」关闭后条件子行消失）、`setBridgeFlag`（`getMeteors` true→false）、`selectLandscape`（guereins→hurricane→复原）、`changeLandscapeTransparency`（0%→55%，opacity 0.0027→0.55，复原）、`setScenery3dEnabled`/`setScenery3dScene`（enabled/current 变更并重启复原）；`pidof` 全程存活、无 jscrash。**未走查（待真机人工）**：`applyTrailColor` 的颜色输入应用、轨道/轨迹同域滑块与下拉、`setLandscapeFadeWithZoom` 开关、地景导入系统文件选择器。

#### 15.12.13 E 轨道 E3：设置面板选项行为 → `capability/SettingsController.ets`（2026-10-05）

> **背景**：E1/E2 之后继续「设置/配置行为残余」清理。E3 是 E 轨道收益最大片：把宿主残留的
> 18 个设置 / 配置行为逐字下沉到新控制器，另 1 个选择项本体（`applySelectedInfoMode` 属
> SelectionService 保留族）留宿主、只迁调用方并经 hook 回注（工作区实测 19 项 = 18 迁 + 1 登记）。

**新增文件**：`capability/SettingsController.ets`（351 行；18 行为法；注入 `CommandPort` +
`InfoWindowStore`/`TimeSettingsStore`/`NavigationSettingsStore`/`ViewSettingsStore`/`EphemerisStore`/
`ObjectDetailStore`/`ToolsStore`/`AtmosphereStore` + `SettingsHostHooks extends BehaviorHostHooks`。
不 import NAPI/UI，仅 `hilog`（与 `TimeController`/`LayerController` 先例一致）；桥经端口）。

**18 法逐条判定（以工作区实测为准）**

| 法 | 目标 | 判定 |
|---|---|---|
| `settingsChoiceSelected` | `SettingsController` | 逐字等价（纯 store 读，零副作用） |
| `selectSettingsChoice` | `SettingsController` | 逐字等价（分派到内部控制 + `hooks.setConfigurationTimeFormat`/`setStartupTimeSetting`） |
| `setInformationMode` | `SettingsController` | 逐字等价（`applySelectedInfoMode` → hooks；`refreshSelectedObject` → hooks） |
| `setInformationField` | `SettingsController` | 逐字等价（`informationMaskBit` 纯函数；刷新经 hooks） |
| `applyCustomInformationMask` | `SettingsController` | 逐字等价（纯 store 读改写 + `Map` 分组过滤） |
| `setConfigurationDateFormat` | `SettingsController` | 逐字等价（`saveTimePreference` 经 hooks，`TimeController` 本体留宿主） |
| `setConfigurationDithering` | `SettingsController` | 逐字等价（`viewSettingsStore` + `loadConfigurationSettings` 回滚） |
| `setDistanceUnit` | `SettingsController` | 逐字等价（`viewSettingsStore.useMetricUnits` + 回滚） |
| `setFovMarkerSetting` | `SettingsController` | 逐字等价（薄桥） |
| `setProjection` | `SettingsController` | 逐字等价（`currentProjection` 宿主 @State 经 `hooks.setCurrentProjection`） |
| `setNavigationBoolean` | `SettingsController` | 逐字等价（`navigationStore` 五分支 + `viewSettingsStore.autoZoomResets`） |
| `setNavigationMaxFov` | `SettingsController` | 逐字等价（1–360 取整后写 `navigationStore`） |
| `setEphemerisEnabled` | `SettingsController` | 逐字等价（未安装守卫 + 四 DE 分支写 `ephemerisStore`） |
| `saveAllCoreSettings` | `SettingsController` | 逐字等价（`saveAppSettings` 经 hooks） |
| `restoreCoreDefaults` | `SettingsController` | 逐字等价（薄桥 + 提示） |
| `exportConfig` | `SettingsController` | 逐字等价（`ToolsStore` 三字段；剪贴板经 `hooks.copyConfigExportText`，`PlatformPort` 适配器留宿主） |
| `importConfig` | `SettingsController` | 逐字等价（`ToolsStore` 消息/文本 + 桥） |
| `applyAtmosphereResponse` | `SettingsController` | 逐字等价（写 `AtmosphereStore`；两处 hook 调用点改指控制器） |
| `applySelectedInfoMode` | **登记保留宿主** | SelectionService 保留族（§15.6-6）：只迁调用方，本体经 `SettingsHostHooks.applySelectedInfoMode` 回注 |

**依赖注入**：`CommandPort`（`requestInteractive` / `requestWhenReady`）+ 8 个 store 实例引用 +
`SettingsHostHooks`（`applySelectedInfoMode` / `refreshSelectedObject` / `setCurrentProjection` /
`saveAppSettings` / `saveTimePreference` / `setConfigurationTimeFormat` / `setStartupTimeSetting` /
`copyConfigExportText`）。项目无控制器互调先例，故时间设置三法用具名 hook 回注，不注入 `TimeController` 实例。
`exportConfig` / `importConfig` 的响应类型收窄沿用既有控制器 `as` 先例（`OcularController` 等 9 处；§15.7-4 的 `as` 禁则限端口适配器）。

**宿主 `MainWindowNativeNode.ets`**：删 18 法 + 清 3 处未用导入（`ExportConfigResponse` / `ImportConfigResponse` / `informationMaskBit`）；增 1 惰性构造器 `settingsCtl()`；全部调用点改指向（SettingsPanel 13 个回调、LayersPanel 的 `onSetFovMarker`、SettingsQuickLegacyPanel 的 `onSetProjection`、ToolsPanel 的 `onExportConfig`/`onImportConfig`、`applySelectedObject` 的 `applyCustomInformationMask`、`AstroCalcHostHooks.applyAtmosphereResponse`、`timeStore.attachHooks.applyAtmosphereResponse`）。

**度量**：宿主 **8,437 → 8,244 行（−193）**、`private` 方法 **250 → 233（−17：删 18 + 增 `settingsCtl()`）**、`@State private` **131 不变**；新增 1 控制器文件（351 行）；未扩展端口/store。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 2 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**（33 面板 / 24 静态 id / 17 动态前缀 / 248 文件）；`test-ohos-information-policy` 3/3、`test-ohos-settings-choice-motion` 4/4 全绿（两夹具改读 `capability/SettingsController.ets`）；全量 `*-ohos*.mjs` 仅 §13.6 的 6 个环境类失败。真机（192.168.50.108:36717）：`openUiPanel settingsInformation` → 点「简短」→ `getInformationSettings` `default→short`、点「默认」复原（`selectSettingsChoice`→`setInformationMode`→控制器全链）；「主设置」页点「英里」→ hilog `setConfigString "astronomy/flag_use_km_for_distance=false"`，点「千米」→ `=true`（`setDistanceUnit` 控制器全链，已复原）；`pidof` 17031 全程存活、无 jscrash。**未走查（待真机人工）**：`保存设置`/`恢复默认`（`saveAllCoreSettings`/`restoreCoreDefaults` 点击未在 hilog 观察到对应 `saveAllSettings`/`restoreDefaultSettings`，疑被面板滚动/命中吞掉）；「视图导航」页（tab 条形横向滚动后不可见）的导航开关与最大 FOV 滑块；`exportConfig`/`importConfig` picker 与剪贴板；`setProjection`（视图导航页下拉）；`setFovMarkerSetting`（图层面板）；星历开关（当前构建 DE430/431/440/441 全部「未安装」，不可启用）。

#### 15.12.14 E 轨道 E4（末片）：搜索 / 音频 / 自检 / 视锁 / 今晚天象行为下沉（2026-10-05）

> **背景**：E3 后 E 轨道收尾片。按「先分组普查、按各法实际读写的 store / 依赖决定去处」处置 5 组 19 法：迁出 13、登记保留 3、并入既有控制器 2 + 既有 store 1。

**迁出（13 法）**

| 组 | 法 | 目标 | 判定 |
|---|---|---|---|
| 搜索 / 筛选 | `scheduleSuggestions` / `fetchSuggestions` / `selectSearchSuggestion` | **新** `capability/SearchController.ets` | 逐字等价；去抖定时器自持 `stop()`（§15.7-3）；`callInteractive`→`port.requestInteractive`；UI（`animateTo` / 滚动复位 / `publishSearchBrowserState` / `searchObject`）经 hooks |
| 搜索 / 筛选 | `refreshSearchFilterResults` / `selectSearchFilterCategory` / `selectSearchVisibilityFilter` / `selectSearchInstrumentFilter` / `setSearchFilterPage` | 同上 | 逐字等价（catalog 校验 + `animateTo` 220ms + `loadCategoryObjects` + 滚动复位） |
| 音乐 | `toggleMusic` / `persistMusicEnabled` | `state/AudioStore.ets` | 逐字等价；引擎经 `AudioStoreHooks.setMusicPlaying`；AppStorage 持久化在 store 内（同 `LocationStore` / `NightModeStore` / `TelescopeStore` 例） |
| 自检 | `selfTestAllActions`（+ `SELFTEST_ACTION_IDS` 83 项） | **新** `capability/SelfTestController.ets` | 逐字等价（`requestWhenReady` 0/100/120）；真机不可触发（编译常量 `SELFTEST=false`） |
| 视锁 | `setViewLockState` / `toggleViewLock` | `capability/LayerController.ets` | 逐字等价；**移除 E2 的 `setViewLockState` hook**，`setBridgeFlag` 的 `setViewLock` 分支改控制器内部直调；新增 `setTrackingText` hook 回注宿主 `trackingText` |
| 指针坐标 | `setPointerCoordinates` | `capability/ViewCoordinateController.ets` | 逐字等价（`requestWhenReady` 0/100/15，失败提示 `I18n.t('plugin_action_failed')`） |
| 今晚天象 | `refreshTonight`（+ 私有纯助手 `fmtIso`） | `state/SessionToolStore.ets` | 逐字等价（既有 `port` / `hooks.flashHint`；`fmtIso` 随之下沉） |

**登记保留（3 法，§15.6-4）**：`setLanguage`（`I18n.setLanguage` + `@StorageLink('i18nLang')` + `panelContentKey++` + 跨 store 重载 + `languageSwitchTimer` + AppStorage）；`setTrackingState` / `stopTracking`（与保留的 `refreshState()` 双向耦合 + 宿主 @State `trackingText` 经 @Prop 下发三壳层；§15.11 M1-A 已登记「引擎耦合」）；`refreshDockClock`（1s 节拍写 `dockClockText` / `currentFovText` 两个宿主 @State）。

**度量（ReadAllLines 口径，与 E1–E3 一致）**：宿主 **8,244 → 7,993 行（−251）**、`private` 方法 **233 → 219（−14：删 16 + 增 `searchCtl()`/`selfTestCtl()` 2）**、`@State private` **131 不变**；新增 2 控制器（`SearchController` 176 行 + `SelfTestController` 117 行）；`LayerController` 487 → 518、`ViewCoordinateController` 162 → 171、`AudioStore` 15 → 57、`SessionToolStore` 220 → 271；未新增端口 / store。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 7 文件 0 error；`BUILD SUCCESSFUL`；契约 44 锚点 intact（33 面板 / 24 静态 id / 17 动态前缀 / 250+ 文件）；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败。真机（192.168.50.108:36717）：搜索筛选全链（`setSearchBrowserPage browse/categories`、`setSearchBrowserFilter visibility|above` / `instrument|binocular`、`selectSearchCategory galaxy`→`NebulaMgr:0`，`getSearchBrowserState` 回读，测后复原）；详情卡「固定位置」→ hilog `setViewLock "1"`→`"0"`；音频面板「背景音乐」→ `StellariumAudio: muted = true`→`false`；位置面板 → `getTonightEvents`；Dock 时钟 1s 节拍；`pidof` 存活、无 jscrash。未走查：紧凑音频快捷 `toggleMusic`（无语义命令）、`pointerCoordinates` 面板（本布局内容为空、既有行为）、`selfTestAllActions`（`SELFTEST=false`）。

**E 轨道收尾结论（E1–E4 全清）**：E1 位置层级选择薄胶水 + 死代码、E2 显示/图层 16 法并入 `LayerController`、E3 设置选项 18 法 → `SettingsController`、E4 搜索/音频/自检/视锁/今晚天象。宿主 **8,646 → 7,993 行（−653）**、`private` **277 → 219（−58）**。**「几何不宜下沉」评审结论**：`viewCoordinateOverlayWidth/Left/Top` + `clampedViewCoordinateOffsetX/Y`、`bottomCardX/Y` 等几何助手与 A2 热路径（`isUiPoint` / `skyZoomButtonAt` / `dockActionAt` / `expandedSafeTargetPoint`）与布局 / 命中逐帧同源，下沉会割裂绘制—命中一致性，**保留宿主**（§15.6-2 已登记）。

#### 15.12.15 E 轨道 E5：解散 `SettingsController`，18 法按字段归属并回各 store（2026-10-05）

> **背景**：E3 曾把 18 个设置/配置行为收进 `capability/SettingsController.ets`（350 行）。E5 按「字段所在处即归宿 / 读本域 store 字段 → 并入该 store 方法」（§14.3，参照 D16 `syncNightModeFromEngine` / `applyJulianDate`）把控制器整体解散、方法并回各域 store，**不新建控制器**（§14.3 P2 范式）。

**18 法逐条归属（以工作区实测为准）**

| 法 | 归宿 | 判定 |
|---|---|---|
| `setInformationMode` / `setInformationField` | `state/InfoWindowStore.ets` | 逐字等价；桥经新增 `attachPort`；`InfoWindowHostHooks` 回注 `flashHint` / `applySelectedInfoMode` / `refreshSelectedObject` / `clearSelectedDetailLoaded` |
| `applyCustomInformationMask` | **`state/ObjectDetailStore.ets`（分配调整）** | 30 个被清字段 + `selectedDetailFields` 过滤全在本 store；`informationMode` 与掩码谓词以参数传入（避免 store 相互 import） |
| `saveAllCoreSettings` / `restoreCoreDefaults` / `exportConfig` / `importConfig` | `state/ToolsStore.ets` | 逐字等价；hooks 增 `saveAppSettings` / `copyConfigExportText`；`ExportConfigResponse` / `ImportConfigResponse` 随方法迁入 |
| `setNavigationBoolean` / `setNavigationMaxFov` | `state/NavigationSettingsStore.ets` | 逐字等价；hooks `flashHint` / `setAutoZoomResets`（autoZoomResets 分支写 ViewSettingsStore） |
| `setEphemerisEnabled` | `state/EphemerisStore.ets` | 逐字等价；hook `flashHint` |
| `setConfigurationDithering` / `setDistanceUnit` / `setFovMarkerSetting` / `setProjection` | `state/ViewSettingsStore.ets` | 逐字等价；hooks `flashHint` / `setCurrentProjection` / `reloadConfigurationSettings` / `logProjectionError`（store 不 import hilog） |
| `applyAtmosphereResponse` | `state/AtmosphereStore.ets` | 逐字等价（纯回包写本域 4 字段，无端口 / hook） |
| `setConfigurationDateFormat` | **保留宿主** | 本体即 `timeCtl().saveTimePreference`，内联到宿主 `selectSettingsChoice` 的 `date` 分支 |
| `settingsChoiceSelected` / `selectSettingsChoice` | **保留宿主** | 跨 4 store 的谓词 / 分派，留宿主薄分派 |

**新增 / 补齐的 attachPort / hooks**：`InfoWindowStore`（+port +hooks）、`NavigationSettingsStore`（+port +hooks）、`EphemerisStore`（+port +hooks）、`ViewSettingsStore`（+port +hooks）、`ToolsStore`（hooks +2）；`AtmosphereStore` / `ObjectDetailStore` / `TimeSettingsStore` 无需新增（无端口依赖 / 以参数与既有 hook 传递）。端口复用 `HostCommandPort`（无 publish*，`attachPort(port)` 单参形态，同 `NightModeStore`）。宿主全部 `settingsCtl().setXxx` 调用点改指对应 store；删除 `SettingsController` / `SettingsHostHooks` import、`settingsControllerImpl` 字段与 `settingsCtl()` 访问器（零残留）。

**度量**：宿主 **7,992 → 8,017 行（+25）**、`private` 方法 **211 → 212（−1 删 `settingsCtl()` + 2 增薄分派）**、`@State private` **131 不变**；删除 `capability/SettingsController.ets`（350 行）；`InfoWindowStore` 57→147、`ObjectDetailStore` 231→284、`ToolsStore` 207→292、`NavigationSettingsStore` 25→99、`EphemerisStore` 43→92、`ViewSettingsStore` 36→135、`AtmosphereStore` 19→32。

**验证**：`check-ohos-refactor-slice` 通过；`arkts_check` 9 文件 0 error；`BUILD SUCCESSFUL`；契约 **44 锚点 intact**（33 面板 / 24 静态 id / 17 动态前缀 / 249 文件）；`test-ohos-information-policy` 3/3、`test-ohos-settings-choice-motion` 4/4 全绿（两夹具同步）；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败。真机（192.168.50.108:36717）：`Smoke: PASS`；信息模式 `default → short → default`（`getInformationSettings` 回读）、距离单位 `英里 → 千米`（hilog `flag_use_km_for_distance=false→true`）、时间面板冒烟（`AtmosphereStore` 消费方渲染）；`pidof` 存活、无 jscrash；测试改动的持久化设置已复原。**未走查同 E3**（保存设置 / 恢复默认 / 投影 / FOV 标记 / 抖动 / 星历 / 导出导入）。

#### 15.12.16 M 轨道 M1：DetailModel 渲染管线迁出 pages/（2026-10-06，纯路径迁移）

> **背景**：STATE-REVIEW §11 的 M 轨道（渲染管线 / 纯计算模块从 `pages/` 归位）。本片为 M 轨道第 1 片，**纯路径迁移**（`git mv` + 同步消费者相对深度），**不改任何运行逻辑**；开工 `git log -1` = `b675c48a0c`，宿主基线 7,573 行。

**文件移动清单（旧 → 新，`git mv` 保留历史）**

| 旧路径 | 新路径 | 行 |
|---|---|---:|
| `pages/DetailModelRenderTypes.ets` | `capability/DetailModelRenderTypes.ets` | 45 |
| `pages/DetailModelRenderClient.ets` | `capability/DetailModelRenderClient.ets` | 106 |
| `pages/DetailModelRasterizer.ets` | `capability/DetailModelRasterizer.ets` | 177 |
| `pages/DetailModelWorker.ets` | `capability/DetailModelWorker.ets` | 21 |
| `pages/DetailModelGeometry.ets` | `common/derive/DetailModelGeometry.ets` | 28 |
| `pages/ProceduralDetailModel.ets` | `common/derive/ProceduralDetailModel.ets` | 134 |

**Worker 入口路径字符串**：`DetailModelRenderClient` 的 `'entry/ets/pages/DetailModelWorker.ets'` → `'entry/ets/capability/DetailModelWorker.ets'`；`scripts/configure-ohos-model-worker.mjs` 的 `sourceOption.workers` 同步改新路径并补「旧→新就地改写」（生成项目 `build-profile.json5` 自动迁移）。

**消费者 import（5 文件 / 6 行）**：`ObjectModelRenderer`（3）、`ObjectInspectorMediaController`（1）、`ObjectDetailStore`（1）、`ObjectMediaStore`（1）、`common/derive/media.ets`（1）；移动文件内部 `DetailModelRasterizer → ProceduralDetailModel` 改走 `../common/derive/`。夹具 3 个同步改读新路径。

**度量**：宿主 `MainWindowNativeNode.ets` **7,573 → 7,573 行**（本片不动宿主）；无 store / 端口新增；净 15 文件、+36 / −23 行。

**验证**：预检通过；`arkts_check` 11 文件 0 error；`BUILD SUCCESSFUL`；契约 44 锚点 intact（249 文件）；受影响 3 测试全绿（12/12、6/6、7/7）；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败。真机（192.168.50.108:36717）：`Smoke: PASS`；`searchObject Mars` → hilog `[detail-model] CPU texture ready … source=sidecar` → `[detail-model] render pixel map created kind=object-inspector-model bytes=409600` → `[detail-media-card] sphere loaded`（worker 链路实证）；`pidof` 存活、无 jscrash。

#### 15.12.17 M 轨道 M2：位置参考数据三文件迁入 `common/location/`（2026-10-06，纯路径迁移）

> **依据**：STATE-REVIEW §11.2.4 的最终决定（三文件由同一脚本生成、被同两个 store 消费，故保持同目录；目录只放参考数据、不放逻辑，文件名去 `location_` 前缀）。本片为 M 轨道第 2 片，**纯路径迁移**（`git mv` + 同步消费者相对深度），**不改任何数据内容 / 运行逻辑**；开工 `git log -1` = `9bc9992c4b`，宿主 `MainWindowNativeNode.ets` 基线 8,017 行。

**文件移动清单（旧 → 新，`git mv` 保留历史，git 识别为 R100）**

| 旧路径 | 新路径 | 行 |
|---|---|---:|
| `pages/location_hierarchy.ts` | `common/location/hierarchy.ts` | 74,611 |
| `pages/location_names_zh.ts` | `common/location/names_zh.ts` | 7,350 |
| `pages/location_countries.ts` | `common/location/countries.ts` | 986 |

**消费者 import（3 文件 / 9 行）**：宿主 `pages/MainWindowNativeNode.ets`（3 行：`./location_*` → `../common/location/{hierarchy,countries,names_zh}`）；`state/LocationStore.ets`、`state/LocationPickerStore.ets`（各 3 行：`../pages/location_*` → `../common/location/*`）。导出名 `LOCATION_HIERARCHY` / `LOCATION_COUNTRY_NAMES` / `LOCATION_ZH_NAMES` 不变。

**生成器 / 夹具输出路径同步（4 脚本 / 7 处）**：`scripts/generate-ohos-location-hierarchy.mjs`（2）、`scripts/generate-ohos-location-zh.mjs`（2）、`scripts/check-ohos-i18n.mjs`（1）、`scripts/verify-ohos-location-search.mjs`（2）——否则下次生成会重新落回 `pages/`。

**度量**：宿主 `MainWindowNativeNode.ets` **8,017 → 8,017 行**（本片不动宿主）；无 store / 端口新增；净 7 个跟踪文件改动（3 重命名 + 3 消费者 import + 4 脚本内 7 处路径）。

**验证**：预检通过；`arkts_check` 3 文件 0 error；`BUILD SUCCESSFUL in 30s`；契约 44 锚点 intact（249 文件）；受影响 `verify-ohos-location-search` 全绿（7,387 地点中文名齐全 + 12 项本地化/归一化检索）；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败。真机（192.168.50.108:36717）：`pidof` 存活、无 jscrash；位置面板「按地区选」层级四列实证数据运行期可加载（大洲「亚洲」→ 国家/地区「不丹/东帝汶/中国」→ 地区「上海市/中国台湾地区/中国澳门特别行政区」→ 城市「上海」），点「上海」后坐标实时刷新为 `31.22°N / 121.46°E`、位置名「上海 · 地球」，`setLocation` 全链生效；测试改动的持久化观测点已恢复到测试前显示值。

#### 15.12.18 M 轨道 M3：导览模型与音频引擎迁出 pages/（2026-10-06，纯路径迁移）

> **依据**：STATE-REVIEW §11.2.2 / §11.2.3 的 M 轨道规划。本片为 M 轨道第 3 片，**纯路径迁移**（`git mv` + 同步消费者相对深度），**不改任何运行逻辑**；开工 `git log -1` = `0c73bbb6ed`，宿主 `MainWindowNativeNode.ets` 基线 8,017 行。

**文件移动清单（旧 → 新，`git mv` 保留历史）**

| 旧路径 | 新路径 | 行 |
|---|---|---:|
| `pages/AstronomyGuide.ts` | `common/derive/AstronomyGuide.ts` | 197 |
| `pages/StellariumAudio.ets` | `capability/AudioEngine.ets` | 927 |

**`AudioEngine` 落点判定（§15.7 规则 1）**：STATE-REVIEW §11.2.2 原记 `common/media/AudioEngine.ets`，但开工核查发现该文件**直接调用音频 NAPI**——`import { audio } from '@kit.AudioKit'` 且 `audio.createAudioRenderer(...)`（另 `import hilog from '@ohos.hilog'`）；§15.7 规则 1 要求 `common/*` 不 import NAPI，故按判定改落 **`capability/AudioEngine.ets`**。判定口径为「是否**调用**设备能力」而非「是否 import 其模块」：既有 `common/media/ImageDecoder.ets` 只把 `@kit.ImageKit` 用作 `image.PixelMap` 类型、设备能力调用均经 `MediaPort`，仍属合规的 `common/media/`；`AudioEngine` 真调 `createAudioRenderer`，故归 `capability/`。文件名按计划改为 `AudioEngine.ets`；原文件同时导出 `export class AudioEngine` 与 `export default AudioEngine`，**两种导出逐字保留**，运行期日志标签 `TAG='StellariumAudio'` **刻意不改**，故所有消费者 import 形式无需变更。

**内部相对深度（2 处）**：`capability/AudioEngine.ets` 的 `./StellariumTypes` → `../pages/StellariumTypes`；文件首行注释更新为新文件名（`AstronomyGuide.ts` 无 import，仅改路径）。

**消费者 import（4 文件 / 4 行）**：宿主 `pages/MainWindowNativeNode.ets`（`./AstronomyGuide` → `../common/derive/AstronomyGuide`、`./StellariumAudio` → `../capability/AudioEngine`）；`state/GuideStore.ets`（`../pages/AstronomyGuide` → `../common/derive/AstronomyGuide`）；`panels/guide/GuideLibrary.ets`（`../../pages/AstronomyGuide` → `../../common/derive/AstronomyGuide`）；`capability/StartupBridge.ets`（`../pages/StellariumAudio` → `./AudioEngine`）。导出名 `ASTRONOMY_GUIDES` / `AstronomyGuide` / `GuideState` / `GuideStep` / `AudioEngine` 全部保持不变。

**夹具同步（2 脚本 / 2 处）**：`scripts/test-ohos-guide.mjs`、`scripts/test-ohos-mist-horizon.mjs` 改读 `common/derive/AstronomyGuide.ts`。

**未改**：`docs/harmonyos/json/ui-contract-baseline.json` 的 `scannedFiles` 与历史 `CHANGELOG` / `HANDOFF.md` 构建产物索引（与 M1/M2 同例——`scannedFiles` 不参与契约 diff，历史文档不回改）。

**度量**：宿主 `MainWindowNativeNode.ets` **8,017 → 8,017 行**（本片不动宿主）；无 store / 端口新增；净 8 个跟踪文件改动（2 重命名 + 4 消费者 import + 2 夹具）。

**验证**：预检通过；`arkts_check` 5 文件 0 error；`BUILD SUCCESSFUL in 30s`；契约 44 锚点 intact（249 文件）；受影响 `test-ohos-guide`（9/9）/ `test-ohos-mist-horizon`（5/5）全绿；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败（4 个 `-pad` / `mist-performance` / `verify-ohos-search`）。真机（192.168.50.108:36717）：`devecocli run --skip-build` → `Smoke: PASS`；导览 CLI `startGuide solar-neighbours` → `getGuideState` 返回 `active/index/count` 与两条完整 `guides[]`、`guideAction next` 前进、`guideAction stop` 复位（`AstronomyGuide`/`GuidePlayer` 迁出后全链生效）；音频「更多功能 → 脚本与自动化 → 音频控制」→ AudioPanel 点「背景音乐」→ hilog `StellariumAudio: audio engine started (v2 ethereal)` + `muted = false`，再点 → `muted = true`（`AudioEngine` 迁出后 `createAudioRenderer` 成功；两次点按 off→on→off 已复原）；`pidof 4005` 全程存活、无 jscrash / 无 faultlog。

#### 15.12.19 M 轨道 M6：MediaPort 接口隔离（2026-10-06，类型层重构）

> **依据**：STATE-REVIEW §11 的 M 轨道第 4 片（接口隔离）。**类型层重构**，不改任何运行逻辑。`bridge/MediaPort.ets`（107 行 / 25 法）混了 5 个关注点；本片按接口隔离原则拆 5 个子接口，消费者只依赖其实测调用的最小接口；适配器 `HostMediaPort` 保持单一、`implements MediaPort` 不变。开工 `git log -1` = `b72f3c542b`。

**5 个子接口（`MediaPort.ets` 107 → 123 行；`MediaPort extends` 全部）**

| 子接口 | 法数 | 方法 |
|---|---:|---|
| `ImagePort` | 7 | `fileExists` / `openReadOnlyFile` / `closeFile` / `createImageSource` / `createPixelMap` / `releaseImageSource` / `releasePixelMap` |
| `ObjectModelMediaPort extends ImagePort` | 3（+7 继承） | `createPixelMapFromRgba` / `readPixelMapPixels` / `readRawSidecar` |
| `FileExportPort` | 3 | `saveFileAs` / `saveTextFileAs` / `deleteFile` |
| `DocumentImportPort` | 4 | `pickDocumentToDir` / `pickDocumentToDirNamed` / `importScriptDocument` / `importLandscapeDocument` |
| `ScreenCapturePort` | 8 | `screenVideoDir` / `makeDir` / `fileSize` / `hasActiveScreenCapture` / `beginScreenCapture` / `stopScreenCapture` / `releaseScreenCapture` / `saveVideoToGallery` |

**子接口互相 extends 的判定**：`ObjectModelMediaPort extends ImagePort`——`ObjectModelRenderer` 的模型纹理路径必然先经 `common/media/ImageDecoder` 的 `decodeLocalImage`/`releaseDecodedImage`（即 `ImagePort`）再做 `readPixelMapPixels`/`createPixelMapFromRgba`，故令其为超集（ArkTS 接口多继承合法），使该控制器只需一个字段类型。**ArkTS 禁交叉类型**（`arkts-no-intersection-types`，本片实测确认），跨接口消费者不用 `A & B`；`SkyCultureMakerController` 需 `ImagePort + DocumentImportPort`，改用本地组合接口 `SkyCultureMakerMediaPort extends ImagePort, DocumentImportPort`。

**消费者 → 最小接口对照表（以本片实测调用为准）**

| 消费者 | 实测调用方法 | 最小接口 |
|---|---|---|
| `common/media/ImageDecoder`（`decodeLocalImage`/`releaseDecodedImage` 的 `port`） | `openReadOnlyFile` / `closeFile` / `createImageSource` / `createPixelMap` / `releaseImageSource` / `releasePixelMap` | **ImagePort** |
| `capability/ObjectInspectorMediaController` | `fileExists`；经 `decodeLocalImage`/`releaseDecodedImage` | **ImagePort** |
| `capability/SkyCultureController` | `fileExists`；经 `decodeLocalImage`/`releaseDecodedImage` | **ImagePort** |
| `common/platform/Share` | `fileExists` | **ImagePort** |
| `capability/ObjectModelRenderer` | `readPixelMapPixels` / `createPixelMapFromRgba`；经 `decodeLocalImage`/`releaseDecodedImage` | **ObjectModelMediaPort** |
| `capability/AstroCalcController` | `saveTextFileAs` | **FileExportPort** |
| `common/platform/Screenshot` | `saveFileAs` / `deleteFile` | **FileExportPort** |
| `capability/LayerController` | `importLandscapeDocument` | **DocumentImportPort** |
| `capability/NebulaTextureController` | `pickDocumentToDir` | **DocumentImportPort** |
| `capability/ScriptPlaybackController` | `importScriptDocument` | **DocumentImportPort** |
| `capability/RecordingController` | `screenVideoDir` / `makeDir` / `fileSize` / `hasActiveScreenCapture` / `beginScreenCapture` / `stopScreenCapture` / `releaseScreenCapture` / `saveVideoToGallery` | **ScreenCapturePort** |
| `capability/SkyCultureMakerController` | `fileExists`；经 `decodeLocalImage`/`releaseDecodedImage`；`pickDocumentToDirNamed` | **ImagePort + DocumentImportPort**（本地组合接口 `SkyCultureMakerMediaPort`） |
| `pages/MainWindowNativeNode`（适配器 `HostMediaPort` / 字段 `hostMediaPort`） | `implements MediaPort`；直接调 `fileExists` / `saveFileAs` / `readRawSidecar`；向 `releaseDecodedImage` / `shareFile` / `saveScreenshot` 传参 | **保持 `MediaPort` 不变** |

**不改**：无任何方法体 / 调用序列 / 适配器实现 / `.id()` / `main_pages.json`；仅类型注解与 import 变更。方法签名、返回类型、注释**逐字保留**（仅搬家）；`MediaSaveResult` / `MediaImportResult` / `ScreenCaptureState` 保持导出。

**度量**：净 13 文件 +79 / −46；`MediaPort.ets` 107 → 123 行；宿主 `MainWindowNativeNode.ets` **8,017 → 8,017 行**（不动宿主）；无 store 新增。`state/ObjectMediaStore` 与 `state/ObjectDetailStore` **不 import MediaPort**（其 `readRawSidecar` 由宿主经 hooks 回注），故本片未触碰。

**验证**：`check-ohos-refactor-slice` 通过（括号深度 0）；`arkts_check` 13 文件 0 error；`BUILD SUCCESSFUL in 29s`；契约 44 锚点 intact（33 面板 / 24 静态 id / 17 动态前缀 / 249 文件）；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败（4 个 `-pad` / `mist-performance` / `verify-ohos-search`）。真机（192.168.50.108:36717）：`devecocli run --skip-build` → `Smoke: PASS`；图片解码经 `ImagePort` 实证（hilog `[detail-media] create image source kind=sky-culture-art-thumbnail …` + `[sky-culture-art] thumbnail ready` + `[body-warmup] ready path=textures/*.png`）；「更多功能 → 工具与数据」面板渲染正常；`pidof 12410` 存活、无 jscrash / 无 faultlog。另存为/CSV 导出、导入 picker、录屏入口因深链 + 系统 picker 未走查（仅类型收窄、调用序列逐字未改），记「待真机人工」。

**本片新踩的坑**：① ArkTS 禁交叉类型（`arkts-no-intersection-types`）——跨多接口消费者只能靠子接口互相 `extends` 或本地组合接口。② 编辑工具会把部分 `.ets` 写回成裸 LF，而仓库 `.ets` 约定 CRLF（`core.autocrlf=true`）——收尾前须逐文件把裸 LF 归一回 CRLF（字节级），否则 `git status` 出现 eol 噪声。


#### 15.12.20 M 轨道 M4：扩展域模型迁入 `common/types/`（2026-10-06，Barrel 兜底）

> **依据**：STATE-REVIEW §11.2.1 的 **Barrel 策略**、M 轨道第 5 片。**纯路径迁移 + 一行式 barrel**，不改任何类型/常量内容与运行逻辑。
> `pages/MainWindowModels.ets`（767 行）是「扩展域模型」（40+ 接口 + 10+ 常量 + `OcularSelInfo` 类），与页面无关却被 `state/` / `bridge/` / `capability/` / `panels/` 大量消费（架构倒挂）。
> 开工 `git log -1` = `126228abd9`。

**做法**

1. `git mv pages/MainWindowModels.ets → common/types/MainWindowModels.ets`（**整文件原样**，不拆域——拆域是后续独立轨道）。该文件仅 1 处内部 import（`from './StellariumTypes'`），移动后相对深度改为 **`../../pages/StellariumTypes`**（本片唯一内容改动，1 行）。
2. 在 `pages/MainWindowModels.ets` 原位新建 **2 行 shim**：说明注释 + `export * from '../common/types/MainWindowModels'`。

**default export 核查（barrel 覆盖范围）**：`grep 'export default'` = **0**；全部为命名导出（94 处 `export`）——故 `export *` 即覆盖接口 + 常量 + 类，**无需** `export { default } from ...`。

**消费者零改动**：全仓 **66 处** `import ... from '.../pages/MainWindowModels'`（`state/`、`bridge/`、`capability/`、`panels/`、`common/` 及宿主 `MainWindowNativeNode.ets`）**全部未改**，经 barrel 解析到新实体。

**不改**：无任何类型/常量/接口内容改动；无 `.id()` / `main_pages.json` / 构建产物改动；`common/types/` 不 import `@ohos.*`（类型层无 NAPI，符合 §15.7 规则 1）。

**度量**：宿主 `MainWindowNativeNode.ets` **8,017 → 8,017 行**（本片不动宿主）；`MainWindowModels.ets` 767 行（内容等价，仅 1 行 import 深度）；新增 `common/types/` 目录 + 1 个 2 行 barrel；`git diff --cached --stat` = 769 insertions / 767 deletions（重命名识别为 A+M）。

**验证**：`check-ohos-refactor-slice` 通过（括号深度 0）；`arkts_check` 2 文件 0 error（首次 `../pages/StellariumTypes` 报 `Cannot find module`，改两级深度后通过）；`BUILD SUCCESSFUL in 1m1s`；契约 44 锚点 intact（33 面板 / 24 静态 id / 17 动态前缀 / 250+ 文件）；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败（5 个 `-pad`/`-performance` 需设备 + `verify-ohos-search` 的平台 hdc 路径），**无新增回归**（`scripts/*.mjs` 不引用 `MainWindowModels`，无夹具需同步）。真机（192.168.50.108:36717）：`devecocli run --skip-build` → `Smoke: PASS`；模型消费域逐项实证 —— CLI `getSatellites`/`getOculars`/`getScriptList`/`listRecordings`/`getBookmarks`/`getTelescopeProfiles` 全部返回真实数据；UI 走查「更多功能 → 天体数据与扩展 → 卫星」（渲染离线轨道目录：`Satellites plugin version 0.15.0` / `目录更新时间：2026-08-27 09:54:53 UTC`）、「更多功能 → 观测工作区 → 书签」（空态渲染）、「… → 望远镜控制」（渲染 `Offline Telescope Simulator` 设备行）；`pidof` = 18034 存活、`hilog -T ArkTS` 无 jscrash/异常。

**未走查（待真机人工）**：脚本面板（本次未定位到入口，未开；已用 CLI `getScriptList`/`listRecordings` 覆盖其数据结构）；导入/picker 等运行期路径（本片仅搬类型，无行为改动）。

**本片新踩的坑**：① **`common/types/` 到 `pages/` 是两级相对深度** —— 首写 `../pages/StellariumTypes` 被 `arkts_check` 报 `Cannot find module`（解析成 `common/pages/...`），须 `../../pages/StellariumTypes`；搬家后务必以实测相对深度为准。② `Get-Content .Count` 对纯 LF 大文件给出偏小行数（8,017 → 7,573），度量须用 `\n` 计数（与仓库既有口径 8,017 一致）。

**后续轨道备注**：消费者直引新路径（`.../common/types/MainWindowModels`）后可删本 shim —— 归入 Phase 7 收口轨道。

#### 15.12.21 M 轨道 M5：核心桥类型迁入 `common/types/`（2026-10-06，Barrel 兜底）

> **依据**：STATE-REVIEW §11.2.1 的 **Barrel 策略**、M 轨道第 6 片（优先 P7）。**纯路径迁移 + 一行式 barrel**，不改任何类型内容与运行逻辑。
> `pages/StellariumTypes.ets`（1,121 行，核心桥响应 / UI 模型 / 天文计算结果类型）与页面无关却被全项目消费（**~98 处** `import`，覆盖 `state/` / `bridge/` / `capability/` / `panels/` / `common/` 与宿主），架构倒挂最严重。
> 开工 `git log -1` = `6b7852d037`，宿主 `MainWindowNativeNode.ets` 基线 8,017 行。

**做法**

1. `git mv pages/StellariumTypes.ets → common/types/StellariumTypes.ets`（**整文件原样**，R100；该文件**无任何内部 import**，搬家不需改相对深度）。
2. 在 `pages/StellariumTypes.ets` 原位新建 **2 行 shim**：说明注释 + `export * from '../common/types/StellariumTypes'`。
3. 消费者 **0 改动**（~98 处仍 `import … from '…/pages/StellariumTypes'`，经 barrel 解析到新实体）。
4. `common/types/MainWindowModels.ets`（M4 迁入，内部 import `'../../pages/StellariumTypes'`）**保留旧路径经 barrel 解析**（未改为同目录 `./StellariumTypes`）——二选一取"零内容改动"。

**default export 核查（barrel 覆盖范围）**：`grep 'export default'` = **0**；全部为命名导出（`export interface` 全表）——故 `export *` 即完整覆盖，**无需** `export { default } from ...`。

**夹具同步（2 脚本 / 2 处）**：`scripts/test-ohos-mist-horizon.mjs`（改读 `common/types/StellariumTypes.ets`，断言 `actionShow_MistHorizon`）；`scripts/verify-ohos-object-details.mjs`（`typesPath` 改新路径）。

**未改**：无任何类型 / 接口 / 常量内容改动；无 `.id()` / `main_pages.json` / 构建产物改动；`common/types/` 不 import `@ohos.*`（类型层无 NAPI，符合 §15.7 规则 1）；`docs/harmonyos/json/ui-contract-baseline.json` 的 `scannedFiles` 不回改（与 M1/M2/M3/M4 同例——不参与契约 diff）。

**度量**：宿主 `MainWindowNativeNode.ets` **8,017 → 8,017 行**（本片不动宿主）；`StellariumTypes.ets` 1,121 行（内容等价，仅路径变化）；`common/types/` 新增 1 文件 + `pages/StellariumTypes.ets` 2 行 barrel；净 4 个跟踪文件改动（1 重命名 + 1 新增 barrel + 2 夹具）。

**验证**：`check-ohos-refactor-slice` 通过（括号深度 0）；`arkts_check` 2 文件 0 error；`BUILD SUCCESSFUL in 1m4s`；契约 **44 锚点 intact**（33 面板 / 24 静态 id / 17 动态前缀 / 251 文件）；受影响 `test-ohos-mist-horizon`（5/5）、`verify-ohos-object-details`（121 字段 / 11 段）全绿；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败（4 个 `-pad` / `mist-performance` / `verify-ohos-search`）。真机（192.168.50.108:36717）：`devecocli run --skip-build` → `Smoke: PASS`；① **桥响应**（`StellariumBridgeResponse`）— CLI `searchObject Mars` 返回完整响应（`found:true` + `detailModel` + 10 条 `liveDetailFields` + `distance`/`magnitude`/`ra`/`dec`）；② **详情卡** — `ui layout` 见 `Text "火星"` + `Scroll#object-detail-content-scroll`，hilog `[detail-model] render pixel map created` + `[detail-media-card] sphere loaded …mars.png`；③ **搜索** — `openUiPanel search` 渲染 `search-browser-scroll`，点搜索框输入 `Jupiter` → 建议 `Jupiter` / `JUPITER 3 (ECHOSTAR 24)`，点选 → 详情卡 `木星` + hilog `…jupiter.png`。`pidof 23856` 全程存活、无 jscrash / 无 faultlog；测试未改动任何持久化设置。

#### 15.12.22 M 轨道 M7：国际化中心迁出 pages/（2026-10-06，Barrel 兜底）

> **依据**：STATE-REVIEW §11 的 **Barrel 策略**、M 轨道第 7 片（末片）。**纯路径迁移 + 一行式 barrel**，不改任何文案/常量/逻辑。
> `pages/I18n.ets`（2,378 行，全项目最大消费者群）与页面无关却被全项目消费；开工 `git log -1` = `b4a94b5aa2`，宿主 `MainWindowNativeNode.ets` 基线 8,017 行。

**§15.7-1 NAPI 判定（最终落点，与 STATE-REVIEW §11.3 原记的 `common/i18n/` 不同）**：开工核查发现 `I18n.ets` 的**唯一 import** 为 `import i18n from '@ohos.i18n'`，并在 **5 处实际调用**设备能力（`i18n.System.getAppPreferredLanguage` / `i18n.getSystemLocale` / `i18n.System.setAppPreferredLanguage` / `i18n.I18NUtil.getBestMatchLocale` / `i18n.System.getDisplayCountry`）。按 §15.7-1（`common/*` 不得 import `@ohos.*` 设备能力）与 M3 对 `AudioEngine` 的判定口径（**是否调用**设备能力，而非是否 import 其模块），**无法落 `common/i18n/`**；按该规则的明文 fallback「应改落 `capability/`」改落 **`capability/I18n.ets`**。文件整内容逐字原样（`git mv`，R100）。

**做法**

1. `git mv pages/I18n.ets → capability/I18n.ets`（整文件原样；该文件除 `@ohos.i18n` 外无内部 import，搬家无需改相对深度）。
2. 在 `pages/I18n.ets` 原位新建 **2 行 shim**：说明注释 + `export * from '../capability/I18n'`。
3. 消费者 **0 改动**（**135 处**仍 `import … from '…/pages/I18n'`，经 barrel 解析到新实体）。

**default export 核查**：`grep 'export default'` = **0**；全部命名导出（`LangCode` / `SUPPORTED_LANGUAGES` / `LANGUAGE_DISPLAY` / `PROJECTION_KEYS` / `I18n`），`export *` 完整覆盖，无需 `export { default }`。

**夹具同步（3 脚本）**：`scripts/check-ohos-i18n.mjs`、`scripts/sync-ohos-i18n-from-po.mjs`、`scripts/test-ohos-object-type-i18n.mjs` 改读 `capability/I18n.ets`（含构建镜像路径）。

**本片新踩的坑**：`check-ohos-i18n.mjs` 长期潜伏两处夹具缺陷，被本片 root 修复暴露 —— ① Windows `root` 路径解析成 `E:\E:\…`（§13.6 同类；因脚本名不匹配全量扫描正则从未被扫到）；② TW/HK/MO 中文地名断言硬编码 `\n` 而 `countries.ts` 为 CRLF。两处均已修，不涉 I18n 内容。

**度量**：宿主 `MainWindowNativeNode.ets` **8,017 → 8,017 行**（不动宿主）；`I18n.ets` 2,378 行（内容等价）；净 5 个跟踪文件改动（1 重命名 + 1 barrel + 3 脚本）。

**验证**：预检通过；`arkts_check` 2 文件 0 error；`BUILD SUCCESSFUL in 44s`；契约 **44 锚点 intact**（33 面板 / 24 静态 id / 17 动态前缀 / 252 文件）；`check-ohos-i18n`（源↔镜像一致）、`test-ohos-object-type-i18n`（7/7）全绿；全量 `*-ohos*.mjs` 仅 §13.6 六项环境类失败。真机（192.168.50.108:36717）：新 HAP 安装成功；**设备安全锁屏**（开发者模式禁止自动解锁，`aa start`=10106102），语言切换走查**待真机人工**；未改持久化设置。

**M 轨道收尾结论（2026-10-06，M7 后；7/7 全清）**：STATE-REVIEW §11 的 **M 轨道**（渲染管线 / 纯计算 / 类型模块从 `pages/` 归位）**7 片全部完成** —— M1（DetailModel 渲染管线 → `capability/` + `common/derive/`）、M2（位置参考数据三文件 → `common/location/`）、M3（`AstronomyGuide` → `common/derive/`、`AudioEngine` → `capability/`）、M6（`MediaPort` 接口隔离）、M4（扩展域模型 → `common/types/`，barrel 兜底）、M5（核心桥类型 → `common/types/`，barrel 兜底）、M7（国际化中心 → `capability/I18n.ets`，barrel 兜底；NAPI 判定见上）。**`pages/` 现仅余页面壳**（`ApplicationRoot` / `PrivacyBootstrap` / `StartupSky` / `StartupStarGeometry.ts` / `MainWindowNativeNode` / `FloatWindowNativeNode` / `SubWindowNativeNode` / `UiExtensionNativeNode`）**与 3 个一行式 barrel**（`pages/StellariumTypes.ets`→`common/types/`、`pages/MainWindowModels.ets`→`common/types/`、`pages/I18n.ets`→`capability/`）。**后续轨道备注**：消费者改直引新路径后可删这 3 个 barrel，归入 Phase 7 收口轨道。

---

## 16. 续作计划四：§9 三层边界优化（依据 STATE-REVIEW §9，2026-10-08 立 / 同日执行）

> **背景**：五波重构（Phase 0–7 + A/B/P/D/M 轨道）完成后，`ARKTS-PAGES-REFACTOR-STATE-REVIEW.md` §9（2026-10-07）审查 `panels / capability / state` 三层边界，判定 P0–P4 五类问题。本轮按用户批准的**阈值拆分**（只拆「桥调用 ≥5 或存在**持续**定时器」的 store）成 9 片执行，顺序 **P4 → P1 → P2 → P0 → 文档**。
> **基线**：开工 HEAD `bf23e7776d`（宿主 8,017 行）；收尾 HEAD `94fbcf964f`。
> **执行方式**：每片独立「开工普查 → store/controller 手术 → 宿主改指向 → 五步验收 → 真机 → 提交」，片间不停顿。真机 = HUAWEI Mate 80 Pro（本轮 IP 变更 `192.168.3.95` → `192.168.1.4:36717`）。

### 16.1 切片总表

| 片 | 问题 | 内容 | 提交 | 关键度量 |
|---|---|---|---|---|
| S1 | P4a | 删宿主 5 个死 import | `964fa2eaa3` | 宿主 −3 行 |
| S2 | P1 | `SettingsRows` 3 个跨域行 → `common/ui/` | `70650955f2` | `SettingsRows` 179→114；新增 3 文件 |
| S3 | P2 | `GraphLoadingRow` + `SkyCultureDescriptionBlockView` → `common/ui/` | `b7497fb450` | 新增 1 + 迁移 1；`LayerSwitchRow` 留原域 |
| S4 | P0 | `AstroStore` 全部 `load*` → `AstroCalcController` | `45e0aff753` | store 1549→558（−991）；ctl 462→1429；宿主净 0 |
| S5 | P0 | `ScriptStore` 桥 / 450ms 轮询 / 播放 → `ScriptPlaybackController` | `4c7362b37e` | store 408→139（−269）；ctl 237→413；宿主 −18 |
| S6 | P0 | `GuideStore` 引擎 / 250ms tick / 桥 → 新建 `GuideController` | `b01c7d22d2` | store 156→20（−136）；新 ctl +161；宿主 +13 |
| S7 | P0 | `TimeSettingsStore` 8 连发配置回读 → 新建 `SettingsController` | `02890884aa` | store 130→19（−111）；新 ctl +113；宿主 +15 |
| S8 | P0 | `TelescopeStore` live-position 持续链 → `TelescopeController` | `94fbcf964f` | store 457→271（−186）；ctl 278→467；宿主 +2 |
| S9 | 文档 | 本节 §16 + CHANGELOG 收口 | （本节） | — |

### 16.2 逐片要点

- **S1（P4a）**：宿主 L111/L128/L143 五个未被引用的 import（`LayerSwitchRow` / `GraphLoadingRow` / `RtsSelectionGuide` / `GraphSelectionGuide` / `SkyCultureDescriptionBlockView`）删除；`TimeWheelController`（`state/`）与 `SpeechService`（`common/`）按 §9.4b/c 维持冻结。
- **S2（P1）**：`NavStarsToggleRow` / `ArchaeoToggleRow` / `MosaicCameraMetric` 各只有一个非设置域消费方，迁 `common/ui/`（§4.2-4 口径）。`SettingsRows.ets` 回归设置域专用（剩 4 个）。
- **S3（P2）**：`GraphLoadingRow` 抽出为新文件；`SkyCultureDescriptionBlockView` `git mv` 迁 `common/ui/`。`LayerSwitchRow` 有 4 个消费方且域特化，按 §9.2 P2 建议归属**不动**。
- **S4（P0 · AstroStore）**：迁出 24 个公开 loader + 8 个私有 helper + 16 个请求序号字段。`AstroHostHooks` 删去已迁走的 `loadWutTargets` / `ephemerisCustomStartJD` / `hecLayoutPositions` / `loadPlanetPositions`；控制器新注入 `hasSelectedObject` / `selectedObjectName` / `hecLayoutPositions`（控制器不 import `ObjectDetailStore`）。**面板文件零改动**（`load*` 入口本就是宿主下发的回调）。真机走查 `searchObject Mars` / `openUiPanel astro` / `getAstroPanelState` / `getTonightEvents` / `getAlmanac` + tab 0/1/5 快照与上下文回读。
- **S5（P0 · ScriptStore）**：迁出 10 方法 + `videoStateTimer` / `seq`；`ScriptHostHooks` 与 `ScriptPlaybackHooks` 合并 / 删除。发现隐藏消费方 `StartupBridge`（`setScriptMetadata`）、`RecordingController`、`LayerController`，按既有「跨控制器经 hooks 转发」模式补注入。真机走查 `getScriptList` / `listRecordings` / `getVideoRecordingState` + 脚本面板启动 / 停止。
- **S6（P0 · GuideStore）**：新建 `capability/GuideController`（`GuideHostHooks` 逐字改名 `GuideControllerHooks`，18 成员原样），store 只剩 `guideState` + `speechStatus`。新增 `resetJourneyFlags()` / `lastRequestId()` / `lastResult()` 供宿主清快照与 CLI 发布。真机走查 `startGuide solar-neighbours` → `next` → `stop` 全链。
- **S7（P0 · TimeSettingsStore）**：新建 `capability/SettingsController`，整接口 `TimeSettingsHostHooks` 迁入；**不复活** M 轨道解散的跨域动作路由（`SettingsController` 只是 IO loader）。真机决定性回读实证：`setDateFormat ddmmyyyy` → 冷启动 → 设置页显示「日-月-年」（只能来自回读加载器），随后复原。
- **S8（P0 · TelescopeStore）**：live-position 持续 `setTimeout` 链（1s 成功 / 1.8s 失败 / 500ms profile）迁入既有 `TelescopeController`；appliers（`applyTelescopeProfile(s)` / `applyTelescopeEndpointStatus`）经实测**整体迁入**（无外部引用，且 `applyTelescopeProfile` 直调已迁的 `schedule` / `stop`，留 store 会形成 `state→capability` 反依赖）。`loadOculars`（`requestWhenReady` 带超时、非持续定时器）留 store。**部分推翻 PLAN §15.12.6 D9 的定时器归属判定**（仅此一面）。真机实证 ~1s 轮询启停：开 → 每 ~1s 一条 `getTelescopePosition`；关 / 离开面板 → 5s 内 0 条（无泄漏）。

### 16.3 登记例外（本轮明确不拆，§9.3）

| 项 | 原因 |
|---|---|
| `CatalogStore` 600ms 下载轮询 / `SatelliteStore` 90ms 防抖 / `LocationStore` 分块 `setTimeout` | **自我收口、非持续**定时器（§15.7 规则 3 只约束持续定时器）；D 轨道 §15.12.6 已判定随方法留 store |
| 桥调用 ≤4 的 39 个 store（`ObjectDetailStore` 4 / `InfoWindowStore` 3 / `SearchStore` 3 / `BookmarkStore` 3 / …） | 简单读写，成本 / 收益不划算（§9.3） |
| `TimeWheelController` 在 `state/`、`SpeechService` 在 `common/` | §9.4b/c 判定合理，维持冻结 |
| `capability → state` 64 处 import、`panels/panels → panels/<domain>` 44 处、shell 跨 6 域 | 设计意图，无环，改动只增复杂度（§9.3） |

### 16.4 验收口径

每片：`check-ohos-refactor-slice.mjs` 通过 → `arkts_check` 0 error → `build-ohos-hap-windows.ps1 -SkipEngine -SkipDeploy` `BUILD SUCCESSFUL` → `check-ohos-ui-contract.mjs` **50 锚点 / 34 面板 / 29 静态 id / 18 动态前缀 intact**（无 `--update`）→ 受影响 `*-ohos*.mjs` 全绿 → 真机 `devecocli run --skip-build` `Smoke: PASS` + 语义 CLI 走查 + `pidof` 存活 + `hilog` 无 jscrash。逐字等价（§15.7 规则 5）：方法体只改取值前缀，比较边界 / 分支 / 错误文案 / 定时参数不变。

### 16.5 与 V2 的衔接

本轮即 STATE-REVIEW §10.3 推荐的**「先拆后翻」**前置：S4–S8 后，astro / script / guide / time-settings / telescope 五域的 store 已是纯数据（S4 后 `AstroStore` 无 `CommandPort`；S6/S7 后 `GuideStore` / `TimeSettingsStore` 仅剩数据），控制器持有桥与定时器 —— 正是 §10.2.1 的 V2 典型形态（`@ObservedV2` 纯模型 + 独立控制器）。V2 翻代另立项，不混入本队列。

