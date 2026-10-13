# 平台与验证环境矩阵（在哪跑这个应用）

> 状态：2026-09-27 查证并实测。适用于 DevEco Studio 26.0.0.821 / HarmonyOS SDK 26.0.0（API 26）/ Qt 6.12.0。
> 目的：回答"我要验证这个应用，能用哪些环境"，并记录每条结论的**证据与复现方式**，避免重复排查。

## 0. 一句话结论

**Windows 本机的 HarmonyOS 模拟器跑不了这个应用。** 可用组合只有三种：

| 方案 | 形态覆盖 | 星图能跑 | 传感器类 | 成本 | 前提 |
| --- | --- | --- | --- | --- | --- |
| **真机**（手机 / 平板） | ✅ 真实形态 | ✅ | ✅ | 已有设备 | 设备系统 ≥ HarmonyOS 7.0（API 26），UDID 已进调试 Profile |
| **Apple Silicon Mac + 官方模拟器** | ✅ 含横竖屏/分屏/自由窗口 | ✅ | ⚠️ 模拟器无法模拟磁力计 | 需要一台 M 系 Mac | 官方 arm64 镜像与我们的 arm64 包天然匹配 |
| **AGC 云调试 / 云测试**（远端真机） | ⚠️ 形态可筛，但非完整真机行为 | ✅ | ❌ 见 §3.4 | 免费额度内 0 元 | 见 §3.2 的 5 项约束 |
| 本机 x86 模拟器 + `abiFilters: x86_64` | ❌ 只有 ArkUI 外壳 | ❌ 黑屏 | ❌ | 0 元 | 只能看布局骨架，见 §1.4 |
| 树莓派 4B | ❌ | ❌ | ❌ | — | 见 §4 |

已验证的事实：最新签名 HAP（679.8 MB）在 **HUAWEI Mate 80 Pro（SGT-AL00，HarmonyOS 7.0.0 / API 26，arm64-v8a）** 上安装、启动并渲染出星图与银河，中文译名（河鼓二 Altair）与方位标注（南）正常。

---

## 1. 为什么本机模拟器不行

### 1.1 模拟器宿主只有 Windows(x86_64) 和 macOS(Apple Silicon)

官方《使用环境》（`开发指南/使用模拟器运行应用/概述/使用环境/ide-emulator-requirements`）原文要点：

- **Windows 运行环境**：CPU「具有二级地址转换 (SLAT) 的 64 位处理器…**不支持在虚拟机系统中运行模拟器**、**不支持采用 ARM CPU 的 Windows 计算机**」；RAM 16GB 起；GPU 需 OpenGL 4.1。
- **Mac 运行环境**：CPU「不支持在虚拟机系统中运行模拟器，**支持 Apple Silicon 芯片，不支持 intel 芯片**」。

《下载与安装 DevEco Studio》另确认「**DevEco Studio 支持 Windows 和 macOS 系统**」——没有 Linux 版，因此也就不存在 Linux/ARM 上的模拟器。

### 1.2 本机实测：模拟器是纯 x86，且没有 ARM 客户机支持

