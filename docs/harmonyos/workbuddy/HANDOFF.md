# WorkBuddy 交接文档 —— Stellarium 鸿蒙移植（签名/运行/调试）

> 交接时间：2026-07-22 00:50
> 分支：`openharmony-preview-v1`（本地 HEAD `3cd2719`，历史已清洗干净）

---

## 一、最重要的警告：用量已耗尽，优先从这里开始

WorkBuddy 当前会话用量已耗尽。接手方请：
1. **首先阅读本文件**，无需重头摸索。
2. 从下文**第七节"下一步"**选取入口继续。
3. 若涉及签名，**切勿**重新跑已经跑通过的 `sign-app` 流程（已记录路径和参数），直接复用产物或走已测通的路线。

---

## 二、签名现状（当前核心堵点）

### 可以做到的事
- ✅ **sign-app 手动签名已完全跑通**：`hap-sign-tool sign-app` 可以产出 `entry-default-signed.hap`（275MB）
- ✅ 使用了**干净的 Debug 类型 profile**（`~/stellarium-signing/app-debug.p7b`），profile type=debug，模拟器认
- ✅ 使用**自己的干净新密钥**（不碰泄露旧钥匙）签名成功
- ✅ 使用 **SDK OpenHarmony 受信证书链**（`OpenHarmony.p12`）签名也成功
- ❌ **模拟器不认自签名**：无论用自建 CA 还是 SDK OpenHarmony 应用证书，`hdc install` 都报错：
  - 自建 CA → `code:9568332 error: install sign info inconsistent`（证书链不一致）
  - SDK OpenHarmony 应用证书 → `sign-app: verify certificate chain failed! Signature does not match`（链条组装有误，见下文）

### 问题的本质
本地 Device Simulator（127.0.0.1:5555）只接受 **DevEco IDE 自动签名的 debug 包**。手动 `sign-app` 的包（不管用哪个证书链）都被拒。`deveco run`（通过 DevEco 后端运行）是唯一被验证能装到模拟器的路径。

### 两条修复路线

#### 路线 A：DevEco 自动签名（推荐，最干净）
- **卡点**：`build-profile.json5` 里 `storePassword`/`keyPassword` 已被 filter-repo 替换为占位符 `***REMOVED_ROTATED***`
- **修复**：打开 DevEco Studio → 打开此工程 → Project Structure → Signing → 取消再重新勾选 "Automatically generate signature" → 会自动重新生成 `~/.ohos/config/openharmony/` 下的全套材料 + 往 `build-profile.json5` 写入正确密码
- **或者**：运行 `deveco run "重新生成自动签名材料并编译安装到模拟器"`（DevEco Code 已登录，免费 GLM-5.1）
- 完成后即可 `hvigorw assembleHap` 产生模拟器接受的 debug HAP

#### 路线 B：用 SDK OpenHarmony 证书链手工 sign-app（卡在链条验证）
- 当前状态：`openssl pkcs12 -legacy -nokeys` 从 `OpenHarmony.p12` 导出 9 个证书块
- 9 个块的 subject/issuer 尚未完全勘正（有重复/异体），`dbg_certs.py` 刚写完还没跑
- 待办：先跑 `python3 /tmp/dbg_certs.py` 看清 9 个块的关系，再正确组装 [release → ca → root] 链条
- `keyAlias = "openharmony application release"`，密码 `123456`
- 此路不通的话别死磕，换路线 A

---

## 三、环境状态清单

### 仓库
```
~/stellarium-src/
  分支: openharmony-preview-v1 (3cd2719)
  未提交变更: docs/harmonyos/SIGNING-GUIDE.md, AGENTS.md, DEBUGGING-GUIDE.md（已改好，需确认后 commit）
  回滚备份: backup-before-cleanup-20260722（指向旧脏版 6e5a8b6，未 push）
```

### 签名材料
```
~/stellarium-signing/              ← 我的干净新密钥
   app.key / app.pem / app-chain.pem / app-debug.p7b / ca.key / ca.pem

~/.ohos/config/openharmony/       ← DevEco 自动签名材料（密码丢失）
   default_libstellarium-harmonyos_*.p12 / .cer / .p7b

/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/
   OpenHarmony.p12（共享调试证书，密码 123456）
   hap-sign-tool.jar（sign-app/sign-profile/verify）

/private/tmp/stellarium-oh-signing/   ← ⚠️ 旧泄露私钥副本(stellarium-app-keypair.p12) + 263MB leaked-signed HAP，仍需销毁
```

