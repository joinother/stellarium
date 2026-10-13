# pages/ 重构终态架构评审（MainWindowNativeNode.ets 及其拆分结构）

- **状态：** 第 4 版（M 轨道终态 + 三层边界审查 + V2 协同分析）。§9 的三层边界问题（P0–P4）已于 2026-10-08 按「阈值拆分」执行完毕（S1–S9，见 `ARKTS-PAGES-REFACTOR-PLAN.md` §16）；本文正文保留 2026-10-07 评审口径，§9.4 附录补充终态实测修正。
- **日期：** 2026-10-07（正文评审）；2026-10-08（§9 实施 + §9.4 实测）。
- **评审基线：** §9/§10 基于 HEAD `cbc8c5bfae`（宿主 7,974 行）；§1–§8 的终态对象为 M 轨道收尾 `c52a517961`（宿主 8,017 行）。
- **评审对象：** `harmonyos/ets-source/pages/MainWindowNativeNode.ets`（**8,017 行**）及
  `bridge/`（6 文件 / 319 行）、`capability/`（31 / 12,329）、`state/`（48 / 9,648）、
  `panels/`（119 / 16,852）、`common/`（31 / 87,486）、`pages/`（11 / 8,587）六层目录终态。
- **对照基准：** `docs/harmonyos/research/ARKTS-PAGES-REFACTOR-PLAN.md`（§3 目标架构、§14 A/B 轨道、§15 D/M 轨道执行记录）。
- **数字口径（重要，本版修正）：** 行数一律 `[System.IO.File]::ReadAllLines`（UTF-8）实测。
  PowerShell `Get-Content` 默认按 GBK 解码 UTF-8 文件，会把含中文注释的 LF 文件的部分换行符
  吞入上一行，行数**系统性偏低**（宿主曾被低估 444 行，"7,573 行"是错误读数）。
  装饰器计数用行锚定正则（附录命令），第 2 版 §7.1 部分数字含注释噪声，本版已修正。
- **文档结构：** §1–§8 为终态评审（自含）；§9 为 2026-10-07 三层边界与交叉审查（量化 + 选项对比）；
  §10 为 V1→V2 升级与 §9 边界问题的协同分析；
  附录为复现命令与历史判据留档。

---

## 1. 摘要

五波重构——Phase 0–7+RA（单体拆分）→ A/B 轨道 38 片（方法下沉 + `CommandPort`）→
P 轨道（控制器 + 三端口）→ D 轨道 17 簇（行为控制器出仓）→ M 轨道 7 片（模型/资源/服务归位）
——**已全部完成**，`check-ohos-ui-contract.mjs` 全绿（33 面板 / 24 静态 id / 17 动态前缀 / 44 锚点）。

### 1.1 宿主终态指标


| 指标                   | 重构前（计划 §1.2） | 第 2 版（10-04） |                                   终态实测 | 总变化                      |
| ------------------------ | ---------------------: | -----------------: | -------------------------------------------: | ----------------------------- |
| 主文件行数             |               32,774 |           18,582 |                                  **8,017** | −75.6%                     |
| `@Builder`             |                  145 |                3 |                                      **3** | −97.9%                     |
| `panelContent` 体量    |                4,707 |              898 |                                    **881** | −81.3%                     |
| 宿主`@State`           |                1,047 |              132 |   **131**（46 store + 85 裸字段，§2.7.1） | −87.5%                     |
| `private` 方法         |              ≈1,109 |              940 |                                    **223** | −79.9%                     |
| `load*`                |                   70 |               70 | **1**（`loadSkyCultureDetails`，登记保留） | −98.6%                     |
| `@BuilderParam`        |                   16 |                0 |                                      **0** | 崩溃面消灭                  |
| 宿主`AppStorage.`      |                   26 |               26 |                                     **12** | −53.8%                     |
| 宿主`nm*()` 色快照调用 |                  145 |              145 |                                      **0** | 收敛为`NightModeStore` 方法 |

> 注：第 2 版记载的 "940 个 private" 与本版 "223" 的差不只是拆分——两版口径也不同
> （第 2 版只数 struct 方法、本版含 static/async 全口径，见附录命令）。同口径对比：
> 拆分前 ≈1,109 → 终态 223。

### 1.2 目录终账（258 文件 / 137,397 行，UTF-8 口径）


| 目录                      | 文件 |   行数 | 职责                                                                                                                                  |
| --------------------------- | -----: | -------: | --------------------------------------------------------------------------------------------------------------------------------------- |
| `bridge/`                 |    6 |    319 | `BridgeClient`（`libentry.so` 唯一出口，51 行）+ 五个端口接口（`CommandPort`/`MediaPort`/`PlatformPort`/`SensorPort`/`LocationPort`） |
| `capability/`             |   31 | 12,329 | 22 个行为控制器 +`AudioEngine`(927)/`I18n`(2,378) 服务 + `StartupBridge`(247) + DetailModel 渲染四件套                                |
| `state/`                  |   48 |  9,648 | 47 个`@Observed` store + `TimeWheelController`（普通类，225 行）                                                                      |
| `panels/`                 |  119 | 16,852 | 25 个面板主体（`panels/panels/`）+ 13 个壳件（`panels/shell/`）+ 16 个领域子目录 + 根 2 件                                            |
| `common/`                 |   31 | 87,486 | 纯逻辑（`derive/` 11 件）+ 类型（`types/`）+ UI 件（`ui/`）+ 平台件（`platform/`）+ 位置数据（`location/` 3 件 82,947 行，`.ts`）     |
| `pages/`                  |   11 |  8,587 | 宿主 8,017 + 启动链小件（`ApplicationRoot`/`StartupSky`/`PrivacyBootstrap`/三个 NativeNode 壳）+ 3 个一行 barrel                      |
| `qability*/` + `process/` |   12 |  2,176 | Ability 壳（`QAbility` 727）、资源引导（`StellariumResourceBootstrap` 1,003）、Qt 互操作适配                                          |

### 1.3 一句话判定

主文件从「单体上帝组件」收缩为**组合根 + 端口适配器 + 版面装配器**：
状态所有权在 47 个 store，设备能力编排行为在 22 个控制器，UI 在 119 个组件文件；
宿主保留生命周期编排、五端口实现、面板路由与版面装配。
依赖单向可审计（§4.3 实测 import 边，`panels/` 零 `bridge`/`capability` 依赖）、
契约护栏全绿、V1 纯度无混用。

---

## 2. MainWindowNativeNode.ets 终态解剖

### 2.1 物理分区（实测行号，UTF-8 口径）

```
L1–244      import 区（222 条 import）
L245–260    文件级常量
L261–955    五个端口适配器类（文件级 class，共 695 行）
              HostCommandPort(L261) / HostMediaPort(L306，475 行，最大)
              HostPlatformPort(L784) / HostSensorPort(L839) / HostLocationPort(L897)
L958        export struct WindowNativeNode
L958–2348   字段声明区（≈1,391 行）
              ├─ @State 131 个 = 46 个 store 实例 + 85 个裸字段（§2.7.1）
              └─ 非 @State private 成员 102 处：28 个惰性控制器 impl、端口引用、
                 定时器句柄、请求序号、手势草稿、渲染管线逐帧字段
L2349–3090  aboutToAppear（742 行）：store attachPort/attachHooks 注入链（L2366–2735）、
            控制器惰性构造、桥/传感器/折叠订阅、启动引导瀑布
L3091–3134  aboutToDisappear：全量定时器/传感器/订阅 stop 收口
L3135–5693  方法区（≈2,559 行，223 个 private 方法，分类见 §2.4）
L5694–7031  build()（1,338 行，结构见 §2.3）
L7032–7088  @Builder floatingPanel()（57 行）
L7089–7136  @Builder compactPanel()（48 行）
L7137–8017  @Builder panelContent()（881 行，33 分支组件装配，到文件尾）
```

与第 2 版分区对比，结构性的变化只有一处：**文件级出现了 695 行的五个端口适配器类**。
它们是实现 `bridge/` 五个接口的 `class HostXxxPort implements XxxPort`，被 `aboutToAppear`
里的 `attachPort` 注入各 store——这是 A/B/P 轨道"store 只依赖端口接口"决定的必然形态，
物理上必须在 struct 之外（class 不能长在 struct 里）。

### 2.2 三个幸存 `@Builder` 的职责


| Builder           | 行号  | 行数 | 职责                                                                               | 保留原因                                                                                                                        |
| ------------------- | ------- | -----: | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `floatingPanel()` | L7032 |   57 | expanded 构型的右侧面板包裹：PadPanelHandle + PanelHeader + Scroll 路由宿主        | 体内调用`this.panelContent()`，**不能**作为 `@BuilderParam` 传入子组件（规则 9：真机实测渲染即应用退出）                        |
| `compactPanel()`  | L7089 |   48 | compact/fold-hover 构型的底部面板包裹（拖拽沉降、snap）                            | 同上                                                                                                                            |
| `panelContent()`  | L7137 |  881 | 33 个`activePanel` 分支 → 组件装配（每分支传 store 引用 + `@Prop` 派生值 + 回调） | 分支入参高度异构（object 分支 25`@Prop` + 17 回调；time 分支 5 store + 12 参数），表驱动需参数装箱层，复杂度反超收益（§4.2-3） |

`@BuilderParam` 已从 16 → **0**：`@Builder` 传子组件这条已知崩溃路径已无暴露面。
宿主 3 个 `@Builder` 全部无参、全部只被 `build()`/彼此调用。

### 2.3 宿主 `build()` 结构（1,338 行）

```
Stack（根）
├─ 语言刷新锚点 Text(i18nLang) + gl-probe XComponent + qohos NODE XComponent（隐私放行后）
├─ 触摸反馈气泡 ×2（单指/双指）+ 全屏触摸承接 Stack（handleOverlayTouch）
├─ 脚本/导览焦点层：scriptPlaybackVisible → InteractiveGuideShell | ScriptFocusShell
│   + RecordingFocusShell（录制沉浸态）
├─ 三壳分发：isFoldHover → HoverObservatoryShell │ isExpanded → ExpandedShell │ else CompactShell
│   每壳之后：if (panelVisible) { this.compactPanel() / this.floatingPanel() }（宿主包裹）
├─ Dock 命中区：顶层命中靶 Stack + HarmonyShell（坐标叠层/陀螺仪指引/反馈气泡）
└─ 浮层与状态条：RecordingControlBar + PolarScopeOverlay + 7 个 overlay 件
    + skyTextureStatus 横幅
```

### 2.4 宿主残留职责：223 个 `private` 方法解剖

全口径实测（含 `static`/`async`/泛型，附录命令）223 个，分类归域：


| 类别                    | 数量 | 代表方法                                                                                                                   |
| ------------------------- | -----: | ---------------------------------------------------------------------------------------------------------------------------- |
| 惰性控制器/上下文访问器 |   28 | `gyroCtl()`/`recordingCtl()`/`skyInputCtl()`/…/`context()`（impl 字段 + getter，首次使用构造）                            |
| 桥薄委托                |    5 | `callNative`/`callNativeFire`/`callNativeWhenReady`/`callInteractive`/…（转发 `BridgeClient`，宿主不 import libentry.so） |
| 生命周期                |   14 | `onQt*`(5)/`onPrivacy*`/`startPageAfterPrivacy`/`startTwinkle`/`stopTwinkle`/…                                            |
| 存储读写 async          |    8 | `saveObservingListToStorage`/`readBookmarksStorage`/`readSearchHistoryStorage`/`saveFileAs`/…（Preferences 封装）         |
| 折叠/响应式分发         |    6 | `updateResponsiveLayout`/foldStatus 分发                                                                                   |
| 面板路由                |   14 | `setPanel`/`closePanel`/`openSubPanel`/`handlePanelBackTap`/`panelTitle`/`panelSubtitle`/…                                |
| 刷新收口                |    4 | `refreshState`/`refreshStateNow`/`triggerAction`/`flashHint`（`ControllerHooks` 三能力的宿主端实现）                       |
| CLI publish             |    4 | `publishCli*` 系列（AppStorage 12 处直用收口于此）                                                                         |
| 选中→详情管线          |   29 | `applySelectedObject`/`refreshObjectDetailConnector`/`refreshObjectInspectorMedia`/…（全应用唯一选中管线）                |
| 命中测试/触摸热路径     |   14 | `handleSkyTouch`/`isUiPoint`/`handleUiTap`/…                                                                              |
| 几何/布局派生           |   47 | `dockTop`/`detailCardWidth`/`compactPanelHeight`/`hoverPanelTop`/…（§2.7.1 保留字段的派生面）                            |
| 星空文化保留            |    7 | `loadSkyCultureDetails`/`drawSkyCultureTerritoryMap`/`skyCultureColorOptions`/…（§2.12）                                 |
| static 纯映射           |    3 | `scriptImportFileName`/`landscapeImportFileName`/`sensorIdForLabel`                                                        |
| 域动作/格式化杂项       | ≈40 | `jumpToWutTarget`、telescope/位置/搜索入口转发、文件导出、格式化                                                           |

**三点结论：**

1. **A/B 类已清零。** 第 2 版 §2.12 的 305 个纯派生（A 类）与 §2.13 的 70 个 `load*`（B 类）
   已在 A/B/D 轨道全部下沉或消灭；现存 47 个几何派生读取的全是 §2.7.1 保留字段
   （原 §2.7.1.1 A2-3 组判据），属永久保留而非残留。
2. **`load*` 只剩 1 个。** `loadSkyCultureDetails` 因渐进写入保留字段 `skyCultureArtStates`
   （逐帧护栏）登记保留，与其余 6 个星空文化保留方法同组（§2.12）。
3. **方法区 ≈2,559 行、223 个方法，平均 11.5 行/方法。** 主体是三类宿主不可让渡的职责：
   选中管线（全应用唯一入口）、命中测试（触摸热路径）、几何派生（读保留字段）。

### 2.5 心智模型：组合根 + 端口适配器 + 版面装配器

第 2 版的心智模型是"宿主 = 控制器"；D/M 轨道完成后这个说法不再成立——**控制器已搬进
`capability/`**。终态宿主的三重身份：

1. **组合根（Composition Root）**：全应用唯一大规模 `new` 的地方——46 个 store 实例、
   22 个控制器的惰性构造、五端口实现、注入接线（`aboutToAppear` 742 行）。
