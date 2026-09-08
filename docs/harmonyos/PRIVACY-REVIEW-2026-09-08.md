# 隐私审核整改与 AGC 草稿记录

## 已核对的事实

### SDK 实际修复及 Pad 回归（2026-09-08 16:30）

- 当前生成工程及独立 Debug 测试包已替换为精确 SDK 源码构建的 libqohos，后文“当前库未替换”是本轮修复前的诊断状态。通知回调不再访问 OH_Pasteboard_GetData，仅失效缓存；新增原生设备信息阶段探针，不记录设备标识值。源码、构建门禁和限制见 `QT-CLIPBOARD-REVIEW-FIX.md`。
- Qt 平台插件、Stellarium 核心构建通过。主工程 Release `default@CompileArkTS` 通过（54.638 秒）；独立 Debug 最终 assembleHap 通过（13.549 秒）并覆盖安装。主工程签名配置 SHA256 与基线一致。
- 39 项隐私/启动/剪贴板测试、358 命令目录检查通过。Pad 20 次系统异步复制、图层切换、查询共 83 个响应全部成功，CLI 端到端最高 662 ms（包含设备传输，不是帧耗时）。新库变化通知探针在真实设备出现，当前采样日志未检出 AppFreeze。截图确认主星图正常显示，不以这轮测试保证所有冻结已根除。
- 用户撤回后，进程 25930 于 16:32:00 冷启动；16:32:00.507 请求系统弹窗，16:32:04 返回同意，16:32:04.997 才进入原生 device-info 读取；系统 SN/UDID IPC 返回失败，不冒称取得了值。短暂未同意阶段无此原生探针，但同意来源及长时间拒绝状态仍需确认。
- 政策按用户要求暂不改动、不提交审核；后续须统一实际功能披露，不能把同意后仍有的 SDK SN 尝试写成完全不访问。

最终确认：用户明确说明第一次是本人点击“同意”。第二次撤回后进程 27848 于 16:36:43 启动，至少至 16:37:46 仍停留系统弹窗；pending 检查确认零 Qt setup、零 SDK device-info 探针、零本进程 SN/UDID IPC 日志。截图已本地检查，用户已获通知恢复操作。此为独立 Debug 包真实调用链验收，不冒充 AGC Release 自动检测报告。用户随后表示已提交审核，要求暂不改政策，已停止协议操作；本轮没有 AGC 写入。

最新结论以本文的“审核 ZIP 与正式政策复核”为准；此前各阶段记录保留，不代表草稿已正式发布。

### 审核 ZIP 与正式政策复核（2026-09-08 下午）

- 已读取用户提供的审核 ZIP，故障版本为 Release 1.0.9 / 1000049，设备 MatePad Pro，故障时间 9 月 7 日 00:52:41。主线程 uvLoopTask 从 00:52:15.038 持续未完成；采样栈为 libqohos → OH_Pasteboard_GetData → GetPasteData → Binder 等待。QtMainThread 同时在 glBufferSubData 驱动等待，不能凭单次堆栈排除关联或解释另一个业务线程冻结事件。
- 当前 libqohos Build ID 与故障库完全相同：`34740ad381912581a0fbd5bd8db7b7b60cba2482`。之前应用层启动改动未替换该库，因此不能宣布此故障已解决。
- SDK 自带 SBOM 确认实际 qtbase 修订为 `97575d35c0cecdc0fb4e12fc3575afaa9fd9d3f1`，不再将最新 dev 树当作实际 SDK 源码。该修订 qohosclipboardobject.cpp 的 SHA1 `2beca4b72fb6b0afbe0f34320e743165e3d26d53` 与 SBOM 完全相符：剪贴板本地/远端变化通知会在 JS 主线程同步读取整个剪贴板，仅用于判断缓存是否由自己写入。即使用户只在图层页操作，也可能进入此通知链。
- SN 对应同一 SDK 修订的 initDeviceInfo 字段读取；现有 QAbilityStage 与根页面继续在有效政策同意前拦截 setupQtApplication。保留用户要求的同意后 SDK 能力，不增加 ACCESS_UDID 权限。35 项隐私/启动测试通过，其中新增生命周期未同意零 Qt 调用、同意后初始化单次/顺序测试；模拟断言不等同于系统隐私检测结果。
- Edge AGC 实际只读核对：测试版本仍为 9 月 7 日上传的 1000049。当前仅一份完成态隐私政策（8 月 4 日版本），正文仍缺重力/磁场/旋转矢量；测试版本隐私标签已列重力，不能用标签替代政策正文。旧整改草稿已经不在协议列表中，先前记录中的草稿状态不能当作当前状态。
- 构建号已按用户要求预备为 1000050，展示版本保持 1.0.9；现有 default 产品已引用 release，配置哈希未变。用户随后要求先修故障，暂停上传/协议操作，不自动提交审核。
- 正在独立构建匹配 SDK 的 Qt 平台插件以修正通知链；不直接替换全局 Qt SDK，不进行二进制地址修改，不删探针掩盖问题。原始审核 ZIP、完整故障日志、截图与 trace 保留在本机，不加入 Git。