### 已编译 HAP
```
build/.../default/entry-default-unsigned.hap   ← 274MB 未签名，可直接 sign
build/.../default/entry-default-signed.hap      ← 之前编的（可能是泄露钥匙签的 release 型）
/tmp/entry-debug-signed.hap                   ← 我用自建 CA 签的 debug HAP（模拟器 reject sign-info-inconsistent）
/tmp/entry-oh-debug-signed.hap                ← 我用 SDK OpenHarmony 签的（链条组装失败）
```

### 工具链
```
deveco CLI v0.1.3（已登录 OAuth，免费 GLM-5.1）→ /opt/homebrew/bin/deveco
hdc → .../sdk/default/openharmony/toolchains/hdc
hvigorw → .../tools/hvigor/bin/hvigorw
java → .../jbr/Contents/Home/bin/java（jbr 无 openssl）
openssl → 系统自带（`openssl` / /usr/bin/openssl）
模拟器在线: 127.0.0.1:5555
```

---

## 四、本会话已完成的实质性工作

### 1. 凭据泄露处置（已完成）
- filter-repo 历史清洗 + 强推 + 轮换签名材料（详细见 `2026-07-22.md` 记忆）
- 仓库内旧 p12 已移入废纸篓
- **待清尾**：`/private/tmp/stellarium-oh-signing/` 仍残留同款泄露 p12 + 263MB 旧钥匙签的 HAP

### 2. 文档修正（已改未提交）
- `SIGNING-GUIDE.md`: 重写，路径/文件名改为新密钥 + 安全通告
- `AGENTS.md`: 路径表、sign-app/install 命令改对
- `DEBUGGING-GUIDE.md`: 路径示例改对
- 三文件在 `git status` 中未 commit

### 3. 签名能力实证
- 自建 CA + debug profile + sign-app → 签名成功（模拟器拒但 sign-app 本身 100% 跑通）
- SDK OpenHarmony cert chain 导出+提取流程已建立
- DevEco Code 登录确认 + delegaate 流程可用

### 4. 移植缺口摸底
- 从 KNOWN-ISSUES/CHANGELOG 确认：所有 P0 bug 已代码修复但**从未在模拟器上实际跑起来验证过**
- 验证清单已整理：星空渲染、点星选中、面板按钮、搜索、竖屏模式等

---

## 五、关键发现（接手方别踩的坑）

1. **DevEco jbr 没有 openssl** —— 需用系统 `/usr/bin/openssl`
2. **`deveco run`（DevEco Code）**可以委派重活，已登录且有免费 GLM-5.1 token，但 WorkBuddy 当前会话已耗尽，接手方若需构建可直接 `deveco run`
3. **zsh 下 awk/csplit 踩坑** —— 证书拆分建议用 Python（`/tmp/split_certs.py` 已验证可用），或用系统 `csplit`（但 zsh 通配符 `*` 无匹配时出错）
4. **模拟器只认 DevEco IDE 自动签名的 debug 包**—— 手动 sign-app 再 debug 也不行。要装模拟器只有 DevEco Run 一条路
5. **`hvigorw assembleHap` 只重编 ArkUI 层 (.ets)** —— 改 C++ 核心需 `cmake --build . --parallel` 重编 `libstellarium.so` 再同步到 `entry/libs/arm64-v8a/`
6. **同步完 .so 后不要跑 `harmonydeployqt`**（会覆盖 .ets 编辑）

---

## 六、待处理尾巴

- [ ] **销毁 `/private/tmp/stellarium-oh-signing/`**：内含泄露旧 p12 + 263MB 泄露钥匙签的 HAP，移入废纸篓
- [ ] **提交文档修正**：3 个 docs/ 文件的改动（或先用户确认再 push）
- [ ] **恢复 DevEco 自动签名**（路线 A）：打开 DevEco Studio → 重新勾选 auto-sign → `hvigorw assembleHap` → 装模拟器
- [ ] **在模拟器上验证**：星空渲染、点星选中、面板按钮、搜索、i18n、竖屏模式、各开关
- [ ] **`/tmp/dbg_certs.py` 跑完**：查明 SDK OpenHarmony 9 个证书块的拓扑（可选，自动签名打通后此路不再需要）
- [ ] **Clear old HAP artifacts**: `/tmp/`, `/private/tmp/` 下的临时文件可清理

### 已知限制（不是 bug）
- 模拟器无 GPS → `getCurrentLocation` 失败是预期
- ShowMySky 未接入 → 用兜底天光
- Symbol 图标受 SDK 限制
- 恒星赤道坐标不随地球自转变（属正常天文学定义）

---

## 七、接手方下一步（按优先级）

