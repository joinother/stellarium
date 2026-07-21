# Stellarium HarmonyOS 调试经验手册

给 WorkBuddy / TRAE / 后续接手者使用。  
日期：2026-07-22  
分支：`openharmony-preview-v1`

这份文档记录的是实战调试经验，不是最终产品说明。重点是帮助下一个人少绕路：先确认环境，再确认签名，再确认应用是否真的启动、是否真的渲染、ArkUI 是否真的把事件送到了 Qt/Stellarium。

## 1. 我是怎么使用 DevEco / 模拟器的

### 1.1 DevEco 主要用来做三件事

1. 管 SDK、模拟器和设备连接。
2. 兜底运行 GUI 的 Run/Debug 流程。
3. 提供项目自带的 Node、JBR、hvigor、hdc、hap-sign-tool。

我平时不依赖 GUI 点点点做主流程，而是用命令行复现，这样 WorkBuddy/Agent 能稳定记录每一步：

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos

env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

关键点：

- `NODE_HOME` 要指向 DevEco 自带 Node。
- `JAVA_HOME` 用 DevEco 自带 JBR。
- `OHOS_BASE_SDK_HOME` 目前优先用 `/Users/jiexuanyang/Library/OpenHarmony/Sdk`。
- 如果 `hvigorw --stop-daemon` 报 `NODE_HOME is not set`，先把上面环境变量 export 好再停 daemon。
- 如果 SDK 报“SDK management mode has changed”，先在 DevEco 的 SDK Manager 修 SDK；命令行硬刚通常浪费时间。

### 1.2 hdc 连接模拟器

```sh
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"

$HDC tconn 127.0.0.1:5555
$HDC list targets
```

注意：

- 在 Codex 沙箱里跑 `hdc` 可能出现 `Connect server failed`，但非沙箱/正常终端能连上。这不是 HAP 签名问题。
- `hdc shell hilog` 默认是流式阻塞，自动化脚本里容易卡死。短抓日志用 `hilog -x -m 300`。
- 安装后确认进程：

```sh
$HDC -t 127.0.0.1:5555 shell pidof org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 shell bm dump -n org.qtproject.example.stellarium
```

`bm dump` 里重点看：

- `appProvisionType`
- `fingerprint`
- `debug`
- `reqPermissions`
- `hapPath`

## 2. 我是怎么知道“必须签名”的

OpenHarmony/HarmonyOS 的 HAP 不是一个普通 zip 包。安装时 Bundle Manager 会验：

- HAP Signing Block 是否存在。
- 证书链是否能验证。
- profile/provision 是否匹配 bundle name。
- 设备上已有同 bundle 的签名 fingerprint 是否一致。

常见错误和含义：

| 现象 | 真实含义 | 处理 |
|---|---|---|
| `install sign info inconsistent` | 设备上已有同 bundle，但签名 fingerprint 不同 | 用同一套材料重签后覆盖，或卸载旧包 |
| `verify-app` 找不到 signing block | 这是 unsigned HAP 或签名过程没完成 | 重新跑 `hap-sign-tool.jar sign-app` |
| profile bundle-name 不匹配 | profile 不是给 `org.qtproject.example.stellarium` 的 | 换正确 profile |
| `keytool` 打不开 DevEco 字段 | `build-profile.json5` 里的字段不等于普通明文密码 | 不要把那串值直接喂给 `keytool` |

当前本机实测结论：

- `stellarium-app-cert-chain.cer` 是 `sign-app` 需要的 App 证书链。
- `stellarium-ca-release-profile.p7b` 是 release profile。
- `hap-sign-tool verify-app` 能通过。
- 当前模拟器 `127.0.0.1:5555` 接受这套 release profile，能安装并启动。

所以不要简单得出“模拟器只接受 debug profile，release profile 命令行必失败”的结论。至少当前环境不是这样。

详细命令见 `docs/harmonyos/SIGNING-GUIDE.md`。

### 2.1 安全注意

签名私钥、profile、真实密码都不应进入公开仓库。

当前仓库历史里曾经出现过签名材料和明文密码，接手者要按安全流程处理：

