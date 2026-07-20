# Stellarium 鸿蒙（OHOS）移植 — 全量移植功能关闭说明

> 适用范围：Phase 2 全量移植 / OHOS Qt 6.12 Beta2
> 负责人：苏星图（Stellarium 架构与天文算法专家）
> 协同：乔渡星（主理人）

---

## 一、总体策略

OHOS Qt 6.12 Beta2 现状：

- **不支持**：`Qt WebEngine`、`Qt VirtualKeyboard`。
- **通常不含**（需自编译或关闭功能）：`Qt Charts`、`Qt Multimedia`、`Qt Sensors`、`Qt Positioning`、`Qt SerialPort`、`Qt TextToSpeech`。

移植决策（最小可用 + 后续可补）：

- **关闭**：WebEngine / Speech / GPS / INDI / Media / ShowMySky / Xlsx / NLS。
- **保留**：Scripting（脚本）、Charts（由另一专家脚本交叉编译进 OHOS Qt，故保持 `REQUIRED`）。
- 对应 CMake 开关全部置 0：`ENABLE_QTWEBENGINE=0`、`ENABLE_SPEECH=0`、`ENABLE_GPS=0`、`ENABLE_INDI=0`、`ENABLE_MEDIA=0`、`ENABLE_SHOWMYSKY=0`、`ENABLE_XLSX=0`、`ENABLE_NLS=0`，`ENABLE_SCRIPTING=1`、`STELLARIUM_GUI_MODE=Standard` 维持默认。

> 配套补丁：`0001-ohos-cmake-adapt.patch`
> 仅做一处最小改动——把 `CMakeLists.txt:632` 的
> `FIND_PACKAGE(Qt${QT_VERSION_MAJOR} COMPONENTS Concurrent Gui Network Widgets Charts Positioning REQUIRED)`
> 改为去掉 `Positioning`（因 `ENABLE_GPS=0` 后 GPS 内部对 Positioning 的 `FIND_PACKAGE` 不再执行，核心不再需要它）。
> 其余组件与逻辑一律不动。`Charts` 保留为 `REQUIRED`，由交叉编译提供。

---

## 二、被关闭功能逐条说明

### 1. 在线百科（Qt WebEngine）→ 关闭
- **原因**：OHOS Qt 6.12 Beta2 不含 WebEngine，且无 Linux 桌面版 `QtWebEngine` 可直迁。
- **替代方案**：首版仅保留手动离线说明；后续用鸿蒙原生 `ArkWeb` 组件替代，提供本地 HTML/在线检索视图，不依赖 Qt WebEngine。

### 2. 语音朗读（Qt TextToSpeech）→ 关闭
- **原因**：OHOS Qt 通常不含 TextToSpeech add-on。
- **替代方案**：暂不提供朗读；界面文本本身可见，不影响观星。如需要可后续单独交叉编译该 add-on 并改回 `ENABLE_SPEECH=1`。

### 3. GPS 自动定位（Qt Positioning）→ 关闭
- **原因**：OHOS Qt 不含 Positioning；且移动端权限/后台定位复杂。
- **替代方案**：用户手动输入经纬度或在城市列表中选取观测点。位置参数是观星计算的核心输入，手动设置后功能完整可用。
- **注意**：关闭 GPS 后，`CMakeLists.txt:632` 的 `Positioning` 已从核心 `REQUIRED` 移除（见补丁），避免 configure 失败。

### 4. 望远镜控制（INDI / SerialPort）→ 关闭移动端望远镜控制
- **原因**：INDI 依赖外部服务与 SerialPort，OHOS 端无成熟移植，移动场景也不常用。
- **替代方案**：首版不连接外部望远镜；如确需，可后续交叉编译 `Qt SerialPort` + INDI 库并改回 `ENABLE_INDI=1`。

### 5. 声音（Qt Multimedia）→ 关闭
- **原因**：OHOS Qt 通常不含 Multimedia add-on。
- **替代方案**：关闭所有音效/提示音；**不影响任何观星与天体计算功能**。

### 6. 大气散射模型 ShowMySky → 关闭（首版）
- **原因**：ShowMySky 为可插拔的大气渲染库，需单独构建且体积较大，首版优先保证核心可用。
- **替代方案**：使用 Stellarium 内置的简化大气/天空辉光渲染；后续可补编 ShowMySky 并改回 `ENABLE_SHOWMYSKY=1` 以获得更真实的大气散射。

### 7. XLSX 导入导出 → 关闭
- **原因**：依赖 `QXlsx`/LibreOffice 相关组件，非观星必需。
- **替代方案**：观测记录等数据先以 Stellarium 原生格式/JSON 保存；如需 Excel 互通，后续可引入并改回 `ENABLE_XLSX=1`。

### 8. NLS 多语言 → 首版关闭，保留英文界面
- **原因**：NLS 需 gettext 工具链与多语言资源打包，首版聚焦功能跑通。
- **替代方案**：界面暂以英文呈现（代码内英文文案完整可用）；后续补齐中文本地化并改回 `ENABLE_NLS=1`。

---

## 三、保留的核心功能（不受影响）

以下功能在 OHOS 首版中**完整保留并可正常使用**，是"看星星"的主功能：

- **核心星空渲染**：地平坐标系投影、星点绘制、银河、黄道、赤道网格。
- **星表**：Hipparcos / Tycho-2 等内置星表与额外星表加载。
- **星座**：连线、图像、神话说明。
- **深空天体**：星云、星团、星系（NGC/IC 等）。
- **AstroCalc 天文计算**：依赖 `Qt Charts`（已交叉编译并 `REQUIRED`），星历、行星位置、凌日/合等计算全部可用。
- **脚本（Scripting）**：`ENABLE_SCRIPTING=1` 保留，可运行 `.ssc` 脚本自动化演示。
- **交互**：触屏拖拽旋转、缩放手势、鼠标交互（桌面/模拟器）均保留。

---

## 四、关于"关闭是否影响看星星"

以上 8 项关闭**均不影响 Stellarium 的核心观星能力**——星图显示、天体定位、时间推演、星历计算、星座/深空浏览、脚本演示均正常工作。关闭项属于"增强体验"或"外部设备/高级导入导出"范畴。

**恢复任一功能的方法**：
1. 交叉编译对应的 Qt add-on / 第三方库进 OHOS Qt 工具链；
2. 将对应 `ENABLE_*` 开关改回 `1`；
3. 若涉及核心 `FIND_PACKAGE` 依赖（如 Positioning），按需把组件加回 `CMakeLists.txt` 的 `REQUIRED` 列表（参考本目录补丁的反向操作）。

---

_文档由苏星图（Stellarium 架构与天文算法专家）产出，供乔渡星（主理人）与移植专家团复核。_