官方核对：[AppFreeze 分析](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/appfreeze-guidelines)、[剪贴板接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-pasteboard)。华为文档要求避免 UI 线程同步读取剪贴板；普通通知失效缓存无需读取用户内容。

- 用户反馈：重力传感器未披露、同意前 SN 调用、`APP_INPUT_BLOCK`。
- Edge AGC 信息中心的 1.0.9 审核意见另显示 `BUSSINESS_THREAD_BLOCK_6S`（MatePad Pro 11、HarmonyOS 6.1/API 23）；另有启动 8268 ms 与设备转向闪动建议。两种冻结记录不能混为同一根因，仍需完整故障栈和时间线。
- 现行托管协议 `2004631976732052288`（更新 2026-08-04）已列 SN、定位、方向、陀螺仪、加速器，但漏重力、磁场和旋转矢量；用途笼统。服务器存储声明与当前应用本地处理实现尚不一致。
- 用户确认将来计划备案并使用境内服务器。这是后续设计，不是当前已经上传位置、传感器或 SN 的证据。资源下载与用户信息上传须分开披露。

## 已实施的代码整改

- 隐私宿主页准备阶段不再初始化 Qt；初始化及原生渲染释放都要求匹配当前协议 ID、版本和明确同意结果。异步资源准备后再次检查，防止撤回及后台切换竞态。
- 串行化启动；增加仅记录状态和延迟的事件循环阻塞探针。探针不是冻结根因结论，也不能代替业务线程故障栈。
- 定位和姿态订阅增加隐私及前台检查；定位在权限和获取结果返回后复核，拒绝或失败保留原地点。
- 常规传感器探针去除原始姿态测量值；部分安装缺失资源通过异步修复，不再回退全量同步解包。
- 未确认 `libqohos.so` 内部 SN 的具体读取字段、必要性和处理路径；初始化延后不等同于 SN 问题全部解决。

## AGC 实际操作

- 在“协议服务”新建并保存 **星象仪隐私政策整改草稿20260908**，页面返回“保存成功”。未生成协议、未提交审核、未更换现行协议或客户端协议 ID。
- 草稿写入定位、姿态用途/时机/停止条件、本地保存期限、主动分享、撤回同意说明，保留现行开发者姓名及联系邮箱。
- 结构化数据项已核对显示磁力计、屏幕方向、重力、陀螺仪和旋转矢量；自定义说明补充系统融合可能使用加速度计。
- 草稿仍不完整：处理依据、其余结构化数据和权限项、SDK/SN 核验及固定服务器模板需完成；不能直接生成作为正式隐私政策。SN 不应填成“仅连接外设时获取”。
- 本地 `docs/PRIVACY-POLICY.md` 与 `docs/privacy/index.html` 同样标记整改草案，不会自动替换 AGC 托管内容。发布前应以同一最终版本统一客户端展示和 AGC 链接。

## 验证和发布阻塞

- 10 项隐私启动测试通过；最终 CompileArkTS 成功，44.741 秒；存在既有 API 弃用告警。
- 生成工程源码同步完成，build-profile SHA-256 与基线一致；未改签名、未签名打包、未安装真机。
- 官方 Privacy Manager 不支持模拟器；需要真机验证全新安装、拒绝、同意、撤回重启、协议升级、前后台切换及设备转向。不能用编译和模拟测试宣称审核通过。
- 冻结验证须脱离 DevEco 调试器进行正常启动，采集完整故障栈及日志；不得仅凭新增探针宣称 `APP_INPUT_BLOCK` / `BUSSINESS_THREAD_BLOCK_6S` 已解决。

## Pad 无线回归（后续执行）

