# 卫星轨道线与分组交互（2026-09-06）

## 问题与处理

- 原版存在轨道线总开关和单星 `orbitVisible` 两层条件。内置 3134 条记录仅 6 条开启单星轨道；只打开总开关不代表所有卫星都有线。鸿蒙增加选中卫星的临时轨道预览，仍受总开关、有效轨道、卫星显示、观测位置和渲染条件限制。选择其他目标后取消临时预览，不改用户保存的单星偏好，不一次生成三千条轨道。
- 开轨道线原来把全部位置更新改成串行。现在保持位置传播并行，再对需要轨道的对象串行采样，保留原版对采样共享状态的并发限制。采样完成恢复当前历元，采样失败清空整条线，不连接异常位置。
- 分组原来位于可变高度结果列表下方，筛选结果数量变化会移动整个分组区域。改成结果之前的固定高度分组滚动区、44vp 点击行、稳定分组键和独立 Scroller。加载图标与勾选图标占位不变，避免插入组件改变高度。
- 使用 UIContext.animateTo 的 180ms EaseOut 只改变选中态颜色和勾选透明度；不以销毁整页、重置 Scroll 或动画包装查询计算来模拟反馈。
- 筛选调度时立即推进请求序号，旧响应不能在防抖期间覆盖新选择；旧查询不得回写较新的开关状态。忽略同值 Toggle 回调，避免状态回读形成写入循环。

## 官方 MCP 依据

通过 `harmonyos_developer_knowledge.searchDocuments` 搜索，并用 `getDocumentsById` 读取全文：

- [显式动画](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-explicit-animation)：使用所在 UIContext 的 animateTo，在闭包中变更可动画属性；本项目使用缓出曲线，不使用线性整页切换。
- [LazyForEach 数据懒加载](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-rendering-control-lazyforeach)：节点键要唯一、稳定，避免无意义的组件重建；懒加载仅在特定滚动容器生效。当前分组约 52 项、结果上限 40 项，沿用现有 ForEach，不把 LazyForEach 直接放进 Scroll 后声称已虚拟化。
- 搜索返回的 `arkts-layout-optimization-guidance` 指出小列表可使用 ForEach；未来取消结果分页上限时，应独立评估 List/Repeat 虚拟化与节点复用。

## CLI 与可验证反馈

- `openUiPanel satellites`：打开卫星面板。冷启动必须等待核心与界面完成装载，accepted 不代表数据已经就绪。
- `setSatellitePanelGroup <group-id>`：走触摸相同选择函数，空字符串取消筛选；同值不重复加载，未知分组在状态反馈中报错。
- `setSatellitePanelScroll <非负vp>`：设置面板纵向滚动，供重现筛选跳顶；不注入坐标点击。
- `getSatellitePanelState`：实际 ArkUI 分组、加载状态、匹配数、目录 ID、请求版本、响应耗时、面板与分组滚动偏移，以及轨道线/标记开关。设置命令 accepted 后应读取此状态确认完成。
- `setSatellitesFlag orbitLines:1/0`：已有原生命令；成功后同步当前 ArkUI，不需退出重进。
- `getSatellites`：新增 `elapsedMs`，以及有选中卫星时的 `selectedOrbit`：保存偏好、临时预览、有效性、实际采样点数、绘制次数、最近绘制 JD。绘制计数代表提交渲染路径，不保证该路径位于视野内或未被地景遮挡。

## 验证与边界

测试代码：`scripts/test-ohos-satellite-panel.mjs` 与 `scripts/test-ohos-satellite-panel-pad.py`。报告：`satellite-panel-pad-test-2026-09-06.json`。

首轮真机 33 项检查通过。追加关闭面板后的 CLI 状态检查发现 Scroller 未绑定时偏移可能为 undefined，已加空值保护和单测，重新构建安装后最终 35 项检查通过。随后 48 项传播安全真机回归通过；22 项 JavaScript 回归通过。最终包 SHA-256 为 `457195b5d94850be10cea1566c00ccd45e03668abdf476671f77e8d76e2b7007`。

6 组筛选后面板滚动偏移均保持 600vp，最终原生目录查询 1–4ms；约 193–194ms 的 UI 请求耗时包含 90ms 防抖与异步回读，不等于阻塞 UI 的耗时。STARLINK-36933 保存的单星轨道开关仍为 false，但临时预览有 181 个实际采样点且绘制计数增长；关闭总开关后计数停止，异常 TLE 不绘制。CLI 与 ArkUI 开关一致性和进程连续性检查通过。

已检查 `/tmp/satellite-selected-orbit.jpeg`，能看到经过选中卫星的轨道；该目标处于地平线下，为单独验证绘制临时关闭地景、大气和雾，随后恢复。`/tmp/satellite-groups-stable.jpeg` 和 `/tmp/satellite-group-selected.jpeg` 确认固定选择区与选中底色/勾选布局正常。

无新联网功能，不改签名、画质、纹理分辨率和正常轨道速度。异常轨道仍需更新数据；轨道在地平线下可能被地景遮挡，不将此正常现象视为开关失败。未宣称已经量化测试所有设备的动画帧率。
