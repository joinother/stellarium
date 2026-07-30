# 星象仪（Stellarium HarmonyOS）交接清单

> 更新：2026-07-30
>
> 接手目标：完成 AppGallery 驳回整改，稳定离线发布版，并建立可追溯的后续开发流程。
>
> **本文件优先级高于仓库内较早的 HANDOFF / COMPLIANCE / KNOWN-ISSUES 文档。** 那些文档记录了有价值的排障过程，但包含旧分支、旧包名、旧签名和“已验证”标记，不能直接当作当前状态。

## 0. 一分钟总览

| 项目 | 当前事实 |
| --- | --- |
| 工作目录 | `/Users/jiexuanyang/stellarium-src` |
| 当前分支 | `release/v1.0-offline-candidate` |
| 可推送远端 | `myfork` -> `https://github.com/joinother/stellarium.git` |
| 上游远端 | `origin` -> `https://github.com/Stellarium/stellarium`，只读，不推送 |
| 发布身份 | 中文名 `星象仪`，包名 `com.joinother.skyinstrument` |
| 发布定位 | 未备案的离线天文星图；无账户、无支付、无联网服务 |
| 当前最大阻塞 | AppGallery 要求将最低 API 从 24 下调；本机只有 API 24 的 DevEco SDK，现配置改为兼容 API 20 后无法构建 |
| 当前风险 | 工作树有未提交的功能、性能、图标和发布配置修改；它们尚未完成完整构建和真机验收 |

## 1. 先做什么，严格按顺序

不要同时改 UI、性能、签名、API 和上架资料。每完成一项必须构建、安装、验证、提交并推送，才进入下一项。

- [ ] **A. 建立干净可复现的 API 20 工具链。** 先阅读第 3 节。成功标准：HAP 能构建，且解包后的 `module.json` 显示最低 API 为 20（或华为审核允许的更低版本），不是只改源码文本。
- [ ] **B. 复核 AppGallery 适配声明。** 成功标准：HAP 仅声明 `phone`、`tablet`，不再出现 `tv`、`wearable`、`2in1`、`car`。
- [ ] **C. 修复审核报告中的可复现功能故障。** 优先时间控制、截图/导出反馈、陀螺仪、天文计算、脚本入口；成功标准见第 6 节。
- [ ] **D. 发布前回归。** 手机、Pad、折叠屏至少各跑一轮；确认定位、搜索、时间、地图、详情、面板、中文、传感器与基本拖动。
- [ ] **E. 生成正式签名发布包。** 使用用户从 AppGallery Connect 生成的发布证书/Profile；绝不上传 debug HAP 或未签名 HAP。
- [ ] **F. Git 收口。** 仅提交已验收的变更，推送到 `myfork/release/v1.0-offline-candidate`，打上可追溯 tag。

## 2. 当前工作树，不要直接覆盖或 reset

当前分支有未提交修改，至少涉及：

- `.gitignore`：已忽略 `.release-signing/`、`*.p12`、`*.p7b`，必须保留。
- `harmonyos/build-profile.json5`：当前为 `compatibleSdkVersion: "6.0.0(20)"`，但 `compileSdkVersion`/`targetSdkVersion` 仍是 `6.1.1(24)`。
- `harmonyos/module.json5`：设备类型已收缩为 `phone`、`tablet`；定位和传感器权限仍在。
- `harmonyos/ets-source/pages/MainWindowNativeNode.ets` 和生成镜像：离线发布入口、时间、UI、后台标题等修改。
- `src/StelMainView.cpp` 与 `harmonyos/cpp-source/hello.cpp`：原生桥接、渲染或行为修改。
- `scripts/sync-ohos-build-sources.sh`、`prepare-ohos-dev.sh`、`prepare-ohos-release.sh`：构建身份和源文件同步脚本。
- `docs/harmonyos/BUILD-IDENTITY.md` 与图标资源：开发版/发布版身份区分。

**禁止：** `git reset --hard`、全目录删除 `build/`、把旧 HAP 的二进制反编译结果覆盖源码、把证书或密码提交到 Git。

