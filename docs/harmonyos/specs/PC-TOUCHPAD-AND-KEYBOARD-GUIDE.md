# PC 触控板与键盘交互指南

## 当前交互

天空触摸面直接绑定 ArkUI `onMouse` 和 `onAxisEvent`，由 `SkyInputController` 处理，不依赖键盘焦点或根节点轴事件冒泡。触控板双指滑动、双指捏合与鼠标滚轮走轴事件；触控板单指移动光标属于鼠标输入，点击选中，按住左键或使用系统拖动手势旋转星图。触屏手指继续走 `onTouch`，鼠标来源的 TouchEvent 不重复处理。

- 触屏点击、触控板点击或鼠标左键：选中天体。
- 触屏单指拖动或按住鼠标左键拖动：旋转星图；有有效速度样本时松手可启动惯性。
- 触控板双指滑动：平移星图。
- 触控板双指捏合：以指针位置为锚点缩放星图。
- 鼠标滚轮：缩放星图；触控板双指捏合以指针位置为锚点缩放。
- 触控板双指滑动结束：应用不额外启动平移惯性，不叠加一套推算出的松手速度。双指手势按起点确定归属，从面板开始再移入天空不会平移星图；天空手势结束或取消时清理自身状态。
- 天空获得键盘焦点时，方向键、PageUp/PageDown、Home/End 向原生发送按下/抬起阶段，按住导航并在松开或失焦时释放，不做绕过原生导航开关的平移/缩放回退。`+` / `-`、空格和回车优先调用原生动作；明确未接受的无修饰键可回退到缩放或选中天体居中。无修饰 `=` 直接兼容放大。
- 默认绑定：`N` 切换深空天体显示提示（`actionShow_Nebulas`，主快捷键 `D`、备用 `N`）；`Ctrl+N` 切换夜间模式；`F` 切换雾。以快捷键编辑器中的当前绑定为准，删除或改绑 F/N 后不会回退到搜索/夜间模式。
- 无修饰 `Esc` 关闭当前面板或退出沉浸预览；`Tab` 留给界面焦点导航。文本输入框获得焦点后，字符与编辑快捷键由输入框处理。
- “设置 → 视角与导航 → 快捷键编辑器”：直接查看全部原版动作、主/备用快捷键和默认值；可以搜索、保存、恢复单项或恢复全部。快捷键冲突会被拒绝，不会覆盖另一个动作。

## 本次修复

触控板捏合上报相对本次手势开始时的累计比例，不是逐帧倍率。原生 `zoomBy` 需要先收到 `1|1|x|y|width|height` 建立起始 FOV，再收到累计比例和 `started=0`，最后收到 `endPinch`。此前 ArkTS 只发送更新，原生没有捏合状态便直接忽略。现在按 `AxisAction.BEGIN/UPDATE/END/CANCEL` 管理生命周期，比例返回 1 也会更新；结束事件比例为 0、结束点移入 UI、取消及控制器停止均能收尾。读取 `axisPinch`，无有效值时尝试 `getPinchAxisScaleValue()`。

输入分类以 `sourceTool` 为准：`SourceTool.TOUCHPAD` 的非捏合轴事件平移；`SourceTool.MOUSE` 的非捏合轴事件调用离散 `zoomStep`。只有 `SourceTool.Unknown` 才用有限且大于 0 的 `scrollStep` 辅助判断鼠标滚轮，不能仅用属性是否存在分类。触控板即使携带 `scrollStep=0` 或非零配置也不会因此误当滚轮。有效捏合比例优先进入缩放路径。

水平、垂直轴增量单位为 vp，发送 `panBy` 时取反并传入画布宽高，不再乘旧的 28 倍增益。坐标使用与星图同原点的天空面局部 `x/y`，不直接使用浮动窗口的 `windowX/windowY`。鼠标使用 `MouseAction.Press/Release/Move` 和 `MouseButton.Left`，避免错误数字映射；悬停节流发送 `setPointerPosition`。