1. 轮换本地预览签名材料和密码。
2. 用 `git filter-repo` 或等价工具从历史中清理私钥/密码。
3. 强推前通知所有协作者重新基于新历史同步。
4. 清理后不要再把 `docs/harmonyos/signing/*.p12`、`.p7b`、真实密码提交；签名材料放仓库外，例如 `~/stellarium-signing/` 或 `/private/tmp/stellarium-oh-signing/`。

只改 `.gitignore` 不等于从 Git 历史或远程移除了已跟踪文件。

## 3. Qt / OpenHarmony 的调试总原则

这个移植的核心不是 ArkUI 单独跑，也不是 Qt 单独跑，而是：

```text
ArkUI 页面
  -> N-API libentry.so
  -> C++ 命令桥 hello.cpp
  -> libstellarium.so / Qt 主线程
  -> OpenGL ES / XComponent
```

排查顺序一定要分层：

1. HAP 是否签名并安装成功。
2. Ability 是否启动。
3. 进程是否还活着。
4. Qt 插件是否启动 main。
5. XComponent surface 是否创建。
6. `libstellarium.so` 是否渲染出非空帧。
7. ArkUI 触摸事件是否到正确层。
8. N-API 命令是否进 C++。
9. C++ 命令是否真的在 Qt 主线程执行。
10. 结果是否回到 ArkUI 状态。

任何一层错了，屏幕上都可能表现成“黑屏”“点不动”“卡住”，但根因完全不同。

## 4. 以前遇到的问题和解法

### 4.1 启动即 SIGABRT

现象：

- `aa start` 返回 success。
- `pidof` 很快没有进程。
- faultlog/hilog 里有 `Qt API was likely used before Qt initialization`。

根因：

- `hello.cpp::resolveStellariumCommand()` 在 ArkUI/JS 线程里主动 `dlopen("libstellarium.so")`。
- `libstellarium.so` 其实是 Qt 应用二进制，应该由 Qt for OpenHarmony 插件在专用 Qt 主线程加载。
- ArkUI 线程抢先加载，破坏 Qt 主线程上下文，触发 qFatal。

修法：

- `resolveStellariumCommand()` 只用 `RTLD_NOLOAD` 查已加载库。
- 库还没加载就返回“bridge not ready”，让 ArkUI 轮询等待。
- 不要在 ArkUI 线程首次加载 Qt 应用二进制。

验证：

- 启动后没有 SIGABRT。
- 日志先出现 Qt 插件启动，再出现 bridge resolved。
- 之后能看到 first framebuffer / frame stats。

### 4.2 启动命令投递死锁

现象：

- 应用不崩，能看到画面。
- 但 `getSkyCultures` / `setLanguage` / `getState` 一直 pending。
- ArkUI 重试几十秒后放弃。

根因：

- OHOS 版 Qt 由 native vsync / render pump 驱动渲染，不稳定依赖普通 Qt event loop。
- 原代码用 `QMetaObject::invokeMethod(..., QueuedConnection)` 投递到 Qt 线程，但队列没有被泵送。

修法：

- 在 `StelMainView.cpp` 做自己的跨线程命令队列。
- 在 `renderOhosFrameNow()` 顶部调用 `ohosDrainCommandQueue()`。
- 每帧在 Qt 主线程排空命令。

验证：

- 日志出现 `ohosDrainCommandQueue ran n=...`。
- ArkUI 启动重试会停止。
- `setLanguage`、`getState` 能拿到真实结果。

### 4.3 黑屏 / 只看到空画面

现象：

- Ability 启动成功。
- 进程还在。
- 屏幕黑，或者只有 UI 没星图。

排查：

```sh
$HDC -t 127.0.0.1:5555 shell hilog -x -m 300
$HDC -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/stel.jpeg
$HDC -t 127.0.0.1:5555 file recv /data/local/tmp/stel.jpeg /tmp/stel.jpeg
```

重点搜：

- `StellariumCpp`
- `StellariumArkUI`
- `submitted first Stellarium framebuffer`
- `frame stats lit=...`

判断：

- `lit=0` 或没有 first framebuffer：C++/GL/XComponent 渲染链路没通。
- 有 `lit>0` 但屏幕黑：可能是 framebuffer 提交、surface 尺寸或层级遮挡问题。
- 有 UI 没星图：优先看 XComponent 是否被 ArkUI 覆盖或尺寸为 0。

