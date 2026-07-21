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

## P1 - 高优先级

### 1. 边缘区域选星被 UI 死区吞掉

- **状态：** 已修复
- **修复记录：** 2026-07-21，`isUiPoint()` 收窄到按钮区域，工具栏容器改为 Transparent

### 2. compactShell（竖屏/窄屏模式）未验证

- **状态：** 已验证（代码审查通过）
- **结论：** 2026-07-21 代码审查确认 compactShell 触摸路由正确
- **待办：** 仍需在模拟器/真机上实际运行验证

### 3. 图层面板缺少多个开关

- **状态：** 已修复（2026-07-21 代码审查确认，文档此前未同步）
- **结论：** `panelContent()` 的 layers 分支现已包含全部 21 个 `switchRow`，分 5 组（基础天体 / 星座 / 网格 / 地平参考 / 标签）。实测代码 `build/.../MainWindowNativeNode.ets` 行 1730–1758。
- **待验证：** 仍需在模拟器/真机上确认每个开关的 `setActionChecked` 实际生效（C++ action ID 是否一一对应，例如 `actionShow_Constellation_Art` 等）。
- **备注：** 原 KNOWN-ISSUES 标注"待修复"是因为文档落后于代码，并非真未做。

---

## P2 - 中优先级

### 4. UI 风格改进（持续进行）

- **状态：** 部分完成
- **已完成：** 品牌色优化、Unicode 图标、响应式面板、结构化详情
- **待改进：** Symbol 图标（SDK 限制）、统一圆角间距

### 5. 对比电脑版功能差距

- **状态：** 已梳理
- **已实现核心功能：** 渲染、搜索、时间、位置、图层(部分)、详情、方向/FOV、多语言、星图文化、观测列表、截图、陀螺仪、LX200、启动画面
- **缺失功能：** 完整图层面板、书签、脚本、插件、卫星追踪、日历事件、视频录制、天体轨迹、配置导入导出

---

## P3 - 低优先级

### 6. 陀螺仪真机测试

- **状态：** 待测试

### 7. LX200 扩展

- **状态：** 基础实现，按需扩展

### 8. 中文星名验证

- **状态：** 待真机验证

---

> **最后更新：** 2026-07-21
