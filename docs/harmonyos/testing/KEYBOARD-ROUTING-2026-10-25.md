# PC 键盘事件路由实现说明（2026-10-25）

## 实现与验证状态

键盘链路由 `KeyboardShortcutController.ets`、`KeyboardShortcutStore.ets`、宿主 `MainWindowNativeNode.ets` 与 `src/StelMainView.cpp` 的 sendKey 桥组成。本文描述当前源码；构建、安装不等于实际按键链路通过。

build5 实机中 PageUp/Left 通过 `-d -i400 -u` 注入没有位移，鼠标、轴和捏合正常；dump 显示原空 Stack 焦点目标在鼠标/触屏点击星图后仍为 focused=false。

build6 将目标替换为 `Text('')` 后，实机反馈确认 dump 为 focused=true；uinput 持有 PageUp 500ms，FOV 从 60° 降至 22.266°，释放后保持稳定。空 Stack 作为无交互焦点叶节点无法获焦的问题已实测解决，PageUp 的按下、持续缩放和释放停止链路通过。15 组自动测试通过；此结果不外推为 Left、失焦释放或所有编辑域用例已通过。所有实机结果、版本和证据统一由[主回归报告](PC-MERGE-REGRESSION-2026-10-25.md)汇总。

## 宿主焦点与编辑域隔离

当前 `sky-keyboard-target` 是 `Text('')`，fontSize、宽高均为 1，位置为 (0, 0)，设置 `HitTestMode.None`、`focusable(true)`、`defaultFocus(true)`。它没有可见文本，也不参与指针命中；程序主动请求焦点。

- 叶节点 onFocus/onBlur 调用 `keyboardShortcutCtl().setSkyFocused(true/false)`；onKeyEvent 调用 `handleSkyKeyboard(event)`。
- `handleSkyKeyboard` 创建当前宿主 hooks：缩放、居中、前往选中目标、关闭面板或沉浸模型；普通路径调用 `handleSkyKey`。
- `focusSkyKeyboard(x, y)` 仅在 `!isUiPoint(x, y)` 时调用 `getUIContext().getFocusController().requestFocus('sky-keyboard-target')`。
- `handleSkySurfaceTouch` 在非鼠标来源的 TouchType.Down 且 touches 非空时，使用第一个触点的 x/y 请求焦点，再转发给 SkyInputController。
- `handleSkySurfaceMouse` 在 MouseAction.Press 使用 event.x/y 请求焦点，再转发鼠标事件。各星图 shell 的 onSkyTouch/onSkyMouse 接入这两个 wrapper；overlay 在 UI 命中检查后接入触摸 wrapper。
- 根 onKeyEvent 调用 `handleSkyKeyboard(event, true)`，仅分发 `handlePanelKey`；旧的根星图键盘处理不再接入。
- 后台与宿主销毁时清除星图焦点状态并释放持有键。

独立叶节点失焦即可覆盖任意 TextInput/TextArea、快捷键编辑框和其他控件，不依赖搜索/地点控件名单。祖先容器可能与编辑框同时处于焦点链，不能以根 onFocus/onBlur 判断编辑状态，也不能在根恢复通用字母/方向键转发。面板根只处理未被输入法或子控件消费的裸 Esc；系统返回键走原有生命周期路径。

## 控制器事件与映射

`handleSkyKey` 先处理 Up，再检查 Down 的焦点与修饰键。Up 使用持有表记录的原始 payload，避免先释放 Ctrl/Shift 后丢失组合键释放。失焦发送全部持有导航键的 Up，清理按下集合，并增加 focusRevision，使迟到异步回包失效。

物理 KeyCode 显式映射 A–Z、0–9、F1–F12、方向、PageUp/PageDown、Home/End、空格、回车、Esc、退格、Delete、正负号及方括号；不依赖 keyText。HarmonyOS DEL（2055）为退格，FORWARD_DEL（2071）为向前删除。

