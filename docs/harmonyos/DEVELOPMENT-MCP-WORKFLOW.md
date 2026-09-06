# HarmonyOS 开发查询与验证流程

## 目的

本项目使用华为开发者知识 MCP 核对 HarmonyOS、ArkTS、ArkUI、CLI 和系统 Kit 的官方能力。MCP 只服务于开发机上的资料查询，不随 HAP 打包，也不改变应用的离线边界。

## MCP 配置

在 Codex 或其他 MCP 客户端的开发配置中登记官方服务：

```json
{
  "mcpServers": {
    "harmonyos_developer_knowledge": {
      "url": "https://connect-api.cloud.huawei.com/api/developerknowledge/mcp"
    }
  }
}
```

配置完成后重启 MCP 客户端，并先用 `searchDocuments` 查询，再用返回的 `parent` 调用 `getDocumentsById` 获取完整文档。不要把搜索结果片段当作完整 API 规范，也不要根据搜索摘要臆造接口。

## 何时必须查询

- 不确定 ArkUI 组件、属性、事件、手势、动画或命中测试语义时。
- 涉及窗口断点、分屏、自由窗口、折叠屏、手机/平板/PC 适配时。
- 涉及权限、隐私、通知、后台任务、文件选择器、系统 AI 或 Ability 交互时。
- 需要确认 API 起始版本、模型约束、系统能力或设备限制时。

查询记录至少保留关键词、文档标题或 `parent`、官方 URI、适用 API 版本和对当前工程的结论。涉及联网、位置、设备标识或敏感权限的查询，还要同步检查 `NETWORK-INVENTORY.md`。

## 当前适配约束

- 当前工程基于 OpenHarmony 基础 SDK API 24。实现优先使用窗口尺寸和已有 `onAreaChange` 状态，不直接引入 API 26 才支持的 `ContainerReader`。
- 手机、Pad 和未来 PC 共用 `ShellAction`、`setPanel`、命令桥和状态模型；只允许改变排列、尺寸、间距和面板呈现方式，不按设备类型复制业务逻辑。
- 响应式布局按窗口宽度/高度断点判断，并覆盖横竖屏、分屏、悬浮窗和可调整窗口。不要仅凭物理设备型号判断布局。
- 当前统一底部 Dock 是正式入口。旧 iPad 左侧侧栏只保留兼容符号，不得重新作为新入口。

## ArkUI 动画约定

- 状态驱动的属性变化使用 `getUIContext().animateTo`，所有参与动画的状态修改放在动画闭包内。
- 组件插入和删除使用 `transition`，进入和退出分别定义时长、透明度和位移。
- 面板路由、Dock、筛选页和脚本控制条使用同一套短时淡入/位移/弹性曲线，避免每个页面自行发明动画。
- 动画不能改变星图的天体位置，也不能抢占 Scroll、Slider、TextInput 或按钮的命中区域。动画期间仍要保持明确的 `hitTestBehavior`。

### 设置选项统一规范（2026-09-06 MCP 核验）

- 信息级别、日期格式、时间格式、启动时间模式共用 `settingsChoiceButton`，显式 `ButtonType.Normal` + 项目 `UI_RADIUS_CONTROL`（14vp），最小高度 40vp，文字可换行。14vp 和 180ms 是本项目设计选择，不是官方强制值。
- 胶囊类型的圆角由宽高决定，`borderRadius` 对它不生效；不能混用胶囊按钮、默认类型按钮和可点击 Text 再靠同一个半径数值声称外观统一。
- 稳定选项的选中背景使用声明式 `.animation({ duration: 180, curve: Curve.EaseOut })`，放在背景属性之后、布局属性之前；无论触摸或 CLI 引起状态改变，都使用相同动效。保留原生 Button/轻量点击反馈，不做影响邻居布局的宽高缩放。
- 条件内容插入/删除使用容器 `transition` 配合 `getUIContext().animateTo` 中的状态更新。异步成功响应才确认设置，不在动画完成回调中提交业务；失败/处理中仍沿用既有防重入逻辑。
- 本次 MCP 查询词：`ArkUI 属性动画 animation animateTo backgroundColor borderRadius 按钮选中状态`、`ArkUI Button type Normal Capsule borderRadius 默认 胶囊`。已检索完整文档：[实现属性动画](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-attribute-animation-apis)、[animation](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-animatorproperty)、[组件内转场](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-component-animation)、[Button](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-button)。使用的基础接口兼容当前 API 24；未引入新版分段控件依赖。
- 短动效必须用连续画面验证，单张截图不能证明中间过渡存在。实测 `snapshot_display` 逐张采样慢于 180ms；改用华为官方[命令行录屏](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-screen-recording)（本次 MCP 已读取全文），再用 `scripts/test-ohos-option-animation-video.py` 检查录像中的稳定按钮背景区域。记录完整的前/中/后帧，不分析文字像素或跨页面位置，不以静态最终颜色代替动画结果；录屏只用于此次应用调试，不上传录像。

