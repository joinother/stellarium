# 修改日志

> 格式说明：每次修改追加一条记录。新 Agent 接手时先读这个文件。

---



## [2026-07-21] WorkBuddy - 修复交互命令 stale-cache 回归（单次点击选中 + 搜索框 + 结构化详情）

- **修改文件：**
  - `src/StelMainView.cpp`（`runOhosCommandOnQtThread` off-thread 分支重写；`s_ohosCmdCache` 改为 consume-on-read 结果仓库 + `s_ohosCmdInflight` 防重入；`zoomBy`/`dragView`/`panBy` fire-and-forget 快速通道）
  - `harmonyos/ets-source/pages/MainWindowNativeNode.ets`（新增 `callInteractive()`；把 `selectAt`/`searchObject`/`getSelectedObjectInfo`/`listMatchingObjects`/`listObjects`/动作/时间/位置/截图/刷新状态等全部改为非阻塞回调；天体详情面板结构化行布局）
  - `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`（与 `harmonyos/ets-source/...` 保持同步）
- **修改内容：**
  1. C++ 命令桥改为**非阻塞**：off-thread 调用立即返回 `{pending: true}`，命令由 `renderOhosFrameNow()` → `ohosDrainCommandQueue()` 在 Qt 主线程每帧执行，结果写入 consume-on-read 仓库；下次同一 key 请求必须重新入队 → 交互命令永远拿到**新鲜结果**。
  2. 废除 0.5 引入的 permanent key cache，消除"双击才选中""搜索按钮无效"的根因。
  3. 高频 fire-and-forget 视图命令（`zoomBy`/`dragView`/`panBy`）绕过仓库直接入队，避免未消费结果污染下次调用。
  4. ArkUI 新增 `callInteractive()` 以 50ms×40 次轮询直到 `ok:true`；所有依赖返回值的命令改为回调处理，保证单 tap 即可更新 UI。
  5. 天体详情面板从单块 `Text(this.selectedInfo)` 改为 `infoRow` 行：名称、类型、状态、追踪、星等、赤道坐标、地平坐标、星座、距离。
- **修改原因（真实根因）：** P0 #0.5 的永久缓存对 startup 命令有效（`callNativeWhenReady` 会重试直到命中缓存），但交互命令只做单次 `callNative`，导致首次调用只能拿到 pending、结果永远留在缓存里被下一次不同请求触发 → 卫星/星星点不到、搜索不反应、需要双击、详情是一团话。
- **构建结果：** `cmake --build . --parallel` 重编 `libstellarium.so` 成功（md5 `2845a13c65942d9d2014c795da7df535`）；`assembleHap` BUILD SUCCESSFUL（275MB，已签名）；未跑 `harmonydeployqt`。
- **验证结果（2026-07-21，模拟器 127.0.0.1:5555）：**
  - 启动无 SIGABRT，启动命令重试仅 19 次后停止（`ohosDrainCommandQueue ran n=2/1`），首帧真实星场 `frame stats lit=296883`。
  - 单次模拟 tap（700,250）→ 150ms 内拿到 `selectAt` 结果：`OCC 988` / 双星 / 星等 5.62 / 高度 30.8° / 方位 152.5° / 星座 Sgr；**一次点击即选中**。
  - 截图 `/tmp/stel_sel.jpeg` 验证：星场选中标记 + 右侧面板结构化展示全部字段，无文本 blob。
- **备注：** 对应 KNOWN-ISSUES P0 #0.6（本轮新增）。本次修复证明：在 OHOS 渲染泵与 N-API 命令桥共享同一线程的前提下，**任何阻塞该线程的尝试都会让渲染泵与命令排空同时停滞**；必须保持非阻塞 + 异步结果投递。

---

## [2026-07-21] WorkBuddy - 修复启动命令跨线程投递死锁（渲染泵驱动的命令队列）

