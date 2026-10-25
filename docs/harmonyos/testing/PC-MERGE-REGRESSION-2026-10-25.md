# PC Dock 与字体合并回归核查

## 提交关系

- 10 月 11 日备份 `aae34f085e` 仍是主线祖先，没有被强推移除。
- PR #3 的 10 月 13 日组件拆分合并 `b432765ef1` 后，部分旧版 Dock 与字号适配未迁入组件。
- PR #6 的 merge base 为 10 月 25 日 `5d99ca6e875494c16274240910826ece105b3696`，并非 9 月 23 日版本。其修改限于天空文化缩略图引用和主题表面颜色。
- 合并 #6 的同时保留 10 月 14 日研究文档分支的三个文档提交；CHANGELOG 冲突保留双方记录。

## 确认的回退与修复

1. Dock 顶层命中层把窗口坐标用于内容区域判断；MateBook 修复前点击搜索标签后，面板仍停留在 quick。改为命中组件自身的 x/y，保留触摸取消与动作去重。鼠标左键由 ArkUI 转为同一 onTouch 路径；不再叠加 onClick，避免开合面板后几何变化使同一次手势二次命中另一按钮。
2. 展开态 Dock 被写死为字号 10、图标 22、按钮高 44。恢复响应式尺寸；绘制与命中层共享 Dock 顶部、宽度和高度，移除整条 Dock 随面板状态缩放/平移。
3. 拆分面板丢失多处 panelFontSize/objectDetailFontSize 调用。抽取共同字号函数，使用 V1 StorageProp 传播可读性状态，恢复观测列表、目镜、导航星、图层标签、指针坐标、时间设置和对象详情中已确认的适配；没有全局机械放大所有文字。
4. 坐标行恢复足够的标签列宽、允许两行数值与最小高度，避免固定行高裁切。
5. 恢复 getUiLayout 状态发布与 setUiLayoutMode 的 auto/compact/expanded 处理；该命令只切换布局策略，不调整系统窗口尺寸。
6. 紧凑面板、详情卡拖动边界、返回命中区和选星避让共用 `dockTop - 10` 基准。移除旧的 `skyHeight - 90`，短窗口保持至少可阅读的面板高度并以可用空间封顶。
7. 鼠标使用官方 MouseAction/MouseButton 和局部坐标；悬停更新指针坐标，拖动与合成触摸去重。鼠标/轴事件直接接到各星图表面，避免覆盖面板输入。
8. 双指平移与鼠标滚轮按 SourceTool 区分；捏合维护完整 begin/update/end，移除平移量的 28 倍放大和重复惯性。系统三指手势不作为双指验证。
9. 键盘使用独立 Text 焦点叶子；空 Stack 在设备上无法获得所需焦点。编辑控件的事件不经过该叶子，根只处理面板 Esc；方向和缩放键通过原生 down/up 协议保持到松开，失焦释放。10 种语言的输入教程同步纠正 F/N/Ctrl+N 的功能。

## 官方依据

通过 HarmonyOS 知识 MCP 查询 `ArkUI TouchObject x y windowX windowY 当前组件 坐标 ClickEvent`，读取完整文档：

- [触摸事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-touch)：TouchObject.x/y 是事件响应组件坐标，windowX/Y 是应用窗口坐标；stopPropagation 阻止冒泡。现有 API 23 最低版本可用。
- [点击事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-click)：ClickEvent.x/y 同为组件坐标，支持鼠标/触屏。没有引入 API 26 的 getCurrentLocalPosition。

## 验证

- Dock 几何回归覆盖 4 种宽度、3 种高度、2 种 padding、5 个按钮及边界；UI 契约和触控板静态契约通过。
- 字号回归与 10 月 11 日备份函数逐项比较，覆盖 62 处文案及 29 个 V1 消费组件；另恢复公共组件的字号和行高。
- 原生 `cmake --build build --target stellarium --parallel 6` 与 Default Debug assembleHap 成功；最终焦点修复构建 1 分 15 秒，已安装 MateBook。未改签名、Profile、Build 号或隐私门控。
- 几何、字号、鼠标/轴行为、表面接线、15 项键盘行为、Dock 响应式和 UI anchor 检查通过。
- MateBook 浮窗与最大化 Dock 首轮触摸、浮窗鼠标均通过；build5 手机布局五个入口关闭后重开均正确，面板底部与 Dock 顶部相距 10vp。
- build5 无点击悬停使指针坐标从 (475,188) 更新为 (523,215)；滚轮 FOV 60°→75.264°，触控板捏合 75.264°→51.744°→66.963°，鼠标拖动改变视向。
- build6 焦点叶子实际 focused=true；PageUp 按住 500ms，FOV 60°→22.266°，松开停止；另一轮 400ms 为 24.850°→11.122°。Left 400ms 使方位角 354.850°→358.786°，FOV 保持不变。
- 搜索英文输入 `nn`，Home/Delete 后为 `n`，End/Backspace 后为空；再次输入 N 时深空显示标志和夜间模式没有变化。Ctrl+N 在星图焦点下打开夜间模式，临时改绑 Ctrl+Shift+Y 能关闭，已恢复 Ctrl+N。
- 系统窗口实际缩为 967×1094px 后，五个 Dock 入口依次重开正确；月球坐标详情截图确认底部没有压到 Dock。截图留在本机临时目录，未上传包含桌面的原图。
- build6 最大化画布约 1642×952vp，自动进入 expanded/readable；五个入口关闭后重开均正确，展开 Dock 字号 14，图标和触摸高度同步增加。
- 临时 ohosTest HAP 构建、安装与 runner 启动成功；`Driver.create()` 返回 null，双指滚动 API 尚未实际调用，故双指平移仍待物理验收。没有将失败的测试基础设施记成应用通过，也没有使用三指系统手势替代。临时测试不进入产品源码或发布包。
- 收尾已卸载独立 entry_test 模块，保留主应用和数据。移除测试模块后首次请求隐私服务返回 1006700003；覆盖安装原 build6 主 HAP 后系统隐私弹窗恢复，按用户此前授权正常确认，getUiLayout.ready=true、getAppState 返回星图状态（约 30fps）。未绕过门控，未改隐私代码。隐私门控没有 CLI 同意命令，本次只对实际系统弹窗操作并留存布局证据。

## 边界

本轮聚焦用户指出的 Dock 和字号回退，没有宣称所有历史功能均已验收。物理触控板手势、其他机型、折叠悬停姿态需要各自真机覆盖；静态契约不能代替这些实测。
