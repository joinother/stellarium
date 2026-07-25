# 交接文件：程序化音乐生成系统（模仿 Sky Guide）

> 写给 TRAE / 下一个接手者。读完此文件你应能继续完成构建、安装、验证、提交。

---

## 一、任务目标

模仿 Sky Guide 的音乐系统，给 Stellarium 鸿蒙版加一套程序化（生成式）音乐：

1. **打开应用就开始播放**空灵氛围音乐（不依赖任何音频文件，纯 PCM 实时合成）。
2. 空灵但不乏味：背景是缓慢飘动的和弦 pad + 偶尔远处星星眨眼声 + 反馈延迟混响。
3. **每点击一个新天体就"叮"一声**，根据天体特点决定音高/音色/音量：
   - 恒星：越热（温度高）音越高，越亮（星等小）音量越大（和 Sky Guide 一致）。
   - 行星/月亮/太阳/星云/星系/星团/彗星/小行星/星座：各有自己的"声线"。
4. 左侧栏加一个音符开关按钮，可随时静音（默认开）。

---

## 二、已完成的工作（代码全部写完）

### 2.1 C++ 端：`src/StelMainView.cpp`（已改，.so 已重编）

**新增辅助函数** `ohosTemperatureFromSpType()`（约 line 694）：
- 输入光谱型字符串（如 "A1V"），输出估算表面温度(K)。
- O型=30000K, B=20000K, A=8750K, F=6750K, G=5600K, K=4450K, M=3500K, W(Rayet)=50000K, C(碳星)=4200K 等。
- 亚型号数字（0最热→9最冷）在本型带宽内做线性微调。

**新增三个 JSON 字段**（在 `selectedObjectJson()` 里，constellation 块之后）：
- `objectType`：英文类型（`object->getObjectType()`），如 "Star"、"Planet"。
- `spType`：光谱型（从 `getInfoMap()["spectral-class"]` 取），如 "G2V"。
- `temperatureK`：由光谱型推算的温度。

> 注意：`getSkyCultures` 命令也顺带加了诊断字段（count/currentId/installDir/userDir/searchPaths/skyculturesModernIndex），这是之前渲染修复遗留的，不要动。

### 2.2 新文件：`harmonyos/ets-source/pages/StellariumAudio.ets`（485 行，已写完）

完整的程序化音乐引擎，核心类 `AudioEngine`（单例）：

**架构**：
- 使用 `@kit.AudioKit` 的 `audio.AudioRenderer`，回调模式（`RENDERER_MODE_CALLBACK`），48kHz 单声道 16bit PCM。
- 实时合成在 `writeData` 回调里跑（音频线程，不要碰 UI）。

**背景 pad（空灵底噪）**：
- 3 个 Pad 振荡器，每个有基频 + 微失谐(second oscillator) + LFO 呼吸感。
- 每 3-7 秒 `rotatePad()` 让某个 pad 缓慢滑向五声音阶里的新音，制造"和弦在飘"。
- 每 7-16 秒 `triggerTwinkle()` 触发一个极轻高音"星星眨眼"。

**星体 chime（叮）**：
- `chimeForSelection(info: StellariumBridgeResponse)` 是对外接口。
- `specForObject()` 根据天体类型/温度/星等算出 ChimeSpec（freq/gain/decay/partials）。
- 恒星：温度对数映射→音阶高区，星等→音量。
- 其他类型：按类型定音区+泛音组合，用 hash 在音区内取确定音（同一天体每次声音一致）。
- 星座：叠 3 个音做柔和和弦。
- 最多 6 个 chime 同时响，超出覆盖最老的。

**混响**：两条反馈延迟（0.26s + 0.33s），低通滤波，湿声 50% 混入。

**音阶**：大调五声音阶 `[0,2,4,7,9]`，A3=220Hz 起，4 个八度共 20 个音。任意两音都不打架。

### 2.3 类型定义：`harmonyos/ets-source/pages/StellariumTypes.ets`（已改）

在 `StellariumBridgeResponse` 接口里新增 3 个可选字段：
```typescript
objectType?: string
spType?: string
temperatureK?: number
```

### 2.4 UI 接入：`harmonyos/ets-source/pages/MainWindowNativeNode.ets`（已改）

**import**：`import { AudioEngine } from './StellariumAudio'`

**新增 @State**：
- `musicEnabled: boolean = true`（默认开，打开应用即播放）
- `lastMusicToggle: number`（350ms 防抖，避免坐标命中+onClick 双触发）
- `panelIdleGlass: boolean`（上一轮 UI 改动的浅色毛玻璃状态，非本次新增但同在此 diff）

**aboutToAppear 启动**：
- 从持久化设置读 `musicEnabled`；若为 true 调 `AudioEngine.getInstance().start()`。