| 证据 | 结果 |
| --- | --- |
| `%LOCALAPPDATA%\Huawei\Emulator\deployed\lists.json` 与各 `config.ini` | 4 个 profile 全部 `"abi":"x86"`、`hw.cpu.arch=x86_64`（Pura 90 Pro / MatePad Pro 13 / Mate X7 / MateBook Pro） |
| `<DevEco>\tools\emulator\pc-bios\` | 只有 x86 固件：`bios.bin`、`bios-256k.bin`、`bios-microvm.bin`、`vgabios-*.bin`、`efi-*-rom`、`kvmvapic.bin`、`linuxboot*`、`multiboot.bin`，**没有 aarch64 固件** |
| `Emulator.exe` 内嵌字符串 | `tcg` 93 次（QEMU 动态翻译引擎，服务 x86 客户机）；`aarch64` / `arm64` 各仅 1 次 |
| 官方设备支持表（`…/概述/设备支持类型/ide-emulator-devicetype`） | 宿主按「**Windows(X86)** / macOS(ARM)」划分 → arm 镜像只随 macOS 版提供 |

### 1.3 官方要求"编译 x86_64"，没有指令集转译

- `…/概述/设备支持类型/ide-emulator-devicetype` 末段：
  > 「使用 x86 模拟器时，C++ 工程及三方库需要编译出 **x86_64 版本的 so**，请在工程级或模块级 `build-profile.json5` 的 `externalNativeOptions/abiFilters` 的值中增加 `"x86_64"`。」
- `FAQ/应用运行/Windows x86模拟器三方C/C++库使用限制`：
  > 「x86 模拟器支持**已 x86 化**的 C/C++ 三方库调试运行，未 x86 化的三方库开发者可以参考 `tpc_c_cplusplus`。」（官方给出的"已 x86 化"名单只有 MMKV、ImageKnife、ohos_videocompressor、ohos_coap、Unrar 等 11 个）
- `FAQ/程序包结构/HSP_HAR包中如何引用外部编译的so库文件`：
  > 「…新版 arm64 为 `libs/arm64-v8a`，老版 arm64 为 `libs/armeabi-v7a`，**x86 模拟器为 `libs/x86_64`**。」

**整个官方文档库没有任何 arm→x86 的转译能力**（没有 Rosetta / WOW 的等价物）。历史文档还记了一笔：早期 DevEco 3.1.1 的模拟器"仅支持 arm64"，所以那时可以在模拟器上验证；Windows 模拟器改成 x86 后就必须提供 x86 化的 so。

### 1.4 我们自己的组件：一个能编、一个编不出

| 组件 | 能否编 x86_64 | 依据 |
| --- | --- | --- |
| `libentry.so`（ArkTS↔C++ 命令桥） | ✅ 能 | OHOS NDK 自带 x86_64 sysroot：`<SDK>\native\sysroot\usr\lib\x86_64-linux-ohos` 内含 `libGLESv3.so`、`libace_napi.z.so` |
| `libstellarium.so`（41 MB，Qt 应用二进制） | ❌ 不能 | **Qt for HarmonyOS 只发布 `harmonyos_arm64_v8a`** |
| 15 个 `libQt6*.so` + `libqohos.so` | ❌ 不能 | 同上 |

Qt 侧的核实结果：安装器组件元数据（`E:\Qt\components.xml`）中所有 HarmonyOS 相关组件都是 `*.harmonyos_arm64_v8a`（连 Qt3D、qt5compat 等附加模块也只有 arm64 变体），没有 x86_64 目标；已装套件里 `libQt6Core.so` 的 ELF 头为 `Machine: AArch64`。

**结论**：星图部分在 Windows 模拟器上无解。唯一路径是**从源码为 OHOS x86_64 编译整个 Qt**（qtbase 起，含 Gui/Widgets/Charts/Svg/OpenGL/Quick 与 `qohos` 平台插件），成本以周计且官方不保证 qohos 的 x86 支持 —— 不建议。

### 1.5 "半验证"（只验壳，不验星图）—— 已实现并实测通过（2026-09-30）

`entry/build-profile.json5` 的 `abiFilters` **本来就同时含 `arm64-v8a` 与 `x86_64`**，`libentry.so` 一直有 x86_64 版本；
缺的只是 Qt/Stellarium 引擎（只有 arm64）。真正挡住界面的是两道启动门控，现已在 **debug-only 条件下放行**：

- 代码侧（提交 `94379aa31f`）：`qability/QAbility.ets` 新增 `engineLessEmulatorUiOnly()`
  = `BuildProfile.DEBUG && deviceInfo.productModel === 'emulator' && deviceInfo.abiList.includes('x86_64')`，
  在根页面加载后放开四个门控键；`pages/ApplicationRoot.ets` 的 `aboutToAppear()` 补 `onSkyReady()`，
  避免门控早于页面挂载导致加载层不消失。真机与 release 包上条件恒为假。
- 模拟器本机前置条件（不涉及仓库）：`hw.ramSize` 4096 → 3072（`config.ini` + `hardware-qemu.ini`），
  镜像 `features.ini` 的 `camera.feature` / `camera.front.back.enable` 置 `off`。
  不改这两项时：09-28 那次模拟器自检直接报 `"Commit charge is not enough!"`；09-30 那次启动到 guest 1.27 s
  即 crash type 2（崩溃瞬间宿主仅剩 4,713 MB 空闲，且崩溃前 0.6 s 刚打开宿主摄像头）。

实测结果（Pura 90 Pro，`127.0.0.1:5555`，`abilist=x86_64`，API 26，`productModel=emulator`）：

- **能得到**：ArkUI 外壳完整渲染（Dock 五项 + 右上陀螺仪/音频按钮）、面板开关与交互（时间面板标题/副标题/日期转轮/速度 chips）、断点与布局、`.id()` 锚点（`panel-close`、`panel-scroll-*`、`panel-content-*` 等）、`devecocli ui layout/click` 语义化操作与截图。
- **得不到**：星图渲染、Qt 命令桥返回的任何数据（`libstellarium.so` 是 arm64，`dlopen` 必然失败，桥回退 `bridge not available`）→ 时间面板显示 `--`。**不等于"能运行此应用"**，引擎相关状态仍需真机复验。
- **注意**：隐私门控在模拟器上永远拿不到同意（AppGallery 返回 `1006700003`），所以必须走上述 debug 放行；
  该放行不得进入发布链路。

---

## 2. 方案对照与选择建议

| 想验证 | 用哪个 | 备注 |
| --- | --- | --- |
| 星图渲染、面板/布局、多语言、离线资源、命令桥 | 真机 / Apple Silicon 模拟器 / 云调试 | 云上不具备完整真机行为，见 §3.4 |
| 手机形态 vs 平板形态兼容性 | 真机（两台）或云调试（筛形态） | 原作者只在**平板**上做过真机验证，手机分支长期未实测 |
| 陀螺仪指向、指南针校准、折叠状态、真实帧率 | **只能真机** | 官方记录云调试下折叠状态监听失效；模拟器无法模拟磁力计 |
| 兼容性/性能/稳定性/UX/功耗专项报告 | DevEco Testing「上架预检（本地）」或 AGC 云测试 | 本地预检 0 成本但只有你接入的机型；云测试提供机型矩阵 |

**建议优先序**：真机（已有 Mate 80 Pro）> 借一台平板（或 AGC 云调试，0 元先试）> Apple Silicon Mac。

---

## 3. AGC 云调试 / 云测试

### 3.1 两项服务的定位

- **云调试（Cloud Debugging）**——远程租用真机，视频流投屏 + 可交互，可上传 HAP/APP 安装调试。官方定位（`FAQ/UI框架/组件使用/云调试环境下无法监听折叠屏屏幕状态的改变`）：
  > 「云调试致力于为开发者提供高效的**云端设备调试**解决方案，解决开发者**设备机型不足、设备管理困难及 bug 无法复现**等问题，降低开发者的采购及管理成本。」
- **云测试（Cloud Testing）**——上传 APP/HAP，在真机机房自动跑**兼容性、稳定性、性能、功耗、UX** 等专项并出报告。
- 相关的本地替代：**DevEco Testing「应用上架预检（本地）」**（`开发指南/专项测试/DevEco_Testing/上架预检/publish-testing`）与 **AppAnalyzer**（可导入上架审核不通过报告做诊断，官方注明仅支持手机报告）。

### 3.2 五项硬约束

| 约束 | 官方依据 | 本项目状态 |
| --- | --- | --- |
| 只能上传 **HAP / APP** | `FAQ/应用调试/云调试应用安装失败常见问题…` 问题三 | ✅ 我们不产出 apk |
| **机型系统版本必须与包匹配** | 同 FAQ 问题四：`error: failed to install bundle. code:9568297 error: install failed due to older sdk version in the device`；问题二：机型 API 9 与 `compatibleSdkVersion 4.0.0(10)` 不兼容 | ⚠️ 我们 `compileSdkVersion/targetSdkVersion = 26.0.0`（HarmonyOS 7.0 / API 26）→ 必须筛到 7.0/API 26 机型 |
| **应用类型要与设备形态匹配** | 同 FAQ 问题六（2in1 应用选 matebook pro 仍报类型错误）、问题七（APP 内含多形态 product 的 hap 不能直接装） | 我们单 HAP，声明 `phone/tablet/2in1`，手机或平板机型应可用 |
| **证书类型** | `FAQ/应用市场服务/使用AppGallery邀请测试打包使用什么类型的证书`：邀请测试用**发布证书**；「使用调试证书生成的安装包仅支持本地调试，使用发布证书生成的安装包仅支持 AGC 做测试或上架」 | ⚠️ 我们现在是 DevEco **自动签名（debugKey）**；云调试 FAQ 里出现"安装 release 包"的报错说明 release 可上传，**debug 包是否被接受需在 AGC 页面确认**，稳妥做法是申请发布证书 + Profile 重打 |
| **实名认证 + 免费额度** | FAQ 提到"浪费**免费体验时长**" | 见 §3.3 |

> 若云侧暂时没有 HarmonyOS 7.0 机型，可另打一个"云测试专用包"：把 `targetSdkVersion` 降到 `6.0.2(22)`。我们并未真正调用 API 26 专属接口（`setImageForRecent` / `removeImageForRecent` 只是适配器转发，运行时不会被调用），因此这样能装到 API 22+ 的云机型上，代价是多一个构建变体。

### 3.3 额度（免费体验时长）

**本地文档库没有计费/配额页**。已穷举检索的关键词：`免费时长`、`计费`、`计时`、`配额`、`剩余时长`、`资源包`、`占用`、`释放设备` —— 只命中一条 FAQ。

有官方依据的两条机制事实：

1. **额度形态是「免费体验时长」**，按账号发放。依据：
   > `问题五：云调试上传软件包耗时过长，浪费免费体验时长。`
2. **上传时间占用同一份额度**。依据是官方给的解决办法：
   > 「（解决）在 **云调试 - 我的信息 - 应用** 中，**提前上传**需要调试的应用。选择调试设备，应用中显示已上传的应用，点击安装即可。」

   官方专门给出"预上传"这一做法，说明上传与调试共用同一份额度。

**查询入口（按权威度）**：

1. **AGC 控制台的云调试页面** —— 唯一能给出实时余额的地方：登录 `https://developer.huawei.com`（此域名取自 IDE 内嵌配置，已核实）→ 进入项目 → 左侧找「云调试」（不同版本可能归在「质量」或「测试服务」分组下），页面显示剩余时长与会话倒计时。
2. **官方文档中心**搜「云调试」，找该服务的概述 / 计费说明。注意：IDE 内嵌的 `agc-harmonyos-clouddev-*` 文档 ID 是**端云一体化**（Serverless 云函数/云数据库），不是云调试。
3. **AGC 工单**：页面上没写清时直接问。