- 方向、Page、Home/End 发送 `KEY|down`，抬起发送 `KEY|up`，不轮询或重试 Down。
- 其余支持键通过单次 sendKey 调用；同一物理键重复 Down 被抑制，避免切换动作反复触发。
- Tab/Shift+Tab 留给系统走焦；Meta、未知键、修饰键查询缺失或抛错返回 false。Ctrl/Alt/Shift 完整传递，不降级为裸键。
- 当前 `event.metaKey !== 0` 也会拒绝 undefined。官方定义 metaKey 为必有 number（0/1），尚未取得实机缺失该字段的证据；测试事件固定使用 0，不能证明设备字段值。
- 裸 Esc 关闭面板/沉浸模型；根面板处理仅接受无修饰 Esc。输入法候选或子控件优先消费 Esc 时，不强制抢先关闭。
- 裸等号直接兼容缩放；Shift+Equals 发送 SHIFT+PLUS。其他兼容回退只在原生明确 `ok=true, accepted=false`、无修饰、焦点仍在且代次一致时执行，仅包含正负号缩放、空格居中及回车前往目标。
- N/F 没有硬编码回退。默认 N 为深空显示备用键，Ctrl+N 为夜间模式，F 为雾；实际配置以 getKeyboardShortcuts 为准。Qt 搜索快捷键不等于已实现 ArkUI 搜索。

编辑器仅接受当前可表示的单组 Ctrl/Alt/Shift 与支持键；拒绝 Meta、Tab、裸 Esc、多段绑定、F13+、不支持标点及管道分隔符。保留所选动作的主/备用保存和单项恢复范围。小键盘、NumLock、非美式布局与系统保留组合键不属于已验证支持范围。

## 原生 held 协议

旧 `sendKey KEY` 继续在一次调用中合成 press/release，保持既有 CLI 契约。新增 `sendKey KEY|down` 与 `KEY|up`；未知 phase 或额外字段被拒绝。阶段命令绕过 consume-on-read 缓存，每次按 FIFO 入队；立即返回 `queued=true` 仅证明排队，不代表动作已执行或接受。

原生按 keyCode 保存首次 Down 的修饰键，重复 Down 不重触发；Up 使用保存的修饰键并删除记录。事件仍经 `StelApp::handleKeyEvent → StelActionMgr → StelMovementMgr`，保留自定义动作优先以及 moveKeys/zoomKeys 门控，不绕过为本地 panBy/zoomStep。

对于允许移动且未匹配动作的方向键，记录持有集合、取消自动平移和惯性；每帧 app.update 后更新选中目标锚点，避免固定位置把键盘平移拉回。释放后恢复正常锚定。禁用 moveKeys 清除持续平移；禁用 zoomKeys 前先停止缩放。

只读复查：阶段队列、原始修饰键释放和失焦释放路径未发现可直接解释单独 Left/PageUp 完全无效的明显问题；build5 的焦点失败发生在原生转发之前，build6 的 Text 替换已恢复 PageUp 实机链路。仍有一个明确的多键限制：StelMovementMgr 每轴只保存一个增量，Left down → Right down → Right up 会清零方位增量，即使 Left 仍按住也不恢复；PageUp/PageDown 同理。按下去重不会重新发剩余键。该限制应单独验证，不应把它当成本次单键无效的原因。

## 诊断顺序

1. 在空白星图按下后检查目标 Text 的 focused、onFocus 和 store 状态；FocusController.requestFocus 返回 void，观察异常与焦点事件，不判断布尔返回值。空 Stack 作为无交互叶节点仅设置 focusable(true) 不具备获焦能力，背景颜色不是解决条件。
2. 目标获焦后确认 onKeyEvent 的 type、keyCode、metaKey 及 getModifierKeyState 能力；若没有事件，检查窗口/原生 XComponent 焦点和注入路径。
3. 若有事件但没有桥调用，核对控制器焦点、Meta 与修饰键门控；仅在实际观察到 undefined 后讨论兼容策略，不先放开所有修饰键或编辑域。
4. 单独用 CLI 的 LEFT/PAGEUP down/up 跨帧验证原生，读取视角/FOV，并检查导航开关和自定义绑定。鼠标/捏合正常不证明键盘门控已开启。
5. 验证结束必须发送对应 Up；不能以 queued、accepted 或构建成功替代实际位移证据。

## CLI / uinput 回归用例

显式填写 DEVICE、BUNDLE、HDC，不依赖 CLI 默认包名。以下是测试步骤，不代表已经在设备执行：

```sh
node scripts/stellarium-cli.mjs --device "$DEVICE" --bundle "$BUNDLE" --command getKeyboardShortcuts --json
node scripts/stellarium-cli.mjs --device "$DEVICE" --bundle "$BUNDLE" --command getNavigationSettings --json
node scripts/stellarium-cli.mjs --device "$DEVICE" --bundle "$BUNDLE" --command openUiPanel --payload search --json
node scripts/stellarium-cli.mjs --device "$DEVICE" --bundle "$BUNDLE" --command getUiPanelState --json
```

