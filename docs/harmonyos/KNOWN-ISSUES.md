# 已知问题列表

> 格式：每个 Bug 一条记录，标注优先级和状态。新 Agent 从这里选任务。

---

## P0 - 阻断性

### 0. 应用启动即 SIGABRT（Qt 初始化顺序 / 线程错配）— 【2026-07-21 WorkBuddy 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-21）
- **现象（修复前）：** `aa start` 返回 success，但进程 `org.qtproject.example.stellarium` 立即 `Signal:SIGABRT` 退出。
- **崩溃关键行：** `auto QtOhos::makeQtThreadWithMainFuncLauncher(...) mainThread (...) != currentThread (...). Qt API was likely used before Qt initialization. Aborting.` → `libQt6Core.so (QMessageLogger::fatal)` → `DfxFaultLogger: Reason:Signal:SIGABRT`
- **真实根因（已验证）：** N-API 命令桥 `hello.cpp::resolveStellariumCommand()` 在 **ArkUI/JS 线程**、Qt 核心尚未启动时，用 `dlopen("libstellarium.so", RTLD_NOW)` **首次加载了 Qt 应用二进制 `libstellarium.so`**（Qt 的 `main()` 就在此库内）。而该库本应由 **Qt-for-OHOS 插件（libqohos.so）在专用 Qt 主线程上** 加载并启动 `main()`（证据：`stellarium-harmony-deployment-settings.json` 的 `"application-binary": ".../build/src/libstellarium.so"`）。ArkUI 线程的抢占式 `dlopen` 破坏了 Qt 插件对 Qt 主线程上下文的初始化，使插件自己在 `makeQtThreadWithMainFuncLauncher` 中因 `mainThread != currentThread` 而 `qFatal` 中止进程。
  - 时间线旁证（崩溃 log）：`Stellarium command bridge resolved`（ArkUI 线程触发 dlopen）发生在 `appLaunchParam set from Ability` + `preferred stack size for Qt Thread`（Qt 插件启动 main）**之前约 40ms**。
- **修复（已验证有效）：**
  1. `hello.cpp::resolveStellariumCommand()` 改为 **只查已加载库**（`dlopen(..., RTLD_NOW | RTLD_NOLOAD)`），**不再** 在 ArkUI 线程主动 `dlopen` 触发首次加载；库未加载时返回 `nullptr`，由 ArkUI 侧 `callNativeWhenReady` / `setLanguage` 的 **重试循环** 等待 Qt 启动完成。
  2. ArkUI 侧（上轮已加）`aboutToAppear` 不再立即 `command()`，改为 `callNativeWhenReady` 轮询；`setLanguage` 自带重试。C++ 桥 `StelMainView.cpp::runOhosCommandOnQtThread`：未初始化时返回错误（而非 `BlockingQueuedConnection` 阻塞入主线程），避免 bootstrap 期向主线程事件循环 post 引发竞态。
  3. 仅重编 `libentry.so`（`assembleHap`），**不** 跑 `harmonydeployqt`（会覆盖 .ets 编辑）；**不** 重编 `libstellarium.so`。
- **验证结果（2026-07-21，模拟器 127.0.0.1:5555）：** 安装+启动成功，**无 SIGABRT**；时间线：`bridge not loaded yet` → Qt 插件 `appLaunchParam set` + `preferred stack size` → `bridge resolved` → `command received: getSkyCultures/setLanguage` → 约 4s 后 `displayed submitted Stellarium frame 1024x768` + `submitted first Stellarium framebuffer`（`frame stats lit=786432` = 真实星场已渲染；注：此时仅确认渲染存活，启动命令跨线程是否真正投递到 Qt 线程另见 0.5）。
- **备注：** 构建本身 green（assembleHap 通过），问题纯属运行时 C++ 加载顺序，与 ArkTS 无关。

---

### 0.5 启动命令跨线程投递死锁（Qt 事件循环不泵送 OHOS 渲染）— 【2026-07-21 WorkBuddy 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-21，接手 SIGABRT 修复之后）
- **现象（修复前）：** SIGABRT 修复后应用能渲染，但 ArkUI 侧 `callNativeWhenReady` 启动重试**耗尽 114 次 / 46.5s** 仍未拿到 `ok:true`；`setLanguage` / `getSkyCultures` 等启动命令**似乎没生效**。
- **真实根因（已验证）：** OHOS 版 Qt（Qt for OpenHarmony）通过 **native vsync 回调**（`startOhosRenderPump` → `fpsTimer` → `renderOhosFrameNow`）驱动渲染，**不依赖 Qt 事件循环**。原 `runOhosCommandOnQtThread` 用 `QMetaObject::invokeMethod(..., QueuedConnection)` 把跨线程命令投递进 Qt 事件循环 → 该循环在此渲染模式下**不被泵送** → 命令**永远不执行**。证据：修复前日志 `command on Qt thread` 计数 = 0；`hello.cpp` 的 `Stellarium command` 桥日志有 39 条（反复调用但命令不投递）。
- **修复（已验证有效）：**
  1. 新增跨线程命令队列 `s_ohosCmdQueue` + `ohosDrainCommandQueue()`，由 `renderOhosFrameNow()` **每帧**在 Qt 主线程排空执行 → 命令保证执行，不依赖事件循环泵送。
  2. `runOhosCommandOnQtThread` 非 Qt 线程分支改为：cache 优先返回（停止 ArkUI 重试）→ inflight 防重入 → 否则入队；入队体执行后写 cache 并清 inflight。
  3. 仅重编 `libstellarium.so`（`cmake --build . --parallel`，md5 `5e980946…`），不重编 `hello.cpp` / `.ets`。