- **修改文件：** `src/StelMainView.cpp`（仅此一处；`libstellarium.so` 重编）
- **修改内容：**
  - 新增跨线程命令队列 `s_ohosCmdQueue`（`QList<std::function<void()>>`）+ 互斥锁 `s_ohosCmdQueueMutex`，以及 `ohosDrainCommandQueue()`：在 Qt 主线程、且 `StelApp` 已初始化时，取出并批量执行队列中的命令，执行后置 `markQtLoopRunning()`，并用 `OH_LOG_Print`（tag `StellariumCpp`）打印 `ohosDrainCommandQueue ran n=...` 作为"命令已在 Qt 线程执行"的原始证明（避免 qInfo 被 hilog 限流吞掉）。
  - `runOhosCommandOnQtThread()` 的**非 Qt 线程分支**重写为：先查 `s_ohosCmdCache`（命中→直接返回 `ok:true`，让 ArkUI 重试循环 `callNativeWhenReady` 停止）；再查 `s_ohosCmdInflight`（进行中→返回 `pending`，让 ArkUI 继续重试）；否则入队 `s_ohosCmdQueue`，入队体在 `command()` 执行后写入 cache 并清除 inflight。**不再**使用 `QMetaObject::invokeMethod(..., QueuedConnection)`（旧机制在 OHOS 渲染被抢占时不被泵送）。
  - 在 `renderOhosFrameNow()` 顶部插入 `ohosDrainCommandQueue();`，由 OHOS 渲染泵**每帧**在 Qt 主线程调用 → 命令保证被排空执行。
- **修改原因（真实根因）：** OHOS Qt for OpenHarmony 通过 **native vsync 回调**（`startOhosRenderPump` → `fpsTimer` → `renderOhosFrameNow`）驱动渲染，**不走 Qt 事件循环**。因此 `QMetaObject::invokeMethod(..., QueuedConnection)` 跨线程投递的调用**永远不会被泵送** → 启动命令（`getSkyCultures` / `setLanguage` 等）**从未在 Qt 线程执行**，ArkUI 侧 `callNativeWhenReady` 重试耗尽（实测 114 次 / 46.5s）后放弃，启动桥实质卡死。证据：修复前日志 `command on Qt thread` 计数 = 0，而 `hello.cpp` 的 `Stellarium command` 日志有 39 条（桥被反复调用但命令不投递）。
- **构建结果：** `cmake --build . --parallel` 增量重编仅 `StelMainView.cpp.o` + 重新链接 `libstellarium.so`（md5 `5e9809466b9fc91174b13506339f727e`，已同步到 3 个打包目录与 `build/src/`）；`assembleHap` BUILD SUCCESSFUL（5.9s，重编 libentry.so）。**未**跑 `harmonydeployqt`（会覆盖 .ets 编辑）。
- **验证结果：** ✅ 模拟器 127.0.0.1:5555，重装启动成功。对比修复前：ArkUI 启动重试 **114 → 42** 次，且**在 18:49:48.031 停止重试**（应用持续运行至 18:49:54 之后）；日志 `ohosDrainCommandQueue ran n=2` 每帧稳定出现 → 证明命令已在 Qt 主线程执行；帧渲染 `lit=574584`（真实星场）。**无 SIGABRT**（进程 pid 14936/15072）。两层启动修复现已**完全闭环并验证**。
- **备注：** 对应 KNOWN-ISSUES P0 #0.5（本轮新增）。`hello.cpp` / `MainWindowNativeNode.ets` 本轮**未改动**（上轮 SIGABRT 修复已就位）。

---

## [2026-07-21] WorkBuddy - 修复启动 SIGABRT（命令桥抢占式 dlopen libstellarium.so）

- **修改文件：** `build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp`, `harmonyos/cpp-source/hello.cpp`（两处同步）, `build/.../MainWindowNativeNode.ets`, `harmonyos/ets-source/pages/MainWindowNativeNode.ets`（ArkUI 重试上轮已加）
- **修改内容：**
  - `resolveStellariumCommand()` 改为 **只查已加载库**（`RTLD_NOW | RTLD_NOLOAD`），**不再** 在 ArkUI 线程主动 `dlopen` 首次加载 `libstellarium.so`。该库即 Qt 应用二进制（`deployment-settings.json` 的 `application-binary`），本应由 Qt-for-OHOS 插件在专用 Qt 主线程加载并启动 `main()`。
  - 库未加载时返回 `nullptr`，ArkUI 侧 `callNativeWhenReady` / `setLanguage` 重试循环等待 Qt 启动。
  - 保留 C++ 桥 `runOhosCommandOnQtThread` 的未初始化返回错误逻辑（不 `BlockingQueuedConnection`）。
