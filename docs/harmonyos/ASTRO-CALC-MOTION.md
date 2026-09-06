# 天文计算动效与验证

## 2026-09-06 检查结论

天文计算原有顶部标签仅有选中色动画，主体直接替换。位置、星历、升中天落、天象、曲线、今晚目标、行星、食与凌日、年历、月相中的大量可点击 Text 没有按压反馈或选中色过渡；重复点击当前顶部标签还会再次发起计算。

本轮覆盖天文计算主分支内 102 个点击定义和 64 处选中背景定义（不是 102 个独立功能，每处 ForEach 会生成多个控件）。统一采用轻微按压反馈，选中背景 180ms EaseOut；不改字号、宽高、圆角和星图画质，不给整个布局设置隐式动画。

顶部三组和十个页面：复用星体详情的 100ms 淡出、170ms 淡入节奏，只改变内容滚动容器的透明度和横向位移。方向依据实际排列 `[5,2,4,9,0,1,6,3,7,8]`，而非内部数字大小。旧内容向离开方向淡出，新内容从目标方向进入。点击相同标签不重算，快速切换只提交最后目标；退出时不再启动隐藏页计算。计算在入场完成后启动，不放进动画状态更新闭包。

筛选仅渐变选中色并保留当前滚动位置，不给每次计算结果刷新加整页转场。平台 Toggle 保留系统交互；没有给每条实时数值补动画，避免持续重排。

真机首次录屏发现旧加载提示在筛选控件之前条件插入，计算期间将按钮整体向下推约 32vp，结束后又缩回。单看 Scroll 偏移不变无法发现这个问题。已将加载提示移到筛选区之后、结果之前，保留进度反馈但不改变筛选按钮的位置；增加源码布局断言和连续画面复测。

## 官方依据

本轮首先调用华为开发者知识 MCP `searchDocuments`，端点传输失败，按工作流降级查询华为官方站点；随后 MCP 重试成功，已读取属性动画、点击回弹、动画使用指南和录屏的完整文档：

- [属性动画更新流程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-animation-usage-guide)：状态变化和动画闭包的作用范围。
- [Builder 状态变化与动画](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1009)：动画必须由可追踪状态驱动。这里保留直接读取组件 @State，避免把选中布尔值复制给 Builder 后失去更新。
- [命令行录屏](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-screen-recording)：延续既有连续画面验证流程，截图只验证布局，不证明中间帧。
- [属性动画](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-animatorproperty)：动画放在背景之后；不使用不支持该动画的 attributeModifier 包装。
- [点击回弹效果](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-click-effect)：用 0.97 的轻微缩放，不使用默认 0.90 的大幅收缩，避免明显改变触点边缘。

时长和位移是本应用设计选择，不是华为强制规范。禁止用宽高动画、延时重建 Scroll、透明覆盖层阻断点击来实现此效果。

## CLI

先 `openUiPanel astro`；以下命令与触摸共用处理器：

| 命令 | 参数 |
|---|---|
| `setAstroGroup` | `0` 观测、`1` 位置、`2` 天象 |
| `setAstroTab` | `0` 位置、`1` 星历、`2` 升中天落、`3` 天象、`4` 曲线、`5` 今晚、`6` 行星、`7` 食与凌日、`8` 年历、`9` 月相 |
| `setAstroFilter` | `period\|evening/midnight/morning/night`、`altitude\|0/10/20/30/45`、`magnitude\|4/6/8/10`、`direction\|all/north/east/south/west`（斜杠表示选一个值） |
| `getAstroPanelState` | 最近一次天文计算面板反馈：group、tab、requestedTab、transitioning、transitionId、scrollY 和四项筛选值 |
| `setAstroScroll` | 非负竖向滚动偏移 vp，仅用于同一滚动容器，不以坐标点击导航 |

`accepted` 仅表示命令接收，测试必须轮询最终 tab 和 `transitioning=false`；状态中的数值不是实际合成帧，也不代替录像证明动画。`loading` 仅表示今晚目标筛选任务，不代表其它计算任务；计算结果仍查原生各计算命令。天文计算应先打开，关闭时状态为最近快照。其它细分筛选暂没有新增专门 CLI 命令，不能声称所有筛选都完成真机逐项测试。

## 验证记录

- 单元/源码回归：17 项通过，包含真实选择方法的模拟回调执行、连续点击、反向切换、同值幂等、关闭中断、筛选验证、加载提示位置及既有布局/设置回归。
- 构建及真机：Native、CompileArkTS、assembleHap、10 项资源审计通过；含既有插件的回归合计 21 项通过，42 项 Pad CLI 检查通过。最终 HAP 已安装，SHA-256 与完整证据见 `astro-motion-pad-test-2026-09-06.json`。
- 最终录像选中/取消背景分别有 4/5 个中间帧，前后控件边界一致；正反页面转场连续画面已查看。另一次实际触摸确认选项可点，随后恢复。不是逐个控件物理测试，也不声称所有动画满帧。
- 命令已注册核心目录，标明 ArkUI 执行层。目录审计同时补入原本已由 QAbility 实现的 `setTelescopeLivePosition` 白名单，352 项一致，不改其业务逻辑。
- 不修改签名、权限或运行时联网策略。
