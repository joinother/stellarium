# Stellarium HarmonyOS 移植交接文档

日期：2026-07-20  
项目路径：`/Users/jiexuanyang/stellarium-src`  
HarmonyOS 工程路径：`/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos`

> 状态更新：本文记录的是 `89d0750` 之前的故障交接状态。用户已在 `89d075087614b62e40e9ddfbdb27778e9c8829aa` 规范化并推进修复。当前状态请优先读同目录下的 `Stellarium-HarmonyOS-当前工作整理-89d0750.md`，以及仓库内 `/Users/jiexuanyang/stellarium-src/docs/harmonyos/AGENTS.md`、`CHANGELOG.md`、`KNOWN-ISSUES.md`。

## 当前目标

把 Stellarium 开源核心移植成一个在 DevEco HarmonyOS 模拟器/Pad 上基本可用的单 HAP 应用。当前已经能启动并渲染星图，但触摸 UI、目标详情、横竖屏适配和整体体验还没有达到可发布状态。

## 当前真实状态

- 应用可以构建、签名、安装、启动。
- 星图画面能显示，C++/Qt 核心通过 OpenHarmony native frame bridge 输出到 ArkUI/XComponent。
- 已尝试加入 ArkUI 外壳 UI：搜索、时间、位置、图层、目标详情、设置。
- 已加入一部分真实功能桥接：
  - 搜索天体：`searchObject`
  - 点击选择：`selectAt`
  - 拖动星图：`dragView`
  - 双指缩放：`zoomBy`
  - 时间速率：`setTimeRate`
  - 图层开关：`setActionChecked`
  - 获取当前位置/手动坐标选择：ArkUI 位置面板 + `setLocation`
  - 陀螺仪平移：ArkUI sensor + C++ `panBy`
  - LX200 GoTo/Sync/Stop：TCP 公共协议实现
- 最近一次构建通过，但最后一处触摸路由改动尚未重新构建/安装验证。

## 最紧急故障

### 1. ArkUI 可见但点击无效

用户反馈：“这些 UI 都点不了。”

我验证到：

- `uitest dumpLayout` 里按钮确实显示为 `clickable: true`。
- 但真实点击后面板没有切换。
- 日志里没有 `StellariumArkUI: setPanel place`。
- 早先版本点击侧边栏会被当成星图触摸，日志出现 `sky touch down` / `dragView` / `selectAt`。

原因判断：

- 当前结构是 ArkUI 外壳叠在 Qt/XComponent 之上。
- 如果顶层 Stack 挂全屏 `.onTouch`，按钮原生 `onClick` 会被吞，需要手写坐标路由。
- 如果顶层 Stack 设置 `HitTestMode.Transparent`，在模拟器里点击可能继续落到底层 XComponent，ArkUI 按钮收不到事件。
- 触摸事件的 `point.x/y` 在某些子组件上是局部坐标，不是屏幕坐标，导致 `isUiPoint()` 误判。
- 应使用 `point.windowX/windowY`，必要时 fallback 到 `screenX/screenY/x/y`。

最新未验证改动：

- 文件：`/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`
- 已把顶层 `harmonyShell()` 改回 `HitTestMode.Block`。
- 已恢复全局 `handleOverlayTouch()` 路由。
- 已把侧边栏命中从写死坐标改成根据 `skyHeight` 计算：
  - `buttonTop = Math.max(0, this.skyHeight - 724) + 30`
  - `step = 104`
  - 用 `actions[index].panel` 切换。
- 这一步还没有重新构建和安装验证。

下一步建议：

1. 先重新构建安装。
2. 点击侧边栏“位置”。
3. 看日志是否出现：`StellariumArkUI: overlay touch down ... ui=1` 和 `setPanel place`。
4. 如果仍失败，建议彻底改结构：不要同时依赖 ArkUI 原生 `onClick` 和全屏手写路由，改成一个明确的全屏 ArkUI 触摸分发器，所有 UI 交互都走同一套坐标系统。

### 2. 点击星图没有目标详情

用户反馈：“点击之后也没出现目标的详情，什么也没有。”

相关链路：

- ArkUI：`handleSkyTouch()` -> `selectAt`
- C++：`StellariumOhos_command("selectAt")`
- C++：`objectMgr->findAndSelect(core, x, y)`
- C++：`selectedObjectJson(core)`
- ArkUI：`applySelectedObject()`
- ArkUI：打开 `activePanel = 'object'`

已做改动：

- C++ `selectedObjectJson()` 已增加 `info` 字段，调用 Stellarium 自己的：
  - `object->getInfoString(core, StelObject::ShortInfo | Magnitude | AltAzi | Distance | Size | PlainText)`
- ArkUI `StellariumBridgeResponse` 已增加 `info?: string`
- 详情面板已显示 `selectedInfo`

风险：

