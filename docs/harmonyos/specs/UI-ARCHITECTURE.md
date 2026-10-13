# 界面与窗口层级总览（UI / Window Architecture）

> 建立时间：2026-09-28（DevEco Code）；2026-10-02 按 pages/ 重构终态校正。
> **来源**：逐条从当前 ArkTS 源码核实；宿主为 `harmonyos/ets-source/pages/MainWindowNativeNode.ets`
> （构建输入，与生成工程一致），面板/壳层在 `panels/**`、状态在 `state/*Store.ets`，
> 另涉 `harmonyos/ets-source/qability/QAbility.ets`、`pages/ApplicationRoot.ets`、各 `*NativeNode.ets`。
> **不再内嵌易失真的行号**（重构会搬动它们），一律以组件/方法名 + 文件定位。
> 末尾第 9 节列出与既有文档的差异 —— **本文以代码为准**。

## 0. 四层结构一览

```
Ability / WindowStage 层   QAbility（单 Ability、单窗口）
        │  一次性 WindowStage.loadContent('pages/ApplicationRoot')
页面层                     ApplicationRoot（@Entry）
        │  三个互斥子层：WindowNativeNode / 启动覆盖层 / PrivacyBootstrap
主页面叠放层               MainWindowNativeNode.build() 的根 Stack（zIndex -1 … 99）
        │  按条件挂载
壳层                       HarmonyShell → CompactShell / ExpandedShell / HoverObservatoryShell
                           （另有 ScriptFocusShell / InteractiveGuideShell；均为 panels/shell/*.ets 组件）
```

## 1. 窗口层：Ability → WindowStage → 页面

- **单 Ability、单窗口、单次 loadContent**。`QAbility.preparePrivacyHostPage()`（`QAbility.ets:363`）执行：
  `getMainWindow()` → 构造 `QtWindowStageAdapter`（`:376`）→ `windowStage.loadContent('pages/ApplicationRoot', this.rootStorage)`（`:377`）→ `enterImmersive(windowStage)`（`:379`）。
- **`QtWindowStageAdapter` 是应用自有的 WindowStage 适配层**（`qability/QtWindowStageAdapter.ets`）：把原生 `createInfo` 与 `onAppear`/`onDisAppear` 回调原样放进根 LocalStorage，**不再次调用真实 `WindowStage.loadContent`**；同时补齐 API 26 新增的 `setImageForRecent` / `removeImageForRecent`。Qt 升级需回归这一层（它不是官方扩展接口）。
- **四种 Qt 嵌入页面**，结构完全相同 —— 只是 `XComponent({ type: XComponentType.NODE, libraryname: 'qohos' })` 的宿主，`createInfo` 从 SharedLocalStorage 读取：

| 页面 | 用途 |
| --- | --- |
| `pages/MainWindowNativeNode.ets` | 主窗口页面壳/装配（18,593 行；面板 UI 已下沉到 `panels/**`） |
| `pages/FloatWindowNativeNode.ets` | 悬浮窗 |
| `pages/SubWindowNativeNode.ets` | 子窗口 |
| `pages/UiExtensionNativeNode.ets` | UIExtension 嵌入 |

  创建与回调绑定由 `qability/QEmbeddedComponentCreator.ets` 负责。

## 2. 页面层：`ApplicationRoot`（@Entry）

`build()` 是一个 Stack，三个互斥子层（背景固定 `#05070F`）：

| 顺序 | 子层 | 出现条件 | 说明 |
| --- | --- | --- | --- |
| 1 | `WindowNativeNode()` | `stellariumPrivacyNativeStartupAllowed && stellariumQtContentReady` | 真正的主界面 |
| 2 | 启动覆盖层：`StartupSky()`（`HitTestMode.Block`）+ 底部 `LoadingProgress` + 加载文案 | `loadingVisible` | 「汇字」动效；`stellariumStartupSkyReady` 与 `stellariumStartupArtComplete` 同时为真后 `animateTo(STARTUP_REVEAL_MS)` 淡出并置 `loadingVisible=false` |
| 3 | `PrivacyBootstrap()` | 原生/ Qt 未就绪 | 隐私门控宿主（未同意时不构建 Qt 内容） |

## 3. 主页面叠放层：`MainWindowNativeNode.build()`