1. **最优先**：恢复 DevEco 自动签名（路线 A）→ 编译 debug HAP → 装模拟器 → 运行 → 抓 hilog 确认是否启动成功
2. **如果用 DevEco Code**：`cd ~/stellarium-src/harmonyos && deveco run "检查自动签名配置，若密码无效则重新生成自动签名材料，编译 entry 模块 debug HAP (assembleHap)，安装到 127.0.0.1:5555 模拟器，启动 App(org.qtproject.example.stellarium, QAbility)，抓 20 秒 hilog 判断崩溃/报错"`
3. **如果手动修复**：打开 DevEco Studio，Project Structure → Signing → 取消 "自动生成签名" 再重新勾选 → 保存 → `hvigorw assembleHap` → `hdc install` → `hdc shell aa start -b org.qtproject.example.stellarium -a QAbility` → `hilog -x | grep -i stel`
4. **App 跑起来后**：用 `uitest dumpLayout -p /data/local/tmp/x.json -b org.qtproject.example.stellarium -m false -i` 抓布局 → `hdc file recv` → 用 `extract_layout.py` 分析 → 逐项验证星空、点星、面板、搜索、按钮、i18n
5. **改 C++ 后**：`cmake --build . --parallel` → 把新 `libstellarium.so` 同步到 `entry/libs/arm64-v8a/` → `assembleHap`（不要 harmonydeployqt）

---

## 最新更新 (2026-07-22 TRAE)

### 当前状态
- **HEAD**: `b912e87cee` (i18n 全量完成)
- **C++ 桥接**: Phase 2 (12 cmd) + Phase 2b (8 cmd) + Phase 2c (3 cmd) = 35 个桥接命令
- **libstellarium.so**: 已重新编译，包含全部 23 个命令
- **ArkTS UI**: ~4200 行 MainWindowNativeNode.ets，10 个面板全部实现
- **i18n**: ~235 个字符串资源键（base/zh_CN/en_US 三 locale）
- **Tab 标签**: 保持硬编码中文（ArkTS $r() 返回 Resource，不兼容 string 类型）

### 桥接命令清单
| 命令 | 参数 | 功能 |
|------|------|------|
| getLandscapeList | - | 地景列表 (id/name) |
| setLandscape | id | 切换地景 |
| setLandscapeTransparency | 0.0-1.0 | 地景透明度 |
| getScriptList | - | 脚本列表 |
| playScript/stopScript/pauseScript/resumeScript | name | 脚本控制 |
| getLoadedModuleNames | - | 已加载模块 |
| getRTS | - | 选中天体升起/中天/落下时间 |
| getAlmanac | - | 太阳/月球年历 (月相) |
| getObjectPositions | - | 行星位置表 (alt/az/mag) |
| getSkyCultureList | - | 天区文化列表 |
| setSkyCulture | id | 切换天区文化 |
| getPluginList | - | 插件列表 (loaded/startup) |
| loadPlugin/unloadPlugin | name | 插件加载/卸载 |
| getConfigString/setConfigString | key[=val] | 配置读写 |
| getObjectInfo | - | 选中天体详细信息 |
| getConstellationInfo | - | 当前星座 |
| getStarCount | - | 可见星数 |

### 面板功能概览
- **Search**: 搜索天体、历史记录、热门搜索、搜索结果列表
- **Time**: 日期时间选择、天文事件跳转（升起/落下/中天/晨光/昏影）、节气跳转、23 种天文时间单位、暂停/加速/后退/前进
- **Detail**: 选中天体详情（名称/类型/RA/Dec/Alt/Az/距离/星等/星座）、上一选中、居中、取消追踪、观测列表
- **Location**: GPS 定位（回退北京）、世界城市列表、经纬度/海拔输入、自定义位置
- **Layers** (View): 7 tab — Sky/SSO/DSO/Markings/Landscape/SkyCulture/Surveys，~70+ toggle
- **Settings**: 快捷设置（夜间模式/赤道仪/陀螺仪/时间控制）
- **Config**: 7 tab — Main/Info/Extras/Time/Tools/Scripts/Plugins
- **AstroCalc**: 9 tab — Position/Ephemeris/RTS/Phenomena/Charts/WUT/Planet/Eclipse/Almanac
- **Help**: 关于/快捷操作/功能面板说明

### 已知限制
1. Tab 标签无法 i18n（ArkTS 限制 $r() → Resource 类型）
2. AstroCalc 星历表/天象/图表/日食等 tab 仅有 triggerAction 按钮，无真实数据计算（需桌面版 AstroCalcDialog 的 C++ 逻辑移植）
3. DSO 星表过滤需要 NebulaMgr 位掩码 API，暂未桥接
4. 地景不随视角自动隐去（P2 KNOWN-ISSUE）
5. 模拟器 GPS 不可用（已回退到北京坐标）