2. **端口适配器**：`L261–955` 五个 `HostXxxPort implements XxxPort`，把"宿主能力"
   （桥调用、剪贴板、分享、TTS、传感器、定位）翻译成 `bridge/` 纯接口。
3. **版面装配器**：`build()`(1,338) + 3 个 `@Builder`(986) 的纯声明式装配，
   加上面板路由与转场状态。

一句话读它：**"声明 UI 怎么装配，把外部事件翻译成端口调用与状态写入；其余一切在六层目录里。"**

### 2.6 六层目录解剖（终态依赖方向）

```
            ┌──────────────────────────────────────────────┐
            │  pages/（宿主 + 启动链）                      │
            │  组合根：唯一 new store/控制器/端口的地方     │
            └──────┬───────────┬──────────┬────────────────┘
                   │           │          │
     ┌─────────┐   │   ┌───────┴───┐  ┌──┴────────┐
     │ panels/ │───┼──▶│ state/    │  │capability/│──┐
     │ 119 件  │   │   │ 47 store  │◀─│ 22 控制器 │  │
     └────┬────┘   │   └─────┬─────┘  └────┬──────┘  │
          │        │         │             │         │
          ▼        ▼         ▼             ▼         ▼
     ┌─────────────────────────────────────────────────┐
     │  common/（derive 11 / types 2 / ui 7 / platform 3 │
     │  / media 1 / location 数据 3 / 根 4）             │
     └─────────────────────┬───────────────────────────┘
                           ▼
     ┌─────────────────────────────────────────────────┐
     │  bridge/（五端口纯接口 + BridgeClient 唯一 so 出口）│
     └─────────────────────────────────────────────────┘
```

实测 import 边（§4.3 全表）：`panels/` 对 `bridge`/`capability` 的依赖为 **0**——
面板只碰 store（133 处）、common 纯逻辑（144 处）与 UI 件；控制器与桥能力一律经宿主注入。
这条"面板不知道桥、也不知道控制器"的边，是 D 轨道最重要的结构成果。

### 2.7 端口与钩子体系

**bridge/ 六文件（319 行）= 五个纯接口 + 一个出口：**


| 文件               | 行数 | 形态                                                                                                                                                                                                                                          |
| -------------------- | -----: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BridgeClient.ets` |   51 | `libentry.so` 唯一 import 点；`request/send/requestWhenReady/requestInteractive` 静态方法                                                                                                                                                     |
| `CommandPort.ets`  |   35 | `request`/`requestWhenReady`/`requestInteractive`/`requestLongRunning`/`fire` 五方法                                                                                                                                                          |
| `MediaPort.ets`    |  132 | M6 拆分后的**组合接口**：`ImagePort`（解码/缓存）/`ObjectModelMediaPort`（模型纹理，extends ImagePort）/`FileExportPort`（导出/另存）/`DocumentImportPort`（选择器导入）/`ScreenCapturePort`（截图/录屏）五个子接口，`MediaPort extends` 全部 |
| `PlatformPort.ets` |   27 | `writeClipboardText`/`shareFile`/`speak`（TTS；API 24 无 CoreSpeechKit，经系统能力封装）                                                                                                                                                      |
| `SensorPort.ets`   |   44 | `probeSensor` + 4 组 subscribe/unsubscribe + `RotationVectorSample` 等类型别名                                                                                                                                                                |
| `LocationPort.ets` |   30 | `requestLocationPermissions`/`getCurrentLocation`/`readObserverLocation`/`writeObserverLocation`（preferences）                                                                                                                               |

宿主侧实现：`L261–955` 五个 `HostXxxPort` 适配器类；`aboutToAppear` 里
`store.attachPort(new HostCommandPort(...), onChanged)` / `attachHooks(...)` 注入（L2366–2735）。

**钩子体系（capability/ControllerHooks.ets，17 行纯接口）：**

```ts
export interface BehaviorHostHooks {
  refreshState(): void
  flashHint(msg: string): void
  panelChange(panel: string): void
}
```

22 个控制器的接入形态（实测）：**11 个** `XxxHostHooks extends BehaviorHostHooks`
（AstroCalc/DetailConnector/Layer/NebulaTexture/PolarScope/PluginFeature/ScriptPlayback/
SkyCulture/SkyCultureMaker/SkyTextureStatus/Time，其中 NebulaTexture/SkyTextureStatus 为空壳占位）；
**9 个**独立 hooks 接口（Location/ObjectInspectorMedia/ObjectModelRenderer/Recording/Satellite/
Search/Sensor/SkyInput/ViewCoordinate）；**2 个**无 hooks（Ocular/Telescope，纯端口注入）。

### 2.7.1 宿主保留字段登记（永久保留）

> 本节是第 2 版 §2.7.1/§2.7.1.1 的终态续篇（PLAN §14/§15 引用锚，锚号不变）。
> **终态实测：宿主 `@State` 131 个 = 46 个 store 实例 + 85 个裸字段。**
> 迁移判据不变：① `@ObjectLink` 只观测字段赋值、观测不到原地变更；② 高频写入
> （定时器/拖拽逐帧/渐进写入）不入被观察 store（否则重渲染风暴）；③ 只搬面板入参，
> 宿主自用的路由/几何/引擎字段不搬。
> 下表为分类登记（第 2 版逐字段快照的类别框架；个别字段经 D/M 轨道微调，
> 完整 85 项清单以附录命令实测为准）：


| 类别                                  | 代表字段                                                                                     | 理由类型            |
| --------------------------------------- | ---------------------------------------------------------------------------------------------- | --------------------- |
| A 折叠屏 / 响应式布局分发             | `createInfo`、`isExpandedLayout`、`isFoldHoverLayout`、`foldStatusValue`、`foldAngleValue`… | 机制类              |
| B 面板路由 / 壳层机制                 | `activePanel`、`panelVisible`、`panelNavigationDepth`、`panelContentKey`                     | 机制类              |
| C 布局几何                            | `skyWidth`、`skyHeight`、`panelWidth`、`panelMaxHeight`                                      | 跨域共用            |
| D 面板/卡片转场、空闲淡出与拖拽瞬时量 | `panelIdleOpacity`、`panelRouteOpacity`、`compactPanelSnapRatio`、`viewTabContentOffsetX`…  | 高频逐帧            |
| E 天体详情指向线几何                  | `objectDetailConnectorX/Y/Length/Angle/…`                                                   | 高频逐帧            |
| F 详情卡宿主控制量                    | `fullInspectorRequested`、`cardOffsetX`、`cardOffsetY`                                       | 机制类/跨域共用     |
| G 视图中心坐标叠层读数                | `viewCoordinatePrimaryText`、`viewCoordinateOffsetX/Y`                                       | 高频逐帧            |
| H 触摸反馈圈 / 快捷控件按压           | `skyTouchFeedback`、`skyTouchX/Y`、`compactQuickPressed`                                     | 高频逐帧            |
| I 定时器回填的状态读数                | `locationText`、`coordinateText`、`fovText`、`dockClockText`…                               | 高频逐帧/跨域共用   |
| J 请求进行中标志 / 桥同步状态         | `trackingRequestPending`、`bridgeSyncStarted`                                                | 机制类              |
| K 时间/日期跨域共用                   | `pickedDate`                                                                                 | 跨域共用            |
| L 星空文化美术渐进写入                | `skyCultureArtStates`、`skyCultureArtThumbnailPixelMaps`                                     | 高频逐帧            |
| M 目录健康（与卫星面板共用）          | `catalogHealthLoaded`、`catalogManifestPresent`                                              | 跨域共用            |
| N 视图/设置标签与投影                 | `fovSliderValue`、`currentProjection`、`viewTab`、`configTab`                                | 跨域共用/机制类     |
| O 启动/加载/提示                      | `isLoading`、`splashGone`、`actionHint`                                                      | 机制类              |
| P 引擎自用 / 已登记约定               | `recordBuffer`、`scenery3dCurrentId`、`planetLabels`…                                       | 引擎自用/已登记约定 |

> 原 §2.7.1.1（"宿主控制器逻辑，永久保留"，A2-3 组 51 个方法）的**终态形态** =
> §2.4 分类表中的 47 个几何/布局派生 + 14 个命中测试 + 6 个折叠分发，同判据
> （读取项 ⊆ 本节保留字段 ∧ 不读 store）永久保留，不再评估下沉。
> **例外登记：`DockStore` 是唯一不由宿主持有的 store**——由 `panels/shell/BottomDock.ets`
> 组件自持（`@State private activeState: DockStore = new DockStore()`）并经 `@ObjectLink`
> 共享给 `DockButton`；这是 `ForEach` 复用下 `@Prop` 快照失效的技术修正（§4.2-7）。

### 2.8 运行时控制流：四个引擎驱动整个文件

**① 启动链（一次性瀑布）**

```
QAbility → StellariumResourceBootstrap（资源落盘）→ ApplicationRoot
  → 宿主 aboutToAppear（L2349，742 行）：
     隐私门控（@StorageLink watch）→ store attachPort/attachHooks 注入（L2366–2735）
     → qohos NODE XComponent onAttach（Qt 引擎挂载）
     → restoreStartupSettings + 串行引导查询瀑布（getSkyCultures/getScriptList/…）