开始前先保存当前状态：

```sh
cd /Users/jiexuanyang/stellarium-src
git status --short
git diff --stat
git diff -- harmonyos/build-profile.json5 harmonyos/module.json5
```

若需单独实验 API 或性能，创建新分支，不污染发布候选：

```sh
git switch -c fix/api20-toolchain
```

## 3. API 24 -> API 20：必须先查实，再改

### 已确认的本机状态

- 已安装 `DevEco Studio 6.1.1`，路径 `/Applications/DevEco-Studio.app`。
- 实际 SDK 目录只有 API 24：`/Applications/DevEco-Studio.app/Contents/sdk/default/hms/.../uni-package.json` 显示 `apiVersion: 24`、`platformVersion: 6.1.1`。
- 使用 API 20 配置调用 Hvigor 会报 `00303168 Configuration Error: SDK component missing.`
- 这说明当前机器上并没有能满足 `compatibleSdkVersion 6.0.0(20)` 的 SDK 组件；这不是代码编译错误。

### 接手者要做的事实核验

1. 在 **当前 DevEco Studio** 的 `DevEco Studio > Settings > HarmonyOS SDK` 检查是否存在 API 20 可安装条目。
2. 若没有，不要凭网上通用教程猜测。去华为官方 **下载中心** 获取包含 HarmonyOS 6.0.0(20) 的旧版 DevEco Studio，并与现有 IDE 并存安装。
3. 用旧 IDE 自带 SDK 构建该分支。允许高编低跑时必须满足：`compatible <= target <= compile`，且实际 HAP 的最低 API 已验证为目标值。
4. 如果项目使用了 API 21-24 专属 ArkTS/HMS API，必须替换、加版本分支或提高最低 API，不能只篡改版本号骗过检测。

### 必须验证 HAP，不接受“配置看起来对”

```sh
unzip -p /path/to/entry-default-signed.hap module.json | jq .
```

记录输出中的 `minAPIVersion`/SDK 声明和 `deviceTypes`，连同 HAP 的 SHA-256 写进提交说明。

## 4. 构建与源码同步：最容易把好版本重新编坏的地方

项目有两套路径：

```text
Git 跟踪源：harmonyos/ets-source/、harmonyos/cpp-source/
实际 Hvigor 工程：build/libstellarium-harmonyos/entry/src/main/
```

构建目录里残留的 `hello.cpp` 曾导致 Git 已回退、实际 HAP 仍是坏渲染器。任何切分支、回退或多人交接后，先同步：

```sh
cd /Users/jiexuanyang/stellarium-src
scripts/sync-ohos-build-sources.sh
```

原则：

- ArkTS 修改要同步到实际构建目录后再编译。
- 修改 `src/StelMainView.cpp` 后，必须重新编译 `libstellarium.so`、重新部署到 `entry/libs/arm64-v8a/`，再构建 HAP。
- 不要在同步后随手运行会覆盖 ArkTS 的部署命令；先检查脚本作用范围。
- 每次构建前记录 `git diff --stat`，避免把生成物当源码。

发布身份准备：