**选中天体时响铃**：
- 在 `applySelectedObject` 里，`if (isNewSelection)` 时调 `AudioEngine.getInstance().chimeForSelection(result)`。

**左侧栏音乐按钮**：
- `@Builder musicButton()`：44×44 圆角，音符 ♪ 图标，开着时亮蓝色+微放大，静音时暗灰。
- 位置：左侧栏底部，在收起按钮下方 52vp。
- 坐标命中：在 `handleUiTap` 和 `handleOverlayTouch`(downY 分支) 两处都加了 `musicTop` 坐标判定。
- `toggleMusic()`：防抖→翻转 musicEnabled→start/setMuted→persist→flashHint 中文提示。

**持久化**：
- `persistMusicEnabled()`：写入 `AppStorage('stellariumSettings')` 的 `musicEnabled` 字段。
- 设置保存/恢复已接入（`saveSettings`/`aboutToAppear` 均已改）。

> 注意：`flashHint` 用的是中文字面量 `'音乐：开 ♪'` / `'音乐：静音'`，不是 `$r()` 资源引用——因为 `i0111` 已被占用，避免改 6 个语言资源文件。

### 2.5 文件同步状态

所有改动已从 `harmonyos/ets-source/` 同步到 `build/libstellarium-harmonyos/entry/src/main/ets/`：
- `MainWindowNativeNode.ets` ✓ synced
- `StellariumTypes.ets` ✓ synced
- `StellariumAudio.ets` ✓ synced（新文件）

### 2.6 .so 编译状态

- `build/src/libstellarium.so` 已于 22:17 重编成功（含 C++ 新字段）。
- 已拷贝到 `build/libstellarium-harmonyos/entry/libs/arm64-v8a/libstellarium.so`。
- 旧缓存已清理。

---

## 三、未完成的工作（TRAE 需要做的）

### 3.1 重新打包 HAP（最重要！）

**当前 HAP 是 22:01 的，但 .so 是 22:17 重编的——HAP 里装的是旧 .so，不含 C++ 新字段！**

```bash
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos && \
env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
    JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
    OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
    PATH="$NODE_HOME/bin:$PATH" \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
    assembleHap --no-daemon --mode module -p product=default
```

输出：`entry/build/default/outputs/default/entry-default-signed.hap`

**可能遇到的编译问题**：
- ArkTS 严格模式：不允许内联对象字面量当类型（`arkts-no-obj-literals-as-types`）。如果报错，把对应类型抽成 named interface。
- `StellariumAudio.ets` 里的 `type { StellariumBridgeResponse }` 导入用的是 `import type`——如果 ArkTS 不支持，改成普通 `import { StellariumBridgeResponse } from './StellariumTypes'`。
- 如果 `audio.AudioRendererInfo` 的 `rendererFlags` 报类型不匹配，改成 `rendererFlags: 0 as number`。
- 如果 `writeData` 回调返回值类型不对，检查 `AudioDataCallbackResult` 的字段名。

### 3.2 安装到模拟器

```bash
# hdc 全路径（不在 PATH 上）
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc

# 连接模拟器（已连接会报 repeat operation，正常）
$HDC tconn 127.0.0.1:5555

# 安装
$HDC -t 127.0.0.1:5555 install -r \
  /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap

# 启动
$HDC -t 127.0.0.1:5555 shell "aa start -b org.qtproject.example.stellarium -a QAbility"
```

### 3.3 验证

**验证音频引擎启动**：
```bash
$HDC -t 127.0.0.1:5555 shell hilog -r   # 清日志
# 等几秒让应用启动
$HDC -t 127.0.0.1:5555 shell hilog -x | grep -i "StellariumAudio"
# 期望看到：audio engine started
```

**验证点选天体响铃**：
```bash
# 用 uitest 点击一个天体（需要先 dump 布局找坐标）
$HDC -t 127.0.0.1:5555 shell hilog -r
# 点击天体...
$HDC -t 127.0.0.1:5555 shell hilog -x | grep -i "StellariumAudio"
# 期望看到：muted = false（如果之前没静音）
```

**验证音乐开关按钮**：
- 左侧栏底部应该有一个 ♪ 图标按钮。
- 点击应弹出 flashHint "音乐：开 ♪" 或 "音乐：静音"。
- 如果点击不生效，检查坐标命中：按钮位于 `RAIL_TOP_PAD + pinnedActions.length * 58 + 112`（vp），密度 2 换算成 px 要 ×2。

### 3.4 Git 提交

所有改动当前都是未提交状态（`git status` 显示 modified/untracked）：
```
 M harmonyos/ets-source/pages/MainWindowNativeNode.ets
 M harmonyos/ets-source/pages/StellariumTypes.ets
 M harmonyos/ets-source/qability/StellariumResourceBootstrap.ets  (上一轮渲染修复)
 M src/StelMainView.cpp
?? harmonyos/ets-source/pages/StellariumAudio.ets
?? scripts/sync-ohos-resources.sh  (上一轮渲染修复)
```