- 已连接用户 Pad，覆盖屏幕超时为 24 小时；设备亮度确认 `DeviceBrightness=1`、`Min=1`。最小亮度键 2724 在此设备无效，工作流新增有界 41 调暗键回退和数值核验。
- 主工程 Release 构建成功（52.439 秒），但安装报 `9568322`，不受信任的应用来源。未卸载现有应用、未降低系统校验。
- 用户随后明确允许独立 Debug 测试副本；副本位于仓库外的私有临时目录，复用已有 default 调试签名。主工程 signingConfig 保持 release，原证书、密钥及配置未改。测试包覆盖安装成功。
- 真机首轮复现 1300002：未加载 UIContent 时设置背景色，导致流程停在启动图标；取消同意前的外观调用，维持单次 Qt 页面加载。
- 第二轮发现资源必需标记为隐藏文件，实际 HAP 中不存在；异步解包后仍判定缺失而退出初始化。修订资源同步流程，在转换完成后生成非隐藏标记，保留异常 message。本轮同时出现 WINDOW_FROZEN_DETECTION，不能将该现象误当作隐私成功或已解决审核全部冻结。
- 新增 CLI `openUiPanel/settingsPrivacy`，仅打开隐私设置，不代用户授权或撤回。后续版本打包、覆盖安装与授权顺序验证继续进行。

### 撤回后启动图标停留的第二层原因

- 真机日志确认撤回流程执行 `DisableService` 和 `terminateSelf`，不是将该次正常退出归为无证据的崩溃。重新启动后停在 `dialog-request-start`，AppGalleryKit 明确记录 `GetUIContentFromBaseContext result failed, uiContent is null`；取得 MainWindow 不代表页面内容已创建。
- 官方隐私管理文档要求同一 Ability 不重复 loadContent。新增不对外导出的 `PrivacyAbility`，只加载一次轻量 `PrivacyBootstrap`，内容加载回调完成后再调用官方弹窗；此页不调用 Qt、命令桥、定位或传感器。主 QAbility 不加载隐私页面，仍由 Qt 唯一加载星图页。
- 同意结果和当前协议再次匹配后才返回 QAbility；拒绝或错误留在轻量页，可重新查看系统提示或关闭，不伪造同意。不在应用页面复制第二套隐私同意条款。新提示简繁中文/英文齐备，其他界面语言回退英文，系统政策语言仍由 Privacy Manager 管理。
- 独立测试构建暴露既有 MainWindow 类型标注错误，补全映射回调返回值、结构化字段 Record 类型和模型 worker 的 lighting/ring 接口显式字段；未借机修改业务或签名。完整 CompileArkTS 通过后继续以独立 Debug 包回归。
- 当前 19 项隐私与文化资源刷新测试通过；内部隐私宿主版 assembleHap 成功（17.962 秒），真机弹窗及返回星图结果在后续记录中追加。

### 内部宿主页实机结果（11:41）

- 覆盖安装成功，未卸载或清除数据。正常启动（未挂调试器）后约 0.43 秒宿主 UIContent 加载完成，随后进入系统隐私请求；实机截图确认“取消/同意”标准弹窗可见，已脱离永久启动图标。
- 该进程从启动到等候用户选择期间，探针的 `accepted/qtAbilityCreated/qtInitialized` 均为 false，无 `qt-setup-start`。这验证了本次未同意路径的初始化隔离，不能推导为所有原生 SN API 已无调用或审核必然通过。
- 已请用户自行阅读并选择，未代点同意；同意后跳转、暖启动和完整冻结回归仍需后续验证。轻量宿主页不改变 AGC 现行政策链接，草稿仍未发布。

### 用户同意后的回归与后台任务修订

