# Stellarium HarmonyOS 当前工作整理

日期：2026-07-20  
基准提交：`89d075087614b62e40e9ddfbdb27778e9c8829aa`  
本地分支：`openharmony-preview-v1`  
本地仓库：`/Users/jiexuanyang/stellarium-src`

## 我已确认的当前状态

- 本地仓库已在 `89d0750`，工作区干净。
- 提交标题：`fix(ui): 修复按钮点击、面板滚动、Toggle防跳动、面板右移、锁定功能`
- 这次提交已经把 HarmonyOS 协作文档规范化到 `docs/harmonyos/`：
  - `AGENTS.md`：Agent 接手规范、构建/签名/调试命令。
  - `CHANGELOG.md`：按时间记录 Codex / WorkBuddy / TRAE 的修改。
  - `KNOWN-ISSUES.md`：当前待修问题列表。
  - `harmonyos-project/`：HarmonyOS 工程源码快照，包含 ETS、cpp、json5。
  - `workbuddy/`：历史记忆、测试截图、布局树和日志。
  - `signing/`：本地签名材料。

## 相比我旧交接文档的变化

我之前写的旧交接文档还停留在“UI 基本点不了、触摸路由未收口”的阶段。  
`89d0750` 之后，项目状态应更新为：

- UI 触摸主问题已由 WorkBuddy/TRAE 多轮修复并验证。
- 横屏 expandedShell 已验证可用。
- 侧栏按钮、面板打开/关闭、图层滚动、搜索芯片、时间控制、位置应用、星图选星等已有实测记录。
- 目标详情不再是纯占位，搜索和选星后可显示名称/类型/状态/星历信息。
- 位置面板已扩展为离线地图 + 大洲/国家/城市三级选择 + 自动定位入口。
- 仍不建议直接发布正式版，原因是竖屏/窄屏和边缘触摸死区等还没完全收口。

## 当前代码/文档入口

优先读这些文件：

- `/Users/jiexuanyang/stellarium-src/docs/harmonyos/AGENTS.md`
- `/Users/jiexuanyang/stellarium-src/docs/harmonyos/CHANGELOG.md`
- `/Users/jiexuanyang/stellarium-src/docs/harmonyos/KNOWN-ISSUES.md`
- `/Users/jiexuanyang/stellarium-src/docs/harmonyos/workbuddy/memory/2026-07-20.md`
- `/Users/jiexuanyang/stellarium-src/docs/harmonyos/harmonyos-project/ets-source/pages/MainWindowNativeNode.ets`

核心运行代码仍在：

- `/Users/jiexuanyang/stellarium-src/src/StelMainView.cpp`
- `/Users/jiexuanyang/stellarium-src/src/StelMainView.hpp`
- `/Users/jiexuanyang/stellarium-src/src/core/StelMovementMgr.hpp`
- `/Users/jiexuanyang/stellarium-src/src/main.cpp`
- `/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`

注意：`docs/harmonyos/harmonyos-project/` 是规范化后的工程源码快照；`build/libstellarium-harmonyos/` 是实际 DevEco 构建工程。接手时要确认两边是否同步。

## 当前已完成能力

- 单 HAP 构建、签名、安装、启动。
- OpenHarmony render pump：
  - `main.cpp` 启动 `startOhosRenderPump()`
  - `StelMainView.cpp` 负责 framebuffer 提交
  - `CMakeLists.txt` 链接 `libhilog_ndk.z.so`
- ArkUI + C++ command bridge。
- 星图渲染、拖拽、点击选星、缩放。
- 搜索 Moon/Mars/Jupiter 等天体并打开目标面板。
- 目标详情基础展示。
- 图层面板滚动和 Toggle。
- 时间控制，包括现在/暂停/前进等。
- 位置面板：
  - 离线世界地图选点
  - 自动定位入口
  - 大洲/国家/城市三级选择
- LX200 基础 GoTo/Sync/Stop。
- 陀螺仪代码已接入，但仍需真机传感器验证。
- UI 点击提示条。

## 当前已知问题

以 `docs/harmonyos/KNOWN-ISSUES.md` 为准，目前重点是：

- P1：边缘区域选星被 UI 死区吞掉。
- P1：compactShell 竖屏/窄屏模式未验证。
- P2：UI 风格仍粗糙，不够 HarmonyOS 原生。
- P2：面板尺寸硬编码，横竖屏切换可能错位。
- P2：与 Stellarium 桌面版功能差距仍大，需要梳理功能矩阵。
- P3：陀螺仪需要真机验证。
- P3：LX200 只有基础协议，没有完整设备管理 UI。
- P3：启动过渡/动画未实现。

## 我建议的下一轮工作顺序

1. **先验证，不先改代码。**
   - 按 `AGENTS.md` 构建、签名、安装。
   - 复测横屏 expandedShell。
   - 复测搜索、图层滚动、位置应用、星图点选。

2. **补 compactShell/竖屏测试。**
   - 旋转模拟器或换窄屏配置。
   - 抓 `dumpLayout`、截图、hilog。
   - 如果 Dock、面板、星图触摸冲突，优先修触摸分层。

3. **修边缘死区。**
   - 收窄 `isUiPoint()`。
   - 工具栏容器透明化，只让真实按钮命中。
   - 复测屏幕左/上/下边缘选星。

4. **整理功能差距矩阵。**
   - 对比桌面版/安卓版。
   - 分成“开源核心可做”“需要公开协议/SDK”“商业/会员不可复制”三类。

5. **再做 UI 美化。**
   - 统一 HarmonyOS 风格。
   - 替换单字图标。
   - 减少硬编码面板尺寸。
   - 增加更自然的动效和触摸反馈。

## 注意事项

- 不要绕过或复制安卓版会员功能。
- GoTo 只走公开 LX200/类似公开协议。
- 地图功能当前是离线方案；接在线地图前必须确认 API Key、SDK 许可和隐私合规。
- ArkUI `@Builder` 参数有响应式陷阱：不要把 `@State` 字符串/数组作为 builder 参数传给 `Text`/`ForEach` 后指望自动刷新，应在 builder 内直接读取 `this.xxx`。
- `uitest dumpLayout` bounds 是设备像素；ArkUI touch `windowX/windowY` 多数场景是 vp，坐标对照要小心。
- `hilog -x` 是非阻塞日志读取；不要用阻塞 hilog 挂住工具。
- 修改后必须同步更新 `CHANGELOG.md` 和 `KNOWN-ISSUES.md`。

## 我的当前结论

`89d0750` 已经把项目从“能渲染但 UI 不可靠”推进到“横屏基本可交互的预览版”。  
下一步不该继续堆功能，而是补验证面：竖屏/窄屏、边缘选星、真机传感器、UI 适配和功能差距清单。