- **修改原因：** `deployment-settings.json` 确认 `libstellarium.so` 即 Qt 应用二进制；ArkUI 线程抢占式 `dlopen` 破坏 Qt 插件的 `makeQtThreadWithMainFuncLauncher` 主线程上下文 → `Qt API was likely used before Qt initialization. Aborting.`
- **构建结果：** BUILD SUCCESSFUL（assembleHap 重编 libentry.so，3.5s；未跑 harmonydeployqt，未重编 libstellarium.so）
- **验证结果：** ✅ 模拟器 127.0.0.1:5555 安装+启动成功，**无 SIGABRT**；约 4s 后 `displayed submitted Stellarium frame 1024x768` + `submitted first Stellarium framebuffer`（lit=786432 真实星场）。根因已闭环。
- **备注：** 对应 KNOWN-ISSUES P0 #0 已修复。

---

## [2026-07-21] WorkBuddy - 接手验证：构建 + 模拟器启动，发现启动即崩溃

- **修改文件：** （仅文档）`docs/harmonyos/KNOWN-ISSUES.md`
- **修改内容：**
  - 修正 P1 #3 图层面板状态：代码已有全部 21 个 `switchRow`（`build/.../MainWindowNativeNode.ets` 行 1730–1758），标记"已修复（文档曾落后）"
  - 新增 P0 #0：应用启动即 SIGABRT（Qt 初始化顺序 / 线程错配）
- **修改原因：** 接手项目，按 AGENTS.md 接手检查清单执行；发现 KNOWN-ISSUES 文档落后于代码
- **构建结果：** BUILD SUCCESSFUL（assembleHap，全 UP-TO-DATE，1.6s）
- **验证结果：** 模拟器已连接（127.0.0.1:5555），安装+启动成功（`install bundle successfully` / `start ability successfully`），但**进程立即 SIGABRT**
- **关键发现：** 日志 `Qt API was likely used before Qt initialization` + `makeQtThreadWithMainFuncLauncher mainThread != currentThread` → 根因疑似 Qt/Stellarium 核心在 `QApplication`(StelApplication) 主线程初始化完成前，被非主线程（N-API 命令桥首调 / XComponent surface 回调）提前调用 Qt API
- **备注：** 此前所有 Agent 的 CHANGELOG 均标"模拟器未启动，待验证"，故该启动崩溃从未被发现。修复需改 C++ 并重的编 libstellarium.so。

---

## [2026-07-21] TRAE - 默认中文 + 多语言切换 + Unicode 工具栏图标

- **修改文件：** `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`, `harmonyos/ets-source/pages/MainWindowNativeNode.ets`
- **修改内容：**
  - aboutToAppear 中自动调用 setLanguage('zh_CN')，默认显示中文星名
  - 设置面板新增语言选择器（中文/繁中/English/日本語/한국어）
  - 语言选择持久化到 AppStorage，重启后恢复
  - 工具栏文字图标替换为 Unicode 符号（⌕◴◎▦ⓘ⚙），单色可控
  - 新增 scripts/check-ohos.sh 提交前检查脚本
- **修改原因：** project_memory 硬性要求星体名称中文显示 + 多语言切换
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：** 待安装验证
- **备注：** 翻译文件 .qm 已打包在 rawfile/stellarium/translations/ 中

---

## [2026-07-21] TRAE - 天体详情面板结构化展示（亮度/高度角/方位角/距离/星座/赤经/赤纬）

- **修改文件：** `src/StelMainView.cpp`, `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`, `harmonyos/ets-source/pages/MainWindowNativeNode.ets`
- **修改内容：**
  - C++ 侧重写 `selectedObjectJson()`，从 `object->getInfoMap(core)` 提取并标准化字段：
    - `vmag` → `magnitude` (视星等, number)
    - `altitude` / `azimuth` → 保持不变 (视高度角/方位角, 度数, number)
    - `ra` → 格式化为 HMS 字符串 (如 "12h 30m 15s")
    - `dec` → 格式化为 DMS 字符串 (如 "+45° 30' 20\"")
    - `iauConstellation` → `constellation` (IAU 星座缩写)
    - `distance` → 格式化为 AU 或 ly 字符串
  - 保留原有的 `info` 纯文本字段作为补充
  - ArkTS 侧新增 7 个 @State 变量 + 7 行 infoRow 结构化展示
  - `StellariumBridgeResponse` 接口新增 magnitude/azimuth/distance/constellation/ra/dec 字段
  - Qt OHOS 交叉编译重新编译 libstellarium.so
  - harmonydeployqt 重新部署 entry/libs/ (33 个 .so)