## CLI 优先

新增功能先定义命令名、payload、结构化返回和错误码，再接入 ArkUI。命令必须登记到 `StelOhosCommandCatalog`，并能通过 `scripts/stellarium-cli.mjs` 查询或执行；ArkUI、脚本和 AI 适配层复用同一命令契约。

日常测试的操作路径必须优先使用现有语义 CLI，而不是逐项查找屏幕坐标：

- 打开、返回、关闭面板，切换标签、修改选项、选择天体及读取反馈，先查 `CLI.md`、命令目录和 ArkUI 命令处理器。已有命令直接调用，不通过 Dock 或坐标点击绕行。
- 原生 `--list` 目录目前不包含全部 ArkUI 专用命令；还需检查 `QAbility.isUiCliCommand` 和页面的 CLI 事件处理器，不能因目录里没有就断言不支持。
- 区分“查询原生计算结果”与“改变 ArkUI 筛选状态”：如 `getWutTargets` 能返回结果，不代表同时更新菜单中的类别、时段或展开状态。发现缺口必须记录并补接共用业务入口，不能把坐标操作作为长期替代。
- CLI 返回 `accepted` 只表示请求已接收，不能替代完成状态或错误反馈。回归应核对最终结构化状态；现有 UI 通道缺少最终回执时明确记录限制。
- 截图、布局树用于排版、裁切和动画验证。仅在专门验证触摸命中、滚动或手势时才模拟触摸，不用它完成普通导航和参数配置；测试报告分别记录 CLI 业务验证与触摸验证。

推荐验证顺序：

```bash
source scripts/dev-env.sh
scripts/check-dev-tools.sh
scripts/sync-ohos-build-sources.sh
scripts/check-ohos.sh
node scripts/stellarium-cli.mjs --device <设备ID> --list --json
node scripts/stellarium-cli.mjs --device <设备ID> --command getState --json
```

界面回归先通过 CLI 设置目标页面和状态，再按需使用 `uitest dumpLayout` 检查节点尺寸和滚动属性、使用 `snapshot_display` 截取 JPEG 核对布局。设备测试前可运行 `scripts/prepare-ohos-device.sh <设备ID> prepare`，结束后按需恢复设备设置。

## CLI、AI 与离线边界

- `hdc`、`aa` 和本地 CLI 是开发调试通道，不是应用运行时网络服务；它们不应进入 HAP 权限或业务逻辑。
- HarmonyOS 官方 Intents Kit、鸿蒙智能体和 Agent Framework Kit 属于后续预研方向。当前 API 24 离线包不直接引入未经验证的 Kit，也不因 AI 能力增加公网请求或设备标识读取。
- 后续 AI 接入优先采用“AI/智能体调用命令目录，命令桥返回结构化 JSON”的适配器；命令权限、隐私门控和离线失败回退仍由应用控制。
- 若未来开放通知、智能体或在线数据，必须先更新权限、隐私说明、联网台账、国内镜像评估和本地缓存方案，再实现代码。

## 变更交接

### 2026-09-06：MCP 请求格式与原生崩溃日志

- 当前服务参数使用包装对象：`searchDocuments({"SearchDocumentsReq":{"query":"检索内容"}})`；全文读取为 `getDocumentsById({"GetDocumentsByIdRequest":{"names":["检索返回的 parent"]}})`。直接传顶层 query 会返回 400，不能据此误判服务没有文档。
- 若工具元数据未展示参数结构，可查询已配置官方 MCP 端点的 `tools/list`，不猜测字段、不索取或记录签名信息。
- 本轮已通过 MCP 阅读[华为 hidumper 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hidumper)。API 22 起支持 `hdc -t <device> shell hidumper -e --print <应用包名> -n 2`，可在直接访问 `/data/log/faultlog/faultlogger` 被拒绝时，通过系统提供的调试接口获取本应用故障栈。
- 崩溃必须分析完整 fault thread，不能把启动日志里普通 ArkCompiler 错误栈当作本次 Native Crash。真机回归记录进程 PID 连续性，不能让 CLI 自动重新启动应用后把流程判为无崩溃。
- 原始故障日志可能含设备指纹、内存映射和其他进程信息，仅留本地调试；文档只保留本应用相关函数链和结论，不提交整份原始日志。

每轮修改完成后按以下顺序执行：

1. 更新 `CHANGELOG.md`，说明 MCP 依据、改动、构建和设备验证结果。
2. 同步 `harmonyos/ets-source` 到生成工程，禁止手动只改生成副本。
3. 运行 ArkTS/HAP、命令目录、资源和 `git diff --check` 检查。
4. 记录未验证的设备、API 或视觉场景，不用静态检查结果代替真机结论。
5. 不修改 `build-profile.json5`、签名材料、隐私门控和联网配置，除非用户明确要求且另有专项流程。
