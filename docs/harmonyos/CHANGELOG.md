# 修改日志

> 格式说明：每次修改追加一条记录。新 Agent 接手时先读这个文件。

---

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
