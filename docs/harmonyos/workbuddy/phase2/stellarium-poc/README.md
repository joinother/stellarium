# Stellarium HarmonyOS 最小渲染 PoC（Phase 2 步骤1）

> **性质说明**：这是**最小验证工程**，**不是**完整 Stellarium。它只用来验证三件事：
> 1. Qt Quick/QML + OpenGL ES 渲染通路能在纯血鸿蒙跑起来；
> 2. `harmonydeployqt` 打包链路可用；
> 3. 触屏单指拖拽可旋转场景（为后续 Stellarium 星空指星打基础）。

---

## 一、环境要求（已核实工具链事实）

| 项 | 版本 / 说明 |
|----|------------|
| Qt | **6.12.0 Beta2**，target `harmonyos_arm64_v8a` |
| DevEco Studio | **6.1.0** |
| HarmonyOS SDK | **API 23** |
| 渲染 | OpenGL ES **3.2**（Qt 6.12 自动检测 Desktop OpenGL 或 OpenGL ES） |
| 设备 | phone / tablet / 2in1 |
| 不支持的 Qt 模块 | WebEngine / Positioning / SerialPort / VirtualKeyboard / TextToSpeech / 旧 Qt OpenGL 模块 |
| 支持的 Qt 模块 | Qt Quick/QML、Qt Gui OpenGL、Qt Sensors（底层 libohsensor） |

---

## 二、文件结构

```
stellarium-poc/
├── CMakeLists.txt          # qt-cmake 配置，产出 SHARED(.so) + 导出 main
├── module.json5            # 鸿蒙应用模块配置（deviceType/abilities/权限）
├── build_ohos.sh           # qt-cmake → cmake --build → harmonydeployqt
├── README.md               # 本文件
└── src/
    ├── main.cpp            # QGuiApplication + QQmlApplicationEngine 入口
    ├── stelrenderer.h/.cpp # C++ 自定义 QQuickItem + QSGRenderNode 画 GLES 星空
    └── stel_poc.qml        # QML 窗口 + 拖拽旋转交互
```

---

## 三、在本地 DevEco 环境编译运行（沙箱无法真编译）

> ⚠️ **沙箱内无法编译**。以下操作都在你本地装有 Qt 6.12 HarmonyOS + DevEco 6.1 的机器上进行。

### 1) 修改 `build_ohos.sh` 中的占位路径
顶部变量按本地环境改：
- `QT_OHOS_DIR`：Qt 6.12 HarmonyOS 安装根（含 `bin/qt-cmake`、`bin/harmonydeployqt`）。
- `DEVECO_DIR`：DevEco Studio 安装位置（默认 macOS 下 `/Applications/DevEco-Studio.app/Contents`）。
- `OHOS_ADDITIONAL_PKGS`：额外包查找根（含 Qt Sensors 的 `libohsensor`），默认 `~/.local/opt/ohos/additional-packages`。

### 2) 构建 + 打包
```bash
cd stellarium-poc
chmod +x build_ohos.sh
./build_ohos.sh
```
脚本流程：
1. `qt-cmake` 配置（注入鸿蒙交叉工具链，`QT_HARMONYOS_TARGET_ARCHS=arm64-v8a`）；
2. `cmake --build` 编译出 `.so`（Qt for HarmonyOS 约定：可执行包装为共享库，导出 `main`）；
3. `harmonydeployqt --hvigor .../hvigorw --input <target>-harmony-deployment-settings.json` 调用 DevEco 打包成 `.hap`。

### 3) 在 DevEco 中签名并运行
- 用 DevEco Studio **打开 `build-ohos/` 构建产物目录**（或直接打开本工程根目录均可，取决于你如何组织）。
- 配置 **签名**（DevEco → Signing Configs，使用你的调试证书）。
- 选择 **模拟器**（Phone/Tablet API 23）或 **真机**，点击 Run 安装 `.hap`。

---

## 四、预期现象（验证通过的标准）

- 启动后全屏显示**近黑深蓝夜空**，上面有约 800 个**柔边白色星点**组成的球形点阵。
- **单指拖拽（触屏）或鼠标拖拽**可旋转整个星空：
  - 水平拖 → 绕 Y 轴转；垂直拖 → 绕 X 轴转。
  - 底部实时显示 `angleX / angleY` 角度数值，随拖拽变化。
- 渲染走 **OpenGL ES 3.2**（顶点/片段着色器用 `#version 320 es`），由 Qt 6.12 在鸿蒙上自动绑定 GLES 上下文。
- 能正常打包出 `.hap` 并安装运行 → 说明 `harmonydeployqt` 链路可用。

---

## 五、与后续 Stellarium 移植的关系

- 本 PoC 的 `StelRenderer`（QQuickItem + QSGRenderNode + GLES）是后续把 Stellarium
  星空渲染接入 Qt Quick 场景图的**最小骨架**。
- `module.json5` 已预留 `ACCELEROMETER` / `GYROSCOPE` 权限，为后续"指哪看哪"的
  传感器驱动星图旋转预留接口（当前 PoC 未启用 Qt Sensors）。
- 验证通过后，即可把 Stellarium 的恒星目录、投影与绘制逻辑替换进 `StelRenderer`，
  而非从零搭建鸿蒙渲染通路。

---

*主理人提示：本脚手架已覆盖 Qt Quick + GLES 渲染、harmonydeployqt 打包、触屏旋转三个验证点；请在本地 Qt 6.12 HarmonyOS + DevEco 6.1 环境实测后回填结果。*