根 `Stack`，`backgroundColor(Color.Black)`、`focusable(true)`、`defaultFocus(true)`、`onKeyEvent(handleSkyKey)`、`onMouse(handleSkyMouse)`。

| zIndex | 层 | 命中行为 | 备注 |
| --- | --- | --- | --- |
| `-1` | 隐藏的 `Text(this.i18nLang)` | — | 语言刷新锚点：让 build 依赖 `AppStorage('i18nLang')`，语言切换后 `I18n.t()` 全部重算 |
| `-1` | `XComponent(NODE, id=createInfo.xComponentId, libraryname:'qohos')` | `None` + `enabled(false)` | Qt 原生节点，仅 `opacity(0.01)`；受 `privacyNativeStartupAllowed` 门控 |
| `0` | `XComponent(SURFACE, id='stellarium_entry_gl_probe', libraryname:'entry')` | `None` | EGL / SURFACE 探针 |
| `0` | 触摸反馈圆点 ×2（单点 / 多点） | `None` | `skyTouchFeedback`、`skyTouchFeedbackMulti`，随触点 `offset` |
| — | 专属触摸面 `Stack()` | `None` + `onTouch(handleOverlayTouch)` | 注释明写：**不能挂在全屏 UI 父上**，否则抑制 toolbar/面板按钮的 `onClick` |
| 条件 | `ScriptFocusShell` / `RecordingFocusShell` / `HarmonyShell`（或 `HoverObservatoryShell` / `ExpandedShell` / `CompactShell`） / `RecordingControlBar` / `PolarScopeOverlay` / 三组预览 Overlay | 各层自管 | 脚本回放、录制、极轴镜、星空文化美术预览、详情媒体/模型预览；互斥条件见宿主 `build()` 的布局分发 |
| `92` | 星纹理状态条（`LoadingProgress` + 重试按钮） | `Transparent` | 180ms 淡入 |
| `98` | 夜间模式红膜 `#A00000`，`blendMode(COLOR, OFFSCREEN)`，`opacity 0.78` | `Transparent` | 450ms `EaseInOut` |
| `99` | 夜间模式黑膜 `opacity 0.48` | `Transparent` | 同上 |

> 宿主单体现只剩 `zIndex` 取值 `-1, 0, 3, 30, 80, 92, 98, 99`（其余组件内的 `zIndex` 见各自文件；全应用层级以 `panels/**` 为准）。

## 4. 壳层与响应式断点：`updateResponsiveLayout()`

### 4.1 判定输入

`skyWidth` / `skyHeight`（vp，实际内容区）→ 短边、长边、宽高比；再叠加 `isFoldableDevice`、`foldStatusValue`、`foldDisplayModeValue`、`responsiveFoldAngle()`。

> 代码注释明确一条原则：**折叠状态描述的是物理设备，不是当前窗口**。浮动模式下 API 22 仍可能报"展开态"，因此**以实际内容边界为准**。

### 4.2 画布阈值

| 名称 | 条件 |
| --- | --- |
| `compactWindow` | 短边 < 520 |
| `largeFoldCanvas` | 可折叠 && 短边 ≥ 620 && aspect ≤ 1.55 |
| `tabletCanvas` | 短边 ≥ 700 **或**（短边 ≥ 620 && 长边 ≥ 1000 && aspect ≤ 1.75） |
| `desktopCanvas` | width ≥ 900 && height ≥ 520 |

半折（half-fold）角度阈值：`158`（完全展开→expanded）/`140`（expanded→hover）/`68`（→hover）/`55`（→compact）。

### 4.3 结果与切换

- `responsiveLayoutMode ∈ { compact, expanded, hover }`，派生出 `isExpandedLayout` / `isFoldHoverLayout` / `isFoldTabletLayout`（可折叠 && expanded && 短边 < 760）。
- 切换动画：`getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, applyLayout)`。
- 壳层转场（`HarmonyShell`，`panels/shell/HarmonyShell.ets`）：`OPACITY 180ms EaseOut` + `scale`（compact/hover `0.985`、expanded `1.015`，220ms `curves.springMotion(0.55, 0.88)`）。

### 4.4 壳层组件（`panels/shell/*.ets`）