**尚未确认的四项（必须以 AGC 页面为准，不要据此做预算）**：免费额度的具体数值与发放周期；计时的精确起止（从"设备分配"还是"进入投屏"开始、离开页面是否暂停、闲置多久回收）；能否手动提前结束以省时长；超量计费与资源包价格。

**3 分钟自测办法**：先在「我的信息 → 应用」上传包（官方建议的省时长做法），进入设备页 → 记录初始倒计时 → 停留 1 分钟 → 再看倒计时；同时刷新页面、切后台各一次。可直接实测出计时起点、是否暂停与扣减粒度。

**省钱操作顺序**：① 预上传包（我们的包 680 MB，云侧上传不便宜）；② 进设备前先筛好机型（系统版本 HarmonyOS 7.0/API 26、形态选手机或平板），避免报 `9568297` 白开一次会话；③ 拿到结论后主动释放设备；④ 不把额度花在传感器类验证上。

### 3.4 能力边界

`FAQ/UI框架/组件使用/云调试环境下无法监听折叠屏屏幕状态的改变` 明确记录：**云调试环境下 `display.on('foldStatusChange')` 无法监听折叠屏状态变化**。说明云调试是"远程真机 + 视频流"，**传感器与硬件状态类能力不等同真机**。因此陀螺仪指向、指南针校准、折叠状态这类验证必须留在本地真机。