确认 search 面板可见，并通过 Tab/Shift+Tab 或实体键盘使搜索框获焦；openUiPanel 不保证输入框获焦。目前没有聚焦任意输入框、读取光标/文本的语义 CLI，使用布局树或人工核对。sendKey N 是原生命令，不能代替 ArkUI 文本输入。

搜索框为空、英文输入状态下依次执行，预期文本 n → nn → Home/Delete 后 n → End/Backspace 后空；星图显示与视角不能改变：

```sh
"$HDC" -t "$DEVICE" shell uinput -K -d 2030 -u 2030
"$HDC" -t "$DEVICE" shell uinput -K -d 2030 -u 2030
"$HDC" -t "$DEVICE" shell uinput -K -d 2081 -u 2081
"$HDC" -t "$DEVICE" shell uinput -K -d 2071 -u 2071
"$HDC" -t "$DEVICE" shell uinput -K -d 2082 -u 2082
"$HDC" -t "$DEVICE" shell uinput -K -d 2055 -u 2055
```

- 所有编辑域：位置、快捷键搜索和主/备用草稿、时间/坐标、书签、TextArea 重复 N/Delete/方向/空格/Enter/Ctrl+A/C/V；检查光标、选区、输入法候选及星图不被误操作。
- 焦点恢复：编辑后空白星图按下应转移到 Text 叶子，UI/Dock 按下不抢焦；验证 Tab/Shift+Tab、面板 Esc 与中文候选 Esc。
- 单键 held：LEFT/PAGEUP down 后跨帧读取 getViewCenterCoordinates / getNavigationSettings.currentFov，Up 后停止。物理/uinput 路径与 CLI 原生路径分别记录，旧单次 LEFT/PAGEUP 不用于证明 held。
- 失焦释放：按住 Left/PageUp 后进入编辑框、切后台或销毁宿主，运动停止；同时 Left+Up 后失焦全部释放；先放 Ctrl 再放 Ctrl+Up，释放仍携带原修饰键。
- 重复与动作：同一次按住 N 不反复切换；给 Left/PageUp 配置无冲突切换动作后长按仅触发一次，松开重按可再次触发，不能额外平移/缩放。结束恢复原配置，不用 resetAll 覆盖其他绑定。
- 导航门控：moveKeys/zoomKeys 关闭时禁止相应导航，持有中禁用立即停止；重新开启不能自动恢复旧运动。选中目标固定位置时检查方向键不会被锚点拉回。
- 多键限制：分别复测 Left/Right、PageUp/PageDown 的交错按下和释放，记录剩余按住键是否继续运动。
- 解析与保存：CLI EQUALS、META+N 应拒绝；物理裸等号和 Shift+= 分别验证。编辑器拒绝 Meta+N、Tab、裸 Esc、F13、多段绑定、不支持标点和管道符；冲突保存不覆盖原动作。

## 自动测试与构建边界

既有记录：`node scripts/test-ohos-keyboard-routing.mjs` 15 组通过。控制器/Store 使用真实源码去类型执行，mock 限于事件、桥和宿主回调；覆盖原始修饰键、多个持有键失焦释放、快速重按、重复抑制与异步回退代次。C++ 检查是源码契约断言，不是原生执行测试；这些测试未发现空 Stack 的实机焦点问题。

配置为 Release / Unix Makefiles / Qt HarmonyOS arm64；原生目标为 stellarium：

```sh
cmake --build build --target stellarium --parallel 6
```

产物为 build/src/libstellarium.so。现有 sync 脚本复制到生成工程，再由 HAP 构建打包；仅运行 Hvigor 不会重编引擎。本文更新不执行构建、同步、设备操作或源码修改。

## 官方依据

- [支持焦点处理](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-common-events-focus-event)：焦点链祖先同时获焦；Text 可显式启用焦点；无交互的 Stack/Column 叶节点仅 focusable(true) 不能获焦。
- [按键事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-key)：按焦点链冒泡、布尔消费、metaKey 及 getModifierKeyState。
- [焦点控制](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-focus)：focusable/defaultFocus 与主动焦点请求。
- [键盘按键事件数据流](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-interaction-development-guide-keyboard)：输入法先于 onKeyEvent，本链路不注册抢先输入法处理。
- [uinput](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uinput)：按设备版本核对按键注入与修饰键保持能力；注入和真实键盘结果分别记录。
