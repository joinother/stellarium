# Stellarium HarmonyOS 移植 — 项目交接文档

> **创建时间：** 2026-07-27
> **最后更新：** 2026-07-27
> **当前分支：** `openharmony-preview-v1`
> **当前状态：** 能构建、安装、启动；存在画面扭曲/模糊问题待修复；UI交互可用但backdropBlur值被降低后视觉效果需验证

---

## 1. 项目概况

将 [Stellarium](https://github.com/Stellarium/stellarium) 开源天文软件移植到 HarmonyOS NEXT 平台。

### 架构

```
ArkUI (MainWindowNativeNode.ets)  ← 用户交互层
    ↓ command bridge (JSON)
C++ Native (hello.cpp → StellariumOhos_command)
    ↓
Stellarium Core (StelMainView.cpp) ← 渲染/计算/选星/搜索
    ↓
OpenGL ES → XComponent → Framebuffer → PBO异步回读 → EGL显示
```

### 渲染管线（关键！）

1. Stellarium Core 在 Qt 主线程渲染到 FBO
2. `glBlitFramebuffer` 降采样到 50% 分辨率的回读 FBO
3. `glReadPixels` 到 PBO（异步，不阻塞）
4. 2帧后 `glMapBufferRange` 读取已完成 PBO 的像素数据
5. 像素数据通过 N-API 传给 ArkUI 的 XComponent
6. `hello.cpp::renderSubmittedFrame()` 用 OpenGL ES 纹理上传 + `eglSwapBuffers` 显示
7. VSync 已禁用（`eglSwapInterval(0)`），防止阻塞

---

## 2. 构建命令速查

### 2.1 生成 libs/（首次或 .so 丢失时）

```bash
/Users/jiexuanyang/Qt/6.12.0/macos/bin/harmonydeployqt \
  --input /Users/jiexuanyang/stellarium-src/build/src/stellarium-harmony-deployment-settings.json \
  --output /tmp/harmony-test --no-build
cp -r /tmp/harmony-test/entry/libs /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/libs
```

### 2.2 构建 HAP

```bash
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos

env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

### 2.3 重编 libstellarium.so（C++ 源码修改后）

```bash
CMAKE="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/build-tools/cmake/bin/cmake"
NINJA="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/build-tools/cmake/bin/ninja"

cd /Users/jiexuanyang/stellarium-src/build
$CMAKE --build . --parallel --target stellarium
```

然后重新运行 2.1 生成 libs/，再运行 2.2 构建 HAP。

### 2.4 安装启动（模拟器）

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
HAP="/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap"

$HDC tconn 127.0.0.1:5555
$HDC -t 127.0.0.1:5555 shell bm uninstall -n org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 install -r "$HAP"
$HDC -t 127.0.0.1:5555 shell hilog -r
$HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

### 2.5 调试

```bash
# 拉日志
$HDC -t 127.0.0.1:5555 shell hilog -x | grep -E "Stellarium|StellariumArkUI|StellariumEntryGL"

# 截图
$HDC -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/ui.jpeg
$HDC -t 127.0.0.1:5555 file recv /data/local/tmp/ui.jpeg /tmp/ui.jpeg
```

---

## 3. 核心文件索引

| 文件 | 用途 | 备注 |
|------|------|------|
| `src/StelMainView.cpp` | C++ 渲染核心 + 命令桥 | PBO回读、FBO降采样、命令队列都在此 |
| `build/.../cpp/hello.cpp` | N-API 命令入口 + EGL显示 | eglSwapInterval(0) 在此 |
| `build/.../ets/pages/MainWindowNativeNode.ets` | **最核心ArkUI文件** (~10000行) | 所有UI布局、触摸、面板 |
| `build/.../ets/pages/StellariumTypes.ets` | 类型定义 + 中文别名表 | StellariumBridgeResponse 接口 |
| `build/.../ets/pages/I18n.ets` | 国际化模块 | 21语言支持 |
| `build/.../ets/pages/StellariumAudio.ets` | 音频引擎 | 天体音效 + 背景音乐 |
| `build/.../ets/qability/StellariumResourceBootstrap.ets` | 资源提取 | 首次启动从rawfile提取Stellarium数据 |
| `AppScope/resources/base/media/app_icon.png` | 应用图标 | 原版Stellarium图标 |
| `entry/.../resources/base/media/foreground.png` | 自适应图标前景 | 原版Stellarium图标 |
| `entry/.../resources/base/media/background.png` | 自适应图标背景 | 纯深色 #05070F |
| `entry/.../resources/base/element/color.json` | 颜色资源 | start_window_background=#05070F |

---

## 4. 已完成功能清单

### 核心功能
- ✅ 星图渲染（OpenGL ES + PBO异步回读，61 FPS）
- ✅ 触摸选星（单次点击即选中）
- ✅ 搜索（中英文/拼音模糊匹配 + 候选列表）
- ✅ 时间控制（23种天文时间单位 + DatePicker/TimePickerDialog）
- ✅ 位置设置（城市列表 + GPS + 世界地图选点）
- ✅ 图层控制（70+ toggle，7个tab）
- ✅ 天体详情（结构化展示 + 自动刷新）
- ✅ 多语言（21语言，8种完整翻译）
- ✅ 星图文化切换
- ✅ 观测列表/书签
- ✅ 脚本播放
- ✅ 插件动态加载
- ✅ 天文计算（9个tab：RTS/年历/行星位置等）
- ✅ 截图
- ✅ 陀螺仪（reticle风格按钮 + 灵敏度选择 + 轴映射修正）
- ✅ 音频引擎（天体音效 + 背景音乐 + 卫星音效优化）
- ✅ 今夜天象（月相 + 太阳/暗夜窗口 + 行星升降 + 流星雨 + 卫星）
- ✅ 夜间模式
- ✅ FPS计数器（实时显示渲染帧率）

### UI设计
- ✅ expandedShell布局（左侧垂直工具栏 + 右侧浮动面板）
- ✅ compactShell布局（底部Dock + 底部面板）
- ✅ 果冻磨砂玻璃面板（rgba(10,14,26,0.55) + backdropBlur 45）
- ✅ 面板5秒空闲自动收起
- ✅ 品牌色钴蓝 #5B93BF
- ✅ 原版Stellarium应用图标
- ✅ 深空黑启动屏 #05070F
- ✅ 无emoji系统UI
- ✅ 三点菜单图标（替代方格UI）
- ✅ Swiper共享按钮行

---

## 5. 本次会话修改记录（2026-07-27）

### 5.1 性能优化（C++ + ArkTS）
- **定时器清理**：`aboutToDisappear()` 中补充清理 `twTimer`、`fpsTimer`、`hintTimer`、`locSearchDebounce`、`panelIdleTimer`、`sidebarAutoCollapseTimer`
- **FPS轮询降频**：从 500ms 延长到 5000ms，移除内嵌 `setTimeout` 重试
- **C++命令队列保护**：添加 256 条上限，队列过大时丢弃新命令；使用 `swap` 零拷贝优化批处理
- **C++队列零拷贝**：`ohosDrainCommandQueue()` 中 `batch = s_ohosCmdQueue; s_ohosCmdQueue.clear();` 改为 `batch.swap(s_ohosCmdQueue);`

### 5.2 面板拖拽双限位弹簧效果
- 底部面板 `PanGesture` 重构：
  - `onActionUpdate`：90%以上施加弹性阻力（overscroll，每多拉1%只显示0.3%）
  - `onActionEnd`：基于 velocity + position 双判断实现三段式限位（0% / 60% / 90%）
  - 三个限位点之间无中间停留位置，轻轻一蹭即滑到下一个限位
  - 全部使用 `springMotion(0.36, 0.72)` 弹簧动画

### 5.3 渲染分辨率限制（C++）
- `renderOhosFrameNow()` 中添加 `MAX_RENDER_SHORT_SIDE = 800` 上限，防止窗口 resize 或获取到错误尺寸时分辨率暴增
- Qt paint 路径同步添加相同 viewport 限制，防止双路径渲染不一致导致画面扭曲
- `OHOS_RENDER_SCALE` 从 0.6 降至 0.5
- `READBACK_SCALE` 从 0.5 降至 0.4

### 5.4 UI调整
- 紧凑布局详情卡片位置：`skyHeight - 280` → `skyHeight - 380`（防止遮挡Dock）
- `isExpandedLayout` 判断：`this.skyWidth >= 900` → `px2vp(this.skyWidth) >= 900`（修复px/vp单位错误）
- Swiper 高度：`130` → `200`，底部 padding：`18` → `50`（防止indicator遮挡内容）
- 大量 `backdropBlur` 值降低（30→16, 40→10, 26→14, 22→12, 35→18, 20→10）
- 流星雨插件默认提示消息已注释掉（`displayMessage(q_("Using the default Meteor Showers catalog."), "#bb0000")`）

---

## 6. 当前已知问题（⚠️ 高优先级）

### 6.1 画面扭曲/模糊（用户反馈最强烈）
- **现象：** 星图画面扭曲、模糊，操作卡顿
- **可能原因：**
  1. `OHOS_RENDER_SCALE=0.5` + `READBACK_SCALE=0.4` 导致渲染分辨率过低（有效分辨率可能只有原始尺寸的20%）
  2. 双渲染路径（Qt paint 路径 和 `renderOhosFrameNow` 路径）viewport 不一致（已尝试修复，但效果不佳）
  3. `MAX_RENDER_SHORT_SIDE=800` 在高分屏上可能过于保守
- **建议修复方向：**
  - 逐步提高 `OHOS_RENDER_SCALE` 和 `READBACK_SCALE`，找到清晰度与性能的平衡点
  - 验证 Qt paint 路径的 viewport 限制是否真的生效（查看 hilog 中的 `PAINT_VIEWPORT` 和 `FIXED_VIEWPORT` 日志）
  - 检查 `pixelRatio` 值（模拟器上可能是 3.5），确保渲染分辨率计算正确
  - 考虑完全禁用 Qt paint 路径，只保留 `renderOhosFrameNow` 单一路径

### 6.2 Swiper 指示器遮挡内容
- **现象：** 星体详情卡片的 Swiper 分页点（三个点）挡住显示内容，且挡住下方UI
- **当前尝试：** Swiper 高度从 130 增至 200，底部 padding 从 18 增至 50，Column 底部 padding 从 20 增至 50
- **建议修复方向：**
  - 进一步增加 Swiper 底部 padding 到 60+，或完全隐藏 indicator（`.indicator(false)`）
  - 将操作按钮行移到 Swiper 外部上方，而非下方
  - 考虑将 Swiper 改为 Scroll + Tab 的方式，避免分页指示器

### 6.3 backdropBlur 降低后的视觉效果
- **现象：** 本次会话将大量 `backdropBlur` 值从 30-40 降低到 10-16，UI 磨砂玻璃效果可能变弱
- **用户偏好：** 要求果冻质感磨砂玻璃（opacity 0.65, backdropBlur 30-45）
- **建议修复方向：**
  - 验证当前 blur 值是否满足用户要求，如不满足需恢复至原值或中间值
  - 注意：backdropBlur 过高在低端设备上可能导致卡顿

### 6.4 手机/平板UI混淆风险
- **现象：** 用户在紧凑布局（手机）下看到 expandedShell 元素，或反之
- **当前修复：** `isExpandedLayout = px2vp(this.skyWidth) >= 900`
- **建议：** 每次修改UI后，分别在模拟器横屏（平板）和竖屏（手机）模式下验证布局

### 6.5 长时间运行后变卡
- **现象：** 运行数小时后应用变卡
- **已尝试修复：** 定时器清理、FPS降频、C++队列保护
- **未验证：** 上述修复是否真正解决了问题，需要长时间运行测试

---

## 7. 待完成任务

### 上架前必须完成
- [ ] 包名规范化（org.qtproject.example.stellarium → org.stellarium.app）
- [ ] 隐私政策页面创建并托管
- [ ] 华为发布证书申请
- [ ] Release签名配置
- [ ] 至少3张截图（Pad横屏 2340×1080）
- [ ] 应用描述（中英文）
- [ ] GPLv2许可证声明
- [ ] 内容分级：所有人
- [ ] 应用体积评估（当前460MB，考虑星表按需下载）
- [ ] Release HAP构建并签名

### 功能完善
- [ ] 华为加载页替换为自定义图片（用户已提供图片）
- [ ] 书签系统完善
- [ ] 视频录制
- [ ] 天体轨迹回放
- [ ] 配置导入导出
- [ ] DSO星表过滤
- [ ] 完整AstroCalc数据计算
- [ ] Satellites插件完善
- [ ] TTS语音播报（需HMS SDK）

### 已知小问题
- [ ] 陀螺仪真机测试
- [ ] 中文星名真机验证
- [ ] LX200扩展

---

## 8. 关键技术决策记录

### 8.1 渲染管线：PBO异步回读
- **问题：** glReadPixels同步阻塞34ms/帧，导致8 FPS
- **方案：** 3个PBO轮换，Frame N发出读取到PBO[N%3]，2帧后映射PBO[(N-2)%3]
- **效果：** 回读时间34ms→1ms，总帧率8 FPS→61 FPS

### 8.2 VSync禁用
- **问题：** eglSwapBuffers因VSync阻塞，帧率限制在20 FPS
- **方案：** eglSwapInterval(display, 0)
- **权衡：** 星图内容缓慢移动，撕裂不明显；性能提升远大于撕裂影响

### 8.3 FBO降采样
- **问题：** 全分辨率回读数据量过大
- **方案：** glBlitFramebuffer降采样到50%后再回读
- **效果：** 减少64%数据量，画质损失可接受

### 8.4 命令桥：渲染泵驱动
- **问题：** Qt事件循环在OHOS渲染模式下不被泵送，跨线程命令无法执行
- **方案：** renderOhosFrameNow()每帧排空命令队列 ohosDrainCommandQueue()
- **效果：** 命令保证在Qt主线程执行

### 8.5 触摸路由：兄弟画布层
- **问题：** 全屏父Stack的onTouch吞掉子组件onClick
- **方案：** onTouch挂到独立兄弟Stack，UI父容器只保留Transparent
- **效果：** UI按钮onClick和天空触摸互不干扰

### 8.6 抽屉触摸穿透
- **问题：** 抽屉面板与缩放按钮在同一层级，点击穿透
- **方案：** 抽屉打开时用条件渲染完全隐藏缩放按钮
- **效果：** 彻底消除穿透

---

## 9. 仓库结构

```
origin  → Stellarium/stellarium      (上游，只读，不可推)
myfork  → joinother/stellarium       (个人 fork，可推可改）
分支    → openharmony-preview-v1     (HarmonyOS 移植开发分支）
```

- 所有提交只推 `myfork`，不向上游提 PR
- GPLv2 合规：保持 fork 仓库公开，应用描述附源码链接

---

## 10. 版本管理策略

- **开发版（联网版）：** `openharmony-preview-v1` 分支，包含全部功能
- **上架版（不联网版）：** 计划从开发版分出 `harmonyos-release` 分支，编译时通过 product 配置关闭联网功能
- 个人开发者无ICP备案，上架版本不能有联网功能（需移除星表下载、卫星TLE更新等）

---

> **新Agent接手请先读：** `AGENTS.md` → `HANDOFF.md`（本文）→ `CHANGELOG.md` → `KNOWN-ISSUES.md`