键盘实际路径是天空焦点节点 → 宿主 `handleSkyKeyboard` → `KeyboardShortcutController` → `sendKey` → 原生动作/导航处理。根节点只处理面板关闭的无修饰 Esc。控制器根据物理键码和 Ctrl/Alt/Shift 组合分发；方向键、PageUp/PageDown、Home/End 采用 `|down` / `|up`，保留按下时修饰键，失焦释放所有持有键。其他单次动作只有引擎明确返回 `ok=true, accepted=false`、无修饰键且焦点版本仍有效时才尝试缩放/居中兼容动作。传输失败、焦点失效或组合键不会降级成裸键动作。

## 使用前检查

1. 将指针放在星图空白区域，详情卡片、设置面板和 Dock 上的手势由对应控件处理。
2. 在“设置 → 视角与导航”确认“鼠标或触控板移动星图”和“鼠标滚轮或触控板缩放”已开启。
3. 如果双指捏合仍无响应，先确认系统触控板设置没有把双指捏合映射为系统缩放，再重新把指针移入星图区域。
4. 该路径不读取设备序列号、UDID、位置或网络数据。

## 验证边界

2026-10-26 MateBook：鼠标悬停、拖动、滚轮、系统注入触控板捏合、方向键/PageUp 连续导航、搜索 Delete/Backspace 及 Ctrl+N/自定义快捷键已实测。临时 TestKit runner 已构建安装，但 `Driver.create()` 返回 null，双指滚动 API 没有执行，双指平移及物理触控板手感仍待验收。完整证据见 [PC 合并回归记录](../testing/PC-MERGE-REGRESSION-2026-10-25.md)。

验证分三层记录，不能互相替代：

1. 行为回归测试执行实际控制器，覆盖源分类、官方枚举、累计捏合、结束/取消、局部坐标、焦点与快捷键；CLI 原生命令验证 FOV、视角和动作桥，但单独调用 `zoomBy`/`zoomStep`/`panBy` 不能证明 ArkUI 收到了输入。
2. `uinput -P -s` 是三指 SWIPE：工具源码的 `SwipeActionEvent` 固定 `fingerCount=3`，发送 `POINTER_ACTION_SWIPE_BEGIN/UPDATE/END`，不发送水平/垂直滚动轴值。不要用它验证双指平移，它可能触发系统窗口手势；没有 SKY_AXIS 日志不能据此判定应用失败。当前检查的 uinput 源码未提供显式双指滚动轴命令。`uinput -P -p x y scale` 可注入捏合，`uinput -M` 可验证鼠标；两者均不能替代双指平移测试。
3. 官方 TestKit 从 API 22 起为 PC/2in1 提供 `Driver.touchPadTwoFingersScroll(point, direction, d, speed?)`。`point` 是鼠标光标位置；`d` 为非负整数格数，每格 120px；`speed` 为 1..500 格/秒，默认 20。可在 UI 测试中使用 `await driver.touchPadTwoFingersScroll({ x: 400, y: 300 }, UiDirection.UP, 1, 10)`，坐标须选当前窗口天空空白处。其他设备返回 17000005。不要替换成 `touchPadMultiFingerSwipe`（只支持 3/4 指）或 `injectMultiPointerAction`（触屏多点路径）。应核对 `[SKY_AXIS]` 的 sourceTool/action/比例/增量/局部坐标/归属及视角变化；边界诊断最多记录每实例 32 条 BEGIN/END/CANCEL，无日志也需排除额度耗尽。该 API 已核实文档，尚不代表本机测试框架或设备已执行通过。
4. 系统注入可验证事件分发链，但不能替代物理触控板的驱动事件、连续帧、自然滚动方向、掌压抑制与手感验收。最终仍需 PC/2in1 实际双指滑动、捏合、释放，覆盖浮动/最大化、面板边界，并验证快捷键改绑保存后的行为。分别标记“系统注入通过”和“物理设备通过”；无法运行上述 TestKit API 时，双指平移保持待物理验收。

依据：[官方 UiTest 双指滚动 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-uitest#touchpadtwofingersscroll22)、[官方 uinput 三指滑动示例](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uinput)、[OpenHarmony 注入工具源码](https://github.com/openharmony/multimodalinput_input/blob/master/tools/inject_event/src/input_manager_command.cpp)。开源 master 实现与设备发行版可能不同；设备行为须单独记录。
