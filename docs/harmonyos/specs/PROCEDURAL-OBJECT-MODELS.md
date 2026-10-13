# 离线程序化天体示意与沉浸查看

## 范围与科学边界（2026-09-06）

星图仍由 Stellarium 绘制；详情三维检查使用独立旋转矩阵和离线 RGBA 渲染，不移动星图、不改变模拟时间，也不把示意模型当作观测影像。

| 类型 | 当前生成内容 | 数据边界 |
|---|---|---|
| 恒星 | 自发光球面、边缘变暗、表面示意纹理 | 目录温度用于近似颜色；缺温度用中性白，不推断真实斑点、半径或自转轴 |
| 类星体 | 中央暗区与可旋转吸积盘 | 通用示意，不是已分辨影像；不推断具体喷流，不模拟广义相对论透镜 |
| 脉冲星 | 紧凑球体与双向辐射锥 | 不代表真实波束角、旋转相位或脉冲；不加入任意闪烁 |
| 球状星团 | 中央密集三维点群 | 稳定程序种子，不冒充目录成员、数量或三维距离 |
| 疏散星团 | 松散三维点群 | 同上，使用不同分布，不与球状星团共用外观 |

已有行星纹理、星座艺术、深空照片保持优先。星团确认没有匹配离线图片才回退示意。星系、普通星云、系外行星、彗星、人造卫星及未知类型暂不臆造模型。太阳仍用太阳纹理；行星继续使用既有星历光照和环平面。双星、变星只展示恒星表面类型示意，不推断伴星结构和光变，界面明确说明。

必须展示“程序化三维示意 · 非实测影像”和类型依据。新文案覆盖英/简繁中文；其余语言使用现有英语回退，不能声称已完成所有语种。