---

## 4. 树莓派 4B 评估（不可行）

三层原因：

1. **模拟器没有 Linux/ARM 宿主**：宿主只有 Windows(x86_64) 与 macOS(Apple Silicon)（见 §1.1），且 DevEco Studio 本身不发 Linux 版 → 树莓派不能当模拟器宿主。
2. **树莓派上只能刷 OpenHarmony（社区移植），那不是 HarmonyOS**：`FAQ/模拟器/模拟器运行应用报错提示设备和应用的API版本不匹配` 记有「**OpenHarmony 社区支持 22 款开发板**」。而本项目是 `runtimeOS: "HarmonyOS"` 且依赖 HarmonyOS SDK 26.0.0 与 HMS，装不到 OpenHarmony 上——官方 `FAQ/编译构建/新建OpenHarmony工程仅修改打包方式未改配置导致加载so库闪退` 正讲这个坑：「…应用安装成功但**在调用加载 so 库的函数时发生闪退**…需要确保**编译运行环境与目标系统匹配**」。此外 RPi 的社区 OpenHarmony 镜像 API 版本普遍很早期（9~12 时代），与我们要的 API 26 差距过大。
3. **它也当不了构建机**：OHOS SDK 的 native 工具链只有 Linux **x86_64** / Windows **x86_64** 二进制，aarch64 Linux 上无法执行。