- **修改原因：** 之前详情面板只有纯文本 info 字段，用户无法快速查看关键天体参数
- **构建结果：** BUILD SUCCESSFUL（CMake + hvigor 均通过）
- **验证结果：** 模拟器未启动，待验证
- **备注：** 字段全部为可选，未选中天体或该天体无此字段时显示 '--'

---
## [2026-07-21] TRAE - 重新编译 libstellarium.so + C++ 头文件修复

- **修改文件：** `src/StelMainView.cpp`
- **修改内容：**
  - 添加 `#include <QJsonArray>` 和 `#include "StelLocaleMgr.hpp"` 修复编译错误
  - 使用 Qt OHOS 交叉编译工具链重新编译 libstellarium.so
  - 新的 .so 包含 listMatchingObjects/listObjects/setLanguage 命令桥
- **修改原因：** C++ 新增命令后缺少必要头文件，导致编译失败
- **构建结果：** BUILD SUCCESSFUL（CMake + hvigor 均通过）
- **验证结果：** 模拟器未启动，待验证分类搜索是否加载真实天体数据
- **备注：** .so 文件通过 harmonydeployqt 重新部署到 entry/libs/

## [2026-07-21] TRAE - 天体分类搜索 UI + 编译修复

- **修改文件：** `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`, `docs/harmonyos/harmonyos-project/ets-source/pages/MainWindowNativeNode.ets`, `src/StelMainView.cpp`
- **修改内容：**
  - 添加 CatOption/NameItem 接口，修复所有 ArkTS 类型错误（bracket notation → dot notation，object → 具体类型）
  - 修复 stopTracking() 方法体被误放到 loadCategoryObjects() 内部的结构错误
  - 在 StellariumBridgeResponse 接口添加 items/count/prefix/moduleId 属性
  - 移除 Row 上的 .scrollable()（Row 不支持），改用 layoutWeight(1)
  - C++ 侧添加 listMatchingObjects/listObjects 命令桥（需 Qt OHOS 重新编译才生效）
  - 搜索面板添加分类 tab（行星/恒星/星系/星团/星云/M天体）+ 预设 fallback 列表
- **修改原因：** 用户反馈天体分类查找功能不可用，冷门天体无法通过分类浏览找到
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：** 编译通过，模拟器未启动（待下次验证）
- **备注：** listMatchingObjects/listObjects 命令需要重新编译 libstellarium.so 才能使用。当前 fallback 模式下显示预设的常用天体名称。
## [2026-07-19] Codex - 项目初始化和核心移植

- **修改文件：** `src/StelMainView.cpp`, `src/StelMainView.hpp`, `src/main.cpp`, `src/core/StelMovementMgr.hpp`, `src/CMakeLists.txt`, `build/libstellarium-harmonyos/` (整个 HarmonyOS 工程)
- **修改内容：** 创建 HarmonyOS NEXT 构建工程；实现 XComponent + OpenGL ES 渲染桥；实现 ArkUI↔C++ 命令桥；实现 selectAt/searchObject/dragView/zoomBy/setTimeRate/setLocation/setActionChecked/getState/panBy/lx200Command 等命令
- **修改原因：** 初始移植
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：** 应用能启动并渲染星图
- **备注：** 建立了整个项目的代码基础

---

## [2026-07-19/20] WorkBuddy - 5 轮触摸/UI 修复 (touchfix1-5)

- **修改文件：** `build/.../MainWindowNativeNode.ets`, `src/StelMainView.cpp`
- **修改内容：**
  - touchfix1-3: 尝试不同的触摸路由方案（全屏 onTouch + 坐标判断 → overlay touch 路由）
  - touchfix4: **确立核心方案** — `harmonyShell` 改为 `HitTestMode.Transparent`，底层 `Blank + onTouch` 处理星图触摸，面板/按钮回归原生 `onClick`
  - touchfix5: 修复位置面板滚动、按钮点击验证通过
