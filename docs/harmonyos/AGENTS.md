# Stellarium HarmonyOS 移植 — Agent 协作工作流

> **最后更新：2026-07-21**
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

### 2.2 文档结构

```
docs/harmonyos/
├── AGENTS.md                  ← 你正在读的这个文件
├── HANDOFF.md                 ← 项目交接文档（给新 Agent 的快速入门）
├── CHANGELOG.md               ← 修改日志（每次变更必须追加）
├── KNOWN-ISSUES.md            ← 已知问题列表（Bug 追踪）
├── SIGNING-GUIDE.md           ← HAP 构建、手动签名、安装排错说明
├── DEBUGGING-GUIDE.md         ← DevEco/模拟器/Qt/ArkUI 实战调试经验
├── DEVECO-COLLAB.md           ← DevEco Code 协作指南（外包鸿蒙重活、省 token）
├── skills/                    ← ArkTS 开发 Skill 参考库（来自 DevEco Code）
│   ├── arkts-error-fixes/     ← 21 种 ArkTS 编译错误修复方案（66 文件）
│   ├── arkts-grammar-standards/ ← ArkTS 语法规范、TS→ArkTS 改写（9 文件）
│   ├── arkts-runtime-fix/     ← 运行时崩溃/faultlog/hilog 诊断（30 文件）
│   └── harmonyos-deveco-bridge/ ← TRAE↔DevEco Code 协调（1 文件）
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
└── signing/                   ← 历史遗留路径；签名私钥/profile 清洗后不要再提交到 git
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

## 2.6 DevEco Code 协作（省 token 必看）

本项目已集成 DevEco Code 的 5 个 skill（arkts-error-fixes / arkts-grammar-standards / arkts-runtime-fix / deveco-create-project / harmonyos-deveco-bridge），TRAE 可直接调用。

**遇到以下场景时，优先走 DevEco Code 协作路径：**

| 场景 | 推荐路径 | 原因 |
|---|---|---|
| ArkTS 编译报错 | 先查本地 skill，复杂错误用 `deveco run` 外包 | 免费 GLM-5.1 扛 token，省约 200 倍 |
| 运行时崩溃/白屏 | 查 arkts-runtime-fix，或 `deveco run` 分析 hilog | 它有内置 faultlog 解析脚本 |
| 鸿蒙 UI 规范咨询 | `deveco run` 外包 | 内置鸿蒙知识库比联网搜准 |
| 编译 / 部署 / 截屏 | 直接用 `hvigorw` / `hdc` 命令 | 零 token，纯命令行 |

**详细指南见 [DEVECO-COLLAB.md](DEVECO-COLLAB.md)。**

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

---

## 4. 构建命令

### 4.1 构建 HAP

```bash
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos

env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

### 4.2 签名 HAP

```bash
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
  -outFile /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap \
  -compatibleVersion 24 -signCode 1
```

### 4.3 安装启动

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"

$HDC tconn 127.0.0.1:5555
$HDC -t 127.0.0.1:5555 shell bm uninstall -n org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 install -r /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap
$HDC -t 127.0.0.1:5555 shell hilog -r
$HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

### 4.4 调试命令

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

| 命令 | 功能 | 参数 |
|------|------|------|
| `searchObject` | 搜索天体 | 名称 |
| `selectAt` | 点击选星 | x\|y\|skyW\|skyH |
| `dragView` | 拖动星图 | dx\|dy |
| `zoomBy` | 缩放 | factor |
| `zoomStep` | 步进缩放 | factor |
| `setTimeRate` | 时间速率 | rate |
| `setLocation` | 设置位置 | lat\|lng\|alt\|name |
| `setActionChecked` | 图层开关 | name\|checked |
| `getState` | 获取状态 | - |
| `getSelectedObject` | 获取选中对象 | - |
| `panBy` | 陀螺仪平移 | x\|y |
| `lx200Command` | LX200 协议 | command |

---

## 6. 布局模式

| 条件 | 布局 | 说明 |
|------|------|------|
| `skyWidth >= 900` | expandedShell | 左侧垂直工具栏 + 右侧浮动面板（Pad 横屏） |
| `skyWidth < 900` | compactShell | 底部 Dock + 底部面板（手机竖屏） |

---

## 7. 注意事项

1. **不要修改 build 目录下的文件后忘记同步到 `harmonyos/`**
2. **HAP、签名私钥、profile、真实密码都不要上传到 git**；签名材料只放本机私有目录或私下交付
3. **不要推送到上游 `Stellarium/stellarium`**，推送到你自己的 fork
4. **ArkTS 限制：** `@Builder` 内不能有 `const/let` 赋值；属性链式调用必须在容器组件 `}` 之后；`Blank()` 只能放在 `Column/Row/Flex` 中
5. **坐标单位：** `onAreaChange` 返回 vp；`TouchObject.windowX/Y` 是 vp；C++ 侧 `selectAt` 需要 vp