- 如果 `selectAt` 的坐标仍然不对，点击星图仍会找不到对象。
- 如果 ArkUI 触摸被 UI 层吞掉，星图也收不到拖拽/点击。
- 需要统一坐标系，星图 native 侧很可能需要与实际 framebuffer/设备像素比对齐。

### 3. UI 风格不统一

用户明确指出：

- 设置是单独齿轮，不统一。
- 很多图标没摆正。
- UI 风格比较粗糙，不符合 HarmonyOS 设计感。

已做但未完整验证：

- 把设置入口并入 `actions` 数组，和搜索/时间/位置/图层/详情同级。
- 图标从 emoji/符号换成单字：`搜 / 时 / 位 / 层 / 详 / 设`，避免字体上下漂移。

仍需继续：

- 用真正的 HarmonyOS ArkUI 组件重新整理控件体系。
- 统一尺寸、间距、选中态、背景玻璃效果。
- 不建议继续用大量硬编码坐标模拟点击。
- 后续可以做成 Pad 横屏侧栏、手机/窄屏底部 Dock，两套响应式布局。

### 4. 横竖屏/比例变化未完成测试

用户指出：没有测试屏幕方向旋转、比例变化。

当前逻辑：

- `onAreaChange` 根据宽度判断：
  - `width >= 900` -> expanded layout
  - 否则 compact layout
- expanded 是左侧栏 + 右侧浮动面板。
- compact 是顶部状态 + 中间星图触摸区 + 底部 Dock + 底部面板。

风险：

- 面板尺寸仍有硬编码：
  - expanded panel 宽 `336`，maxHeight `430`
  - panel position/helper 仍使用 `panelLeft/panelRight/panelTop`
- 部分 `handleUiTap` 坐标命中是手写逻辑，旋转后容易错。
- `uitest uiInput` 坐标和 `dumpLayout` 坐标可能不是同一缩放单位，之前测试存在坐标不一致疑点。

需要补测试：

- 横屏 2880x1920
- 竖屏/窄屏
- 分屏或窗口大小变化
- 点击侧栏、底部 Dock、关闭按钮、面板内按钮、输入框
- 星图拖拽和双指缩放

## 已实现功能清单

- 单 HAP 方向。
- Immersive mode 尝试：
  - `QAbility.ets` 里用 `setSpecificSystemBarEnabled`
  - 构建警告：该 API 不是所有设备支持
- 星图渲染桥：
  - `StelMainView.cpp` 里 `submitOhosFramebuffer()`
  - `libentry.so` 里 `StellariumEntry_submitFrame`
- ArkUI 与 native 命令桥：
  - `entry/src/main/cpp/hello.cpp`
  - `command(name, payload)`
  - C++ 导出 `StellariumOhos_command`
- 位置：
  - 自动定位权限已加
  - 离线坐标选择器已加
  - 不依赖地图 API
- LX200：
  - 不复制商业/会员功能
  - 只实现公开 LX200 TCP 基础命令
- 陀螺仪：
  - ArkUI sensor 已接入
  - 用 `panBy` 驱动视角微动
  - 需要真机或支持传感器的模拟器继续测

## 未实现/不应实现的功能

- 安卓版/电脑版完整 GUI 未移植。
- 会员功能不能免费绕过，也不应该复制闭源商业功能。
- AR 功能未实现。
- 真地图选择未接入。当前只是离线经纬度 picker；如要接地图，需要确认地图 SDK、API Key、许可协议。
- 完整 GoTo 设备管理 UI 未实现，只是 LX200 host/port + 当前目标 GoTo/Sync/Stop。
- 天体详情还不是完整桌面版详情页，只是接入了 core 的 short info。
- 没有发布 GitHub；当前不建议发布，交互问题未收口。

## 关键文件

- `/Users/jiexuanyang/stellarium-src/src/StelMainView.cpp`
  - HarmonyOS frame bridge
  - native command bridge
  - select/search/location/time/layers/LX200/pan/zoom
- `/Users/jiexuanyang/stellarium-src/src/StelMainView.hpp`
  - HarmonyOS render pump 字段/方法声明
- `/Users/jiexuanyang/stellarium-src/src/core/StelMovementMgr.hpp`
  - 暴露或适配移动相关方法
- `/Users/jiexuanyang/stellarium-src/src/main.cpp`
  - HarmonyOS 启动/窗口相关改动
- `/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`
  - ArkUI 主界面
  - 当前触摸故障核心文件
- `/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp`
  - ArkUI -> native command bridge
- `/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/src/main/ets/qability/QAbility.ets`
  - ability 和沉浸式窗口设置
- `/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/src/main/module.json5`
  - 权限、ability 配置

## 构建命令

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos

env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

## 签名命令