- **修改原因：** ArkUI 触摸事件被 UI 层拦截，导致按钮点击无效和星图无法选星
- **构建结果：** BUILD SUCCESSFUL (touchfix4/5)
- **验证结果：** 侧边栏按钮可点击、面板可打开/关闭、星图可拖拽/选星
- **备注：** 详见 `docs/harmonyos/workbuddy/memory/2026-07-20.md`

---

## [2026-07-20] TRAE (会话1) - 尝试 px→vp 坐标转换

- **修改文件：** `build/.../MainWindowNativeNode.ets`
- **修改内容：** 添加 `displayDensity` 和 px→vp 转换；尝试改 `touchWindowX/Y` 用 screenX/Y
- **修改原因：** 怀疑坐标系不匹配导致选星偏移
- **构建结果：** FAILED（编译破坏）
- **验证结果：** 未验证
- **备注：** 此会话的修改导致编译失败，被下一会话修复

---

## [2026-07-20] TRAE (会话2) - 修复编译失败 + 恢复 expandedShell

- **修改文件：** `build/.../MainWindowNativeNode.ets`
- **修改内容：**
  - 修复孤立的 `return` 语句（568-574行）— 恢复 `touchWindowX/Y` 函数签名
  - 修复 `aboutToAppear()` 缺失的闭合 `}`
  - 修复 `if (this.skyTouchFeedback)` 缺失的闭合 `}`
  - 恢复 `onAreaChange` 为简单版本（移除 displayDensity 转换）
  - 把 `harmonyShell()` 的 `Stack` 属性从尾随位置移到 `}` 后面（标准 ArkTS 写法）
  - **添加 `isExpandedLayout = this.skyWidth >= 900` 到 `onAreaChange`**
  - 添加 `onAreaChange` 日志
- **修改原因：** 上一会话修改导致 1299 个编译错误；`isExpandedLayout` 从未被赋值导致永远走 compactShell
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：**
  - 横屏模式下左侧垂直工具栏（搜/时/位/层/详/设）正常显示 ✅
  - 缩放按钮 (+/−) 正常显示 ✅
  - 底部 Dock 消失（确认走了 expandedShell）✅
  - 星图渲染正常（银河、方位标记、选中准星）✅
  - 星图触摸和选星功能正常（selectAt 返回正确结果）✅
  - 日志确认 `onAreaChange w=1440 h=960 expanded=true` ✅
- **备注：** 参考了 WorkBuddy 的完整工作记录；核心修复是把 `isExpandedLayout` 赋值逻辑加回 `onAreaChange`

---

## [2026-07-20] TRAE - 整理文档 + 规范 Agent 协作工作流

- **修改内容：**
  - 整理 Codex/WorkBuddy/TRAE 的工作文档到 `docs/harmonyos/`
  - 创建 `AGENTS.md`（Agent 协作规范）
  - 创建 `CHANGELOG.md`（本文件）
  - 创建 `KNOWN-ISSUES.md`
  - 准备上传 GitHub
- **修改原因：** 用户要求统一管理、规范工作流、方便跨 Agent 接手

---

## [2026-07-20] TRAE - 修复按钮点击 + 面板滚动 + Toggle 防跳动 + 面板右移 + 锁定功能

- **修改文件：** `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`
- **修改内容：**
  1. **修复按钮点击**：给 `verticalRail` 中每个按钮的 `Stack` 显式添加 `.width(44).height(44)`，解决 `onClick` 无法触发的问题
  2. **修复面板滚动**：移除面板外层 `Stack` 的 `.hitTestBehavior(HitTestMode.Block)`，恢复 `Scroll` 内部手势识别
  3. **修复 Toggle 跳动**：在 `handleSkyTouch` 的 Down 处理中加入 `isUiPoint` 检查；完善 `isUiPoint` 增加工具栏按钮区域判定；Up 处理保留面板区域跳过逻辑
  4. **面板右移**：`floatingPanel` 从居中改为右对齐 `position({ x: skyWidth - 392, y: 28 })`
  5. **锁定功能**：添加 `@State uiLocked` + `panelOffsetX/Y` + `lockRow()` Toggle，可在设置面板中锁定/解锁界面位置
  6. **重构 expandedShell**：按 WorkBuddy 方案分层 — 底层空 `Stack + Block + onTouch(handleSkyTouch)` 负责星图触摸，上层 `Stack + Transparent` 放 UI 元素，面板在最上层
  7. **panelTop() 修正**：从 `270` 改为 `28`，使面板顶部对齐