### 4.4 点一下就黑屏

现象：

- 启动时能看。
- 一触摸屏幕就黑屏或像卡死。

排查思路：

- 先区分是进程崩了，还是渲染仍在但 UI 状态遮挡。
- `pidof` 确认进程。
- `hilog -x -m 300` 看是否有 SIGABRT、native crash、JS crash。
- 看触摸日志是否把 UI 点击误当成 sky touch。

曾经的问题：

- ArkUI 全屏父容器挂 `onTouch(handleSkyTouch)`，子按钮事件被父容器吞掉。
- 点工具栏本应打开面板，却被当成星图点击，进而触发 `selectAt`。

修法：

- 把星图触摸层做成根 `Stack` 的平级兄弟层。
- UI 面板/按钮层不挂全局 `onTouch`。
- 空白区域通过透明触摸层转发给星图。

### 4.5 UI 按钮点不了 / 搜索框输不进字

现象：

- 工具栏图标没有反应。
- 搜索框无法输入或输入后没候选。
- 面板按钮 `刷新/居中/追踪` 无反应。

根因：

- 大屏布局 `expandedShell()` 的父容器挂了全屏 `onTouch`，导致子组件 `onClick` 被抑制。
- 这和 C++ 命令缓存问题不同：这里是 ArkUI 事件根本没触发。

验证：

- 点按钮时日志应该出现 `setPanel search/time/place/layers/object/settings`。
- 如果出现的是 `sky touch down`，说明仍然被星图触摸层误吃。

修法：

- `expandedShell` 父容器移除 `onTouch`。
- 在 `build()` 根 `Stack` 下放独立透明 sky touch 层。
- 不要给按钮容器乱加 `HitTestMode.Block`，它可能让容器自身 onClick 失效。

### 4.6 选星 / 搜索要双击才有结果

现象：

- 第一次点星只 pending。
- 第二次才显示第一次的结果。
- 搜索也像延迟一拍。

根因：

- C++ 侧命令结果缓存是 per-key 永久缓存。
- 首次交互命令入队后，结果被留在 cache 里；下次请求才读到旧结果。

修法：

- 把永久 cache 改成 consume-on-read 结果仓库。
- 高频视图命令 `zoomBy/dragView/panBy` 用 fire-and-forget 快速通道。
- ArkUI 侧所有需要返回值的交互命令走 `callInteractive()`，按 50ms 轮询直到 `ok:true`。

验证：

- 单次 tap 就能 `selectAt found=1`。
- 搜索候选点击后能在 150ms 左右更新详情。

### 4.7 拖动卡、上下/左右方向奇怪

现象：

- 手指拖动星图，画面变化滞后。
- 方向和直觉相反。
- 拖动时 UI 卡顿。

处理原则：

- 不要让每个 move 事件都等待 C++ 同步返回。
- `dragView` / `panBy` 必须 fire-and-forget。
- ArkUI 只做轻量节流和手势解释，重计算留给 Qt 渲染帧。
- 方向是否反，需要在 `handleSkyTouch` 和 `StelMovementMgr` 语义之间统一，不要一边 ArkUI 反向、一边 C++ 再反向。

后续建议：

- 给拖动加最小位移阈值和节流，例如 16ms 或每帧一次。
- 双指缩放只发送缩放倍率，不等待返回。
- 在文档里记录“手指拖动天空”的产品语义：手指向右拖时，是天空跟手移动，还是视角向右转。

### 4.8 目标详情不刷新

现象：

- 选中天体后，详情面板有内容。
- 过一段时间高度/方位不变，看起来像死数据。

根因：

- 详情面板最初只是选中瞬间快照。
- 后来即使加了刷新，ArkUI `@Builder` 参数按值捕获，传进去的文本不会跟随 `@State` 更新。

修法：

- 目标详情打开且有选中对象时，每秒拉 `getSelectedObjectInfo`。
- 详情行直接绑定 `@State`，不要把动态文本作为 `@Builder` 参数传入。
- 高度/方位显示用更细精度，例如度分，避免 0.1 度太粗看不出变化。

