# HarmonyOS PC 端规范审计（2026-09）

## 结论

星象仪的 PC/二合一端已经采用同一套响应式 ArkUI 页面，并保留全屏、分屏和自由窗口模式。本轮补齐窗口变化监听、最小自由窗口约束、鼠标/触控板悬停反馈和键盘焦点入口；Qt 原生桥不再从布局尺寸回调中重复触发同步调用。

## 与官方规范对照

| 检查项 | 现状 | 处理 |
| --- | --- | --- |
| 自由窗口、分屏、全屏 | 已支持 | 保留三种窗口模式，启动时只修复异常的小型自由窗口，不覆盖用户正常调整的尺寸 |
| 窗口尺寸变化 | 已补齐 | QAbility 监听 `windowSizeChange`、`windowRectChange` 和去重后的 `windowStatusDidChange`，通过 `AppStorage` 通知 ArkUI 布局层 |
| 系统显示缩放 | 已补齐 | 监听 `systemDensityChange`，布局状态可回读当前缩放环境 |
| 避让区与沉浸式窗口 | 已支持 | 继续使用 `avoidAreaChange`，Dock 和面板根据上下安全区计算位置 |
| 极小自由窗口 | 已补齐 | `module.json5` 设置最小窗口宽高和宽高比，避免文字、控件和 Dock 被压成不可操作状态 |
| 鼠标/触控板悬停 | 已补齐 | Dock、顶部陀螺仪/声音控件增加 `HoverEffect.Auto` |
| 键盘焦点 | 已补齐基础入口 | Dock 和顶部快捷控件可获得焦点；星图根节点继续处理方向键、快捷键和鼠标/轴事件 |
| 响应式断点 | 已支持 | 手机、平板、PC 使用同一页面，通过实际内容区尺寸和折叠状态切换布局，不以设备名硬编码页面 |
| 布局回调性能 | 已修正 | `onAreaChange` 只更新尺寸和轻量状态，启动桥同步由页面生命周期负责 |

## 暂不强行加入的项目

- 不把 PC 自由窗口强制最大化：只有检测到启动时恢复的异常小窗口才修复，用户主动调整的窗口保留。
- 不把系统标题栏、系统 Dock 或外接显示器管理复制到应用内：这些由 HarmonyOS 窗口管理器负责。
- 不在布局回调中执行网络请求、文件读写或重建星表；在线目录和资源预热继续走独立任务。
- 高级快捷键编辑器、右键上下文菜单、文件拖放和高对比度主题仍列为后续 PC 专项增强，不影响当前主流程。

## 依据

- [鸿蒙电脑应用开发入门](https://developer.huawei.com/consumer/cn/multidevice/pc/get-started/)
- [鸿蒙电脑与平板适配开发指南](https://developer.huawei.com/consumer/cn/multidevice/pc/adapt/?ha_source=202608yk&ha_sourceId=89000503)
- [设计基础](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/smart-cockpit-ux-basic-0000002622965869)
- HarmonyOS Developer Knowledge MCP：多设备窗口模式、窗口状态变化、窗口尺寸变化、系统密度变化和交互归一化文档。
