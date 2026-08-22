# Stellarium HarmonyOS 移植 — Agent 协作工作流

> **最后更新：2026-07-20**
> **当前分支：** `openharmony-preview-v1`
> **当前状态：** 能构建、安装、启动；横屏 UI 正常；星图触摸/选星可用；触摸事件已修复但仍有边缘死区问题

---

## 1. 项目概述

将 [Stellarium](https://github.com/Stellarium/stellarium) 开源天文软件移植到 HarmonyOS NEXT 平台，以单 HAP 应用形式运行在 DevEco Studio 模拟器/真机上。

### 架构

```
ArkUI (MainWindowNativeNode.ets)  ← 用户交互层
    ↓ command bridge
C++ Native (hello.cpp → StellariumOhos_command)
    ↓
Stellarium Core (StelMainView.cpp) ← 渲染/计算/选星/搜索
    ↓
OpenGL ES → XComponent → Framebuffer
```

### 关键技术

- **渲染桥**：C++ Stellarium Core 通过 OpenGL ES 渲染到 XComponent
- **命令桥**：ArkUI → N-API → C++ `StellariumOhos_command()`，JSON 返回结果
- **触摸路由**：ArkUI `onTouch` + `HitTestMode` 分发星图触摸 / UI 点击

---

## 2. Agent 协作规范

### 2.1 文档即状态机

**核心原则：任何 Agent 在做任何操作之前，必须先读文档；做完任何操作之后，必须立即写文档。**

| 操作 | 前置动作 | 后置动作 |
|------|----------|----------|
| 修改代码 | 读 `HANDOFF.md` + `CHANGELOG.md` | 在 `CHANGELOG.md` 追加记录 |
| 构建/测试 | 读构建命令（本文档第4节） | 记录结果到 `CHANGELOG.md` |
| 发现 Bug | 读 `CHANGELOG.md` 避免重复 | 在 `KNOWN-ISSUES.md` 追加 |
| 修复 Bug | 读 `KNOWN-ISSUES.md` 选任务 | 标记已修复，更新 `CHANGELOG.md` |
| 更换 Agent | 读全部文档 | 无需额外动作 |

### 2.1.1 联网功能登记

所有新增或修改的联网行为，必须同步维护 `NETWORK-INVENTORY.md`：

- 新增 URL、网络 API、文件下载、自动更新、远程端口或外部网页跳转时，先登记功能、触发方式和默认状态。
- 明确记录外发字段，特别是观测经纬度、查询词、设备标识、账号标识和隐私同意状态；未经明确设计，不得外发 SN 或设备序列号。
- 区分运行时联网与构建阶段联网；构建依赖下载不能被描述成应用功能联网。
- 对每个联网功能记录国内镜像或同类替代的评估结果，不得未经验证宣称存在等价国内服务。
- HarmonyOS 默认保持离线优先。开放联网前必须有用户主动触发、隐私说明、超时、失败回退和本地内置数据策略。
- 仅监听本机或局域网的 RemoteControl/RemoteSync 也要登记，并说明端口、认证、CORS 和暴露范围。

### 2.2 文档结构

```
docs/harmonyos/
├── AGENTS.md                  ← 你正在读的这个文件
├── HANDOFF.md                 ← 项目交接文档（给新 Agent 的快速入门）
├── CHANGELOG.md               ← 修改日志（每次变更必须追加）
├── KNOWN-ISSUES.md            ← 已知问题列表（Bug 追踪）
├── codex/                     ← Codex Agent 的工作记录
│   ├── Stellarium-HarmonyOS-交接文档.md
│   └── ohos_patch/            ← Codex 编写的补丁代码
├── workbuddy/                 ← WorkBuddy Agent 的工作记录
│   ├── memory/                ← Agent 记忆文件
│   ├── phase2/                ← 第二阶段进度
│   └── outputs/               ← 测试截图
├── trae/                      ← TRAE Agent 的工作记录
│   └── memory/                ← Agent 记忆文件
├── harmonyos-project/         ← HarmonyOS 工程源码快照
│   ├── ets-source/            ← ArkUI/ETS 源码
│   ├── cpp-source/            ← C++ Native 源码
│   └── *.json5                ← 构建配置
└── signing/                   ← 签名证书和配置
    ├── stellarium-app-keypair.p12
    ├── stellarium-app-cert-chain.cer
    └── stellarium-ca-release-profile.p7b
```

### 2.3 CHANGELOG.md 格式

每次修改必须追加一条记录，格式如下：

```markdown
## [日期] Agent名称 - 简述

- **修改文件：** `相对路径`
- **修改内容：** 描述做了什么
- **修改原因：** 为什么改（关联的 Bug / 需求）
- **构建结果：** BUILD SUCCESSFUL / FAILED（失败则附错误摘要）
- **验证结果：** 通过 / 未验证 / 部分通过（附具体现象）
- **备注：** 其他 Agent 需要注意的事项
```

### 2.4 接手检查清单

新 Agent 接手时，必须按顺序完成：

1. [ ] 读完 `HANDOFF.md`（了解项目全貌）
2. [ ] 读完 `CHANGELOG.md`（了解最近改动）
3. [ ] 读完 `KNOWN-ISSUES.md`（了解待修问题）
4. [ ] 检查构建环境是否可用（运行 `check_env.sh`）
5. [ ] 执行一次完整构建（确认代码能编译）
6. [ ] 签名、安装、启动（确认能运行）
7. [ ] 选择下一个任务（从 KNOWN-ISSUES 或 HANDOFF 的待办中选）
8. [ ] 开始工作前，在 CHANGELOG.md 记录"开始处理 XXX"

### 2.5 Agent 切换时的紧急保存

如果 Agent 即将中断（额度不足/超时/崩溃），必须立即：

1. 在 `CHANGELOG.md` 追加当前进度（做到了哪一步）
2. 在 `KNOWN-ISSUES.md` 标记当前正在处理的问题（标注"进行中"）
3. 如果代码改了一半导致编译失败，**立即回滚**（`git checkout .`），不要留半成品
4. 如果代码改了一半但逻辑正确，在 `CHANGELOG.md` 精确记录改了哪些行、下一步该做什么

---

## 3. 环境要求

### 3.1 开发环境

- macOS（当前在 Mac 上开发）
- DevEco Studio（已安装在 `/Applications/DevEco-Studio.app`）
- HarmonyOS SDK（在 `/Users/jiexuanyang/Library/OpenHarmony/Sdk`）
- Node.js（DevEco 自带）
- JDK（DevEco 自带 JBR）
- CMake + Ninja（构建 C++ native）
- hdc（HarmonyOS 设备连接工具）

### 3.2 源码路径

| 路径 | 用途 |
|------|------|
| `/Users/jiexuanyang/stellarium-src/` | Stellarium 源码仓库（git） |
| `/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/` | HarmonyOS 构建工程 |
| `.../entry/src/main/ets/pages/MainWindowNativeNode.ets` | **最核心的 ArkUI 文件** |
| `.../entry/src/main/cpp/hello.cpp` | Native 命令桥 |
| `/Users/jiexuanyang/stellarium-src/src/StelMainView.cpp` | C++ 渲染/命令核心 |
| `/private/tmp/stellarium-oh-signing/` | 签名文件和已签名 HAP |
| `/Users/jiexuanyang/Qt/6.12.0/macos/bin/harmonydeployqt` | Qt OHOS 部署工具（生成 libs/） |
| `/Users/jiexuanyang/stellarium-src/build/src/stellarium-harmony-deployment-settings.json` | Qt OHOS 部署配置 |
| `/Users/jiexuanyang/stellarium-src/build/src/libstellarium.so` | 预编译的 Stellarium 引擎库 |
| `.../entry/libs/arm64-v8a/` | Native .so 文件目录（**不要删除！** 不在 git 中） |

---

## 4. 构建命令

### 4.1 确保 entry/libs/ 存在（首次或 .so 丢失时）

```bash
# 使用 harmonydeployqt 生成 libs/（不覆盖 ETS 源码）
/Users/jiexuanyang/Qt/6.12.0/macos/bin/harmonydeployqt \
  --input /Users/jiexuanyang/stellarium-src/build/src/stellarium-harmony-deployment-settings.json \
  --output /tmp/harmony-test --no-build
cp -r /tmp/harmony-test/entry/libs /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/libs
```

### 4.2 构建 HAP

```bash
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos

env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

### 4.3 签名 HAP（如果 hvigor 未自动签名）

```bash
/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java \
  -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  sign-app -mode localSign \
  -keyAlias stellarium-app-key -keyPwd 123456 \
  -appCertFile /private/tmp/stellarium-oh-signing/stellarium-app-cert-chain.cer \
  -profileFile /private/tmp/stellarium-oh-signing/stellarium-ca-release-profile.p7b \
  -inFile /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-unsigned.hap \
  -signAlg SHA256withECDSA \
  -keystoreFile /private/tmp/stellarium-oh-signing/stellarium-app-keypair.p12 \
  -keystorePwd 123456 \
  -outFile /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap \
  -compatibleVersion 24 -signCode 1
```

### 4.4 安装启动

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
HAP="/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap"

$HDC tconn 127.0.0.1:5555
$HDC -t 127.0.0.1:5555 shell bm uninstall -n org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 install -r "$HAP"
$HDC -t 127.0.0.1:5555 shell hilog -r
$HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

### 4.5 调试命令

```bash
# 拉日志
$HDC -t 127.0.0.1:5555 shell hilog -x | grep Stellarium

# 截图
$HDC -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/ui.jpeg
$HDC -t 127.0.0.1:5555 file recv /data/local/tmp/ui.jpeg /tmp/ui.jpeg

# 布局树
$HDC -t 127.0.0.1:5555 shell uitest dumpLayout
```

---

## 5. 已实现的命令桥

> 命令按功能分类；每条命令一行。`setActionChecked` 可映射任意 action 名称，以下仅列主要类别。

### 基础交互

| 命令 | 功能 | 参数 |
|------|------|------|
| `searchObject` | 搜索天体 | 名称 |
| `selectAt` | 点击选星 | x\|y\|skyW\|skyH |
| `dragView` | 拖动星图 | dx\|dy |
| `panBy` | 陀螺仪平移 | x\|y |
| `zoomBy` | 缩放 | factor |
| `zoomStep` | 步进缩放 | factor |

### 对象查询

| 命令 | 功能 | 参数 |
|------|------|------|
| `getSelectedObjectInfo` | 选中天体详细信息 | - |
| `getObjectInfo` | 指定天体详细信息 | 名称 |
| `getRTS` | 选中天体升起/中天/落下 | - |
| `getObjectPositions` | 行星位置表 | - |
| `listMatchingObjects` | 模糊匹配天体列表 | pattern |
| `listObjects` | 枚举天体（指定类型） | type |

### 状态查询

| 命令 | 功能 | 参数 |
|------|------|------|
| `getState` | 获取全局状态 | - |
| `getAppVersion` | 应用版本 | - |
| `getFPS` | 帧率 | - |
| `getObserverInfo` | 观测者经纬度/海拔 | - |
| `getScreenInfo` | 屏幕尺寸/DPI | - |
| `getSimTime` | 当前模拟时间 | - |
| `getSimulationTime` | 当前 JD/时间速率 | - |
| `getStarCount` | 可见星数 | - |
| `getDSOCounts` | 可见深空天体分类计数 | - |
| `getAlmanac` | 太阳/月球年历+月相 | - |

### 时间控制

| 命令 | 功能 | 参数 |
|------|------|------|
| `setTimeRate` | 时间速率 | rate |
| `advanceTime` | 快进指定秒数 | seconds |
| `setJD` | 设置 Julian Date | jd |
| `setDate` | 设置日期时间 | YYYY-MM-DDThh:mm |
| `setTimeToJD` | 设置模拟时间为指定 JD | jd |

### 位置/观测

| 命令 | 功能 | 参数 |
|------|------|------|
| `setLocation` | 设置位置 | lat\|lng\|alt\|name |
| `setLocationByName` | 按城市名设置位置 | city name |
| `setLocationCoords` | 按经纬度设置位置 | lat,lon[,alt] |
| `moveToSelected` | 移动视角到选中天体 | - |

### 显示控制（图层开关）

| 命令 | 功能 | 参数 |
|------|------|------|
| `setActionChecked` | 通用图层开关 | name\|checked |
| `setGridFlag` | 网格线 | checked |
| `setMilkyWayFlag` | 银河 | checked |
| `setSolarSystemFlag` | 太阳系 | checked |
| `setStarFlag` | 恒星 | checked |
| `setNebulaFlag` | 星云 | checked |
| `setAtmosphereFlag` | 大气层 | checked |
| `setLandscapeFlag` | 地景 | checked |
| `setCardinalsFlag` | 方位标 | checked |
| `setAsterismFlag` | 星宿连线 | checked |
| `setDeepSkyFlag` | 深空天体标签 | checked |

> 其他图层（星座线、星座标签、行星标签等）均通过 `setActionChecked(action_name, checked)` 控制，action 名称须与 C++ `StelActionMgr` 一致。

### 投影/FOV

| 命令 | 功能 | 参数 |
|------|------|------|
| `setProjectionType` | 投影方式 | name |
| `setFOV` | 设置视场角 | degrees |
| `getFieldOfView` | 获取当前 FOV | - |
| `setFieldOfView` | 设置 FOV (0.1-360°) | degrees |

### 星座/文化

| 命令 | 功能 | 参数 |
|------|------|------|
| `setSkyCulture` | 切换天区文化 | id |
| `getSkyCultureList` | 天区文化列表 | - |
| `getConstellationList` | 所有星座英文名列表 | - |
| `getConstellationInfo` | 当前星座信息 | - |

### 书签

| 命令 | 功能 | 参数 |
|------|------|------|
| `addBookmark` | 添加书签 | name\|ra\|dec\|fov |
| `getBookmarks` | 书签列表 | - |
| `gotoBookmark` | 跳转书签 | name |
| `deleteBookmark` | 删除书签 | name |

### 星表下载

| 命令 | 功能 | 参数 |
|------|------|------|
| `getStarCatalogs` | 可用星表列表 | - |
| `downloadStarCatalog` | 下载星表 | id |
| `getStarCatalogStatus` | 星表下载进度 | - |

### 深空图像资源探针

| 命令 | 功能 | 参数 |
|------|------|------|
| `getDeepSkyImageStatus` | 区分索引、沙箱文件和当前纹理就绪状态 | 空参数检查重点图片；`all|偏移|数量` 分页列出 PNG |

### 卫星

| 命令 | 功能 | 参数 |
|------|------|------|
| `getSatellites` | 可见卫星列表 | - |
| `setSatellitesFlag` | 卫星图层开关 | checked |

### 流星雨

| 命令 | 功能 | 参数 |
|------|------|------|
| `getMeteorShowers` | 流星雨列表 | - |
| `setMeteorShowersFlag` | 流星雨图层开关 | checked |

### 望远镜（Oculars 插件）

| 命令 | 功能 | 参数 |
|------|------|------|
| `getOculars` | 目镜列表 | - |
| `setOcularMode` | 目镜模式开关 | checked |
| `setTelrad` | Telrad 叠加 | checked |
| `setCrosshairs` | 十字丝 | checked |
| `setCCD` | CCD 叠加 | checked |

### 脚本

| 命令 | 功能 | 参数 |
|------|------|------|
| `playScript` | 播放脚本 | name |
| `stopScript` | 停止脚本 | - |
| `pauseScript` | 暂停脚本 | - |
| `resumeScript` | 恢复脚本 | - |
| `listRecordings` | 录制列表 | - |
| `saveRecording` | 保存录制 | name |
| `loadRecording` | 加载录制 | name |
| `deleteRecording` | 删除录制 | name |

### 视频

| 命令 | 功能 | 参数 |
|------|------|------|
| `startVideoRecording` | 开始视频录制 | path |
| `stopVideoRecording` | 停止视频录制 | - |
| `getVideoRecordingState` | 录制状态 | - |

### 配置

| 命令 | 功能 | 参数 |
|------|------|------|
| `getConfigString` | 读取配置 | key |
| `setConfigString` | 写入配置 | key=val |
| `exportConfig` | 导出配置 | path |
| `importConfig` | 导入配置 | path |

### LX200 / 望远镜控制

| 命令 | 功能 | 参数 |
|------|------|------|
| `telescopeLx200GotoSelected` | LX200 转到选中天体 | - |
| `telescopeLx200SyncSelected` | LX200 同步选中天体 | - |
| `telescopeLx200Abort` | LX200 中止 | - |
| `lx200Command` | LX200 原始命令 | command |

### 地景/大气

| 命令 | 功能 | 参数 |
|------|------|------|
| `getLandscapeList` | 地景列表 | - |
| `setLandscape` | 切换地景 | id |
| `setLandscapeTransparency` | 地景透明度 | 0.0-1.0 |
| `setLightPollution` | 光污染等级 | level |
| `setBortleScale` | Bortle 等级 (1-9) | level |

### 音频

| 命令 | 功能 | 参数 |
|------|------|------|
| `setAudioEnabled` | 音频开关 | checked |
| `setAudioVolume` | 音频音量 | 0.0-1.0 |

### 多设备同步

| 命令 | 功能 | 参数 |
|------|------|------|
| `getSessionState` | 获取会话状态 JSON | - |
| `applySessionState` | 应用会话状态 | json |

### 指星笔

| 命令 | 功能 | 参数 |
|------|------|------|
| `pointAtSky` | 指星笔指向 (RA/Dec) | ra\|dec |
| `pointAtSkyStop` | 关闭指星笔 | - |

### 视角控制

| 命令 | 功能 | 参数 |
|------|------|------|
| `setVerticalClamp` | 垂直角度钳制 | degrees |
| `setViewLock` | 锁定视角 | checked |
| `setFlatHorizon` | 平地平线模式 | checked |

### 天象

| 命令 | 功能 | 参数 |
|------|------|------|
| `getTonightEvents` | 今夜天象（月出/月落/升/中天等） | - |

### 插件

| 命令 | 功能 | 参数 |
|------|------|------|
| `getPluginList` | 插件列表 | - |
| `loadPlugin` | 加载插件 | name |
| `unloadPlugin` | 卸载插件 | name |

### 语音/帮助

| 命令 | 功能 | 参数 |
|------|------|------|
| `getObjectSpokenText` | 选中天体语音描述文本 | - |
| `getLog` | 应用日志 | lines |
| `getAboutInfo` | 关于信息（版本/许可/作者） | - |

### 兼容旧名（保留但不推荐）

| 旧命令 | 等价新命令 | 说明 |
|--------|------------|------|
| `getSelectedObject` | `getSelectedObjectInfo` | 旧版别名 |
| `getSelectedType` | `getSelectedObjectInfo` | 仅返回类型 |
| `getLoadedModuleNames` | `getPluginList` | 旧版别名 |
| `getScriptList` | - | 脚本列表已整合到脚本命令中 |

---

## 6. 布局模式

| 条件 | 布局 | 说明 |
|------|------|------|
| `skyWidth >= 900` | expandedShell | 左侧垂直工具栏 + 右侧浮动面板（Pad 横屏） |
| `skyWidth < 900` | compactShell | 底部 Dock + 底部面板（手机竖屏） |

---

## 7. 注意事项

1. **不要修改 build 目录下的文件后忘记同步到 `docs/harmonyos/harmonyos-project/`**
2. **HAP 文件不要上传到 git（太大），只上传签名证书和配置**
3. **不要推送到上游 `Stellarium/stellarium`**，推送到你自己的 fork
4. **`entry/libs/` 目录不要删除！** 其中 .so 文件不在 git 中，丢失后只能通过 `harmonydeployqt` 重新生成
5. **hvigor 只构建 ArkTS + 打包资源**，不编译 `libstellarium.so`。C++ 源码修改需要 Qt OHOS 交叉编译才能生效
6. **ArkTS 限制：** `@Builder` 内不能有 `const/let` 赋值；属性链式调用必须在容器组件 `}` 之后；`Blank()` 只能放在 `Column/Row/Flex` 中
7. **坐标单位：** `onAreaChange` 返回 vp；`TouchObject.windowX/Y` 是 vp；C++ 侧 `selectAt` 需要 vp
8. **action ID 必须与 C++ 源码一致**，不能凭记忆编造。修改前必须 grep C++ 源码验证