- **修改原因：** 用户反馈：按钮点不了、面板滑不动、Toggle 点完星图乱跳、设置面板应在右侧
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：**
  - 图层面板可正常上下滑动 ✅
  - 所有侧边栏按钮可点击并打开对应面板 ✅
  - 点击设置面板内 Toggle 星图不跳动 ✅
  - 面板显示在右侧 ✅
  - 应用无 ANR ✅
- **备注：** 学习了 WorkBuddy 历史版本的触摸分层方案；`Blank()` 在 Stack 内会导致 ANR，已替换为空 `Stack()`

---

## [2026-07-20] TRAE - 修复自动定位应用 + 排查自动时间同步

- **修改文件：** `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`
- **修改内容：**
  1. **修复自动定位不应用**：`useDeviceLocation()` 获取设备位置后，自动调用 `applyPickerLocation()` 将位置同步到星图，不再需要用户手动点"应用"
  2. **排查自动时间同步**：确认 C++ 层 `StelCore` 构造函数中已调用 `setTimeNow()`，配置文件 `startup_time_mode=Actual`，启动时自动同步系统时间；ArkUI 层过早调用 Native 命令会导致 ANR，故不在 ArkUI 层重复实现
  3. **回滚不安全的自动时间同步尝试**：移除了 `aboutToAppear` 和 `onAreaChange` 中调用 `triggerAction('actionReturn_To_Current_Time')` 的代码（会导致应用 ANR）
- **修改原因：** 用户反馈无法自动定位并应用现在位置、不能自动设定星图时间
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：** 应用启动正常，无 ANR，按钮点击和面板滚动正常 ✅
- **备注：** 自动时间同步已在 C++ 层实现，ArkUI 层不应重复调用

---

## [2026-07-20] TRAE - 手动设定星图时间 + C++ setJD 命令

- **修改文件：**
  - `src/StelMainView.cpp` — 新增 `setJD` 命令桥，支持通过 Julian Day Number 设置星图绝对时间
  - `build/.../MainWindowNativeNode.ets` — 时间面板新增手动输入日期时间的 UI 和逻辑
- **修改内容：**
  1. **C++ setJD 命令**：接收 Julian Day 字符串参数，调用 `core->setJD(jd)` 设置星图时间
  2. **手动时间 UI**：时间面板底部添加年/月/日/时/分输入框 + "应用"按钮，点击后计算 JD 并通过 `setJD` 命令同步到星图
  3. **同步当前时间按钮**：从星图当前 JD 反向解析为年月日时分，填充到输入框
  4. **JD↔Gregorian 转换**：在 ArkUI 侧实现了 `dateToJD()` 和 JD 到 Gregorian 的反向转换算法
  5. **状态变量**：新增 `manualYear/Month/Day/Hour/Minute` 五个 @State 变量
- **修改原因：** 用户需要手动设定星图时间（查看特定日期的星空）
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：** 时间面板正常打开，手动时间输入 UI 显示正确 ✅
- **备注：** 自动定位"定位不可用"是模拟器预期行为（无 GPS 硬件），真机可正常使用

---

## [2026-07-20] TRAE - 时间滚动选择器 + 星星中文化 + 语言选择器 + 搜索分类

- **修改文件：**
  - `src/StelMainView.cpp` — 新增 `setLanguage` 命令桥
  - `src/core/StelLocaleMgr.cpp` — OHOS 平台启用 NLS 支持
  - `build/.../MainWindowNativeNode.ets` — 时间UI重构、语言选择器、搜索分类
  - `build/.../rawfile/stellarium/translations/` — 编译中文翻译文件 .qm
  - `build/.../rawfile/stellarium/data/default_cfg.ini` — 默认语言改为 zh_CN