### 4.9 旋转 / 窗口比例变化

现象：

- 横竖屏或窗口尺寸变化后，UI 比例不对。
- 面板遮挡星图。
- 触摸坐标偏移。

已有机制：

- `skyWidth >= 900` 走 expandedShell。
- `skyWidth < 900` 走 compactShell。
- `onAreaChange` 更新 `skyWidth/skyHeight`。

接手者要继续测：

- 横屏 Pad 模拟器。
- 竖屏窄屏。
- 运行中旋转。
- 改窗口大小。

验证重点：

- 工具栏/底部 Dock 是否还可点。
- 星图空白触摸是否仍然 `selectAt`。
- `selectAt` 传给 C++ 的坐标是否和实际屏幕一致。
- 状态栏/底部手势条是否沉浸，是否占用内容区域。

## 5. ArkTS / ArkUI 经验

本项目 ArkTS 需要格外保守：

- `@Builder` 里不要写复杂局部变量。
- 组件链式属性要放在容器闭合 `}` 后。
- 动态 UI 文本优先直接绑定 `@State`。
- `onTouch` 不要挂在全屏 UI 父容器上。
- 图标和点击热区要用固定尺寸，避免触摸范围漂移。
- 修改 `harmonyos/ets-source/...` 后，记得同步到 `build/libstellarium-harmonyos/entry/src/main/ets/...`，否则构建用的可能不是你改的那份。
- 不确定 ArkTS 语法时，先查 DevEco Code skill 或跑 DevEco 编译，不要凭 TypeScript 经验硬写。

常见编译坑：

- `Row` 不支持某些 Web/TS 直觉里的属性。
- `Blank()` 只能放在合适容器里。
- ArkTS 对结构类型、索引访问、可选字段比普通 TS 更严格。
- `@Builder` 的参数捕获容易让显示“看似不更新”。

## 6. C++ / Qt 经验

关键文件：

- `src/StelMainView.cpp`
- `src/StelMainView.hpp`
- `build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp`
- `harmonyos/cpp-source/hello.cpp`

原则：

- Qt/Stellarium 对象只在 Qt 主线程访问。
- ArkUI/N-API 线程不要直接触碰 Qt API。
- 跨线程命令不要依赖普通 Qt event loop。
- 高频交互命令不要同步阻塞。
- 每次改 `src/StelMainView.cpp` 后需要重编 `libstellarium.so`，再确保打包目录里的 `.so` 是新的。

重编 C++ 后检查：

```sh
cmake --build /Users/jiexuanyang/stellarium-src/build --parallel
```

如果只改 ArkTS：

- 通常只跑 `hvigorw assembleHap` 即可。
- 不要随手跑 `harmonydeployqt`，它可能覆盖 `.ets` 改动。

## 7. 推荐验证清单

每次改完至少做：

1. `hvigorw assembleHap --no-daemon`
2. `hap-sign-tool verify-app`
3. `hdc install -r`
4. `aa start`
5. `pidof org.qtproject.example.stellarium`
6. 截图确认非黑屏。
7. 点 6 个工具栏按钮。
8. 搜索 `Jupiter` 并选中。
9. 点星图空白处确认 `selectAt`。
10. 拖动星图确认不卡死。
11. 打开目标详情等待 10 秒，看高度/方位是否变化。
12. 改窗口比例或旋转后重复按钮/星图触摸。

## 8. 接手者优先看哪里

建议顺序：

1. `docs/harmonyos/AGENTS.md`
2. `docs/harmonyos/SIGNING-GUIDE.md`
3. 本文档
4. `docs/harmonyos/KNOWN-ISSUES.md`
5. `docs/harmonyos/CHANGELOG.md` 最新几条
6. `harmonyos/ets-source/pages/MainWindowNativeNode.ets`
7. `src/StelMainView.cpp`
8. `build/libstellarium-harmonyos/entry/src/main/cpp/hello.cpp`

不要只看屏幕现象猜问题。这个项目里“黑屏”“点不了”“没反应”至少曾经对应过四类完全不同的根因：签名/安装、Qt 初始化、命令投递、ArkUI 命中测试。