```

**② 桥回调引擎（C++ → ArkTS 推送）**：`libentry.so` → `BridgeClient` →
宿主 `HostCommandPort` 分派 → 控制器/store **直写字段** → `@ObjectLink` 组件自刷新。
D 轨道的关键收益：回包摊铺不再经过宿主方法链，宿主不因域数据到达而重渲染。

**③ 交互引擎（ArkTS → C++ / store）**：panels 回调 → 宿主方法 →
控制器（域行为）/`callNative*`（桥）/store 直写。星图触摸热路径保持原设计：
惯性滚动在 Qt 渲染循环里跑，ArkTS 只传释放速度。

**④ CLI/自检引擎**：`@StorageLink('stellariumCliUiEvent')` → `onCliUiEventChanged`
（语义 CLI 路由器）→ 面板/搜索/卫星联动；`publish*` 系列 + AppStorage 12 处直用收口。

**定时器终态**：宿主仅剩 Dock 时钟与启动闪烁两处；**7 个 store 自持定时器**——
`ScriptStore`(450ms)/`CatalogStore`(600ms)/`SatelliteStore`(90ms)/`GuideStore`/
`TelescopeStore`/`LocationStore`/`SessionToolStore`——挂摘随面板可见性，
`aboutToDisappear`（L3091–3134）统一收口。

### 2.9 横切机制（四个惯用法 + 两条新收敛）

1. **请求序号防过期**：每个异步域 `xxxRequestSequence`/`xxxMutationId`，回包比对序号丢弃过期
   （A/B 轨道后序号随 loader 下沉进 store，如 `TimeStore.ets:100–116`、`AstroStore.ets:328–372`）。
2. **`callNativeWhenReady` 重试**：启动期 Qt 未就绪按 200ms×60 退避，不崩溃。
3. **`@Prop` 快照 + 回调回注**：所有下沉组件的统一接口，单向数据流。
4. **逐帧字段隔离**：模型渲染像素/指向线几何由管线逐帧写入，绝不进 `@Observed` store，
   只以 `@Prop` 快照进组件（§2.7.1 D/E/L 类）。
5. **（新）夜视色方法化**：145 处 `nm*()` 宿主色快照调用收敛为 0——组件直接调
   `NightModeStore` 上的方法（`nmText()/nmSub()/nmAccent()` 成了 store 方法），
   V1 内消灭了 §7.4-3 列的颜色快照问题。
6. **（新）跨 store 写经宿主 hooks**：store 之间不互相 import（唯一例外
   `TimeWheelController` → `TimeWheelStore`）；跨域同步由宿主 hooks 完成
   （例：`TimeStore` 的 `hooks.syncNightModeFromEngine` → `NightModeStore`）。

### 2.10 store 层形态（47 + 1）

- **规模分布**（与领域复杂度正相关，无空壳 store）：
  `AstroStore` 1,578 / `SkyCultureSettingsStore` 672 / `LocationPickerStore` 587 /
  `TelescopeStore` 486 / `ScriptStore` 437 / `CatalogStore` 352 / `SearchStore` 342 …
  `DeltaTStore` 8 / `DockStore` 12 最小。
- **注入协议**：`attachPort(CommandPort, onChanged)` + `attachHooks(...)`，
  宿主 `aboutToAppear` L2366–2735 完成；store 因此不碰 NAPI、可用假 port 单测。
- **加载自持**：loader 已随 A/B 轨道搬入 store（含请求序号），宿主 `load*` 只剩 1。
- **`flashHint` hooks 12+ 个 store 在用；`refreshState` 仅 `GuideStore`**（行为刷新类钩子
  已被控制器 hooks 取代大半）。
- **`TimeWheelController` 为普通类**（非 `@Observed`）：时间轮拖拽是逐帧手势草稿写入，
  可观测化会引发重渲染风暴——与 §2.7.1 逐帧护栏同一判据，住在 `state/` 是正确位置。

### 2.11 控制器层形态（22 + 支撑件）

- **构成**：22 个 `*Controller`（`SensorController` 920 / `SkyInputController` 708 /
  `SkyCultureController` 700 / `ObjectModelRenderer` 540 / `LayerController` 518 /
  `SkyCultureMakerController` 511 / `AstroCalcController` 482 / `TimeController` 446 /
  `ObjectInspectorMediaController` 463 / `RecordingController` 435 / `DetailConnectorController` 399 /
  `TelescopeController` 284 / `ScriptPlaybackController` 250 / `LocationController` 245 /
  `PolarScopeController` 212 / `PluginFeatureController` 205 / `OcularController` 200 /
  `SearchController` 176 / `ViewCoordinateController` 171 / `SkyTextureStatusController` 165 /
  `SatelliteController` 152 / `SelfTestController` 117 / `NebulaTextureController` 112）
  + 服务件（`AudioEngine` 927、`I18n` 2,378）+ `StartupBridge` 247
  + DetailModel 渲染四件套（`RenderTypes` 45/`Rasterizer` 177/`RenderClient` 106/`Worker` 21）。
- **接入宿主**：惰性构造——`private xxxCtlImpl` 字段（L1004–1049 一带）+ getter（L1664–2344 一带），
  首次使用才 new；hooks/port 注入在构造参数。
- **对 store 的依赖是直接的**：64 处 `import { XxxStore } from '../state/...'`，
  控制器在桥回调里直写 store 字段（D 轨道设计如此——刷新面 = `@ObjectLink` 订阅者）。
- **纯度约束（实测）**：零 `libentry` import；`hilog` 15 处（调试日志例外，登记）；
  `@kit` 24 处（`ImageKit` 4/`ArkTS` worker 2/`AudioKit` 1/`InputKit` 1 + hilog 15），
  设备能力调用全部有据可查。

### 2.12 保留项终版清单（勿再动）

合并第 2 版 §9.6/§10.5 的保留项登记，终态逐项判定：


| #  | 保留项                                                          | 终态判定                                                              |
| ---- | ----------------------------------------------------------------- | ----------------------------------------------------------------------- |
| 1  | `loadSkyCultureDetails` + `skyCultureArtStates` 渐进写入        | 永久保留（逐帧护栏，§2.7.1 L 类）                                    |
| 2  | `drawSkyCultureTerritoryMap` 领土图绘制                         | 永久保留；**内容合规约束**（AGENTS.md：涉华地图呈现），改动需人工审查 |
| 3  | 47 个几何派生 + 14 个命中测试 + 6 个折叠分发                    | 永久保留（读取项 ⊆ §2.7.1 保留字段）                                |
| 4  | 五个端口适配器类（L261–955）                                   | 永久保留（组合根职责）                                                |
| 5  | `aboutToAppear` 注入链（742 行）                                | 永久保留（组合根职责；全应用唯一 new 的地方）                         |
| 6  | `build()` + 3 个 `@Builder` 装配                                | 永久保留（V1 规则 9 约束）                                            |
| 7  | 选中→详情管线（29 方法）                                       | 永久保留（全应用唯一管线，任何面板不拥有它）                          |
| 8  | CLI`publish*` 4 方法 + AppStorage 12 处                         | 保留至 V2 B 阶段（AppStorageV2 单独立项，§7.6）                      |
| 9  | 逐帧字段组（`objectDetailConnector*`/`skyCultureArtStates` 等） | 永久保留（性能护栏；V2 下同样不得入`@Trace`）                         |
| 10 | `LocalStorage`（Qt 桥面 `getSharedLocalStorage`）               | 不可迁移（Qt 互操作），保持不动                                       |

---

## 3. 拆分方式与执行轨迹

### 3.1 目录总账（终态实测）


| 目录                                       |   文件 |       行数 | 内容                                                                                                                                                           |
| -------------------------------------------- | -------: | -----------: | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `state/`                                   | **48** |  **9,648** | 47 个`@Observed` store + `TimeWheelController`（普通类 225 行）                                                                                                |
| `panels/panels/`                           |     25 |      4,058 | **一面板一组件**（`panelContent` 33 分支的落地件，45–2,218 行/文件）                                                                                          |
| `panels/shell/`                            |     13 |      1,898 | 六壳 + BottomDock/DockButton/PanelHeader/把手等壳件                                                                                                            |
| `panels/<domain>/**`                       |     79 |     10,812 | 16 个领域子目录（astro/object/search/time/layers/skyculture/telescope/tools/overlay/view/location/satellite/sensors/settings/guide/common）                    |
| `panels/`（根）                            |      2 |        125 | `BookmarkPanel` / `QuickChipRow`                                                                                                                               |
| `capability/`                              | **31** | **12,329** | 22 控制器 +`ControllerHooks`(17) + `AudioEngine`(927) + `I18n`(2,378) + `StartupBridge`(247) + DetailModel 四件套                                              |
| `bridge/`                                  |  **6** |    **319** | 五端口接口 +`BridgeClient`（`libentry.so` 唯一出口）                                                                                                           |
| `common/derive/`                           |     11 |      2,191 | 纯派生逻辑（`labels` 453/`astro` 349/`geometry` 322/`AstronomyGuide.ts` 197/…）                                                                               |
| `common/types/`                            |      2 |      1,888 | `StellariumTypes`(1,121) / `MainWindowModels`(767)                                                                                                             |
| `common/ui/` + `platform/` + `media/` + 根 |     15 |        403 | UiTokens/ShellIcons/InfoRow/…；Clipboard/Screenshot/Share；ImageDecoder；SpeechService 等                                                                     |
| `common/location/`                         |      3 |     82,947 | 位置参考数据（`hierarchy.ts` 74,611 / `names_zh.ts` 7,350 / `countries.ts` 986，`.ts` 数据文件）                                                               |
| `pages/`                                   | **11** |  **8,587** | 宿主 8,017 + 启动链 5 件（`ApplicationRoot` 71/`StartupSky` 218/`StartupStarGeometry.ts` 91/`PrivacyBootstrap` 65/三个 NativeNode 壳 36–47）+ 3 个一行 barrel |

**全工程最大文件 TOP**：`hierarchy.ts` 74,611（数据）→ 宿主 8,017 → `I18n` 2,378 →
`AstroPanel` 2,218 → `AstroStore` 1,578 → `StellariumResourceBootstrap` 1,003 →
`countries.ts` 986（数据）→ `SkyCultureViewTab` 943 → `AudioEngine` 927 → `SensorController` 920。

### 3.2 拆分方式：八条已固化模式（均经真机验证，PLAN §13.1/§14/§15）


| # | 模式                           | 典型落地                                                                                                                                                   | 评价                                                      |
| --- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| 1 | **store + 读取方 UI 同片搬迁** | `TimeStore`+`TimePanel`、`LayerStore`+103 个 switchRow 调用点                                                                                              | V1 下只搬 store 必丢刷新（修订 1）；每片独立回归          |
| 2 | **注入式拆分**                 | `CommandPort` 注入 store（`attachPort`）；hooks 注入控制器（`attachHooks`/构造参数）                                                                       | 依赖不硬搬；store/控制器保持可测（假 port）               |
| 3 | **逐帧字段不进被观察 store**   | `objectDetailConnector*`(9 字段)、`skyCultureArtStates` 以 `@Prop` 快照传入                                                                                | 性能护栏；避免重渲染风暴                                  |
| 4 | **参数化 `@Builder` 全部消灭** | `switchRow`/`speedChip`/… → 子组件或内联读 store；`@BuilderParam` 16→0                                                                                  | 修复"首帧冻结"bug 族；消灭规则 9 崩溃暴露面               |
| 5 | **搬迁前先清死代码**           | 三轮 54 方法 + 13 builder + 39 字段（−1,274 行），级联复扫至收敛                                                                                          | 死代码不进新结构                                          |
| 6 | **高频链隔离**                 | Dock 时钟独立于时间面板链；定时器随域下沉自持（7 store）                                                                                                   | 刷新范围=订阅者；`aboutToDisappear` 统一收口              |
| 7 | **端口隔离与子接口化**         | `CommandPort`(A/B) → 三端口(P4) → `MediaPort` 五子接口(M6：`ImagePort`/`ObjectModelMediaPort`/`FileExportPort`/`DocumentImportPort`/`ScreenCapturePort`) | 接口即依赖清单；M6 后媒体能力按用途分面，消费侧不再拖全量 |
| 8 | **barrel 过渡 + 数据归位**     | 3 个一行 barrel 保消费者不变；`location/` 82,947 行 → `common/location/`；types → `common/types/`；`I18n` → `capability/`（NAPI 判定）                  | 大迁移零消费者改写；删除留待收口（§3.5）                 |

### 3.3 五波执行轨迹（commit 锚点）


| 波次 | 日期             | 轨道                            | 宿主变化                                             | 代表产出                                                                                                                                                                                                                                                                                                  |
| ------ | ------------------ | --------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | 09 月下旬–10-04 | Phase 0–7 + RA（PLAN §13）    | 32,774 →**18,582**；`@State` 1,047→132             | 119 组件、47 store、六壳、契约脚本、域状态下沉（§2.7 旧版）                                                                                                                                                                                                                                              |
| 2    | 10-04            | **A/B 轨道 38 片**（PLAN §14） | →**14,347** / 593 方法 / 3 `load*`                  | `bridge/CommandPort`；A 类 305 纯派生下沉；B 类 70 loader 下沉（24+35+11 阶梯）                                                                                                                                                                                                                           |
| 3    | 10-05            | **P1/P4**                       | →**12,321** / 501 方法                              | 4 控制器（Sensor/Recording/ObjectModel/SkyInput）+`MediaPort`/`PlatformPort`/`SensorPort`                                                                                                                                                                                                                 |
| 4    | 10-05            | **D0–D17**（PLAN §15）        | →**8,437** / 242 方法                               | 17 簇行为控制器出仓 →`capability/` 22 控制器 + `ControllerHooks`                                                                                                                                                                                                                                         |
| 5    | 10-06            | **M1–M7**                      | →**8,017** / 223 方法 / 131 `@State` / 3 `@Builder` | `b675c48a0c` 解散 SettingsController；`9bc9992c4b` DetailModel 管线出 pages；`0c73bbb6ed` 位置数据 → `common/location/`；`b72f3c542b` guide+audio 出 pages；`126228abd9` MediaPort 子接口化；`6b7852d037`+`b4a94b5aa2` 类型 → `common/types/` barrel；`c52a517961` `I18n` → `capability/`（NAPI 判定） |

每波内部沿用切片纪律："量化→建 store/控制器/组件→单体手术→五步验收→提交"，
执行记录完整可追溯（PLAN §13.5 表 1–12、§14 逐片、§15.12 逐片）。

### 3.4 案例：`SettingsController` 的建立与解散

P 轨道曾建立 `SettingsController` 作为跨域设置动作的中转层（P 轨道产物）；
M 轨道 `b675c48a0c` 将其**解散**：域内设置动作归各自 store
（`ViewSettingsStore`/`NavigationSettingsStore`/`TimeSettingsStore`/…），
跨域分派留宿主、桥调用走 `CommandPort`。

这是全程唯一"先建后拆"的组件，教训值得留档：**中转层是脚手架，不是架构**。
当各域的 store 与端口成熟后，"把动作转发给正确的域"这个职责会自然回流到
组合根（宿主）与 store 本身，专门的中转控制器就成了多余的一跳。
判定标准：控制器的每个方法若都能回答"我其实属于哪个域"，它就不该存在。

### 3.5 `pages/` 终局与收口项

```
pages/
├─ MainWindowNativeNode.ets   8,017  宿主（组合根 + 端口适配器 + 版面装配器）
├─ ApplicationRoot.ets           71  根组件（宿主挂载 + 语言刷新锚点）
├─ StartupSky.ets               218  启动星幕动画
├─ StartupStarGeometry.ts        91  启动星几何（纯数据）
├─ PrivacyBootstrap.ets          65  隐私门控首屏
├─ FloatWindowNativeNode.ets     36  悬浮窗壳
├─ SubWindowNativeNode.ets       36  子窗口壳
├─ UiExtensionNativeNode.ets     47  UI 扩展壳
├─ I18n.ets                       2  barrel → capability/I18n.ets（M7）
├─ MainWindowModels.ets           2  barrel → common/types/MainWindowModels.ets（M6）
└─ StellariumTypes.ets            2  barrel → common/types/StellariumTypes.ets（M6）
```

**收口项（Phase 7，非阻塞）**：三个 barrel 当前承载 **293 处**消费者 import
（`I18n` 131 / `StellariumTypes` 97 / `MainWindowModels` 65，实测）。
barrel 的意义是"大迁移零消费者改写"；收口时把消费者 import 改指真实位置即可删 barrel
（机械替换 + 构建验证，一个独立小切片）。删除前 barrel 不是技术债——它正是
M6/M7 能以 7 个小 commit 完成的原因。

---

## 4. 路径与结构合理性评估

### 4.1 与计划 §3 蓝图的偏差清单（终态）


| # | 计划蓝图                                    | 实际落地                                                                                  | 评价                                                                         |
| --- | --------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| 1 | `window/shell/`、`window/overlay/` 独立目录 | `panels/shell/`、`panels/overlay/`                                                        | **可接受**（已固化约定，成本是一次性认知）                                   |
| 2 | `panels/PanelHost.ets` 表驱动 + 懒加载      | `panelContent()` 881 行 if/else，每分支已是组件                                           | **部分未达**，见 4.2-3                                                       |
| 3 | `state/` 13 个 store                        | **48 文件 / 47 store**，粒度更细                                                          | **优于蓝图**（刷新范围=订阅者）；代价是 import 区长                          |
| 4 | `panels/<domain>/` 平级领域目录             | 多出`panels/panels/` 双层（面板主体）+ 根 2 件                                            | **命名笨拙但语义自洽**，见 4.2-1                                             |
| 5 | 通用件统一                                  | `panels/common/`(1) + `common/ui/`(7) 两处                                                | 微瑕，见 4.2-4                                                               |
| 6 | `bridge/` 按域类型化方法                    | 五端口接口（`CommandPort` 五方法 + 三端口 + M6 五子接口）                                 | **形态优于蓝图**：接口即依赖清单，类型化以"面"而非"文件数"实现               |
| 7 | 计划未预见的`capability/` 层                | D 轨道新建：22 控制器 + 服务件（31 文件 12,329 行）                                       | **超出蓝图的正确新增**；控制器形态（hooks 注入 + 直写 store）在 D 轨道中定型 |
| 8 | 设置动作归`SettingsController`（P 轨道）    | M 轨道`b675c48a0c` 解散，域动作归 store                                                   | **计划外修正**，见 3.4                                                       |
| 9 | 位置/类型/服务文件散在`pages/`              | M 轨道归位：`common/location/`(82,947 行)、`common/types/`、`capability/I18n+AudioEngine` | **§11 迁移动议全部兑现**，`pages/` 只剩宿主+启动链+barrel                   |

### 4.2 逐项分析

**1. `panels/panels/` 双层目录 —— 可用，不改名。** 25 个文件全部 `XxxPanel` 命名，
语义"一个 `activePanel` 取值一个组件"，与契约脚本 33 面板清单可直接对照。
改名收益小于成本（156+ 处 import 改写 + 脚本文本切片风险）。保持。

**2. `state/` 粒度 —— 合理，一处命名说明。** `TimeWheelController`(225) 是普通类，
住 `state/` 是正确物理位置（它就是状态机）；`DockStore`(12)/`DeltaTStore`(8) 不是碎片化
——各自对应独立订阅域。**例外：`DockStore` 由 `BottomDock` 组件自持而非宿主**
（`ForEach` 复用下 `@Prop` 快照失效的修复，`DockButton` 经 `@ObjectLink` 共享），
是 47 个 store 中唯一不由组合根持有的——组件生命域恰好等于订阅域时的合理偏离。

**3. `panelContent` 未表驱动 —— 维持是合理取舍。** 分支入参高度异构
（object 分支 25 `@Prop` + 17 回调 vs hub 分支 4 参数），统一签名需参数装箱层。
33 分支全量静态 import 的启动期解析成本实测可接受（启动链脚本 17/17）。
触发条件不变：面板数 >40 再评估。

**4. 通用件分裂两处 —— 微瑕，维持冻结策略。** `common/ui/` 是跨面板通用；
`panels/common/HierColumn` 是两域共用。新通用件统一进 `common/ui/`，
`panels/common/` 冻结。

**5. 壳层在 `panels/shell/` —— 结构健康。** 六壳 + Dock/PanelHeader 等 13 件全部组件化，
`build()` 只保留"三选一分发 + 面板包裹"；叠层 zIndex/HitTestMode 契约由
`specs/UI-ARCHITECTURE.md` 锚定。

**6. 宿主 8,017 行 —— 数字仍超"瘦身"直觉，但性质已终局化。** 223 个方法全部可归域
（§2.4），无 A/B 类残留；695 行适配器类 + 742 行注入链 + 2,324 行装配区是
组合根+端口适配器+版面装配器的**最小闭包**。继续减行只有两条路：V2 翻代（§7）
或打破规则 9（已证不可行）。

**7. `common/` 的两条"向上"边 —— 登记后可接受。** 实测 `common` → `bridge` 7 处
（`SpeechService`/`ImageDecoder`/`Clipboard`/`Screenshot`/`Share` 引用端口接口，
**纯类型依赖**，不触碰运行时桥）与 `common/ui/NightModeToggleRow` → `state/NightModeStore`
1 处（叶子 UI 行消费单一 store）。均为最小必要边，见 4.3。

**8. `I18n`(2,378) 落 `capability/` 而非 `common/` —— NAPI 判定的正确执行。**
PLAN §15.7-1 规则：`common/` 不得 import/调用 `@ohos.*` 设备能力。`I18n` 有 5 处
`@ohos.i18n` 实调（系统语言/地区），故落 `capability/`，消费者经 `pages/I18n.ets`
一行 barrel 无感（131 处）。`AudioEngine` 同理（`AudioKit`）。

### 4.3 依赖方向审计（实测 import 边）

全树扫描（`from '...'` 全文匹配，含多行 import；仅 `.ets`，252 文件）：


| 目录             |         → bridge |                → state | → capability | → common |        → pages(barrel) | → @kit/@ohos                                        |   → libentry |
| ------------------ | ------------------: | ------------------------: | --------------: | ----------: | ------------------------: | ------------------------------------------------------ | --------------: |
| `bridge/`        |                — |                       0 |             0 |         0 |        3（类型 barrel） | 2（ImageKit/SensorServiceKit 类型）                  | **1（唯一）** |
| `state/`         |                37 |                      — |             0 |        31 |  84（类型+I18n barrel） | 8（ImageKit 类型 3 + hilog 5）                       |             0 |
| `capability/`    |                32 |                  **64** |            — |        33 |  53（类型+I18n barrel） | 24（ImageKit 4/ArkTS 2/AudioKit/InputKit/hilog 15）  |             0 |
| `panels/`        |             **0** |                 **133** |         **0** |       144 | 131（I18n barrel 为主） | 26（ArkUI 22/ImageKit 3/hilog 1）                    |             0 |
| `common/`        | 7（端口接口类型） | 1（NightModeToggleRow） |             0 |        — |            21（barrel） | 1（ImageDecoder 的 ImageKit 类型）                   |             0 |
| `pages/`（宿主） |                 6 |                      48 |            27 |        29 |                      — | 21（AbilityKit/CoreFileKit/LocationKit/MediaKit/…） |             0 |

**审计结论：**

1. **单向性成立**：`panels → state → bridge`、`capability → state → bridge`，
   无环。宿主是唯一全向依赖点（组合根的本分）。
2. **`panels/` 对 `bridge`/`capability` 依赖为 0**——面板不知道桥、也不知道控制器。
   这是 D 轨道最重要的结构成果：设备能力行为全部经宿主注入，面板级改动天然不触碰 NAPI 面。
3. **`libentry.so` 唯一出口未破**（`bridge/BridgeClient.ets` 1 处）。
4. **例外登记 3 条**（§4.2-7/8）：common→bridge 7 处端口接口类型依赖、
   common→state 1 处（NightModeToggleRow）、common/platform 三件（Clipboard/Screenshot/Share）
   承载 `@ohos` 剪贴板/分享调用——按 §15.7-1 判定属"平台件"例外，登记在案。
5. **`pages` barrel 293 处**消费者 import 是收口项（§3.5），非违规。

### 4.4 质量护栏现状（实测确认）


| 护栏                          | 状态                                                                                        |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| `check-ohos-ui-contract.mjs`  | **全绿**：33 面板 / 24 静态 id / 17 动态前缀 / 44 锚点 / 252+ 文件（本轮实测）              |
| V1/V2 不混用                  | 确认：0 个`@ComponentV2`/`@ObservedV2`/`@Local`/`@Trace`；纯 V1                             |
| `.id()` 锚点稳定              | 契约内 44 锚点未漂移（较第 2 版 +2，随 M 轨道新面板登记）                                   |
| `libentry.so` 唯一出口        | 确认（§4.3-3）                                                                             |
| `LocalStorage`（Qt 桥面）未动 | 确认：仅`getSharedLocalStorage()` 取 createInfo                                             |
| 文档同步                      | `UI-ARCHITECTURE.md`、根 `AGENTS.md` 结构约定已固化；PLAN §14/§15 逐片记录                |
| 行数口径                      | **本版新增纪律**：行数必须 `ReadAllLines`（UTF-8）；`Get-Content` 默认编码会吞 LF（附录 0） |

---

## 5. 风险登记与建议（终态更新）


| #  | 事项                                                                                                                                                                     | 性质 | 状态/建议                                                                                                                        |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| 1  | `panelContent` if/else 链 + 全量静态 import                                                                                                                              | 中低 | **维持**。触发条件不变（面板 >40 或启动劣化再评估表驱动/动态 import）                                                            |
| 2  | 回调仓库规模（`LayersPanel` 93 / `CompactShell` 48 / `ExpandedShell` 43 / `HoverObservatoryShell` 35 / `SkyCultureViewTab` 35 / `UnifiedObjectDetailCard` 24，实测未涨） | 中   | V1 表达上限已达；回调继续膨胀优先翻 V2（§7），不加参数                                                                          |
| 3  | ~~`nm*()` 色快照散布~~                                                                                                                                                   | —   | **已消解**：145 → 0（NightModeStore 方法化，§2.9-5）                                                                           |
| 4  | 死分支（`settings_quick_legacy` 无入口等）                                                                                                                               | 低   | 产品决策项，确认后走删除流程，勿混入重构提交                                                                                     |
| 5  | `OFFLINE_APPGALLERY_BUILD` 跳过 astro 前四段                                                                                                                             | 中   | 待非 appgallery 构建真机走查一次（PLAN 终态遗留#4）                                                                              |
| 6  | 测试脚本存量环境类失败                                                                                                                                                   | 低   | 与重构无关，按 PLAN §13.6 单独修                                                                                                |
| 7  | `panels/common/` 与 `common/ui/` 双目录                                                                                                                                  | 低   | 维持冻结策略                                                                                                                     |
| 8  | **`AstroStore` 1,578 行**（最大 store，超 800 行心理阈值）                                                                                                               | 中低 | 天文域是聚合根（星历/行星/月相/现象全在一个 store），拆分会造跨 store 编排；**暂不拆**，V2 翻代时按 `@ObservedV2` 子模型自然分面 |
| 9  | **`hierarchy.ts` 74,611 行外层中文键**                                                                                                                                   | 中   | 打包体积/解析成本；建议后续评估转 JSON 资源文件（`rawfile`）+ 启动期懒解析，独立立项                                             |
| 10 | **3 个 barrel 待删**（293 处消费者）                                                                                                                                     | 低   | Phase 7 收口切片：机械替换 import + 构建 + 删 barrel（§3.5）                                                                    |
| 11 | **hooks 接缝认知成本**（11 `extends` + 9 独立接口）                                                                                                                      | 低   | 形态已定型且有登记（§2.7）；新增控制器按"能用`BehaviorHostHooks` 就不建独立接口"收敛                                            |
| 12 | **M7 真机语言切换走查待人工**                                                                                                                                            | 中   | `I18n` 迁移后 131 消费者仅经 barrel 验证 + 构建通过；真机切语言回归未做，列入下次装机验证                                        |
| 13 | **测量口径陷阱（工具纪律）**                                                                                                                                             | 中   | `Get-Content` 默认 GBK 吞 LF 已造成一次 444 行误读；已写入附录 0 与 AGENTS 纪律，行数一律 `ReadAllLines`                         |
| 14 | `drawSkyCultureTerritoryMap` 领土图内容                                                                                                                                  | 合规 | 涉华地图呈现约束（根 AGENTS.md）；任何改动需人工审查后再动                                                                       |

---

## 6. 结论

1. **重构队列全部完成且闭环。** 五波轨迹把 32,774 行单体拆成六层目录 + 8,017 行宿主；
   八条模式全部真机验证并固化；契约护栏全绿（33/24/17/44）。
2. **宿主终态 = 组合根 + 端口适配器 + 版面装配器**，8,017 行是该身份在 V1 下的最小闭包：
   695 行五端口适配器 + 742 行注入链 + 2,324 行装配区 + 2,559 行可归域方法（223 个）+ 131 `@State`
   （46 store + 85 登记保留）+ 102 个 private 成员。**没有"没拆干净"的部分**——
   每一行都能归入 §2.4 的十四类之一，A/B 类残留为零。
3. **结构优于蓝图的三处**：`capability/` 控制器层（计划未预见的正确新增）、
   五端口 + M6 子接口化（以"接口面"实现类型化）、47 store 细粒度（刷新范围=订阅者）。
   **对蓝图的四处偏离**（`panels/panels/` 双层、PanelHost 未表驱动、通用件两处、
   SettingsController 先建后拆）均为理性取舍且已登记。
4. **依赖审计干净**：单向无环、`libentry.so` 唯一出口、`panels` 零桥/控制器依赖、
   三条例外登记在案。`pages/` 的 293 处 barrel import 是唯一收口项（Phase 7 小切片）。
5. **下一步是独立决策，不是本队列的延续**：V2 试点（§7，建议卫星域）、
   性能基线采集（§8，S0–S6）、barrel 删除、M7 语言切换真机走查。
   四件事互相独立，都不改变本文的结构结论。

---

## 7. V1 → V2 演进评审（目标形态、收益与路径）

> **前提事实：** 工程 `compileSdkVersion 26.0.0` / `compatibleSdkVersion 6.0.2(22)`，
> V2 全能力 + API 19 混用放宽 + API 22 `animateTo` 缓解均可用。
> 官方 FAQ 明确把 V2 推荐给本仓库正在遭遇的三个症状——
> "深度状态观测""计算属性重复计算""状态变量修改监听"（`faqs-arkui-885`）。
> 本节是计划 §8.2 既定路线"先拆分、再逐模块翻 V2"的兑现评估；拆分已完成，前置条件已具备。
> **拆分终态对 V2 是利好**：47 个 store 已按域隔离、22 个控制器已把行为从宿主剥离、
> 端口/hooks 接缝已把依赖显式化——V2 翻代的"单元"（模型 + 读取方）已经天然成形。

### 7.1 现状量化：V1 的"浪费面"（实测，252 个 `.ets`，行锚定口径）


| 装饰器/模式                                                    |         数量 | 说明                                    |
| ---------------------------------------------------------------- | -------------: | ----------------------------------------- |
| `@Component` / `@ComponentV2`                                  |  **181 / 0** | 全工程无 V2 组件                        |
| `@State`                                                       |      **143** | 宿主 131 + 组件 12                      |
| `@Prop`                                                        |    **1,045** | 参数快照负担                            |
| 回调型成员（行首`onX:`，含可选）                               |    **1,272** | 与第 2 版 1,280 同口径基本持平          |
| `@ObjectLink` / `@Observed`                                    | **149 / 47** | 观测对；47 = store 数（口径修正见附录） |
| `@Watch`                                                       |        **8** | 宿主 2                                  |
| `@BuilderParam`                                                |        **0** | 规则 9 崩溃面已消灭                     |
| `@Computed`/`@Param`/`@Event`/`@Provider`/`@Consumer`/`Repeat` |       全为 0 | V2 能力零使用                           |
| 宿主`AppStorage.`                                              |       **12** | 较 26 收敛（publish 收口）              |
| 宿主`nm*()` 色快照                                             |        **0** | 已在 V1 内收敛为`NightModeStore` 方法   |

> **口径修正说明：** 第 2 版 §7.1 的 `@Observed` 63 / `@ObjectLink` 260（及正文引用的 197）
> 含注释噪声（行内提及也被计数）。本版行锚定重测：47 恰等于 store 数、149 为真实
> `@ObjectLink` 成员数。callbacks（1,280→1,272）与 `@Watch`/`@BuilderParam` 同口径可比。

**官方 V1→V2 装饰器映射（`arkts-v1-v2-migration-inner-component`）：**


| V1                      | V2                                          |
| ------------------------- | --------------------------------------------- |
| `@State`                | `@Local`（需外部初始化时 `@Param`/`@Once`） |
| `@Prop`                 | `@Param`                                    |
| `@Link`                 | `@Param`/`@Event`                           |
| `@ObjectLink`           | `@Param`                                    |
| `@Provide` / `@Consume` | `@Provider` / `@Consumer`                   |
| `@Watch`                | `@Monitor`                                  |
| （无对应能力）          | `@Computed`                                 |

### 7.2 目标形态：`@ObservedV2 模型 + @ComponentV2 视图`

```
state/     @ObservedV2 class XxxModel {
             @Trace field: T          // 属性级可观测
             @Computed get derived()  // 依赖变化才重算一次
             method()                 // 纯逻辑，可单测
           }
panels/    @ComponentV2 struct XxxPanel {
             @Param model: XxxModel   // 1 个 @Param 取代 N 个 @Prop 状态快照
             @Param port: XxxPort     // 1 个端口对象取代 N 个回调
             @Event onClose: () => void   // 类型化事件（真正的动作）
           }
host       @ComponentV2 WindowNativeNode {
             @Local  壳层/路由状态（原 131 中保留的裸字段，见 §2.7.1）
             @Provider appModels / themeModel
             build() 读 @Computed，不再有 1,045 个 @Prop 转发
           }
bridge/    五端口不变；控制器照旧注入模型（"store 不碰 NAPI"护栏延续）
```

关键差别：**状态同步不再走回调**——子组件直接改模型（或 `!!` 双向），
`@Trace` 只通知"真正读了该属性的那个 UI 元素"。

### 7.3 性能收益（机制均有官方文档依据）


| # | V1 现状（本仓库）                                                                | V2 机制                                                 | 依据（本地文档）                                                        |
| --- | ---------------------------------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------- |
| 1 | 宿主 131`@State` 集中一个 struct，任一变更重跑整棵 `build()`(1,338 行)+3 builder | `@Trace` **属性级**刷新                                 | "被`@Trace` 装饰的属性变化时，**仅会通知 property 关联的组件**进行刷新" |
| 2 | 派生值每次重渲染重复计算（`panelTitle`/尺寸/颜色等 47 个几何派生）               | `@Computed` 缓存，依赖变化才计算一次                    | "依赖的状态变量变化时，**只会计算一次**"                                |
| 3 | 域状态已入 47 store，但宿主持 46 实例 + 85 裸字段 → 任一写入仍重跑`build()`     | 状态入`@Trace` 模型、宿主不读取 → **变更彻底不过宿主** | 同上                                                                    |
| 4 | loader 连续写 N 个字段 → N 次重渲染                                             | `@Monitor` 一次事件合并 + 可取变化前值                  | "不仅感知变化后数据，还能获取**变化前**的数据"                          |
| 5 | 组件内`ForEach` 列表                                                             | `Repeat` 键控 diff                                      | "V2**推荐**使用 `Repeat` 替代 `ForEach`"                                |
| 6 | 深度数据需`@ObjectLink` 逐层拆解（149 处）                                       | `@ObservedV2`+`@Trace` 直接观测嵌套                     | "提供对嵌套类对象属性变化**直接观测**的能力"                            |

**最核心的是 #1#1**：计划 §2 的根因原文即"1,047 个 `@State` 集中在同一个 struct 实例上，
任何一个变更都在同一棵渲染树上求值"——V2 属性级刷新是**对该根因的直接解**。

**诚实边界：**

1. V2 不自动更快；收益 ∝ 当前"浪费的重渲染量"。本仓库宿主 `build()` 巨大、定时器各频率写入、
   域标量高度集中 → **浪费量确实大**，但**必须逐域真机实测**（UI-only 模拟器验不了刷新，计划 §13.1 规则 4）。
2. **逐帧字段仍须排除 `@Trace`**（`objectDetailConnector*`、`skyCultureArtStates` 等）：
   每帧写 `@Trace` 属性同样逐帧发通知，"逐帧字段留宿主"的护栏必须保留（§2.12-9）。
3. `@Computed` 仅在 V2 上下文生效。

### 7.4 可维护性收益


| # | 现状（V1）                                                                                                                                                                    | V2 后                                                                                                | 规模                  |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------- |
| 1 | **回调仓库** 1,272 个 `onX`（`LayersPanel` 93 / `CompactShell` 48 / `ExpandedShell` 43 / `HoverObservatoryShell` 35 / `SkyCultureViewTab` 35 / `UnifiedObjectDetailCard` 24） | 状态同步型回调**整体消失**（直接改模型）；真动作收敛为**每域一个 Port**（`@Param`）                  | 1,272 → ≈15 个 Port |
| 2 | `@Prop` 快照 1,045（壳层 61–67 个/个）                                                                                                                                       | `@Param model`（1 个）+ `@Computed` 读派生                                                           | 数量级下降            |
| 3 | ~~145 处 `nm*()` 色快照~~ → **已在 V1 内解决**（`NightModeStore` 方法化，0 残留）                                                                                            | V2 下变为 1 个`@ObservedV2 ThemeModel(@Trace nightMode)` 经 `@Consumer` 就地取色，删掉逐面板传 store | 可选优化              |
| 4 | 壳层 61–67 个`@Prop` 多为把 store/状态**逐层转发**                                                                                                                           | `@Provider/@Consumer` 后代直读，删除转发链                                                           | 壳层签名大幅收缩      |
| 5 | `@Watch` 8 处（一事件多变化多次触发）                                                                                                                                         | `@Monitor` 合并 + 前后值                                                                             | 8                     |
| 6 | 派生靠手写方法 + 手动 publish 胶水                                                                                                                                            | `@Computed` / `@Monitor`                                                                             | —                    |
| 7 | `@Component` 禁 getter（V1 转换会丢弃，有崩溃风险）                                                                                                                           | V2 无此限制，`@Computed get` 即派生                                                                  | 消除一类隐性坑        |
| 8 | `AstroPanelHost` 端口对象 93 键（A 轨道后已从 114 收缩）                                                                                                                      | 状态同步键随模型直读消失，端口只剩真动作                                                             | 93 → ≈30            |

**最大项是 #1#1**：宿主 `panelContent`/方法区含大量 `onX: () => this.doX()` 转发胶水；
回调仓库坍缩会同时缩小宿主与每个面板的签名。注意：这不减少业务方法数，
但消除"参数管道"与"每渲染分配箭头函数"的开销，并让宿主不再因这些域重渲染。

### 7.5 迁移路径：粒度与顺序（非大爆炸）

**粒度单位 = "模型 + 它的全部读取方"，一次提交整体翻代**（V1 不能一半一半；
只翻 store 不翻读取方会丢刷新，见计划修订 1）。仍远小于 8k 宿主。

**关键洞察（避免大爆炸）：宿主可作为"挂载点"而不翻代。**
V1 `@Component` 中放 `@ComponentV2` 子组件、并传入 `@ObservedV2` 模型是允许的（API 19 起放宽混用）；
只要**宿主自身不读取该模型字段**，宿主就不会因该域变更而重渲染 → 域刷新被限制在 V2 子组件内。
跨代传递按混用指导处理：V1→V2 用 `UIUtils.enableV2Compatibility(...)`，
V2→V1 用 `makeV1Observed(...)`。


| 阶段                               | 内容                                                                                                                         | 目标域                                                                                                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **A：V2 叶子 + V2 模型，宿主不动** | 把现有`@Observed` store 改为 `@ObservedV2`+`@Trace`、交 `@ComponentV2` 叶子持有；宿主以普通成员持有、不读取                  | 已 store 化的域（卫星 / 流星 / 星表 / 导航星 / 考古线 / 拼贴 / 插件命令 / 陀螺仪 / 叠层 / Dock / 对象媒体…）——**47 store 已全部就绪，A 阶段可直接进行** |
| **B：翻宿主**                      | `@State`→`@Local`；`@Prop`→`@Param`；`@Watch`→`@Monitor`；`AppStorage`→`AppStorageV2`（经 `enableV2Compatibility` 过渡） | 宿主、`ApplicationRoot`、`QAbility`（启动门控 + CLI 事件通道 + `i18nLang`）——**最高风险，放最后**                                                        |
| **C：收口**                        | `@Prop` 快照→`@Computed`/`@Consumer`；回调→Port；`ForEach`→`Repeat`；删兼容胶水                                           | 全量                                                                                                                                                       |

**终态新增的两个便利（第 2 版没有的）：**

- **控制器无需翻代**：`capability/` 22 个控制器是普通类，不持有 V1 装饰器；
  翻代只改 store 装饰器（`@Observed`→`@ObservedV2`、字段→`@Trace`）与读取方组件装饰器。
- **hooks/port 接缝天然是 V2 的 Port**：`attachPort`/`attachHooks` 注入的接口
  直接映射为 V2 的 `@Param port`，跨域动作面已经类型化。

前置条件：A 阶段要求**宿主不再读这些字段**。现状 `panelTitle()`/`panelSubtitle()` 与
部分布局助手会读少数状态——这几处与该域**同片翻代**，或暂留 V1。

### 7.6 成本与风险


| 风险                                             | 说明                                                                                 | 对策                                                                                                 |
| -------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **`AppStorage` ↔ `AppStorageV2` 不互通**        | 宿主 12 处引用、17 个 key 含`QAbility`（无装饰器）隐私门控、CLI 事件通道、`i18nLang` | 过渡期用`enableV2Compatibility`/`makeV1Observed`；**唯一高风险项，须专片**                           |
| **`animateTo`/`transition` 动效异常**            | 官方："V2 中使用`animateTo` 可能出现动画效果异常"                                    | 项目 API 26，可用 API 22+ 的`applySync`/`flushUpdates`/`flushUIUpdates` 规避；宿主弹簧转场须逐条回归 |
| **V1 装饰器不能与 `@ObservedV2` 混用**           | 官方混用限制条件 1                                                                   | 翻代时一并替换读取方装饰器                                                                           |
| **V2→V1 不能直接用装饰器接收 `@ObservedV2` 类** | 编译报错（限制条件 2）                                                               | 中间期走`makeV1Observed`                                                                             |
| **store 翻代是原子提交**                         | 大 store（`AstroStore` 1,578 / `SkyCultureSettingsStore` 672）读取方多               | 按域分片，单域可回滚                                                                                 |
| **真机验证必需**                                 | 模拟器无引擎数据，验不了刷新                                                         | 每片真机 A/B（计划 §13.1）                                                                          |
| **`LocalStorage`（Qt 桥面）**                    | 不可迁移                                                                             | 保持不动                                                                                             |
| **`@Watch`→`@Monitor` 语义差异**                | 合并/前后值                                                                          | 8 处行为回归                                                                                         |
| **逐帧字段护栏**                                 | V2 下误加`@Trace` 同样触发逐帧通知                                                   | §2.12-9 的保留组在 V2 评审中逐字段复核                                                              |

**工作量：** 计划 §8.2 对"单体原子翻代"估 2–3 周；拆分完成后改为**分域增量**，
粗估 3–5 周，但**每片独立可编译、可装机、可回滚**——把原来"一次不可分割的大提交"
变成十几次小提交。

### 7.7 收益量化总表


| 指标                       |                  现状（V1 实测） |                   V2 目标 | 收益类型 |
| ---------------------------- | ---------------------------------: | --------------------------: | ---------- |
| 触发宿主整树重渲染的状态数 |  **131**（46 store + 85 裸字段） |   ≈50–80（仅壳层/路由） | 性能     |
| 域标量变更路径             |                     经宿主重渲染 | `@Trace` 属性级，不过宿主 | 性能     |
| 重复派生计算               | 每次 build 重算（47 个几何派生） |          `@Computed` 一次 | 性能     |
| 回调型成员                 |                        **1,272** |              ≈15 个 Port | 可维护性 |
| `@Prop` 快照               |                        **1,045** |         `@Param` 模型引用 | 可维护性 |
| `@ObjectLink` 逐层拆解     |                          **149** |    `@Param`+`@Trace` 直读 | 可维护性 |
| `AstroPanelHost` 端口键    |                               93 |        ≈30（只剩真动作） | 可维护性 |
| 列表渲染                   |                        `ForEach` |        `Repeat` 键控 diff | 性能     |

### 7.8 建议

1. **不做全量翻代**。V1 目前正确、契约全绿；V2 是**性能/可维护性投资**，非缺陷修复。
2. **先做 A 阶段 1–2 个独立域试点**（推荐**卫星域**：`SatelliteStore`(182 行) 已建且含自持定时器、
   配套 `SatelliteController`(152)/`SatellitesPanel`(221)/`SatelliteGroupSelector` 规模适中，
   且无 `AppStorage` 依赖），用真机量化"属性级刷新"的实际帧率/重排收益，**拿数据再决定是否扩大**。
3. **B 阶段（`AppStorage` 桥）单独立项**：它触碰隐私门控与 CLI 通道，风险与收益须单独评估。
4. **`animateTo` 回归列入 A 阶段验收**——这是官方明示的 V2 已知异常点。

---

## 8. UI 性能测试方法与计划

> 目的：为 §7 的 V1→V2 演进提供**可复现、可比对**的性能基线与 A/B 方法。
> 原则：**真机 + 语义 CLI + 引擎遥测**，不使用坐标点击；所有场景可重放、可恢复现场。
> 本节只定义方法与计划，**不修改任何代码**；实测数据待执行后登记。

### 8.1 指标分层（三个互补通道）


| 层               | 指标                                                              | 采集通道                                                                                                                                                          | 语义边界                                                                                          |
| ------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| L1 引擎帧遥测    | 每帧`total/cmd/update/draw/submit` (ms)                           | hilog tag**`StellariumFps`**，行 `frame: total=… cmd=… update=… draw=… submit=…`                                                                             | 最细，用于拖动/时间高频链的帧成本分布                                                             |
| L1' 引擎 FPS     | 瞬时帧率                                                          | CLI`getFPS`（C++ 原子 `s_ohosRenderFps`=1.0/dt）                                                                                                                  | 粗粒度单点读数，仅作交叉印证                                                                      |
| L2 启动/交互时序 | 首帧就绪、面板切换完成、模型帧完成                                | `getPresentationState.ready`、`getAstroPanelState.transitioning`、`getObjectModelView.renderedAt`；hilog `presented-frame-ready`/`title-assembled`/`sky-revealed` | 端到端时延                                                                                        |
| L2' 主线程健康   | `uiPulseCount`/`uiMaxDelayMs`、`computeMs`/`pixelMapMs`/`totalMs` | `getObjectModelView`                                                                                                                                              | **≠ FPS、≠ 触摸延迟**（`DETAIL-MODEL-PERFORMANCE.md` 明确）；仅区分"后台计算耗时"与"主线程被堵" |

### 8.2 工具链与前置

- **驱动**：`node scripts/stellarium-cli.mjs --device <id> --command <name> [--payload …] --json`
- **包名陷阱（必须）**：CLI 默认 `--bundle com.joinother.skyinstrument`，而本机验收/前台可能是
  **另一个由 DevEco 自动签名决定的调试包名**（计划 §13.3）。每次显式 `--bundle <本机调试包名>`（或设 `STELLARIUM_BUNDLE`），
  并用 `aa dump -l` 复核 `state #FOREGROUND`，否则会整段测到另一个包。
- **设备**：真机（Mate 80 Pro）。x86_64 模拟器无 `libstellarium.so`，引擎遥测全为 `--`，
  **只可用于结构回归，不可用于性能结论**。
- **日志**：每轮前 `hdc shell hilog -r` 清缓冲，窗口内采样，避免回绕污染。
- **可选系统级（尚未在本仓库使用，按需）**：`hitrace`（render service 帧时序）、
  `hidumper`（内存）。需先在设备上验证可用性与权限。

### 8.3 场景矩阵（确定性、可重放）


| ID     | 场景          | 步骤要点                                                                   | 主指标                                              |
| -------- | --------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------- |
| **S0** | 冷启          | `force-stop` → `aa start` → 计时到 `getPresentationState.ready==true`    | 启动→首帧 (ms)                                     |
| **S1** | 星图空转      | `setTimeRate 0`、`clearSelection`、固定 `setJD`/`setFOV 70`                | `total`/`draw` 中位数（静态基线）                   |
| **S2** | 拖动/惯性     | `moveToAltAz` → `startPanInertia` ×4 → `stopPanInertia`（既有脚本做法） | `total` 分布 p50/p95、丢帧                          |
| **S3** | 时间高频链    | `setTimeRate` 高速 + 打开时间面板                                          | `total`/p95（时间域定时器已入 store，自持链影响）   |
| **S4** | 面板开/切     | `openUiPanel <panel>` → 等 `getAstroPanelState.transitioning=false`       | 打开时延 + 打开后帧成本                             |
| **S5** | 详情媒体/模型 | `getObjectModelView`（Moon/Saturn/Jupiter，worker 帧）                     | `computeMs`/`totalMs`/`uiPulseCount`/`uiMaxDelayMs` |
| **S6** | 叠层密集      | `actionShow_MistHorizon` 0/1、网格/标签/星座线开关                         | `total` 差值与 p95 劣化                             |

### 8.4 采集协议

1. **统一条件**：同一真机、同一构建（记录 HAP 版本/提交 hash）、固定 JD/FOV/location、
   `setTimeRate 0`、关闭无关叠层。
2. **冷启**每轮 `force-stop` 后 `aa start`；**稳定态**场景先预热 ≥1.5s 再丢弃。
3. **增量采样**：`before = Set(hilog 行)` → 施加载荷 → 取新增行
   （既有 `test-ohos-mist-performance.mjs` 的做法），避免把历史帧计入统计。
4. **重复**：每场景 ≥3 次独立运行，报告 `median(p50)/p95/max` 与样本数。
5. **恢复现场**：脚本改动的持久化设置（图层/时间/位置）必须复原。
6. **产物**：JSON 报告（含原始帧行）写入 `docs/harmonyos/json/perf/`，便于版本间比对。

### 8.5 基线采集（现在，V1）

- **复用既有范式**：`scripts/test-ohos-mist-performance.mjs`（帧遥测 + `summarize()` median/p95/max +
  增量采样）、`scripts/test-ohos-model-performance-pad.py`（模型 worker 指标 + `renderedAt` 异步等待）。
- **产出建议**：新增 `scripts/measure-ohos-ui-performance.mjs`（通用场景运行器：
  `--scenario S0..S6 --device <id> --bundle <本机调试包名> --output <json>`），
  首轮生成 `docs/harmonyos/json/perf/baseline-v1-<date>.json` 并登记到 CHANGELOG。
- 基线必须**可复跑**：记录设备 SN 简写、构建提交、完整命令序列。
- **基线时机**：应在 barrel 删除等收口切片**之后、V2 试点之前**采集，
  使基线对应本文记载的终态（HEAD `c52a517961` 一线）。

### 8.6 A/B 对比（V2 试点后）

- 同一设备、同一场景脚本、同一构建开关（**仅差 V1/V2 代码**）。
- **交替运行**（V1→V2→V1→V2）以抵消热漂移；报告 p50/p95 差值。
- 判据建议：
  - **不回退**：任一场景 p95 劣化 > 10% 视为回归，须解释或阻回。
  - **改进目标**：V2 试点域对应场景（如 S4 打开卫星面板、S3 时间高频链）p95 应有可测改善。
  - **交互正确性**（点击后是否实时更新）以真机 A/B 判定，不能只看布局一致（计划 §13.1 规则 4）。

### 8.7 已知限制

1. UI-only 模拟器验不了引擎与刷新 → 性能/刷新类结论**必须真机**。
2. `totalMs`/`uiPulseCount` 等**不是 FPS 或触摸延迟**（`DETAIL-MODEL-PERFORMANCE.md` 明确）——
   禁止跨语义混用与拼凑结论。
3. 双包名与前台切换会污染测量（计划 §13.3）——全程显式 `--bundle` + `aa dump -l` 复核。
4. 热/温控与系统负载会抖动 p95——交替 A/B + 多轮取中位数。
5. hilog 缓冲回绕——每轮 `hilog -r`，控制采样窗口。

### 8.8 与 §7 的衔接

§7 建议先做**卫星域** V2 试点；对应性能验证即 **S4（打开卫星面板）+ S1/S2（面板打开前后星图帧成本）

+ 该域状态切换（如 `setSatellitesFlag`）的 p95**。V1 基线（S0–S6）应在试点**之前**采集入库，
  作为唯一对照来源。

---

## 9. panels / capability / state 三层边界与交叉审查

> **日期：** 2026-10-07（评审）；2026-10-08（实施 + §9.4 终态实测）
> **基线：** HEAD `cbc8c5bfae`（宿主 7,974 行）
> **依据：** 本文 §4.3 依赖审计、`ARKTS-PAGES-REFACTOR-PLAN.md` §15.7 架构规则 / §11 Barrel 策略
> **方法：** 全量 import 扫描（252 `.ets`）+ 逐文件导出/消费追踪 + 规则对照
> **范围：** 只做分析与选项对比，不选推荐方向，零代码改动（评审时）
> **实施状态（2026-10-08）：** P0–P4 已按「阈值拆分」执行完毕（S1–S9），执行记录见 `ARKTS-PAGES-REFACTOR-PLAN.md` §16；
> 五个超标 store（Astro/Script/Guide/TimeSettings/Telescope）的桥调用与持续定时器已移交各自控制器。
> 下文量化件保留评审当时口径，§9.4 附录补充终态实测修正。

### 9.1 层间依赖现状

#### 9.1.1 六层 import 矩阵

| 源 → 目标 | import 数 | 合规性 | 说明 |
|---|---|---|---|
| panels → state | 133 | ✅ 合规 | 面板读 store 渲染，§4.3 设计意图 |
| panels → capability | 0 | ✅ 合规 | 面板不碰控制器 |
| panels → bridge | 0 | ✅ 合规 | 面板不碰桥 |
| capability → state | **64**→**65** | ✅ 合规 | 控制器持有 store 引用以写入桥回包数据（§9 队列后实测 65，见 §9.4.1） |
| capability → panels | 0 | ✅ 合规 | 控制器不依赖面板 |
| state → panels | 0 | ✅ 合规 | store 不依赖面板 |
| state → capability | 0 | ✅ 合规 | store 不依赖控制器 |
| state → bridge | 0 | ✅ 合规 | store 依赖端口接口（非桥实现），经 `attachPort` 注入 |
| common → state | 1 | ⚠️ 已登记 | `SpeechService` → `GuideStore`（§4.3-4，冻结） |

**方向性结论**：六层之间无环、单向成立。`capability → state` 的 64 处（§9 队列后实测 65 处）
是设计意图（控制器持有 store 引用、写入桥回包数据、触发 UI 刷新），不是违规。

#### 9.1.2 panels 内部域间依赖

| 源域 → 目标域 | import 数 | 评估 |
|---|---|---|
| panels/panels/ → panels/\<domain\>/ | 44 | ✅ 面板体组合域子组件，属正常组合 |
| panels/shell/ → 6 域 | 各 1–3 | ✅ 壳层编排器职责所需（§9.2-P3） |
| panels/settings/ → panels/view/ | 1 | ✅ settings 引用 view 域子组件 |
| panels/layers/ → panels/view/ | 1 | ✅ 图层标签页含视图坐标设置 |
| panels/skyculture/ → panels/layers/ + panels/astro/ | 2 | ⚠️ 跨域组件消费（§9.2-P2/P3） |

### 9.2 发现的问题（按严重程度分级）

#### P0 · Store 同时承担控制器职责（state/capability 边界模糊）

**现象**：绝大多数 store 持有 `CommandPort` 并直接调用 `requestInteractive`——
这是控制器的本职。按 §15.7 规则 2「可观测数据入 `@Observed` store，
草稿/逐帧字段留控制器」，store 应只承载数据，桥调用/定时器应归控制器。

**量化**：

| store 文件 | `requestInteractive` 调用数 | 定时器（`setInterval`/`setTimeout`） | 评估 |
|---|---|---|---|
| **AstroStore** | **15** | 0 | ⚠️ 实质上是控制器 + store 的混合体 |
| **ScriptStore** | **8** | `setInterval` 450ms（视频状态轮询）+ `setTimeout` | ⚠️ 控制器职责重 |
| **TimeSettingsStore** | **8** | 0 | ⚠️ 桥读密集 |
| **TelescopeStore** | **3** | `setTimeout`（LX200 轮询） | ⚠️ 有定时器 |
| **GuideStore** | **1** | `setInterval`（导览步进）+ `start()`/`stop()` | ⚠️ 有定时器 + 播放器 |
| **CatalogStore** | **0** | `setInterval` 600ms（下载状态轮询） | ⚠️ 有定时器 |
| **LocationStore** | **0** | 多条 `setTimeout` 链（分块索引构建/搜索） | ⚠️ 有定时器 |
| **SatelliteStore** | **1** | `setTimeout` 90ms（防抖加载） | 中等 |
| 其余 40 个 store | 1–4 | 0 | ✅ 可接受（少量桥调用属简单读写） |

**根因**：D 轨道（STATE-REVIEW §10）将宿主行为下沉时，选择了
「简单桥调用下沉进 store、复杂行为保留控制器」的策略。
这对简单 store 合理（1–2 个 `requestInteractive`），但对 AstroStore/ScriptStore 等
已累积到 8–15 个桥调用 + 定时器的 store，实质已无法单测、无法替换桥、
且破坏了「store 无 IO」的初衷。

**影响**：
- Store 内桥调用不可 mock（需真桥才能测试）
- 定时器在 store 里无法被宿主生命周期统一收口（§15.7 规则 3 要求
  `start()`/`stop()` 在控制器里由宿主调度）
- 桥调用失败时 store 内部处理错误路径，混合了数据逻辑与 IO 逻辑

**选项对比**：

| 维度 | A) 维持现状 | B) 全面拆分 | C) 阈值拆分（桥调用 ≥5 或有定时器） |
|---|---|---|---|
| **成本** | 零 | 极高（48 store × ~2 load* 方法 ≈ 96 个方法搬迁 + 宿主接线翻倍 + 控制器文件数激增） | 中（~7 store × ~5 方法 ≈ 35 个方法搬迁 + 已有控制器复用） |
| **收益** | 无 | 边界清晰、全量可单测、宿主可统一调度所有定时器 | 解决最严重问题（AstroStore/ScriptStore 等）、其余 40 store 零风险 |
| **风险** | 边界线持续模糊，新人难判断"几个桥调用算过多" | 大规模搬迁可能引入接线错误；控制器与 store 的 1:1 配对导致文件数翻倍 | 灰色地带仍存（4 个桥调用的 store 是否应拆？） |
| **与 V2 协同** | V2 不改 IO 边界，维持现状无增量 | 拆分后的纯数据模型在 V2 下收益最大（§10 详述） | 同 B 方向，但范围可控 |
| **影响面** | 0 文件 | 48 store + 22 控制器 + 宿主 | ~7 store + 已有控制器 + 宿主 |

> 注：自然断点在 5——AstroStore(15)/ScriptStore(8)/TimeSettingsStore(8) 明显超标，
> 其余 store 的 1–4 个桥调用属简单读写。但"5"本身是经验值，无严格理论依据。

---

#### P1 · SettingsRows.ets 承担跨域共享组件库

**现象**：`panels/settings/SettingsRows.ets`（179 行）的 7 个导出中，
4 个被非 settings 面板消费：

| 导出 | 消费方 | 实属域 |
|---|---|---|
| `NavStarsToggleRow` | NavStarsPanel | sensors/navstars 域 |
| `ArchaeoToggleRow` | ArchaeoLinesPanel | archaeo 域 |
| `MosaicCameraMetric` | MosaicCameraPanel | tools 域 |
| `NavigationSwitchRow` | SettingsPanel | settings 域 ✅ |
| `EphemerisToggleRow` | SettingsPanel | settings 域 ✅ |
| `InformationModeButton` | SettingsPanel | settings 域 ✅ |
| `InformationSwitchRow` | SettingsPanel | settings 域 ✅ |

该文件是**事实上的共享行组件库**，放在 settings/ 下是名称误导。

**选项对比**：

| 维度 | A) 消费方就近 | B) common/ui/ 收口 | C) 混合（通用件进 common、域特化件归域） |
|---|---|---|---|
| **成本** | 中（4 组件迁至消费方域 + import 修正） | 中（4 组件迁 common/ui/ + 命名去域化） | 中（2 通用件迁 common + 2 域特化件归域） |
| **收益** | 域内聚，每个组件与主消费者同目录 | 零跨域依赖，共享组件集中管理 | 与 §4.2-4 口径一致（新通用件统一进 common/ui/） |
| **风险** | 次消费方仍需跨域 import | common/ui/ 膨胀；命名需去域化（`NavigationSwitchRow` → `SettingsNavigationSwitchRow`？） | 两种归属策略并存，规则需明确 |
| **与 V2 协同** | 无直接影响 | V2 `@Param` 替代 `@Prop` 可简化共享组件参数传递，但不影响文件归属 | 同上 |
| **影响文件** | SettingsRows + NavStarsPanel + ArchaeoLinesPanel + MosaicCameraPanel | SettingsRows + 所有消费方 | 同 A + B 的子集 |

---

#### P2 · 跨域通用组件（3 件）

**P2a · GraphLoadingRow**（`panels/astro/GraphGuides.ets`）

被 `SkyCultureViewTab`（skyculture 域）消费。文件名和位置暗示纯 astro，
但 `GraphLoadingRow` 是通用 spinner + label 行，无天文域硬编码。

**P2b · SkyCultureDescriptionBlockView**（`panels/skyculture/`）

被 `object/ConstellationCultureView`（object 域）和
`skyculture/SkyCultureViewTab`（skyculture 域）共用。
文件注释已承认「天体详情卡与星文化查看器共用」。

**P2c · LayerSwitchRow**（`panels/layers/`）

被 `SkyCultureViewTab`（skyculture 域）消费。
图层开关行，含图层域特化逻辑。

**选项对比**：

| 维度 | A) 留原域 | B) 迁 common/ui/ | C) 混合（通用件迁 common、域特化件留原域） |
|---|---|---|---|
| **成本** | 零 | 小（3 组件迁 + import 修正） | 小（2 通用件迁 + 1 域件留） |
| **收益** | 无 | 零跨域依赖 | 精确分类 |
| **风险** | 跨域消费持续 | common/ui/ 增长 | 两次搬迁规则需文档化 |
| **与 V2 协同** | 无 | V2 `@Provider`/`@Consumer` 可减少 prop drilling，但不改 import 关系 | 同上 |
| **建议归属** | — | `GraphLoadingRow` → common/ui/（通用加载行） | `SkyCultureDescriptionBlockView` → common/ui/（参数化描述块）；`LayerSwitchRow` → 留 layers/（域特化） |

---

#### P3 · shell/ 跨域依赖广度 + layers/view/skyculture 交叉

**P3a · shell/ 跨 6 域**

`shell/` 的 6 个壳层文件从 6 个不同域（sensors/overlay/object/tools/guide/astro）
import。壳层是布局编排器，需组装各域的浮层/卡片/控件。
与 `pages/` 宿主的组合根职责同构，只是粒度更细。

**评估**：**合理**。不建议拆分。

**P3b · layers → view 与 skyculture → layers + astro**

- `LayerViewTabs` → `ViewCoordinateSettings`（view 域）：「标记」标签页含视图坐标设置，合理
- `SkyCultureViewTab` → `LayerSwitchRow`（layers 域）+ `GraphLoadingRow`（astro 域）：
  星文化查看器引用图层开关和加载行

**评估**：面板间引用对方域的**子组件**而非 store/控制器，属 UI 组合层交叉，风险可控。
`LayerSwitchRow` 被两域消费可考虑迁 common/ui/（见 P2c）；
`ViewCoordinateSettings` 被 layers 域消费合理，不动。

---

#### P4 · 宿主死 import / TimeWheelController 归属 / SpeechService 归属

**P4a · 宿主死 import**

宿主 L128/L143 有 4 个未使用的 import：
`GraphLoadingRow`/`RtsSelectionGuide`/`GraphSelectionGuide`/`SkyCultureDescriptionBlockView`。

**评估**：清理即可，极小工作量。

**P4b · TimeWheelController.ets 位于 state/**

`TimeWheelController`（225 行，普通类）与 `TimeWheelStore` 配对放在 `state/`。
文件头部注释明确解释了分拆理由（逐帧字段不入 `@Observed`），
控制器自持定时器、注入依赖、不碰 NAPI。

**评估**：**合理**。与 store 配对放置便于维护。不改。

**P4c · SpeechService.ets 位于 common/**

`common/SpeechService.ets` 写入 `GuideStore.speechStatus`。
语义上 SpeechService 是跨域服务而非 settings 专属。

**评估**：已登记为例外（common→state 1 处，§4.3-4）。维持冻结。

---

### 9.3 不建议动的部分

| 部分 | 原因 |
|---|---|
| capability → state 的 64 个 import | 设计意图，无环，拆分只增复杂度 |
| panels/panels/ → panels/\<domain\>/ 的 44 个 import | 面板体组合域子组件，属正常组合 |
| shell/ 跨 6 域 import | 壳层编排器职责所需 |
| TimeWheelController 在 state/ | 配对放置有理，不改 |
| SpeechService 在 common/ | 已登记例外，维持冻结 |
| 桥调用 ≤4 的 40 个 store | 成本/收益不划算 |
| state → bridge 的依赖 | store 依赖端口**接口**（非桥实现），经 `attachPort` 注入，符合依赖倒置 |

### 9.4 附录：capability→state 依赖明细 + Store 桥调用计数

#### 9.4.1 capability → state 依赖（评审时按语义分组）

| 控制器 | 持有的 store 引用 |
|---|---|
| AstroCalcController | AstroStore, EphemerisStore, WutStore, SearchStore |
| DetailConnectorController | ObjectDetailStore, InfoWindowStore |
| LocationController | LocationPickerStore, LocationStore, SessionToolStore |
| LayerController | LayerViewStore, LayerStore, SceneryStore, ObjectDetailStore |
| ScriptPlaybackController | ScriptStore |
| RecordingController | ScriptStore |
| SearchController | SearchStore, ObjectDetailStore |
| BookmarkController | BookmarkStore |
| CatalogController | CatalogStore |
| SatelliteController | SatelliteStore |
| MeteorShowerController | MeteorShowerStore |
| TelescopeController | TelescopeStore |
| TimeController | TimeSettingsStore |
| GuideController | GuideStore |
| SessionToolController | SessionToolStore |
| ObjectMediaController | ObjectDetailStore |
| NavStarsController | NavStarsStore |
| ArchaeoLinesController | ArchaeoStore |
| MosaicCameraController | MosaicCameraStore |
| PluginCommandController | CommandStore |
| DockController | DockStore |
| OverlayController | OverlayStore |

> 注：部分控制器持有多个 store 引用是因为其编排逻辑跨域
> （如 AstroCalcController 编排星历/行星/月相/现象，对应 AstroStore + EphemerisStore + WutStore）。
> 这是组合根的合理下沉，不是循环依赖。
>
> **2026-10-08 终态实测修正**：上表部分名称是评审时的前瞻命名或近似 ——
> `BookmarkController` / `CatalogController` / `MeteorShowerController` / `SessionToolController` /
> `NavStarsController` / `ArchaeoLinesController` / `MosaicCameraController` / `PluginCommandController` /
> `DockController` / `OverlayController` / `ObjectMediaController` 均无对应文件；
> 这些 store（`BookmarkStore` / `MeteorStore` / `DockStore` / `CommandStore` / `NavStarsStore` /
> `ArchaeoStore` / `MosaicStore` / `OverlayStore` / `ObjectMediaStore`）实际由宿主或其他 store 消费，
> 不经 capability 控制器。按文件实测的 capability → state 边（2026-10-08，65 处 `import` 语句）如下：
>
> | capability 文件 | 持有的 store 引用 |
> |---|---|
> | AstroCalcController | AstroStore, EphemerisStore, WutStore, SearchStore |
> | DetailConnectorController | ObjectDetailStore, InfoWindowStore |
> | GuideController | GuideStore |
> | LayerController | LayerStore, LayerViewStore, SceneryStore, ObjectDetailStore, PluginStore, ScriptStore, ViewSettingsStore |
> | LocationController | LocationPickerStore, LocationStore, SessionToolStore |
> | NebulaTextureController | NebulaTextureStore |
> | ObjectInspectorMediaController | ObjectDetailStore, ObjectMediaStore |
> | ObjectModelRenderer | InfoWindowStore, ObjectDetailStore, ObjectMediaStore |
> | OcularController | ArchaeoStore, EquationOfTimeStore, MosaicStore, TelescopeStore |
> | PluginFeatureController | AstroStore, PluginStore, SearchStore |
> | PolarScopeController | PolarScopeStore |
> | RecordingController | ToolsStore, ScriptStore |
> | SatelliteController | SatelliteStore |
> | ScriptPlaybackController | ToolsStore, ScriptStore |
> | SearchController | CatalogStore, LanguageStore, SearchStore |
> | SensorController | GyroStore, SessionToolStore |
> | SettingsController | TimeSettingsStore |
> | SkyCultureController | SkyCultureSettingsStore, SkyCultureViewStore |
> | SkyCultureMakerController | SkyCultureMakerStore |
> | SkyInputController | NightModeStore |
> | SkyTextureStatusController | ToolsStore |
> | StartupBridge | AstroStore, AudioStore, GyroStore, LanguageStore, LayerStore, LayerViewStore, NightModeStore, OverlayStore, PluginStore, ScriptStore, SkyCultureViewStore, TelescopeStore, ViewSettingsStore |
> | TelescopeController | TelescopeStore |
> | TimeController | DeltaTStore, TimeSettingsStore, TimeStore |
> | ViewCoordinateController | OverlayStore |
>
> 注：本轮 §9 队列新增 `GuideController`（S6）与 `SettingsController`（S7）；`StartupBridge` 是启动服务
>（非控制器），但也持有 store 引用。

#### 9.4.2 Store 桥调用计数明细（`requestInteractive` 调用数，行锚定口径）

| Store | 调用数 | 主要桥命令 |
|---|---|---|
| AstroStore | 15 | `getPlanetPositions`/`getEphemerisData`/`getTonightEvents`/`getAlmanac`/`getMoonPhase`/… |
| ScriptStore | 8 | `playScript`/`stopScript`/`pauseScript`/`resumeScript`/`getVideoRecordingState`/… |
| TimeSettingsStore | 8 | `getSimTime`/`setTimeRate`/`advanceTime`/`setJD`/`setDate`/… |
| ObjectDetailStore | 4 | `getSelectedObjectInfo`/`getObjectInfo`/`getRTS`/… |
| InfoWindowStore | 3 | `getSelectedObjectInfo`/`searchObject`/… |
| SearchStore | 3 | `searchObject`/`listMatchingObjects`/`listObjects` |
| BookmarkStore | 3 | `getBookmarks`/`addBookmark`/`deleteBookmark` |
| CatalogStore | 0 | 无桥调用，但有 `setInterval` 600ms（下载状态轮询） |
| LocationStore | 0 | 无桥调用，但有多条 `setTimeout` 链 |
| EphemerisStore | 2 | `getEphemerisData`/… |
| LayerStore | 2 | `setActionChecked`/… |
| TelescopeStore | 3 | `getTelescopeControl`/`telescopeLx200GotoSelected`/… + `setTimeout` |
| GuideStore | 1 | `getObjectSpokenText` + `setInterval`（导览步进）+ `start()`/`stop()` |
| SatelliteStore | 1 | `getSatellites` + `setTimeout` 90ms |
| 其余 33 store | 0–2 | 简单读写（`setConfigString`/`getState`/…） |

> **2026-10-08 终态修正**：本轮 §9 P0 执行后，`AstroStore`（15→0）、`ScriptStore`（8→0）、`GuideStore`（1→0）、
> `TimeSettingsStore`（8→0）的 `requestInteractive` 已随桥加载迁入各自控制器；`TelescopeStore` 的
> live-position 持续轮询（`setTimeout` 链）亦迁入 `TelescopeController`（`loadOculars` 仍留 store）。
> 上表为评审当时（2026-10-07）口径，保留以对照。

---

## 10. V1→V2 升级与 §9 边界问题的协同分析

> **目的：** 评估 §7 V2 迁移能否优化 §9 发现的架构问题，以及拆分与 V2 的时序取舍。
> **范围：** 只做分析，零代码改动，不选推荐方向。
> **前提：** §7 已建立 V2 目标形态与迁移路径（A 阶段叶子+模型、B 阶段翻宿主）；
> §9 已识别 P0–P4 五级问题。本节分析两者的交叉影响。
> **实施状态（2026-10-08）：** §10.3 推荐的「先拆后翻」之「先拆」已完成（S1–S9，见
> `ARKTS-PAGES-REFACTOR-PLAN.md` §16）——五域 store 已还原为纯数据、控制器持桥与定时器，正是
> §10.2.1 的 V2 典型形态；V2 翻代（A/B/C 阶段）另立项。

### 10.1 V2 对 §9 各问题的直接影响评估

| 问题 | V2 是否触及根因 | 分析 |
|---|---|---|
| **P0 · Store 持有 CommandPort** | **否** | 桥调用是 IO 问题，非响应式问题。`@ObservedV2` + `@Trace` 不改变 store 是否应持有 `CommandPort`——V2 装饰器只影响"字段变更如何通知 UI"，不影响"谁应该调桥"。store 内桥调用在 V2 下依然存在，依然不可 mock、依然混合 IO 与数据逻辑。 |
| **P1 · SettingsRows 跨域** | **否** | 文件组织问题，非响应式问题。V2 `@Param` 替代 `@Prop` 可简化共享组件的参数传递（1 个 model 对象替代 N 个 `@Prop` 快照），但不影响组件文件归属哪个目录。 |
| **P2 · 跨域通用组件** | **否** | 同 P1，文件归属与 V2 无关。V2 `@Provider`/`@Consumer` 可减少 prop drilling，但不改变 import 关系。 |
| **P3 · shell/ 广度 + 域间交叉** | **否** | 布局编排层的跨域组合，V2 无影响。 |
| **P4 · 死 import / 归属** | **否** | 工程整洁问题，与响应式模型无关。 |

**结论**：V2 对 §9 的五个问题均**不直接解决根因**。这些是架构/组织层面的问题，
需要通过代码搬迁和职责重新划分来修复，而非响应式模型升级。

### 10.2 V2 对 §9 问题的间接协同：拆分控制器的 V2 收益

虽然 V2 不解决 §9 的根因，但**如果先做了 P0 拆分（store 内桥调用迁入控制器），
则 V2 的收益会被放大**。反过来，如果不拆分就翻 V2，某些 V2 收益会被 store 内 IO 混合所稀释。

#### 10.2.1 拆分后的 V2 典型形态

```
state/       @ObservedV2 class AstroModel {      // 纯数据，零 IO
                @Trace planetPositions: PlanetPosition[]
                @Trace ephemerisData: EphemerisData
                @Computed get tonightEvents(): TonightEvent[]  // 派生缓存
              }

capability/  class AstroCalcController {         // 纯编排，持有桥
                private port: CommandPort
                private model: AstroModel         // 写入模型
                loadPlanetPositions() {            // 桥调用
                  this.port.requestInteractive('getPlanetPositions', ...)
                    .then(data => { this.model.planetPositions = parse(data) })
                }
              }

panels/      @ComponentV2 struct AstroPanel {     // 纯展示
                @Param model: AstroModel           // 1 个 @Param 取代 N 个 @Prop
                @Param controller: AstroCalcController  // 动作入口
              }
```

#### 10.2.2 拆分对 V2 收益的放大点

| # | V2 收益点 | 不拆分（现状 V2） | 拆分后 V2 | 放大机制 |
|---|---|---|---|---|
| 1 | `@Trace` 属性级刷新 | store 内桥调用写 `@Trace` 字段时，每次写入都触发 UI 通知——但桥回调内常连续写 N 个字段（如 AstroStore 收到星历包后写 `planetPositions`/`moonPhase`/`almanac` 等），N 次写入 = N 次重渲染 | 控制器收到桥回调后，一次性赋值 `model.planetPositions = ...`——只有**真正被 UI 读取的字段**才触发刷新，且 `@Monitor` 可合并同帧多次写入 | 拆分使 store 变成纯数据，控制器控制写入节奏，`@Trace` 的属性级粒度才真正生效 |
| 2 | `@Computed` 派生缓存 | store 内桥方法（`load*`）和 `@Computed` 混在一起——`@Computed` 依赖的字段可能被桥回调高频更新，缓存频繁失效 | 控制器负责桥调用与写入时机，`@Computed` 只依赖纯数据字段，缓存命中的条件由控制器控制 | 拆分后 `@Computed` 的依赖图更清晰，缓存失效频率降低 |
| 3 | `@Monitor` 写入合并 | store 内桥回调连续写 N 个字段 → V1 下 N 次重渲染，V2 下 `@Monitor` 可感知但仍然 N 次通知 | 控制器可在桥回调完成后再统一写入模型，`@Monitor` 一次感知 | 拆分使写入节奏可控，`@Monitor` 的合并能力才有用武之地 |
| 4 | 可单测性 | store 内桥调用不可 mock（需真桥），V2 不改变这一点 | 控制器可注入 mock 桥，store 纯数据可独立验证 `@Computed`/`@Trace` | 拆分 + V2 = 可单测的纯数据模型 + 可 mock 的控制器 |

#### 10.2.3 不拆分就翻 V2 的风险

| 风险 | 说明 |
|---|---|
| `@Trace` 逐帧通知 | 如果 store 内有定时器驱动的桥轮询（如 ScriptStore 的 450ms 视频状态轮询、CatalogStore 的 600ms 下载状态轮询），每次轮询结果写 `@Trace` 字段都触发 UI 通知——与 V1 的 `@State` 重渲染等价，V2 的属性级优化被绕过 |
| `@Computed` 频繁失效 | 桥回调写入依赖字段 → `@Computed` 缓存每次都失效 → 退化为无缓存的普通 getter |
| 混合逻辑的 `@Monitor` | store 内桥调用的错误处理与 `@Monitor` 的数据响应逻辑混合，难以区分"桥调用失败的回退"与"数据变更的响应" |
| 逐帧字段护栏 | §2.12-9 的逐帧字段在 V2 下仍须排除 `@Trace`（每帧写 `@Trace` 同样逐帧发通知）。store 内 IO 混合使"哪些字段不该加 `@Trace`"的判断更困难 |

### 10.3 时序取舍：先拆后翻 vs 先翻后拆 vs 同步

#### 10.3.1 三种时序的利弊对比

| 维度 | A) 先拆后翻 | B) 先翻后拆 | C) 同步（拆+翻同批） |
|---|---|---|---|
| **依赖关系** | 拆分不依赖 V2，V2 不依赖拆分，两者独立可行 | 同左 | 同左 |
| **V2 收益最大化** | ✅ 拆分后的纯数据模型在 V2 下收益最大（§10.2.2 四个放大点全部生效） | ⚠️ V2 收益被 store 内 IO 混合稀释（§10.2.3 四个风险） | ✅ 同 A |
| **拆分的 V1 安全性** | ✅ 拆分在 V1 下做，现有 22 个控制器已验证过"控制器持有 store"模式 | ✅ 同 A | ⚠️ 同时改响应式模型 + 职责归属，变更面大 |
| **风险控制** | ✅ 两步独立验证：先验证拆分（V1 build + 契约）、再验证 V2（A 阶段试点） | ⚠️ V2 先行时 store 内 IO 混合可能导致 V2 性能收益不达预期，需回溯排查 | ⚠️ 同批变更面大，出错时难定位是拆分问题还是 V2 问题 |
| **回滚粒度** | ✅ 拆分回滚与 V2 回滚独立 | ⚠️ V2 翻代后若发现 store 内 IO 问题，需再拆分——但此时代码已是 V2 形态，拆分变更量更大 | ⚠️ 同批回滚，粒度粗 |
| **总工作量** | 中（拆分 ~35 方法搬迁 + V2 A 阶段按域翻） | 中偏高（V2 A 阶段 + 发现 IO 问题后追加拆分，拆分在 V2 代码上做更复杂） | 高（同批变更量大，测试覆盖要求高） |
| **与 §7 路径的兼容** | ✅ §7 A 阶段"V2 叶子 + V2 模型"天然契合拆分后的纯数据模型 | ⚠️ §7 A 阶段直接在现有 store 上加 `@ObservedV2`/`@Trace`，store 内桥调用导致 `@Trace` 逐帧通知 | ⚠️ 偏离 §7 "逐模块翻 V2"的渐进路径 |

#### 10.3.2 依赖关系图

```
  拆分（P0）              V2 A 阶段
  store内桥调用            @ObservedV2 模型
  迁入控制器              + @ComponentV2 叶子
       │                       │
       │    ┌──────────────────┘
       │    │  V2 收益被拆分放大
       ▼    ▼
  ┌──────────────────┐
  │  纯数据模型 V2    │  ← 拆分 + V2 的终态
  │  + 独立控制器     │
  │  + 属性级刷新     │
  └──────────────────┘

  但两者无硬依赖：
  - 拆分可在 V1 下独立完成（控制器持有 store，V1 已验证）
  - V2 可在未拆分的 store 上独立进行（但有 §10.2.3 风险）
  - 协同有增量收益，但不协同也不阻塞
```

### 10.4 P1–P4 与 V2 的协同评估

| 问题 | V2 协同 | 分析 |
|---|---|---|
| **P1 · SettingsRows 跨域** | 弱协同 | V2 `@Param` 可简化共享组件参数传递（1 个 model 替代 N 个 `@Prop`），但不影响文件归属。无论选哪种归属策略，V2 翻代时机与 P1 搬迁时机独立。 |
| **P2 · 跨域通用组件** | 弱协同 | 同 P1。V2 `@Provider`/`@Consumer` 可减少 prop drilling，但不改 import 关系。组件搬迁可在 V1 下完成，V2 翻代时自然受益。 |
| **P3 · shell/ 广度** | 无协同 | 布局编排问题，V2 无影响。 |
| **P4 · 死 import / 归属** | 无协同 | 工程整洁问题，与 V2 无关。 |

**结论**：P1–P4 的搬迁与 V2 翻代**无时序依赖**，可独立安排。
建议在 V2 A 阶段之前完成 P1–P2 搬迁（减少 V2 翻代时的 import 变更量），
但非强制。

### 10.5 综合分析总结

1. **V2 不解决 §9 的根因**：五个问题均为架构/组织层面，需代码搬迁修复，
   非响应式模型升级所能覆盖。

2. **P0 拆分与 V2 有强协同**：拆分后的纯 `@ObservedV2` 数据模型 + 独立控制器
   是 V2 的典型形态，四个放大点（属性级刷新生效、`@Computed` 缓存命中、
   `@Monitor` 写入合并、可单测性）全部依赖拆分才能充分实现。

3. **不拆分就翻 V2 有风险**：store 内 IO 混合会导致 `@Trace` 逐帧通知、
   `@Computed` 频繁失效、`@Monitor` 逻辑混合、逐帧字段护栏判断困难。

4. **P1–P4 与 V2 无强协同**：文件组织问题与响应式模型无关，搬迁时机独立。

5. **时序建议**：基于分析，三种时序各有适用场景——
   - 追求 V2 收益最大化且可接受拆分工作量 → 先拆后翻
   - 优先验证 V2 可行性、拆分留后 → 先翻后拆（但需接受 V2 收益可能不达预期）
   - 人力充足且变更控制能力强 → 同步（风险最高但最快到达终态）

## 附录：本文数字的复现命令

> **0) 口径警示（本版新增纪律）**
> **不要用 `Get-Content`/`Measure-Object -Line` 统计行数。**
> UTF-8 中文注释 + LF 文件在 PowerShell 默认 GBK 解码下会把部分换行符吞进上一行，
> 行数系统性偏低（宿主实测被低估 444 行：8,017 被读成 7,573）。
> 行数一律 `[System.IO.File]::ReadAllLines`；装饰器计数一律行锚定正则（`(?m)^\s*@Xxx`），
> 否则注释里的装饰器名会被计入（第 2 版 §7.1 的 `@Observed` 63 即噪声，实际 47）。

```powershell
# 1) 主文件体量与结构指标（§1.1/§2.1）
$p = (Resolve-Path 'harmonyos/ets-source/pages/MainWindowNativeNode.ets').Path
[System.IO.File]::ReadAllLines($p).Count                    # → 8017
$raw = [System.IO.File]::ReadAllText($p)
([regex]::Matches($raw,'(?m)^import ')).Count               # → 222
([regex]::Matches($raw,'(?m)^\s*@State\s')).Count           # → 131
([regex]::Matches($raw,'(?m)^\s*@Builder\b')).Count         # → 3
# private 方法（含 static/async/泛型，§2.4 的 223）：
([regex]::Matches($raw,'(?m)^\s*private\s+(static\s+)?(async\s+)?[A-Za-z_]\w*\s*(<[^>]+>)?\s*\(')).Count
# @State 类型分布（46 store + 85 裸字段，§2.7.1）：
#   逐 @State 行（含续行）提取冒号后类型计数；*Store 各计 1（共 46），
#   number/boolean/string/Record/Array/ResourceStr/WindowNativeNodeCreateInfo 合计 85。

# 2) 区块定位（§2.1 的行号）
Select-String -Path $p -Pattern '^class Host|^export struct|^  aboutToAppear|^  aboutToDisappear|^  build\(\)|^  @Builder'
# → HostCommandPort 261 / HostMediaPort 306 / HostPlatformPort 784 / HostSensorPort 839 /
#   HostLocationPort 897 / struct 958 / aboutToAppear 2349 / aboutToDisappear 3091 /
#   build 5694 / floatingPanel 7032 / compactPanel 7089 / panelContent 7137

# 3) 目录总账（§1.2/§3.1，UTF-8 行数；勿用 Get-Content 计数）
Get-ChildItem 'harmonyos/ets-source' -Directory | ForEach-Object {
  $n=0; $l=0
  Get-ChildItem $_.FullName -Recurse -File | Where-Object {$_.Extension -in '.ets','.ts'} |
    ForEach-Object { $n++; $l += [System.IO.File]::ReadAllLines($_.FullName).Count }
  "$($_.Name): $n files / $l lines"
}
# → bridge 6/319  capability 31/12329  state 48/9648  panels 119/16852
#   common 31/87486  pages 11/8587  qability 10/2027  qabilitystage 1/135  process 1/14

# 4) 全工程装饰器普查（§7.1，行锚定口径，仅 .ets=252 文件）
$files = Get-ChildItem 'harmonyos/ets-source' -Recurse -File -Filter *.ets
$keys = 'Component','Observed','ObjectLink','Prop','State','Watch','BuilderParam'
#   逐 key 累加 ([regex]::Matches($raw, "(?m)^\s*@$k\b")).Count：
# → Component=181 Observed=47 ObjectLink=149 Prop=1045 State=143 Watch=8 BuilderParam=0
#   回调型成员：([regex]::Matches($raw, '(?m)^\s*on[A-Z]\w*\??\s*:')).Count → 1272
#   （第 2 版口径说明：旧回调数 1,280 与本口径一致可比；旧 @Observed 63/@ObjectLink 260
#    为非行锚定噪声读数，勿引用。）

# 5) 依赖方向审计（§4.3；from '...' 全文匹配以覆盖多行 import）
#   逐目录统计 from '../<dir>/…' 边数，另计 @kit/@ohos 与 libentry。
#   关键断言：panels → bridge = 0、panels → capability = 0；libentry.so 仅 bridge/BridgeClient.ets 1 处。

# 6) barrel 消费者数（§3.5）
$all = Get-ChildItem 'harmonyos/ets-source' -Recurse -File -Filter *.ets
#   I18n：from '…pages/I18n' → 131；MainWindowModels → 65；StellariumTypes → 97（合计 293）

# 7) 契约护栏
node scripts/check-ohos-ui-contract.mjs
# → UI contract intact: 33 panels, 24 static ids, 17 dynamic prefixes, 44 id anchors, over 252 files.

# 8) CRLF 规范化（本文档自身的写回纪律）
$t = [System.IO.File]::ReadAllText($targetPath)
$t = $t -replace '(?<!\r)\n', "`r`n"
[System.IO.File]::WriteAllText($targetPath, $t, [System.Text.UTF8Encoding]::new($false))
```

**历史普查判据留档（考古用）：**
A 类纯派生判据 = 非 void/Promise 返回 + 名字非动作动词 + 无成员写/IO/桥/路由/定时器/AppStorage/hilog；
B 类可沉性判据 = 按依赖足迹 B1（仅桥+本域 store）/B2（+助手/他域/publish）/B3（+宿主裸字段写）。
两者在终态的残量：A 类 0、B 类 1（`loadSkyCultureDetails`，§2.12）。