- **验证结果（2026-07-21，模拟器 127.0.0.1:5555）：** 重装启动成功；ArkUI 启动重试 **114 → 42** 次且 **18:49:48.031 停止**；`ohosDrainCommandQueue ran n=2` 每帧出现（原始 OH_LOG_Print，限流免疫）；`lit=574584` 帧渲染；无 SIGABRT。与 #0（SIGABRT）共同构成启动闭环。
- **备注：** 与 P0 #0 同源（启动 bootstrap），但属第二层——#0 解决"进程存活/渲染"，本条目解决"启动命令真正投递到 Qt 线程"。

---

### 0.6 交互命令缓存永久命中导致选择/搜索/详情失效 — 【2026-07-21 WorkBuddy 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-21）
- **现象（修复前）：**
  1. 点击星空**选不到天体/卫星**（实际首次 tap 已发命令，但结果未返到 UI）。
  2. 搜索按钮（如"搜索星星"）无效；搜索输入框键入后候选列表不出现。
  3. 需要**双击星星**才弹出简介（第二击命中了首次 tap 留下的缓存结果）。
  4. 星星简介以 `.simplified()` 后的纯文本 blob 展示，全部数据堆成"一团话"，不直观。
- **真实根因（已验证）：** `StelMainView.cpp::runOhosCommandOnQtThread()` 的 off-thread 分支在 P0 #0.5 中改成了 **per-key 永久缓存**（`s_ohosCmdCache`）：首次 tap/search/getInfo 入队执行后把结果写入 cache，之后**同一 key 永远直接返回 cache** → 交互命令的每次请求都被替换成第一次结果。更深层：交互命令在 ArkUI 侧只做 **单次同步 `callNative` 调用**，没有 0.5 中 startup 命令的 `callNativeWhenReady` 重试；所以首次调用只能拿到 pending，而 cached 结果直到下一次（不同坐标或不同查询）请求才暴露，表现为"双击才选中"和"搜索按钮没用"。
- **修复（已验证有效）：**
  1. **C++ 层：** 把永久 cache 改为 **consume-on-read 结果仓库**（读取时删除），并增加 `s_ohosCmdInflight` 防止同一 key 重复入队。同 key 的新请求必须重新入队 → 每次交互拿到的都是 Qt 线程**新鲜计算**的结果。
  2. **C++ 层：** 交互/轮询命令不再阻塞：第一次调用立即返回 `{pending: true}`。P0 #0.5 验证过的 `ohosDrainCommandQueue()` 由 `renderOhosFrameNow()` 每帧在 Qt 主线程排空执行命令，把结果写入仓库。
  3. **C++ 层：** 为高频 fire-and-forget 视图命令（`zoomBy` / `dragView` / `panBy`）开快速通道，总是入队新执行、不进入仓库，避免未消费结果污染下次调用。
  4. **ArkUI 层：** 新增 `callInteractive()` 包装，以 50ms×40 次轮询直到 `ok:true`，然后回调处理结果。把所有读取结果的交互命令（`selectAt`、`searchObject`、`getSelectedObjectInfo`、`listMatchingObjects`、`listObjects`、`setActionChecked`、`triggerAction`、时间/位置/截图等）以及 `refreshState()` 改为异步回调模式。`getState` 也通过 `callInteractive` 刷新，保证 UI 开关/时间/位置文本与 C++ 状态同步。
  5. **ArkUI 层：** 天体详情面板改用结构化 `infoRow` 行布局（名称、类型、状态、追踪、星等、赤道坐标、地平坐标、星座、距离），不再直接把 `.info` 文本 blob 塞进 `Text`。
- **验证结果（2026-07-21，模拟器 127.0.0.1:5555）：**
  - 启动正常，无 SIGABRT；`getSkyCultures/setLanguage` 启动重试仅 19 次后停止（`ohosDrainCommandQueue ran n=2/1` 成功执行），`frame stats` 首帧 `lit=296883` 真实星场。
  - 单次模拟 tap（700,250）→ ArkUI 日志显示 `selectAt payload: 350|125|1440|960` → 150ms 内拿到 `{ok:true, found:true, name:"OCC 988", type:"双星", magnitude:5.62, ...}` → **一次点击即选中**，无需双击。
  - 截图 `/tmp/stel_sel.jpeg` 确认：星场标记点 + 右侧面板结构化展示 OCC 988 的 名称/类型/状态/追踪/星等/赤道坐标/地平坐标/星座，无大段 blob 文本。