> 纯旁路：树莓派装 Raspberry Pi OS 后可编译**桌面版 Stellarium（Qt6 + GLES）**，但那只验证上游 Qt 渲染，完全不覆盖鸿蒙侧（ArkUI、HAP 打包、签名、命令桥、OHOS 图形路径、平板断点布局），不能当作 MatePad 验证的替代。

---

## 5. 复现这些结论的方式

```powershell
# 1) 模拟器 ABI 与 profile
Get-Content "$env:LOCALAPPDATA\Huawei\Emulator\deployed\lists.json"
Get-Content "$env:LOCALAPPDATA\Huawei\Emulator\deployed\Pura 90 Pro\config.ini"   # hw.cpu.arch / imageSubPath

# 2) 模拟器后端是否支持 ARM 客户机
Get-ChildItem "<DevEco>\tools\emulator\pc-bios"                                   # 只有 x86 固件

# 3) 本机 SDK 是否具备 x86_64 原生能力
Test-Path "<DevEco>\sdk\default\openharmony\native\sysroot\usr\lib\x86_64-linux-ohos"

# 4) Qt for HarmonyOS 是否有 x86_64 目标
Select-String -Path "E:\Qt\components.xml" -Pattern "harmonyos"
Get-ChildItem "E:\Qt\6.12.0" -Directory                                          # 只有 harmonyos_arm64_v8a

# 5) 查官方文档（本地库）
devecocli docs search "使用 x86 模拟器时 C++ 工程及三方库"        → ide-emulator-devicetype
devecocli docs search "x86模拟器三方C_C_库使用限制"               → faqs-app-running-25
devecocli docs search "云调试应用安装失败"                        → faqs-app-debugging-80
devecocli docs search "云调试环境下无法监听折叠屏"                 → faqs-arkui-1589
```

### 引用到的官方文档

| 文档 | 内容 |
| --- | --- |
| `开发指南/使用模拟器运行应用/概述/使用环境/ide-emulator-requirements` | 模拟器宿主环境要求（Windows x86 / macOS Apple Silicon） |
| `开发指南/使用模拟器运行应用/概述/设备支持类型/ide-emulator-devicetype` | 设备类型支持表 + x86 模拟器需编译 x86_64 so |
| `FAQ/应用运行/Windows x86模拟器三方C_C_库使用限制/faqs-app-running-25` | 三方库必须"已 x86 化" |
| `FAQ/程序包结构/HSP_HAR包中如何引用外部编译的so库文件/faqs-package-structure-6` | x86 模拟器的 so 目录为 `libs/x86_64` |
| `FAQ/应用调试/云调试应用安装失败常见问题排查与解决方案/faqs-app-debugging-80` | 云调试 7 类安装问题 + 预上传省时长 |
| `FAQ/UI框架/组件使用/云调试环境下无法监听折叠屏屏幕状态的改变/faqs-arkui-1589` | 云调试能力边界 |
| `FAQ/模拟器/模拟器运行应用报错提示设备和应用的API版本不匹配/faqs-simulator-3` | OpenHarmony 社区开发板范围 |
| `FAQ/编译构建/新建OpenHarmony工程仅修改打包方式未改配置导致加载so库闪退/faqs-compiling-and-building-new-00001` | OpenHarmony 与 HarmonyOS 运行环境不通用 |
| `FAQ/应用市场服务_AppGallery_Kit/使用AppGallery邀请测试打包使用什么类型的证书/faqs-appgallery-49` | 调试证书 vs 发布证书的适用范围 |
| `开发指南/专项测试/DevEco_Testing/上架预检/publish-testing` | 本地上架预检（兼容性/性能/稳定性/UX/功耗） |