- 日志随后记录用户完成系统选择：11:41:58.543 弹窗结果返回，11:41:59.342 才进入 Qt setup，59.707 释放原生节点；进程持续输出星图帧。该次资源检查约几百毫秒，没有再次全量解包。并非 Agent 代为同意。
- 用户指出隐私页上下系统栏未沉浸、最近任务中有两张应用卡片；实机截图复现。新增宿主页内容加载后的背景色、全屏布局、系统栏与导航提示条处理，并在回到前台时恢复；不在页面加载前调用外观 API。
- 内部 PrivacyAbility 原本结束后仍保留历史任务，现配置 `removeMissionAfterTerminate: true`。不使用 `excludeFromMissions`：当前官方文档明确其对第三方应用不生效，不能假装开启该字段即可隐藏任务。
- 同应用 Ability 往返使用 `withAnimation: false`；官方仅保证自由窗口下生效，不能将其描述为所有全屏设备都无切换动画。架构仍有内部隐私宿主，不宣称已重构成单 Ability/单 Window。若仍能感知全屏切换，需继续验证 Qt 内容加载适配，而不是恢复同意前 Qt 初始化。
- 22 项回归测试通过，独立 Debug assembleHap 成功（21.113 秒）；覆盖安装后继续检查宿主页、同意往返和最近任务。
- 11:49 覆盖安装成功并截图：隐私页上下白色系统栏背景消除、全屏暗色底正常，系统弹窗下仍可显示系统手势提示条。日志确认 `privacy-host-immersive-ready`，未进入 Qt setup。用户尚未选择，退出后任务清除和全屏交接动画尚未完成新版本实机确认；不得据配置直接标记为视觉验收通过。主工程签名哈希再次一致，设备亮度仍为最低 1。

相关官方依据：[Module 配置](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/module-configuration-file)、[StartOptions](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-startoptions)。

### 无线回归官方资料

- [键值定义](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-keycode)：2724 最小亮度键、41 调暗键；实际必须读取设备状态验证。
- [窗口常见问题](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/window-faqs)：在页面加载完成后设置窗口背景色。
- [安装工具错误码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/bm-tool)：签名信任失败不能靠修改应用代码或权限绕过。

### 前期官方依据