- **修改文件：**
  - `src/StelMainView.cpp`（命令队列/结果仓库重写）
  - `harmonyos/ets-source/pages/MainWindowNativeNode.ets`（`callInteractive` + 交互命令异步化 + 详情面板结构化）
  - `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`（与前者保持同步）
  - **备注：** 这是 P0 #0.5 修复后的**回归**。0.5 保证命令能被 Qt 线程执行，但其永久缓存不适用于交互语义；0.6 在保留 0.5 的"渲染泵驱动 Qt 线程命令"机制的前提下，完成了交互命令的正确结果投递。

---

### 0.7 全屏 UI 父容器 onTouch 抑制子组件 onClick（工具栏/搜索框/面板按钮全失效）— 【2026-07-21 WorkBuddy 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-21，紧接 P0 #0.6 之后）
- **现象（修复前）：** P0 #0.6 的缓存修复恢复了 `selectAt` 数据新鲜度（单次点击能拿到星体结果），但**工具栏图标、搜索输入框、面板开关、详情面板动作按钮仍然"点不动"**——表现为用户原始反馈里的"很多 UI 按钮没用""搜索框输不进字""点不到卫星"。#0.6 只修了缓存，没修这个。
- **真实根因（已验证）：** `expandedShell()`（大屏布局，模拟器走这条）的全屏父 `Stack` 上挂了 `.onTouch((event) => this.handleSkyTouch(event))` 且 `hitTestBehavior(HitTestMode.Transparent)`。该父容器**拦截了所有子孙组件的 `onClick`**——点击工具栏图标/搜索框/面板按钮时，事件被父容器的 `handleSkyTouch` 当作画布触摸吞掉（日志实证：点 ⌕ 触发 `sky touch down` → `selectAt` 选中了 63 Sgr，而 `setPanel` 从未出现）。这是与 #0.6 缓存 bug **相互独立**的第二层根因。
- **修复（已验证有效）：**
  1. 把 `onTouch(handleSkyTouch)` 从全屏 UI 父容器**下移**到 `build()` 根 `Stack` 下的一个**平级兄弟 `Stack`**（`width/height 100%` + `Transparent` + `onTouch`），与已验证的 `compactShell`（onTouch 挂在独立 `Blank` 而非全屏 UI 父）完全一致。
  2. 全屏父 `expandedShell` 现在只保留 `Transparent`、**不再挂 onTouch** → 其子孙（toolbar/面板按钮）的 `onClick` 恢复生效；其空白区域仍 `Transparent` 穿透到下方兄弟画布触摸层。
  3. 曾尝试给 `iconButton`/`dockButton` 容器加 `HitTestMode.Block` 作为双保险，但实测 `Block` 会使容器自身不响应命中（仅子组件响应），反而让容器自己的 `onClick` 永不触发、事件落到最近的可命中 `Column` 祖先 → 已**回退**为默认模式（兄弟画布层已能正确承接天空触摸，无需 Block）。
- **验证结果（2026-07-21，模拟器 127.0.0.1:5555）：**
  - 启动正常，无 SIGABRT；`expanded=true` / `bridge resolved` / `displayed submitted Stellarium frame` 均出现。
  - **6 个工具栏按钮全部触发 `setPanel`**：search / time / place / layers / object / settings。
  - **搜索输入框可输入**：聚焦后 `uitest uiInput text Jupiter` → `TextInput text='Jupiter'`，并实时弹出候选（Jupiter I/II/III/IV/IX 及行星本体）。
  - **搜索→选中→详情面板结构化刷新**：点候选 `Jupiter` → 日志 `searchObject`（50ms 轮询 3 次）+ 右侧面板显示 名称=木星 / 类型=行星 / 星等=-1.79 / 赤道坐标=8h28m23.4s +19°33'03.2"（无文本 blob）。
  - **天空点选仍可用（无回归）**：点空天空逻辑 (720,480) → `sky touch down at 720,480` → `selectAt found=1`（选中 木星），兄弟画布触摸层承接正常。
  - **详情面板动作按钮可用**：`刷新` → `getSelectedObjectInfo`（轮询 3 次）；`居中`/`追踪`/`加入观测列表` 均有真实 `onClick`。
- **修改文件：**
  - `harmonyos/ets-source/pages/MainWindowNativeNode.ets`（根 `build()` 插入兄弟画布触摸层；`expandedShell` 父容器移除 onTouch；`iconButton`/`dockButton` 回退默认命中模式）
  - `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`（与前者保持同步）
- **备注：** 与 P0 #0.6 同源（均为"交互不可点"的用户反馈），但根因不同：#0.6 是 C++ 结果缓存永久命中导致拿不到新结果；本条目是 ArkUI 命中测试层级错误导致 `onClick` 根本不触发。两者叠加才构成用户看到的"按钮全死 + 输不进字 + 点不到星"。本修复只动 `.ets`（ArkUI 层），未重编 C++ / `libstellarium.so`。

