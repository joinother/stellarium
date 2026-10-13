# 启动星空动效

## 参考与取舍（2026-09-08）

参考用户指定的 [Apple Event — September 7, 2022](https://www.youtube.com/watch?v=ux6zXguiqxM) 开头。在浏览器实际播放并检查 0 秒星点群、5 秒星点苹果轮廓、8 秒星空、22 秒地球画面。借鉴前后景层次和形状融入空间的连续感；这些离散观察不是整段逐帧测量，不复制苹果标志、音乐或视频资源。

本应用保留不规则独立星点和本地化名称。开场采用有界的轻微纵深推进，远近星点位移不同，不恢复共同旋转或中心空洞。原生画面真实就绪后，亮星以带随机错峰的弧线收束成名称。用户反馈旧版 720ms 汇字和 620ms 退场仓促后，调整为每颗星 1250ms 汇聚、最多 120ms 错峰、全部成字后 220ms 阅读停留、1100ms 退场，总预算 2690ms。几何曲线采用五次缓入缓出，两端速度及加速度归零；淡出仍采用官方 EaseInOut，同步共用时长常量，减轻文字与根层双重透明度衰减。此调整会比上一版增加约 1.35 秒视觉收尾，不应宣称核心加载加快。退场时文字星点轻微散开、背景星点向外产生纵深位移，与真实星图交叠。只移动加载页粒子，不缩放真实星图、不降低分辨率。

## 加载提示

按用户最新要求，在名称下方 88vp 保留轻淡 msg_loading 本地化文字，移除末尾省略号，在文字右侧放置同色 14vp 官方 LoadingProgress，间距 8vp，不恢复胶囊底色。整行居中、最大占宽 85%，文字 12vp、最多两行；仅本地展示层处理省略号，不修改共享翻译资源。转圈跟随前后台启停，与根层统一退场，不虚构进度百分比。未同意隐私时不展示原生加载提示，也不初始化 Qt。通过华为 MCP 再次核对 [LoadingProgress](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-loadingprogress) 文档：采用 API 8 组件、API 10 enableLoading，不使用已不支持的样式枚举。

## 实现约束

- `StartupStarGeometry.ts`：确定性漂移、纵深投影、错峰弧线汇聚和散开纯函数，可脱离 ArkUI 做连续性及边界测试。
- `StartupSky.ets`：复用单个 Canvas、最多 900 背景星和 900 汇字星；字形采样仅在准备阶段运行，颜色分组批量画圆。继续保留亮星增大 50% 的可读性修订。后台及卸载停止计时。
- `ApplicationRoot.ets`：复用原有单一显式 opacity 动画，等待真实呈现就绪和汇字完成，不改变窗口生命周期、隐私门控和 Qt 接入。
- 开发阶段通过华为 MCP 查询“CanvasRenderingContext2D globalAlpha 动画 性能”，读取[优化动画性能](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-animation-usage-guide)全文。整层使用系统显式动画、不以布局尺寸动画驱动转场；逐星字形仍需自有几何计算，不盲目给持续重绘的 Canvas 设置 renderGroup 缓存。沿用当前 API 支持的 Canvas/animateTo，不新增 SDK 依赖。
- 此处星点是品牌动画，不是真实天文观测数据；不是把每个动画星点映射成原生星图中的同一颗恒星。
- 保留 getPresentationState 与启动阶段探针作为验证依据；触摸拨动惯性、低动态偏好适配及核心串行初始化优化仍需单独完善。