```sh
/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java \
  -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  sign-app -mode localSign \
  -keyAlias stellarium-app-key -keyPwd "$STELLARIUM_SIGNING_PASSWORD" \
  -appCertFile /private/tmp/stellarium-oh-signing/stellarium-app-cert-chain.cer \
  -profileFile /private/tmp/stellarium-oh-signing/stellarium-ca-release-profile.p7b \
  -inFile /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-unsigned.hap \
  -signAlg SHA256withECDSA \
  -keystoreFile /private/tmp/stellarium-oh-signing/stellarium-app-keypair.p12 \
  -keystorePwd "$STELLARIUM_SIGNING_PASSWORD" \
  -outFile /private/tmp/stellarium-oh-signing/stellarium-ui-fix-signed.hap \
  -compatibleVersion 24 -signCode 1
```

## 安装启动命令

```sh
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc tconn 127.0.0.1:5555

/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 install -r /private/tmp/stellarium-oh-signing/stellarium-ui-fix-signed.hap

/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 shell aa force-stop org.qtproject.example.stellarium

/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 shell hilog -r

/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

## 验证命令

```sh
# 抓布局树
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 shell uitest dumpLayout

# 拉取布局树，文件名需要看 dumpLayout 输出
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 file recv /data/local/tmp/layout_xxxxx.json /private/tmp/stellarium_layout.json

# 点击位置按钮。注意：uitest 坐标可能和 dumpLayout 坐标有缩放差异。
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 shell uitest uiInput click 102 1478

# 看日志
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
  -t 127.0.0.1:5555 shell hilog -x
```

## 建议给 work buddy 的下一步

1. 不要先美化，先修 UI 点击。
2. 重新构建最新代码，验证 `handleOverlayTouch()` 日志。
3. 如果日志没有出现，说明 ArkUI 顶层仍没有收到触摸，要检查 XComponent/Stack hitTestBehavior 和 zIndex。
4. 如果日志出现但 `ui=0`，说明坐标系仍错，打印 `x/y/windowX/screenX` 对比。
5. 如果 `ui=1` 但没有 `setPanel place`，检查 `handleUiTap()` 的动态侧栏坐标。
6. 点击能切面板后，再测星图点击详情、拖动、缩放。
7. 最后再做横竖屏和 UI 设计统一。

## 当前结论

这个项目还不能发布第一版。  
它现在是“能跑起来并渲染星图的工程原型”，但不是“可用版本”。最需要接手的是触摸事件体系和响应式 UI，不是继续加新功能。

---

## 2026-07-20 TRAE 修改记录

### 修改 1：expandedShell() 触摸事件分发结构重构

**文件：** `entry/src/main/ets/pages/MainWindowNativeNode.ets`

**问题：** 全屏 `Column` 设置 `HitTestMode.Block` + `onTouch`，导致同层上部的 zoom 按钮、侧边栏等子组件的 `onClick` 被拦截，UI 点击无效。

**修复：**
- 移除全屏 Column 的 `onTouch`
- 添加底层 `Blank()` 作为星图触摸区，`HitTestMode.Block` + `onTouch` → `handleSkyTouch`
- 左侧 UI 栏父 `Stack` 改为 `HitTestMode.Transparent`，让空白区域穿透到 Blank
- zoom 按钮保持 `HitTestMode.Block` + `onClick`，正常接收点击
- observerBadge 父 Stack 改为 `HitTestMode.None`，让事件穿透到星图

**事件流：**
- 点击空白区域 → Blank(Block) → handleSkyTouch（拖拽/缩放/选星）
- 点击 zoom 按钮 → 按钮(Block) → onClick（放大/缩小）
- 点击 observerBadge → None → 穿透到 Blank → handleSkyTouch

### 修改 2：坐标系统一（px 单位）

**文件：** `entry/src/main/ets/pages/MainWindowNativeNode.ets`

**问题：** `onAreaChange` 返回的 `Area.width`/`height` 是 **像素值（px）**，而 `TouchObject.windowX`/`windowY` 是 **vp 值**。两者单位不一致导致 native 侧 `scaleX = viewportPixel / skyVp` 计算错误，选星坐标偏移。

**修复：**
- `touchWindowX()` 改为优先使用 `screenX`（px），fallback 到 `windowX`（vp）
- `touchWindowY()` 改为优先使用 `screenY`（px），fallback 到 `windowY`（vp）

### 修改 3：增强日志

**文件：** `entry/src/main/ets/pages/MainWindowNativeNode.ets`

- `handleSkyTouch` Down 事件日志增加坐标输出：`sky touch down at x,y sky=WxH`

### 下一步验证

1. 重新构建并安装
2. 验证 UI 按钮点击：zoom +/-、侧边栏按钮、底部 Dock
3. 验证星图触摸：拖拽、双指缩放、点击选星
4. 检查日志 `sky touch down at ...` 和 `selectAt payload: ...` 的坐标是否合理
5. 如仍有问题，检查 `isUiPoint()` 硬编码坐标是否需要调整