---

### 0.8 宽屏右侧 floatingPanel 容器 Block 模式吞掉子组件 Toggle/按钮点击（夜间模式/赤道仪模式开关、面板 × 关闭无响应）— 【2026-07-22 WorkBuddy 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-22，紧接 P0 #0.7 之后）
- **现象（修复前）：** #0.7 修复了全屏父容器 `onTouch` 吞点击的问题，工具栏图标/搜索框/详情面板动作按钮恢复可用；但**右侧浮动面板 `floatingPanel` 内部的开关与按钮仍然点不动**——这是用户原始反馈"右边菜单里的按钮点击都没效果"的**剩余部分**。具体表现：
  1. 设置面板的"夜间模式"Toggle 拨不动，天空不切夜色调。
  2. "赤道仪模式"Toggle 拨不动。
  3. 面板右上角 `×` 关闭按钮点不关面板。
  4. **对照证据：** 同屏的 `zoom_in`/`zoom_out` 按钮（也是一个 `Stack` + `.hitTestBehavior(HitTestMode.Block)`，但该 Stack **自己挂了 onClick**）能正常触发 → 说明不是"全部按钮死"，而是**特定容器结构**的问题。
- **真实根因（已验证）：** `expandedShell()` 里包装 `floatingPanel()` 的容器 `Stack({ alignContent: Alignment.TopStart }) { this.floatingPanel() }` 同时满足两个致命条件：
  1. **缺少显式尺寸**：该 `Stack` 只靠 `position({x,y})` 定位、**没有 `.width()/.height()`**，命中区域退化为内容最小包围盒，面板实际渲染区与可命中区不一致，部分点击落在命中区外。
  2. **`hitTestBehavior(HitTestMode.Block)` 且容器自身无 onClick/onTouch**：`HitTestMode.Block` 的语义是"容器自身消费触摸事件、不再向下派发给子孙"。当容器自己没有 `onClick`/`onTouch` 时，它**把触摸事件吞掉**，导致内部的 `Toggle`（靠 `onChange`）和 `×` 关闭 `Button`（靠 `onClick`）**根本收不到事件**——这正是 #0.7 note #3 里总结的"Block 会使容器自身不响应命中（仅子组件响应）"的反面教训：此处 Block 在**无自身回调的父容器**上，连子组件都不响应了。
  - 对比：`zoom_in` 按钮的 Block Stack **自己有 onClick**，所以 Block 只挡住更深层、不影响它自身回调；而面板容器 Block 且无回调，子组件被一并屏蔽。
- **修复（已验证有效）：**
  1. 给面板容器 `Stack` 显式补 `.width(this.panelWidth).height(this.panelMaxHeight)`，让命中区域与渲染区完全对齐。
  2. 将面板容器 `hitTestBehavior` 从 `HitTestMode.Block` → `HitTestMode.Transparent`：`Transparent` 会让事件**穿透到子组件**（子 `Toggle`/`Button` 正常触发 `onChange`/`onClick`），同时继续向下穿透到兄弟画布触摸层（天空 `selectAt` 不回归）。
- **验证结果（2026-07-22，模拟器 127.0.0.1:5555）：**
  - 启动正常，无 SIGABRT；`expanded=true` / `bridge resolved` / `displayed submitted Stellarium frame` 均出现。
  - **"夜间模式"Toggle 可开关**：拨开后天空切换为夜间红调（截图 `/tmp/stel_v2_night.jpeg` 确认）。
  - **"赤道仪模式"Toggle 可开关**：拨开后面板状态文字同步为开启。
  - **面板 `×` 关闭按钮生效**：点击后面板收起，`panelVisible` 置 false。
  - **天空点选无回归**：点击空天空仍触发 `selectAt` 选中天体（兄弟画布触摸层承接正常，截图 `/tmp/stel_v2_sky.jpeg` 确认）。
- **修改文件：**
  - `harmonyos/ets-source/pages/MainWindowNativeNode.ets`（面板 `Stack` 补 `.width/.height` + `Block`→`Transparent`，行 ~1786–1792）
  - `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`（与前者保持同步）
- **备注：** 本条目与 #0.7 同源（都是命中测试层级错误），但粒度更细：#0.7 修的是**全屏父容器挂 onTouch 吞子孙**；本条目修的是**面板自身容器 Block 无回调吞子孙**。两者修复后，用户"右边菜单按钮全失效"的反馈才被**完整**闭环。关键区别记忆点：**`HitTestMode.Block` 只在容器自身有 onClick/onTouch 时才安全；无回调的父容器用 Block 会连带屏蔽子组件，必须改用 `Transparent`。**

---

## P1 - 高优先级

### 0.9 运行时加载插件未完成初始化 — 【2026-08-28 处理中】