| 组件 | 文件 | 结构要点 |
| --- | --- | --- |
| `HarmonyShell` | `HarmonyShell.ets` | 按 `isFoldHoverLayout` / `isExpandedLayout` 三选一分发；承载视图坐标 Overlay 与 Dock 专用命中层 |
| `ExpandedShell` | `ExpandedShell.ets` | 星图面 `HitTestMode.Block` + `onTouch(handleSkyTouch)`；底部 Dock `Row` 高 54 |
| `CompactShell` | `CompactShell.ets` | 手机/窄窗：底部面板向上拉起 + 底部 Dock |
| `HoverObservatoryShell` | `HoverObservatoryShell.ets` | 半折「观测台」形态 |
| `ScriptFocusShell` | `ScriptFocusShell.ets` | 脚本回放焦点层 |
| `InteractiveGuideShell` | `InteractiveGuideShell.ets` | 交互导览焦点层 |

> 浮动/底部面板容器（`floatingPanel` / `compactPanel`、`position(panelLeft, panelTop)`、`HitTestMode.Default`、`zIndex 30`）按 ArkUI 限制**仍留在宿主**（不能在子组件里调用宿主 `@Builder`，见计划 §13.1 规则 9）。

## 5. 入口与面板

- **Dock**：`DockButton` 组件（`panels/shell/DockButton.ets`）由 `ShellAction` 驱动。
- **面板 id**：宿主 `setPanel('id')` 现用 `search` / `time` / `more` / `astro` / `scripts`（其余入口经 `openSubPanel` / `openPanelFromCli`）；**权威清单**是 `scripts/check-ohos-ui-contract.mjs` 校验的 33 个 `activePanel` id（基线 `docs/harmonyos/json/ui-contract-baseline.json`）。
- **跨设备一致性约定**（`HANDOFF.md:5-9`、`research/PANEL-PLUGIN-ARCHITECTURE-ROADMAP.md`）：
  手机/平板/桌面共用一套底部 Dock（搜索 / 时间 / 位置 / 图层 / 更多）；`moreActions` 是**唯一**的低频功能清单；设备尺寸**只改变呈现**，不改变功能入口；手机与宽屏共享同一 `setPanel` 状态机；关闭按钮关闭整个面板，**不等同于返回**。

## 6. 命中测试（HitTestMode）规则

实测分布（宿主单体，组件化后）：`None 5` / `Default 4` / `Transparent 4` / `Block 1`；其余组件的命中模式见各 `panels/**` 文件。

| 模式 | 用在哪 | 规则 |
| --- | --- | --- |
| `Block` | 壳层星图触摸面（`ExpandedShell` 的第一层）、启动覆盖层 `StartupSky` | 承接星图手势，**但绝不能覆盖 UI 父层** |
| `Default` | 面板容器（如浮动面板 `zIndex 30`）、坐标 Overlay | 让**最深子控件**（Button / Slider / Scroll / TextInput）拿到手势 |
| `None` | 纯装饰层（隐藏锚点、触摸反馈圆点、探针表面） | 不参与命中 |
| `Transparent` | 夜间模式膜、状态条 | 自身不响应，子控件仍可响应 |
| `BLOCK_HIERARCHY` | 需要整棵子树吞掉事件的少数场景 | 谨慎使用 |

**历史教训**（`archive/MOBILE-UI-HANDOVER.md:243-264` 有完整正误对照）：曾用「全屏 Column + `HitTestMode.Block`」重构手机壳层，结果星图无法拖动、星星点不中、Dock 被吞、`isUiPoint` 失效 → 该 commit 被回退。**结论：星图触摸只挂专属触摸面，UI 组件各自 `onClick`。**

## 7. 视觉与动效常量（代码常量）

```ts
const UI_RADIUS_CONTROL: number = 14     // 常规控件圆角
const UI_RADIUS_PANEL:   number = 22     // 面板
const UI_RADIUS_SHEET:   number = 28     // 半屏面板
const UI_RADIUS_PILL:    number = 999    // 胶囊
const UI_OPTION_ANIMATION_MS: number = 180   // 选项切换过渡
```

官方口径提醒（`DEVELOPMENT-MCP-WORKFLOW.md` 的 2026-09-06 MCP 核验）：**14vp 与 180ms 是本项目的设计选择，不是官方强制值**；胶囊按钮的圆角由宽高决定，`borderRadius` 对它不生效；动画必须状态驱动（`getUIContext().animateTo`），且不得抢占 `Scroll` / `Slider` / `TextInput` / 按钮的命中区域。

