# Stellarium for HarmonyOS — Vision & Onboarding

## 1. 项目远景目标

### (a) 跨设备运行
在所有鸿蒙设备上无缝运行：手机、平板、车机（HarmonyOS Cockpit）、智慧屏、PC。

- **共享 C++ 核心**：`libstellarium.so` 跨设备通用。
- **自适应 UI**：根据屏幕尺寸自动切换 `expandedLayout`（平板/电视）和 `compactLayout`（手机/车机）。
- **分辨率无关**：OpenGL ES 渲染使用设备实际视口，FOV 动态计算。

下一步：接入**鸿蒙分布式软总线**，实现手机启动→迁移到车机/电视的无缝流转。

### (b) 手机遥控模式
车机/电视只显示**纯净星空画布**（无菜单按钮），手机作为**触控器+菜单面板**：

- 手机端：平移、缩放、时间控制、搜索、设置、AstroCalc 数据
- 通信方式：HarmonyOS **Distributed Data Object** 或轻量 WebSocket 桥接
- 灵感来源：Stellarium Web 的分离式控制 UI，但原生低延迟

---

## 2. 本地构建简化路线

当前构建依赖较重（DevEco Studio + Qt 6.12 + OpenHarmony SDK）。计划：

1. **`BUILD.md`** — 从零到运行 HAP 的完整步骤
2. **`Dockerfile`** — 预装工具链的容器，无需本地安装 DevEco Studio
3. **CI workflow** — GitHub Actions 自动编译 `arm64-v8a` 的 `.so`
4. **预编译 `.so` 产物** — Release 中附带 `libstellarium.so`，用户只需构建 ArkTS HAP 层

目标：`clone → hvigorw assembleHap → 签名 HAP → 安装到设备`

---

## 3. 上游合并策略

### 可上游化（轻量重构后）
- `StelMainView.cpp` 命令分发器（~35 个 `if` 块）→ 提取为 `StelMobileBridge` 可选模块
- `StelCore` / `SolarSystem` 微小增补（`NebulaMgr` include 等）
- `StelFileMgr.cpp` 的 `__OHOS__` 路径搜索（宏隔离，不影响其他平台）

### 平台专属（留在 Fork）
- ArkTS 壳层（`MainWindowNativeNode.ets` ~4000 行）— 完整移动端 UI
- NAPI 桥接层（`StellariumBridge.ets/cpp`）— HarmonyOS 特有
- `StellariumResourceBootstrap.ets` — HAP rawfile 提取逻辑

建议：`ENABLE_MOBILE_BRIDGE` 编译选项，桌面端不受影响，Android/iOS 也可复用同一桥接 API。