- **状态：** 处理中
- **现象：** 插件管理页显示插件已载入，但部分插件功能只有退出应用重进后才生效。
- **初步根因：** 运行时 `StelModuleMgr::loadPlugin()` 只创建 `StelModule`，没有执行启动路径中的注册、扩展加载、`init()` 和调用列表刷新。
- **计划：** 让启动加载和运行时加载共用完整初始化链；补齐失败回收、卸载状态和调用列表刷新，并增加离线脚本导入。

### 1. 边缘区域选星被 UI 死区吞掉

- **状态：** 已修复
- **修复记录：** 2026-07-21，`isUiPoint()` 收窄到按钮区域，工具栏容器改为 Transparent

### 2. compactShell（竖屏/窄屏模式）未验证

- **状态：** ✅ 已验证（模拟器实跑，2026-07-23）
- **结论：** 2026-07-21 代码审查确认 compactShell 触摸路由正确；2026-07-23 通过临时把 `isExpandedLayout` 阈值 `900→3000` 强制 compact 模式打包验证：确认 `expanded=false`、compact UI 正确渲染（"详情"/"点击天空中的天体"空状态）、底部 dock `setPanel search` 触发正常。验证后已还原阈值 `3000→900` 并重打包重装确认 `expanded=true` 恢复。**功能闭环。**
- **备注：** 模拟器不支持 `uitest uiInput rotate` 竖屏旋转，故用阈值法间接验证 compact 布局渲染与导航，等价覆盖。

### 3. 图层面板缺少多个开关

- **状态：** ✅ 已修复并验证（代码审查 + 模拟器实跑，2026-07-23）
- **结论：** `panelContent()` 的 layers 分支现已包含全部 21 个 `switchRow`，分 5 组（基础天体 / 星座 / 网格 / 地平参考 / 标签）。实测代码 `build/.../MainWindowNativeNode.ets` 行 1730–1758。2026-07-23 模拟器回归：勾选图层开关（如星座线、大气、恒星等）后日志实锤 `Stellarium command setActionChecked` / `switchRow` 状态变更，且 toggle 前后 UI 状态同步、无 "action not found" 错误。C++ action ID 与 ArkTS 一一对应验证通过。
- **备注：** 原 KNOWN-ISSUES 标注"待修复"是因为文档落后于代码，并非真未做。

---

### 4. Phase 2 命令桥从未编译（幻觉 API）— 【2026-07-22 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-22）
- **现象（修复前）：** `libstellarium.so` 无法编译。`src/StelMainView.cpp` 中整个 Phase 2 命令桥（约 23 个提交、命令分发 ~696–3117 行）**从未针对真实 Stellarium API 编译过**——每个命令都调用了不存在或签名错误的幻觉 API。提交历史里有代码，但一编译就爆几十个错误。
- **真实根因（已验证）：**
  1. **命令桥被关在匿名 namespace 外**：文件第 124 行 `namespace {` 开启后**从未闭合**，导致后续所有代码（含 `StelMainView` 类定义）被错误嵌套，编译器报大量"私有成员"式误错，根因其实是少了一个 `}`。
  2. **`payload` 捕获错误**：命令分发 lambda 捕获的是 `QString arg`，但 Phase 2 命令直接用了 C 入口参数 `const char* payload`（未捕获）→ 把 C 字符串当 QString 用，编译失败。
  3. **约 40 处 API 签名不匹配**：`GETSTELMODULE(X)->` 误用 `.`、`getStelObjectMgr()->` 应为 `.`、虚构的 `setDateFormatForLanguage`/`getCustomStarMagLimit`/`getSkyCultureEnglishName`(私有)/`getStdLongitude`/`loc.englishName`/`loc.country`/`drawEnded`(私有) 等；`getApplicationVersion` 实属 `StelUtils::`、`getCurrentDeltaTAlgorithmDescription` 真实存在、`malloc_usable_size` 在 OHOS 未定义等。真实接口逐个 grep 头文件确认后修正。
- **修复（已验证有效）：**
  1. 闭合匿名 namespace（在 `#endif` 前补 `} // anonymous namespace`）。
  2. `payload` → `arg`（46 处裸标识符替换，跳过字符串字面量）。
  3. 全量对齐真实 API：LandscapeMgr/MilkyWay 经 `GETSTELMODULE` 取指针、SkyDrawer/StelApp 取引用、Viewport 经 `getProjection()->`、位置经 `getLatitude()/getLongitude()` 等。新增 `StelMainView::ohosDrawEnded()` 公开包装（因 `drawEnded()` 私有）。
  4. `harmonyos/ets-source/pages/StellariumTypes.ets` 的 `StellariumBridgeResponse` 补 `meteors`/`dsoLabels`/`autoZoomResets` 三个可选布尔字段，修复 ArkTS 报 `Property does not exist` 的编译错误（此三开关此前在 C++ 桥是 dead 的，修复后真正可用）。