科学依据：[NASA 类星体](https://science.nasa.gov/mission/hubble/science/science-behind-the-discoveries/hubble-quasars/)、[NASA 恒星](https://science.nasa.gov/exoplanets/stars/)、[NASA 脉冲星](https://science.nasa.gov/mission/hubble/science/science-behind-the-discoveries/hubble-pulsars/)。介绍文章不用于推算特定目标的未知几何参数。

## 布局、动效与性能

人造卫星无实物资源时复用目录已有的 `ic_catalog_satellite.svg`，等比显示 72vp，容器高 104vp、透明无底框，不叠加月球、球体或轨道装饰。附多语言“类别图标 · 非该天体实物影像”；不把通用图标宣称为具体卫星形态。图标不参与触摸捕获，直接上下滑动即可阅读资料；天然卫星与真实三维表面仍单独处理。

### 详情滚动与三维手势（2026-09-06）

- 用户确认采用空间分工，而非方向限制：内嵌模型最大 200vp，窄卡自动缩小；扣除详情内边距后，两侧各保留至少 40vp 的阅读滑动区。视觉尺寸和触摸尺寸同步缩小，不能只是缩小图片而保留整行触摸拦截。
- 模型内部保留任意方向旋转与双指缩放，复用全屏触摸处理；两侧空白交给原生 Scroll。小模型自身使用 `BLOCK_HIERARCHY` 防止旋转同时滚资料；其全宽父容器不拦截触摸。整张统一详情卡根部仍使用 `BLOCK_HIERARCHY` 隔离外部星图，展开按钮为 Default，图片不参与命中测试。
- 之前验证过的“纵向滚动、横向旋转”方案被用户否定，已移除方向判定与相关手势辅助方法。不得恢复为仅横向旋转。交互归属由起始触摸区域确定，不在跨越边缘时中途切换。
- 全屏根仍保留 `BLOCK_HIERARCHY`，关闭按钮和自由旋转、双指缩放不变。不能把内嵌修复机械地应用到全屏，否则会再次穿透到星图。
- 拖动结束或被取消时统一退出交互态，恢复稳定质量帧；只调整布局大小，不降低模型渲染尺寸、星图分辨率或画质。内嵌和全屏分别显示准确的多语言操作提示。
- `getObjectModelView` 新增 `detailScrollY`：独立于模型帧时间戳的实时详情 Scroll 偏移（vp）。旋转矩阵仍代表实际完成的渲染帧；不能因滚动而伪造新模型帧。
- 回归：`scripts/test-ohos-model-scroll.mjs`；`scripts/test-ohos-model-scroll-pad.py --device <设备> --output <报告>`。通过 CLI 导航、选择、读取状态，只在显式手势/命中测试中从最新布局树定位后注入触摸。验证左右边缘滚动、返回顶部、模型横纵旋转、全屏纵向旋转、真实关闭及关闭后仍可滚动，检查星图/选中对象不变。
- 华为开发知识 MCP 全文依据：[触摸测试控制](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-hit-test-behavior)、[滑动手势](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-gestures-pangesture)、[手势冲突处理](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-gesture-events-gesture-judge)。使用当前 API 24 已支持的接口。

- 移除详情模型的装饰蓝底圆和描边，保留真实行星环，透明图像底不另套蓝框。
- 独立全屏查看：深色背景；顶部目标、说明、关闭；底部依据、手势提示、复位。中间旋转/双指缩放，关闭回到同一详情。
- 顶部复用安全区，按钮至少 44vp。打开 220ms EaseOut、关闭 180ms EaseIn，透明度局部动画；结束回调以代次保护。
- 全屏根使用 API 20 已支持的 `BLOCK_HIERARCHY`，自身及子控件响应，阻断下层星图和祖先的触摸/鼠标处理；不能使用 Transparent。真机曾发现关闭点击穿透选中另一颗卫星，修复后必须检查真实触摸而不只检查 CLI。依据：[华为触摸测试控制](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-hit-test-behavior)（MCP 全文）。
- 不引入全屏实时模糊、嵌套动态材质或任意自转定时器。复用失效帧保护、PixelMap 释放队列。
- 详情静态 320、交互 224 保持不变；全屏静态 640。复杂模型后续升级渲染后端，不通过降低主星图画质规避耗时。

已通过华为开发知识 MCP 取得全文：[沉浸式适配](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-develop-apply-immersive-effects)、[模糊效果](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-blur-effect)、[沉浸光感约束](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-constraints)。关键控件不能伸入挖孔安全区；实时模糊逐帧处理；API 26 新材质不直接引入当前 API 24 工程。

## 接口与后续扩展

- `ProceduralDetailModel.ets`：类型识别、温度近似色、稳定粒子与矩阵渲染，不依赖网络或页面状态。
- `setObjectModelView`：`open` 打开详情；`immersive` 展开；`close` 返回；`reset` 复位；`dx|dy` 旋转。
- `getObjectModelView`：实际帧的 `kind`、`schematic`、`temperatureK`、`immersive`、分辨率、矩阵和时间戳；不可用时返回错误，不复用旧目标成功帧。
- 后续同一协议可接 GPU 或独立 Celestia 后端；观测照片、测量模型、推断模型、艺术示意必须分开标识。
- 单测：`node --test scripts/test-ohos-procedural-model.mjs scripts/test-ohos-detail-model-geometry.mjs`。
- 真机：`python3 scripts/test-ohos-procedural-model-pad.py --device <设备> --touch --output <报告.json>`；普通导航用 CLI，只有显式命中测试从最新布局树定位模型区域/关闭按钮并注入触摸，验证星图和选择不变。
- 不修改签名配置，不新增应用网络权限或资源下载。

## 真机发现的文件判断问题

`objectInspectorFilePath` 曾忽略 `fileIo.accessSync` 的布尔返回值，只处理异常。文件不存在返回 false 时仍返回伪有效路径，导致 NGC 7006 尝试解码不存在的 n7006.png，无法进入资源匹配。修复后正确找到生成资源包中的 n7006-sdss.png；完全缺图的 NGC 6256 则进入程序化回退。显式检查布尔结果，并测试存在、不存在、抛异常三种路径。

通过华为 MCP 取得 [fileIo 官方全文](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-fs)并核对当前 SDK 类型声明，不能与已废弃的旧 `fileio.accessSync(...): void` 混用。

## 完成验证

- 最终 18 项单测、56 项新模型真机检查、34 项原有行星模型检查通过；报告为同目录 `procedural-model-pad-test-2026-09-06.json` 和 `procedural-existing-model-pad-test-2026-09-06.json`。
- 编译与资源审计通过；保留既有 4 项警告。已装 MatePad Mini，签名和联网策略未修改。
- 真实手势检验包括详情内/全屏旋转、关闭不选到星图目标、不移动星图，以及手势之后改变模拟日期仍更新光照且保持检查角度。内嵌模型和展开按钮同样隔离祖先及下层命中链。
- 渲染反馈捕获开始时的模式，异步完成回调不能把旧 320 帧标成新的全屏帧。CLI 测试同时匹配目标、时间戳、模式和最终静态质量。
- 已检查五种示意和月球截图。后续补手机大字号、极小窗口、动态帧时间测量；当前不宣称覆盖全部设备、全部类型或所有语言。
