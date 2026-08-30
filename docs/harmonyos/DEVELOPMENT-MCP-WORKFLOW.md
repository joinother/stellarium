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

## CLI 优先

新增功能先定义命令名、payload、结构化返回和错误码，再接入 ArkUI。命令必须登记到 `StelOhosCommandCatalog`，并能通过 `scripts/stellarium-cli.mjs` 查询或执行；ArkUI、脚本和 AI 适配层复用同一命令契约。

推荐验证顺序：

```bash
source scripts/dev-env.sh
scripts/check-dev-tools.sh
scripts/sync-ohos-build-sources.sh
scripts/check-ohos.sh
node scripts/stellarium-cli.mjs --device <设备ID> --catalog --json
node scripts/stellarium-cli.mjs --device <设备ID> --command getState --json
```

界面回归使用官方 `aa`、`hdc` 和 `uitest`：先用 `aa start -W` 测启动耗时，再用 `uitest dumpLayout` 检查节点尺寸和滚动属性，最后用 `screenCap` 截图核对布局。设备测试前可运行 `scripts/prepare-ohos-device.sh <设备ID> prepare`，结束后按需恢复设备设置。

## CLI、AI 与离线边界

- `hdc`、`aa` 和本地 CLI 是开发调试通道，不是应用运行时网络服务；它们不应进入 HAP 权限或业务逻辑。
- HarmonyOS 官方 Intents Kit、鸿蒙智能体和 Agent Framework Kit 属于后续预研方向。当前 API 24 离线包不直接引入未经验证的 Kit，也不因 AI 能力增加公网请求或设备标识读取。
- 后续 AI 接入优先采用“AI/智能体调用命令目录，命令桥返回结构化 JSON”的适配器；命令权限、隐私门控和离线失败回退仍由应用控制。
- 若未来开放通知、智能体或在线数据，必须先更新权限、隐私说明、联网台账、国内镜像评估和本地缓存方案，再实现代码。

## 变更交接

每轮修改完成后按以下顺序执行：

1. 更新 `CHANGELOG.md`，说明 MCP 依据、改动、构建和设备验证结果。
2. 同步 `harmonyos/ets-source` 到生成工程，禁止手动只改生成副本。
3. 运行 ArkTS/HAP、命令目录、资源和 `git diff --check` 检查。
4. 记录未验证的设备、API 或视觉场景，不用静态检查结果代替真机结论。
5. 不修改 `build-profile.json5`、签名材料、隐私门控和联网配置，除非用户明确要求且另有专项流程。