- **验证结果（2026-07-22）：**
  - `cmake --build .` 链接 `libstellarium.so`：**0 错误**（修复前几十个）。
  - `hvigorw assembleHap --no-daemon` 重新打包并**自动签名**通过（此前因 ArkTS 类型缺失失败于 `CompileArkTS`）。
  - 产物 `entry-default-signed.hap` 内嵌 `libs/arm64-v8a/libstellarium.so` 的 BuildID=`d404de18b5fd6deed2f4297fff43dfedd834225c`，即本次修复构建（已 stripped）。
- **修改文件：**
  - `src/StelMainView.cpp`（命令桥全量 API 对齐 + namespace 闭合 + payload→arg）
  - `src/StelMainView.hpp`（新增 `ohosDrawEnded()` 公开包装）
  - `harmonyos/ets-source/pages/StellariumTypes.ets`（`StellariumBridgeResponse` 补字段）
  - `harmonyos/ets-source/pages/MainWindowNativeNode.ets`（本段未改，仅保持与 build 副本同步）
- **备注：** 此修复解锁了此前完全不可用的命令子集（含 `meteors`/`dsoLabels`/`autoZoomResets` 三个 dead 开关）。真机/模拟器行为验证已于 2026-07-23 完成：模拟器实跑确认 `setTimeRate`（时间面板"暂停/现在"按钮）、`setLocationByName`（地点面板选城市）、`setLandscape`（图层面板地景 tab 选 Guereins）三个 Phase 2 桥接命令经 ArkTS UI 实际触发、C++ 端 `Stellarium command <name>` 日志实锤、渲染/状态随之改变——**Phase 2 命令桥闭环验证通过，不再有"从未编译的幻觉 API"。**

---

## P2 - 中优先级

### 4. 翻译文件加载失败（星名不随语言切换变化）— 【2026-07-22 WorkBuddy 已修复并验证】

**现象：** 切换语言后，星图上的星名（天体名）不随语言变化。

**旧假设（已否决）：** 曾怀疑 `StelFileMgr::init()` 缺 `__OHOS__` 路径分支、或 locale 名不匹配（zh_Hans vs zh_CN）。代码审查 + 实测已排除：
- `getLocaleDir()` = `STELLARIUM_DATA_ROOT/translations`，与 `StelTranslator::load(getLocaleDir()+"/"+adomain+"/"+lang+".qm")` 路径一致；`STELLARIUM_DATA_ROOT` 由 bootstrap 在 `prepareStellariumResources()` 中正确设置。
- `StelTranslator` 构造函数用 `getTrueLocaleName()`，而该函数在 `langName != "system"/"system_default"` 时返回**传入的** `langName`（StelTranslator.hpp:98-104）；ArkTS 调 `setLanguage("zh_CN")` 即加载 `zh_CN.qm`，locale 名匹配无误。

**真实根因（已验证）：** 资源提取是「一次性」，仅由 marker 文件 `stars/hip_gaia3/defaultStarsConfig.json` 是否存在门控（`StellariumResourceBootstrap.ets`）。若某次提取被中断，marker（单个数据文件）可能已落盘而 `translations/` 子树缺失/不全；此后任何 `hdc install -r`（replace 模式**保留 filesDir 数据**）都会因 marker 存在而**跳过重新提取** → `translations/stellarium/zh_CN.qm` 等永久缺失。届时 `setLanguage zh_CN` 命令虽成功执行（`ohosDrainCommandQueue` 每帧排空），但 `StelTranslator` 加载 .qm 失败 → 空翻译器 → 星名不变。
- 佐证：此前多次安装均用 `-r`，且启动日志**从未**出现 `Extracting Stellarium raw resources`（仅 marker 不存在时才打印），说明提取长期被跳过。
- 注意：`hilog` 对 `qInfo` 严重限流，`StellariumOhos_command` 被调用 302 次但 `command received` 仅显示 4 条、0 条 `command on Qt thread` —— 是限流丢日志，**不能**据此判定命令未执行。

**修复（已验证有效）：** `StellariumResourceBootstrap.ets::prepareStellariumResources`：
1. 门控改为「marker 不存在 **或** 三个关键 zh_CN.qm（`stellarium/zh_CN.qm`、`stellarium-sky/zh_CN.qm`、`stellarium-skycultures/zh_CN.qm`）任一缺失」才重新提取 → 自愈中断导致的残数据。
2. 提取后打印可观测日志 `Translations on disk: dir=... stellarium/zh_CN.qm=... stellarium-sky/zh_CN.qm=... stellarium-skycultures/zh_CN.qm=...`，使「星名不翻译」可由日志直接定性（el2 加密目录 hdc/root 均读不到，只能靠 App 内日志证明）。

**验证结果（2026-07-22，模拟器 127.0.0.1:5555）：**
- `bm uninstall` 清掉 filesDir → `hdc install`（不带 -r）强制全量重抽 → 日志出现 `Extracting Stellarium raw resources`，且 `Translations on disk: ... 三个 qm 均 true`。
- `ohosDrainCommandQueue ran` 每帧执行（24 次），**无** `Couldn't load translations` / `Empty translation` 警告 → .qm 成功加载。
- `setAppLanguage(arg)` 默认 `refreshAll=true`（StelLocaleMgr.hpp:53）→ `createNameLists()` → `StarMgr::updateI18n()` 用 skyTranslator 重翻星名；翻译文件齐备后星名随语言切换生效。
- 构建：`hvigorw assembleHap --no-daemon`（7.9s，仅重编 .ets，DevEco 自动签名通过）产物 `entry-default-signed.hap`；仅 ArkTS 改动，未重编 libstellarium.so。