- [配置隐私政策](https://developer.huawei.com/consumer/cn/doc/app/agc-help-privacy-policy-app-0000002282162168)：按实际处理情况填写；支持保存草稿，生成与发布是后续操作。
- [隐私托管 FAQ](https://developer.huawei.com/consumer/cn/doc/app/agc-help-privacy-policy-faq-0000002342315628)：客户端与托管协议一致，避免重复自建首次隐私弹窗。
- [隐私管理服务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/store-privacy)：初始化/授权和真机测试边界。
- [隐私管理接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/store-privacymanager)：协议 ID、版本和同意结果校验。
- [AppFreeze 分析](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/appfreeze-guidelines)：区分输入阻塞与线程阻塞，检查完整故障记录。

## 单窗口与星点启动页（12:01 起，替代临时 PrivacyAbility）

- ApplicationRoot 是唯一主页面；QtWindowStageAdapter 将原生 createInfo 对象和回调原样放入根 LocalStorage，不再次调用真实 WindowStage.loadContent。未同意时不构建 WindowNativeNode。已删除临时 PrivacyAbility，不使用隐藏历史任务冒充单窗口。
- 进程 59743：12:01:09.709 窗口 307 加载一次；12:01:09.888 请求官方同意，用户于 12:01:20.191 完成选择；Qt setup 为 12:01:20.860。帧输出和真实星图截图均已确认。用户随后确认不再跳窗口。
- 进程 64550：12:13:35.077 窗口 315 加载一次；12:13:35.247 至 12:14:05.931 等待用户本人选择；12:14:06.612 才进入 Qt setup。CLI getAppState 成功、约 30fps。没有代理代点同意或清除用户数据。
- 两段应用加载画面改为根层持续存在的 StartupSky，跨隐私流程与 Qt 接入不重建。Canvas/OffscreenCanvas 从本地字体生成字形粒子；简中“星象仪”、繁中“星象儀”，其他语言复用原有 QAbility_label，不擅自翻译品牌名。普通语言仍可能使用品牌 Stellarium，不能称作每种语言有不同译名。
- 初版真机发现系统启动图标遮住了 Canvas；根据[WindowStage 官方接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-window-windowstage#removestartingwindow14)，在首帧回调后移除系统启动页，并配置 enable.remove.starting.window。官方还提供五秒超时兜底；并非再次创建页面或强制延长系统开屏。
- 用户要求最终字形仍由星点组成：正常路径不绘制实心文字，后台和组件卸载停止调度。最新要求取消整体规则旋转：900 背景星与最多 900 字形星使用逐星独立的缓慢连续漂移，不逐帧随机跳位，也无最小半径中心空洞；大小、明暗、白/淡蓝/暖金色及闪烁周期各异。字形采样限制 30000 次，归一化到实际轮廓边界并分六批圆形路径绘制。真实呈现就绪后约 720ms 汇字、620ms EaseInOut 淡入，不让固定启动动画冒充核心加载完成。只在字体像素采样失败时回退文字。
- 首帧日志为 1023×767，而稳定后 getViewportSize 为 2560×1600。原入口呈现器把任何源帧拉满 Surface；现两条纹理/RGBA 路径均等比例呈现，过渡尺寸暂时留边，不降低画质或目标分辨率。最新通过 `getPresentationState` 原子快照读取两次实际成功提交的比例匹配帧，免除 Qt 异步查询的额外等待；Surface 创建/变化/销毁清零。仅记录尺寸及阶段耗时，不获取 SN/UDID。
- QtWindowStageAdapter 为当前 Qt 6.12 的应用自有兼容层；升级 Qt 须回归 createInfo、回调重载、窗口恢复和隐私路径，不宣称是 Qt 官方插件接口。

## SN 来源进一步核查（仍非“零读取”结案）

- 官方 Qt dev 树 `71794df97d32ff6a06dfc47dd40abf47132af367` 的 [qohosjsmain.cpp](https://github.com/qt/qtbase/blob/71794df97d32ff6a06dfc47dd40abf47132af367/src/plugins/platforms/ohos/qohosjsmain.cpp)：setupQtApplicationImpl → initAppData → initDeviceInfo，strPropertiesMap 包含 serial、udid，循环读取后存入 QOhosDeviceInfo 缓存。此源文件 blob 为 `7c546b10199a9531107ba54d3ab43e7f8f9d3385`。当前 SDK 二进制也含对应模块/字段字符串，但尚未证明它与该上游提交逐字一致。
- Pad 进程 64550 在用户同意后的 12:14:06.614 出现 IDeviceInfo IPC 失败，时间落在 Qt setup 内；这支持继续核验该初始化路径，不能凭失败认定取得了真实 SN，也不能凭普通日志没有 SN 字样认定没有调用。
- 华为 MCP 的 [deviceInfo 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-device-info)说明 serial 权限受限且调用可能阻塞。业务 ArkTS 和 manifest 检索未发现直接 serial/udid 读取或 ACCESS_UDID 申请；未增加权限或记录标识符原值。
- 当前证据结论：用户未同意期间已阻断已知 Qt setup 链；同意后 Qt SDK 仍存在标识符读取尝试的风险。2026-09-08 用户明确要求暂不移除 serial/udid 清单，保留 SDK 能力并维持有效隐私同意后初始化；暂停此前建议的移除及平台库重建方案。当前尚未发现星图业务必须使用 SN/UDID 的用途，也未确认实际读取成功，不能以未来可能需要为由虚构当前用途或扩充权限。隐私说明须区分 SDK 读取尝试、实际取得、存储与传输，按证据修订；同意时序测试不等同于 AGC 审核通过。不可通过隐藏探针、伪造授权、修改日志或政策泛化来代替整改。
- AGC 新草稿尚未生成发布，正式隐私协议未替换；本轮无线日志不是 AGC 隐私检测报告，APP_INPUT_BLOCK 等完整冻结报告仍待复核。

## 加载提示与亮星汇字补充验证（13:02）

以下为该轮验证记录。随后根据用户反馈去掉转圈和胶囊，仅保留轻淡加载文字，并加入空间层次转场；最新视觉规范见 [启动星空动效](STARTUP-MOTION-DESIGN.md)。这些视觉修订不改变本节隐私门控结论。

- 通过华为开发文档 MCP 核对 [LoadingProgress](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-loadingprogress)，采用官方组件及 enableLoading 前后台控制，不自绘转圈或新增弹窗。加载提示使用现有 msg_loading 翻译，放在名称下方，跟随整个加载层淡出；没有新增权限、网络或设备信息读取。
- 独立星点漂移提高至原先 1.4 倍；汇字星半径逐渐增加 50%、透明度最多增加 0.2，不增加采样数，不使用实心文字替代正常粒子字形。
- Pad PID 26053：13:02:10.468 确认有效同意，13:02:10.857 开始 Qt setup，13:02:23.912 呈现就绪，13:02:24.636 汇字完成，13:02:25.275 淡入完成。本次使用用户已保存的有效同意，并非新一轮撤回后手动同意测试；只能佐证已知初始化调用链的时序，不能据此保证 SDK 全路径零读取或 AGC 通过。
- 35 项 Node 回归通过，独立 Debug 包构建及覆盖安装成功，中文横屏截图已检查，CLI 呈现就绪为 2560×1600；主 Release 签名配置未变。当前启动仍约 15.3 秒，视觉提示不替代核心性能优化。