```sh
./scripts/prepare-ohos-release.sh
cd build/libstellarium-harmonyos
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

开发身份准备：

```sh
./scripts/prepare-ohos-dev.sh
```

开发版名称为 `星象仪·开发版`，带 DEV 图标；它与正式包使用同一 bundleName 时会覆盖安装，不能上传商店。

## 5. 签名和密钥：绝对不要重复泄露

- 仅上传 **AppGallery 发布签名后的 `.app`/`.hap` 产物**，不要上传 unsigned/debug 包。
- 仓库曾有 `.p12` 和明文密码进入 Git 历史，已进行清理/轮换。不得恢复、复制或重新提交旧材料。
- 所有 `.p12`、`.p7b`、`.cer`、CSR、密码只放本机受限目录（例如 `.release-signing/`），确认被 `.gitignore` 覆盖。
- 每次 `git add` 前运行：

```sh
git status --short
git diff --cached --check
git grep -nE 'storePassword|keyPassword|BEGIN (PRIVATE|EC) KEY' -- ':!docs/harmonyos/workbuddy/**'
```

- 模拟器通常只接受 DevEco 自动生成的 debug 签名。发布签名、手工签名、模拟器调试签名是三件不同的事，不能混用结论。

## 6. AppGallery 已报告或用户实际看到的问题

下列项目都必须先复现、再修复；不要把“有 UI”当成“功能已完成”。

### P0：上架阻断

- [ ] 最低 API 不能是 24。审核提示会导致部分机型不可见。
- [ ] HAP 设备类型只允许 `phone`、`tablet`。
- [ ] 隐私政策的权限声明必须与包内 user_grant 权限完全匹配：目前至少有 `LOCATION`、`APPROXIMATELY_LOCATION`。若保留陀螺仪/加速度计，也必须按平台表单要求声明。政策不可写“上传到服务器”，离线版应表述为本机处理、不上传。
- [ ] 离线发布包必须无 `INTERNET`、`GET_WIFI_INFO`，并隐藏星表下载、TLE 更新、在线地图/API、TCP/LX200 等联网入口。

### P1：审核和用户均遇到

- [ ] 时间前进、后退、暂停、现在：速率和模式展示要正确；调用 `setTimeRate` 的单位/方向必须实测。
- [ ] 截图、导出会话：若不能真实写文件，不得显示“成功”。离线发布版可先隐藏入口；恢复时需接入正确文件权限和用户可见保存位置。
- [ ] 陀螺仪：当前存在“打开后乱飞、朝向不匹配”的反馈。需要启动校准、低通滤波/平滑、坐标轴与屏幕旋转映射；至少在用户 Pad 上实测。
- [ ] 天文计算中的无效按钮、脚本空列表、角距离测量无效：要么接通真实桥接，要么在离线发布版隐藏，不能保留假按钮。
- [ ] 地图选点/城市选择：必须更新经纬度、时区、星图时间地点；曾出现固定巴黎时区和英文地点名。
- [ ] 搜索：有输入框、可横滑的分类、中文结果；选择星体后关闭/缩小搜索面板，并以可见倍率平滑移动到目标，不能显示“已找到”却是空天空。

### P1：交互与布局

- [ ] 面板拖动不得穿透到背后的星图；UI 区触摸反馈不得覆盖星图或反向穿透。
- [ ] 详情卡关闭一次应生效；卡片不能遮挡被选星体、系统挖孔、底部 Dock 或右侧平板大面板。
- [ ] 手机、Pad、折叠屏必须分别测试。手机 `compactShell` 和平板 `expandedShell` 只共享数据/行为，不共享绝对位置和触摸热区。
- [ ] 折叠屏：折叠走手机布局，完全展开走平板布局，半折叠以可用区域尺寸和稳定滞回决定布局，禁止在临界角度来回跳变。
- [ ] 所有图标使用同一套鸿蒙风格、圆角、间距、选中态；操作态图标变蓝，不叠加莫名蓝底或多重九宫格/三点菜单。

### P1：渲染与性能

- [ ] 用户反馈：星图比 ArkUI 层卡、拖动松手无惯性、快速滑动更卡、画面曾被降采样得模糊。
- [ ] 性能优化只能用 profiler/hilog 和屏幕录制前后对比验收。不要仅通过降低 `OHOS_RENDER_SCALE` / `READBACK_SCALE` 换取 FPS 后宣布完成；清晰度是同等指标。
- [ ] 检查触摸 move 事件的节流、C++ 命令队列积压、每帧 `glReadPixels` / 纹理上传、Qt/XComponent 双路径渲染。优先消除不必要的 CPU-GPU 像素回读，而非继续压低分辨率。
- [ ] 期望至少稳定 60 FPS；120 Hz 设备能否达到取决于显示刷新率和管线，但应提供真实测量，不要显示伪 FPS 或 `0 FPS` 调试文本。

### P2：内容和国际化

- [ ] 简体中文下星图方位显示 `东/南/西/北`，而非 `N/S/W/E`。
- [ ] 搜索命中、地点、时区、候选星体中文化；英文天体名可作为次要别名。
- [ ] 详情页展示真实结构化数据（星等、坐标、距离、视直径、大气消光等），不能出现固定 `99`、被截断或手机比平板信息更完整的倒挂。
- [ ] 星座分类选择时默认同步开启必要的星座线/名称/边界，且视野应覆盖整组星座线，不是只移动到空天区或过度放大中心。

## 7. 设备验收矩阵

每一格必须有“设备、构建 SHA、截图或日志、结果”。未测就是未完成。

| 场景 | Phone 竖屏 | Pad 横屏 | 折叠屏折叠/半折/展开 |
| --- | --- | --- | --- |
| 冷启动和首次资源解包 | [ ] | [ ] | [ ] |
| 拖动/惯性/缩放/点选星体 | [ ] | [ ] | [ ] |
| 搜索并平滑定位天体 | [ ] | [ ] | [ ] |
| 时间、地点、地图、时区 | [ ] | [ ] | [ ] |
| 图层与地景透明度 | [ ] | [ ] | [ ] |
| 详情卡展开/收起/不遮挡 | [ ] | [ ] | [ ] |
| 陀螺仪校准和朝向 | [ ] | [ ] | [ ] |
| 中文化与深色主题 | [ ] | [ ] | [ ] |
| 连续运行 30 分钟 | [ ] | [ ] | [ ] |

建议设备：手机模拟器用于布局冒烟；用户 Pad 用于真实触摸、性能和陀螺仪；折叠屏模拟器用于阈值、旋转和过渡验证。模拟器没有真实 GPS/陀螺仪，不能据此判定传感器功能完成。

## 8. Git 流程（以后不再把好版本丢掉）

1. 每项可测试小改动使用一个主题分支，例如 `fix/api20-toolchain`、`fix/gyro-calibration`。
2. 构建、安装、截图/日志验证通过后才 commit；提交信息必须写构建目标和测试设备。
3. 每个已验收提交立即推送 `myfork`。不要推送 `origin`。
4. 上架候选只通过合并/拣选经过验证的提交进入 `release/v1.0-offline-candidate`。
5. 生成发布包后写 tag，例如 `v1.0.0-harmonyos-offline.1`，并存档 SHA-256、版本号、签名/Profile 标识（不含密钥）。

示例：

```sh
git add <已验证文件>
git commit -m "fix(ohos): verify API 20 release compatibility"
git push myfork HEAD
git tag -a v1.0.0-harmonyos-offline.1 -m "AppGallery offline candidate"
git push myfork v1.0.0-harmonyos-offline.1
```

## 9. 参考资料（仅作背景，不覆盖本文件）

- `docs/harmonyos/DEBUGGING-GUIDE.md`：Qt、N-API、黑屏和渲染排障历史。
- `docs/harmonyos/MOBILE-UI-HANDOVER.md`：旧 compactShell 触摸穿透事故与恢复建议。
- `docs/harmonyos/BUILD-IDENTITY.md`：开发版/发布版名称、图标和版本号准备脚本。
- `docs/harmonyos/APP-STORE-SUBMISSION.md`：上架资料和早期流程，包名/状态有旧信息，使用前核对。
- `docs/harmonyos/workbuddy/HANDOFF.md`：早期签名与生成目录问题；其中路径、签名材料状态和分支已过时，不要照抄。

## 10. 交接完成条件

WorkBuddy 接手后，先回复以下五项的实际结果，而不是开始大改 UI：

1. 当前 `git status --short` 与分支名。
2. 当前 DevEco/SDK 实际可用 API 列表。
3. 使用哪个签名配置构建、HAP 输出路径和 SHA-256。
4. HAP 解包后最低 API 与设备类型。
5. 在手机模拟器和用户 Pad 上的启动/渲染/交互冒烟结果。

只有这五项清楚后，才进入性能、陀螺仪、折叠屏和 UI 迭代。