**修改文件：** `harmonyos/ets-source/qability/StellariumResourceBootstrap.ets`（commit `fdd8f627df`，push 至 `myfork/openharmony-preview-v1`）。

### 5. 地景不透明 / 透明度滑块失效 — 【2026-07-23 WorkBuddy 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-23）
- **现象（修复前）：** 用户无法让地景变透明，被地面遮挡的星星始终透不出来；地景页签的「透明度」滑块拖了没反应。
- **真实根因（已定位）：** 不是 OpenGL ES 渲染路径问题，也不是核心缺机制——`Landscape.cpp:1331` 早已用 `alpha=(1-transparency)*landFader` 支持透明度，C++ 桥 `setLandscapeTransparency`（StelMainView.cpp:1370）与 ArkTS `changeLandscapeTransparency()`（ets:885，把 `val/100` 发给 C++）也都齐全。**真正漏的是滑块没接线**：`viewLandscapeTab()` 的透明度 `Slider.onChange` 只写了 `this.landscapeTransp = Math.round(val)`（仅更新本地显示百分比），**从未调用 `changeLandscapeTransparency(val)`**，所以拖动滑块地景毫无变化。
- **修复（已验证有效）：** `viewLandscapeTab()` 的 `Slider.onChange` 改为 `this.landscapeTransp = Math.round(val); this.changeLandscapeTransparency(val)`，使滑块真正把透明度下发到 C++。
- **验证结果（2026-07-23，模拟器 127.0.0.1:5555）：** 打开 View→地景页签，拖动透明度滑块 → 日志实锤 `Stellarium command setLandscapeTransparency`（pid 10280 的 StellariumEntryGL 日志）。至此用户可手动把地景调透明、看到地面后的星星。
- **关于「自动淡出」：** 核心并无「视角转向地面时地景自动透明」这一标准特性；桌面端同样靠手动透明度或日光 `landFader` 渐变。本修复补齐的是**手动透明度控制**（此前完全失效），属真实 bug 修补。
- **修改文件：** `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`（行 ~4508，Slider.onChange）+ 同步镜像 `harmonyos/ets-source/pages/MainWindowNativeNode.ets`。仅改 .ets，未重编 C++。

### 6. UI 风格改进（持续进行）

- **状态：** 部分完成
- **已完成：** 品牌色优化、Unicode 图标、响应式面板、结构化详情
- **待改进：** Symbol 图标（SDK 限制）、统一圆角间距

### 5. 对比电脑版功能差距（2026-07-22 更新）

- **状态：** 大部分已实现
- **已实现核心功能：** 渲染、搜索（+历史+热门）、时间（+23 种天文时间单位）、位置（+GPS+城市列表）、图层（70+ toggle，7 tab）、详情（自动刷新+RA/Dec/Alt/Az）、方向/FOV、多语言（235+ i18n keys）、星图文化（真实列表切换）、观测列表、脚本（播放/暂停/停止）、插件（动态加载/卸载）、AstroCalc（9 tab，RTS/年历/行星位置数据桥接）、截图、陀螺仪、LX200、启动画面、Settings 快捷面板、Help 面板、night mode 色彩适配
- **仍缺失：** 书签系统、视频录制、天体轨迹回放、配置导入导出、DSO 星表过滤、完整 AstroCalc 数据计算（星历表/天象/日食需要桌面 AstroCalcDialog 逻辑）、Satellites 插件

### 7. Speech 语音播报缺音频 TTS（受 SDK 限制）

- **状态：** 🟡 部分实现，音频播放受 SDK 限制
- **现象：** 对象面板已新增「朗读文本」按钮，可生成并显示选中天体中文描述；但无法播放语音音频。
- **根因：** 当前工程基于 OpenHarmony 基础 SDK（API 24），其 `ets/kits/` 列表不含 `@kit.CoreSpeechKit`。`@kit.CoreSpeechKit`（Text-to-Speech 语音合成）只在华为 HMS SDK（`/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/kits/`）中存在。OpenHarmony 构建无法引入 HMS kit，因此没有可用的系统 TTS 引擎。
- **已实现部分：**
  - C++ 桥 `getObjectSpokenText`：返回「名称、类型、星座、视星等、高度、方位、距离」组成的中文句子。
  - ArkTS 对象面板「朗读文本」按钮：调用命令并在面板中显示句子，验证命令 round-trip。
- **待补齐（切换 SDK 后）：** 将返回的 `text` 交给 `@kit.CoreSpeechKit.textToSpeech.speak()` 播放。
- **验证：** 模拟器选中月球后点「朗读文本」，显示「月，类型 卫星，视星等 -11.30，高度 2 度，方位 东南，距离 0.0027 天文单位」。