- **修改内容：**
  1. **时间UI改为滚动选择器**：用 `DatePickerDialog` 和 `TimePickerDialog` 替换文本输入框，解决文字被边框切除问题
  2. **星星名称中文化**：编译 `zh_CN.po` → `.qm` 翻译文件并打包；修改 `StelLocaleMgr` 在 OHOS 上启用 NLS；设置默认 `app_locale = zh_CN`
  3. **语言选择器**：设置面板新增"界面语言"行，支持中文/English 切换；C++ 侧新增 `setLanguage` 命令调用 `StelLocaleMgr::setAppLanguage()`
  4. **搜索分类**：搜索面板新增"天体分类"快捷搜索，按行星/恒星/深空天体分类显示
- **修改原因：** 用户反馈时间UI太烂文字被切、星星名称是英文、需要语言选择、搜索需要分类
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：**
  - 时间面板滚动选择器正常显示，文字完整 ✅
  - 界面完全中文化（设置/搜索/时间/详情面板）✅
  - 语言选择器显示中文/English，中文高亮 ✅
  - 搜索分类显示行星/恒星/深空天体 ✅

---

## [2026-07-21] TRAE - 设置面板添加 P0 功能（方向/FOV/坐标切换/截图/夜间模式）

- **修改文件：** `build/.../MainWindowNativeNode.ets`
- **修改内容：**
  1. 新增 `@State equatorialMount` 和 `@State nightMode` 状态变量
  2. 设置面板添加：方向快捷查看（东/南/西/北/天顶/北天极）、FOV 快捷切换（1°~120°）、坐标模式 Toggle（地平/赤道）、截图保存按钮、夜间模式开关
  3. `handleChip()` 方法新增 13 个 case 分支处理方向和 FOV chip 点击
- **修改原因：** 增强设置面板功能，提供常用天文操作快捷入口
- **构建结果：** 未验证
- **验证结果：** 未验证
- **备注：** 依赖 C++ 侧实现 `saveScreenShot` 命令及 `actionLook_*`/`actionSet_FOV_*`/`actionSwitch_Equatorial_Mount`/`actionToggle_Night_Mode` 等 action

---

## [2026-07-21] TRAE - 修复 action ID + 搜索天体 + 22语言 + libs恢复 + 完整HAP打包

- **修改文件：**
  - `build/.../MainWindowNativeNode.ets` — 修复 action ID、搜索天体处理、22语言选择器、锁定修复
  - `build/.../entry/libs/arm64-v8a/` — 通过 harmonydeployqt 恢复 .so 文件（48个）
  - `build/.../rawfile/stellarium/translations/` — 32语言 x 2域名 = 64个 .qm 文件
  - `src/core/StelFileMgr.cpp` — getLocaleDir() 添加 __OHOS__ 条件（需重编 .so）
- **修改内容：**
  1. 修复所有 action ID 错误（grep C++ 源码验证）：actionLook_East→actionLook_Towards_East, actionSet_FOV_1°→actionSet_FOV_9(索引映射), actionToggle_Night_Mode→actionShow_Night_Mode
  2. 搜索分类天体处理：handleChipClick 新增 Sun/Mercury/Venus/Saturn/Sirius/Vega/Betelgeuse/Polaris/M31/M42/M45/NGC2244 → searchObject
  3. 语言选择器扩展：2语言→22语言（zh_CN/zh_HK/ja/ko/de/fr/es/pt_BR/ru/uk/it/nl/pl/sv/cs/tr/ar/hi/th/vi/en），水平滚动
  4. 锁定功能修复：handleOverlayTouch 添加 if (this.uiLocked) return true
  5. 搜索反馈：searchObject 成功后显示"已找到: xxx"
  6. 恢复 libstellarium.so：通过 harmonydeployqt --no-build 生成完整 libs/（48个.so），HAP 1.2MB→263MB
- **修改原因：** 用户反馈功能全部无效、搜索分类没反应、语言太少、锁定功能是假的
- **构建结果：** BUILD SUCCESSFUL
- **验证结果：** HAP 263MB 包含完整 .so 链；安装启动成功，星图正常渲染
- **待验证：** FOV切换、语言切换（需重编.so）、夜间模式、截图
- **备注：** 不要删除 entry/libs/ 目录！.so 只能通过 harmonydeployqt 重新生成。C++ 修改需要 Qt OHOS 交叉编译。