建议分两个 commit：
1. 渲染修复：`StellariumResourceBootstrap.ets` + `scripts/sync-ohos-resources.sh` + `StelMainView.cpp` 里 `getSkyCultures` 诊断字段
2. 音乐系统：`StellariumAudio.ets` + `StellariumTypes.ets` + `MainWindowNativeNode.ets` + `StelMainView.cpp` 里温度推算/三字段

---

## 四、关键注意事项

### 4.1 MainWindowNativeNode.ets 有两批未提交改动

这个文件的 diff 包含**两批改动**：
1. **上一轮 UI 改进**（已完成验证）：`RAIL_TOP_PAD` 搜索图标居中、钉子→收起按钮(`collapseButton`)、空闲浅色毛玻璃(`panelIdleGlass`)。
2. **本轮音乐系统**：`import AudioEngine`、`musicEnabled` 状态、`aboutToAppear` 启动、`applySelectedObject` 响铃、`musicButton()` builder、`toggleMusic()`、`persistMusicEnabled()`、坐标命中分支。

两批改动在同一 diff 里，提交时可以一起提。

### 4.2 ic_forward 图标已存在

`collapseButton()` 用的是 `ic_forward.svg` 旋转 180° 做向左箭头。这个 SVG 已在 `entry/src/main/resources/base/media/ic_forward.svg`，不需要新增资源。

### 4.3 音乐按钮没有用 $r() 资源引用

`toggleMusic()` 里的 `flashHint` 直接传中文字符串（`'音乐：开 ♪'` / `'音乐：静音'`），不是 `$r('app.string.xxx')`。这是故意避开 `i0111` 键冲突。如果要规范化，需在 6 个语言的 `string.json` 里加新键。

### 4.4 AudioRenderer 回调线程安全

`render()` 在音频回调线程跑。代码里没有碰任何 UI 状态或 ArkTS `@State`，全部操作都在引擎内部成员变量上。`chimeForSelection()` 由 ArkTS 主线程调用，只写 `Chime.active=true` 等简单标志，音频线程读取——这种"单写多读"在 JS 引擎里是安全的（单线程事件循环，不会有真竞态）。

### 4.5 模拟器可能没有音频输出

本地 Device Simulator 不一定有真实音频设备。如果 `AudioEngine.start()` 失败，hilog 会打印 `audio engine start failed`。这不影响应用其他功能，只是没声音。真机上应该正常。

### 4.6 构建命令的环境变量

必须设置 `NODE_HOME`、`JAVA_HOME`、`OHOS_BASE_SDK_HOME`、`PATH`，否则 hvigor 会找不到 node/jdk/sdk。完整命令见 3.1 节。

---

## 五、文件清单

| 文件 | 状态 | 改动内容 |
|------|------|----------|
| `src/StelMainView.cpp` | Modified | +温度推算函数 +3个JSON字段 +getSkyCultures诊断字段 |
| `harmonyos/ets-source/pages/StellariumAudio.ets` | **New** (485行) | 程序化音乐引擎 |
| `harmonyos/ets-source/pages/StellariumTypes.ets` | Modified | +3个可选字段 |
| `harmonyos/ets-source/pages/MainWindowNativeNode.ets` | Modified | +音乐import/状态/启动/响铃/按钮/开关/持久化 +上轮UI改进 |
| `harmonyos/ets-source/qability/StellariumResourceBootstrap.ets` | Modified | (上轮渲染修复，skycultures重解压) |
| `scripts/sync-ohos-resources.sh` | **New** | (上轮渲染修复，资源同步脚本) |

---

## 六、快速恢复命令（复制粘贴可用）

```bash
# 1. 确认 .so 是最新的
ls -la /Users/jiexuanyang/stellarium-src/build/src/libstellarium.so
ls -la /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/libs/arm64-v8a/libstellarium.so

# 2. 确认 ets 已同步
diff /Users/jiexuanyang/stellarium-src/harmonyos/ets-source/pages/StellariumAudio.ets \
     /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/src/main/ets/pages/StellariumAudio.ets

# 3. 打包 HAP
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos && \
env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
    JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
    OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
    PATH="$NODE_HOME/bin:$PATH" \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
    assembleHap --no-daemon --mode module -p product=default 2>&1 | tail -40

# 4. 安装
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC -t 127.0.0.1:5555 install -r \
  /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap

# 5. 启动
$HDC -t 127.0.0.1:5555 shell "aa start -b org.qtproject.example.stellarium -a QAbility"

# 6. 查音频日志
$HDC -t 127.0.0.1:5555 shell hilog -r
sleep 5
$HDC -t 127.0.0.1:5555 shell hilog -x | grep -i "StellariumAudio"
```