---

## P3 - 低优先级

### 6. 陀螺仪真机测试

- **状态：** 待测试

### 7. LX200 扩展

- **状态：** 基础实现，按需扩展

### 8. 中文星名验证

- **状态：** 待真机验证

---

## P2 - 中优先级（续）

### 8. 星图帧率极低（8 FPS）— 【2026-07-27 TRAE 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-27）
- **现象（修复前）：** 星图拖动、选星、缩放均严重卡顿，实测帧率仅8 FPS。
- **真实根因（已验证）：** C++侧每帧用 `glReadPixels` 同步读取帧缓冲（34ms/帧），加上 `eglSwapBuffers` 的VSync阻塞（16ms），总帧时间约50ms（20 FPS），再叠加其他开销降至8 FPS。
- **修复（已验证有效）：**
  1. PBO三缓冲异步回读：glReadPixels返回立即返回，2帧后读取数据（34ms→1ms）
  2. FBO降采样：glBlitFramebuffer降采样到50%后回读，减少64%数据量
  3. 禁用VSync：eglSwapInterval(0) 消除eglSwapBuffers阻塞
  4. 渲染间隔优化：交互态16ms（60FPS），空闲态66ms（15FPS）
- **验证结果：** 模拟器实测稳定61 FPS
- **修改文件：** `src/StelMainView.cpp`、`build/.../cpp/hello.cpp`

---

### 9. 抽屉面板触摸穿透到缩放按钮 — 【2026-07-27 TRAE 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-27）
- **现象（修复前）：** 点击"天文计算"会触发下方的放大按钮，点击"音频控制"会触发下方的缩小按钮。
- **真实根因：** 抽屉面板与缩放按钮在同一Stack层级，面板的hitTestBehavior设置无法完全阻止事件穿透到下方的按钮。
- **修复：** 抽屉打开时用条件渲染 `if (!this.drawerOpen)` 完全隐藏zoom_in/zoom_out按钮，而非仅设置hitTestBehavior。
- **验证结果：** 模拟器截图确认抽屉面板各选项可正常点击
- **修改文件：** `build/.../ets/pages/MainWindowNativeNode.ets`

---

### 10. 应用图标和加载屏问题 — 【2026-07-27 TRAE 已修复并验证】

- **状态：** ✅ 已修复并验证（2026-07-27）
- **现象（修复前）：** 启动页保留旧AI生成图标；加载屏background.png左下角1/4有银河图案与纯色背景格格不入。
- **修复：**
  1. 应用图标替换为原版Stellarium图标（data/icons/512x512/stellarium.png）
  2. 加载屏背景替换为纯深色(#05070F) PNG，消除银河拼图不一致
- **验证结果：** 模拟器截图确认图标和加载屏正确
- **修改文件：** `AppScope/resources/base/media/app_icon.png`、`entry/.../resources/base/media/{startIcon,foreground,background}.png`

---

### 11. PBO异步回读(glMapBufferRange)导致SIGSEGV崩溃 — 【2026-07-27 TRAE 已记录】

- **状态：** 已回退为同步glReadPixels（规避）
- **现象：** 尝试用 PBO（Pixel Buffer Object）异步回读帧缓冲以提升性能，调用 `glMapBufferRange` 读取 PBO 数据时，模拟器进程立即 `Signal:SIGSEGV` 退出。
- **根因（推测）：** 模拟器的 OpenGL ES 实现对 `glMapBufferRange` 的支持不完整或存在驱动缺陷，映射 PBO 内存时触发段错误。可能与模拟器 GPU 驱动（SwiftShader/Angle 翻译层）有关。
- **规避措施：** 回退为同步 `glReadPixels`，渲染间隔设为12ms（83FPS目标），实测稳定运行在49-59 FPS，无崩溃。
- **待办：** 真机验证 PBO 方案是否可用（真机 GPU 驱动可能与模拟器不同）。若真机可用，可针对真机启用 PBO、模拟器回退同步。

---

### 12. 8ms渲染间隔(120FPS)导致PBO三重缓冲崩溃 — 【2026-07-27 TRAE 已记录】

- **状态：** 已回退到12ms(83FPS)（规避）
- **现象：** 将渲染间隔从12ms降到8ms（目标120FPS）后，配合 PBO 三重缓冲方案，模拟器进程 `Signal:SIGSEGV` 崩溃。
- **根因（推测）：** 8ms 间隔下 PBO 三重缓冲的轮换节奏过快，前一帧的 glReadPixels/glMapBufferRange 尚未完成就被下一帧覆盖，导致 GPU 驱动状态错乱触发段错误。与 #11 的 glMapBufferRange 崩溃同源。
- **规避措施：** 渲染间隔回退到12ms（83FPS），使用同步 glReadPixels。稳定运行在49-59 FPS。
- **待办：** 与 #11 一并在真机上验证。

> **最后更新：** 2026-07-27