其他已核实的动效参数：壳层转场 180ms + `springMotion(0.55, 0.88)`；夜间模式 450ms `EaseInOut`；启动层淡出 `STARTUP_REVEAL_MS`（见 `specs/STARTUP-MOTION-DESIGN.md`）。

## 8. 沉浸式与安全区

- 启动即 `enterImmersive(windowStage)`（`QAbility.ets:379`）。
- 顶部安全区：`QAbility.publishScreenSafeArea(topPixels)` 把 `avoidArea.topRect.height`（px）发布到 AppStorage `stellariumScreenSafeTopPixels`；页面侧用 `@StorageLink` 读取并按 `px2vp()` 换算，再做避让（例：`Math.max(8, safeTop + 8)`、`Math.max(18, safeTop + 12)`）。
- 状态条/面板的 `position` 会按 `isExpandedLayout || isFoldHoverLayout` 走不同 y 偏移（例：状态条 y = 58 / 98）。

## 9. 与既有文档的差异（**以本文与代码为准**）

| 文档 | 差异与提醒 |
| --- | --- |
| `HANDOFF.md:3-11`（「当前 UI 架构」） | 结论与代码一致（唯一 Dock、一套 `setPanel`、按窗口断点适配、废弃 iPad 侧栏）；但同文件写「当前 API 24 工程」，**已滞后于 API 26 现状** |
| `archive/MOBILE-UI-HANDOVER.md` | **回退态文档**，标题状态即「已回退到 `ba34693f4e`，手机端 UI 功能缺失，需重新实现」。其中 `compactShell` 是**待恢复目标**而非当前实现；其 zIndex 约定（1/3/50）与现状（0~1100 分布）不一致 |
| `archive/design/DESIGN-VISION.html` | 设计愿景（弹回 `response 0.55s` / `dampingFraction 0.8`）；落地后的真实参数是 220ms / 180ms / `springMotion(0.55, 0.88)` |
| `policy/PRIVACY-REVIEW-2026-09-08.md` + `KNOWN-ISSUES.md` P0 | 「单窗口、不重复 loadContent、ApplicationRoot 唯一主页面」与代码一致 ✔ |
| `research/PANEL-PLUGIN-ARCHITECTURE-ROADMAP.md` | 入口边界表仍是有效约定（唯一入口 + 关闭≠返回） |

**已知空白**：至今没有任何文档描述过「Ability → WindowStage → ApplicationRoot → 四种 NativeNode → 壳层」这条完整链路；本文第 1~4 节即为此补齐。

## 10. 核对方法（可复现）

```powershell
# 契约基线（33 面板 / 22 静态 id / 17 动态前缀 / 42 锚点）——改 UI 后必须跑
node scripts/check-ohos-ui-contract.mjs
node scripts/check-ohos-refactor-slice.mjs      # 切片结构自洽（括号/@Builder/引用）

$m = 'harmonyos/ets-source/pages/MainWindowNativeNode.ets'
Select-String -LiteralPath $m -Pattern 'zIndex\(' | Select-Object LineNumber, Line          # 宿主剩余叠放层
Select-String -LiteralPath $m -Pattern 'HitTestMode\.' | Group-Object { $_.Line -replace '.*HitTestMode\.(\w+).*','$1' }
Select-String -LiteralPath $m -Pattern 'updateResponsiveLayout|desktopCanvas|tabletCanvas|responsiveLayoutMode'
Select-String -LiteralPath $m -Pattern 'setPanel\(' | Select-Object LineNumber, Line          # 面板 id
Select-String -LiteralPath $m -Pattern '^const UI_'                                          # 视觉常量
# 壳层/面板（组件化后按文件核对）
Get-ChildItem harmonyos/ets-source/panels/shell -Filter *.ets                                # 六个壳 + chrome 件
Get-ChildItem harmonyos/ets-source/state -Filter *Store.ets                                  # 各域 store
Select-String -LiteralPath 'harmonyos/ets-source/qability/QAbility.ets' -Pattern 'loadContent|preparePrivacyHostPage|publishScreenSafeArea'
Get-Content      'harmonyos/ets-source/pages/ApplicationRoot.ets'                            # 页面三层
```
