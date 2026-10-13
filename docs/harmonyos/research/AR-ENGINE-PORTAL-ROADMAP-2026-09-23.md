# AR 星空与地景递进预研（2026-09-23）

## 结论

可以做“只保留星空、逐步抠除地景”的 AR 体验，但它不是把现实世界的地面真的删除，而是把摄像头画面作为背景，再用 AR Engine 的空间跟踪、竖直平面、环境 Mesh 和深度信息决定星空覆盖范围。当前官方能力重点是平面、深度和 Mesh，并不等于已经提供通用的“天空语义分割”；因此第一版应将地面/墙面识别为遮罩，识别失败时保留手动地平线遮罩。所谓“打碎一面墙”应实现为门户、裂隙或碎片化遮罩的视觉效果，现实墙体仍然存在。

本轮已加入一个离线 AR 预研面板和 CLI 契约，用于验证四种模式与递进参数；没有申请摄像头权限，也没有在未明确开启前采集相机画面。

## 四种模式

| 模式 | 视觉目标 | 后续真实实现 |
| --- | --- | --- |
| 星空叠加 | 摄像头背景上叠加星空、方位和目标信息 | AR 世界坐标、相机位姿、时间/位置同步 |
| 地景递进 | 从完整地景逐步显现星空，保留柔和门户边缘 | 竖直平面锚点 + 门户裁剪面 + 动画进度 |
| 深度遮挡 | 墙、树和地面遮挡部分星空，转动设备仍稳定 | 深度估计优先，环境 Mesh 作为高质量回退 |
| 只保留星空 | 将识别出的地面/墙面遮罩抠除，只显示星空层 | 语义/深度遮罩 + 星图渲染层，无法识别时回退手动地平线遮罩 |

## 当前实现

- ArkUI 面板 `ar` 可从“更多功能 → 天空数据 → AR 预研”或 CLI `openUiPanel ar` 打开。
- `overlay`、`portal`、`depth`、`sky-only` 四种模式可切换。
- `setARRevealProgress` 控制 0 到 1 的地景遮罩递进；0 表示地景层完整，1 表示星空层完整。`sky-only` 是明确的“只保留星空”预览状态。
- native 命令 `getARCapabilities`、`getARState`、`setARMode`、`setARRevealProgress` 返回明确的“预览模式”状态，不伪称已经启动摄像头 AR。

## 真实 AR 接入路线

1. 先通过 `SystemCapability.AREngine.Core` 和 `arViewController.isARTypeSupported` 检测设备；不支持时回退普通星图，不申请无效权限。
2. 用户主动开启 AR 后，才申请相机权限并创建 `ARView`/`ARSession`。应用启动、隐私同意前和普通星图模式不申请相机。
3. 使用 `ARPlaneFindingMode.HORIZONTAL_AND_VERTICAL` 识别地面与墙面，使用相机位姿把 Stellarium 的时间、地点和目标坐标转换到 AR 世界坐标。
4. 深度估计可用时使用深度图和置信度图；需要复杂遮挡时使用环境 Mesh。透明、反光、弱光环境要显示精度提示，并提供无深度安全回退。
5. “抠除地景”的渲染顺序固定为：相机背景 → 深度/平面遮罩 → 门户裂隙动画 → 星空与标签。这样不会把 AR 业务逻辑混进 Stellarium 核心星图，也不会影响普通 2D/3D 星图。
6. 最后再加入目标锁定、星体详情、脚本和 CLI 参数同步；相机帧不上传网络，位置外发仍需单独的用户授权和联网清单登记。

## 官方依据与限制

- [AR Engine 概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arengine-overview)：运动跟踪、平面识别、环境 Mesh、深度估计等能力。
- [ARViewController](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arengine-api-arviewcontroller)：创建 AR 会话、查询设备支持情况和生命周期管理。
- [平面检测](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arengine-get-plane)：平面位姿和竖直墙面识别。
- [环境 Mesh](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arengine-get-mesh)：复杂遮挡和空间交互所需的网格能力。
- 官方文档注明 AR 能力只在部分手机/平板可用，不能以模拟器结果代替真机验收；深度精度会受光照、反光和透明材质影响。

## 隐私与联网边界

当前预研面板完全离线，不新增 `INTERNET`、相机权限、设备标识读取或后台采集。接入真实 AR 前必须补充隐私政策中的相机用途、处理范围、保存期限和关闭路径；不需要上传相机帧的方案优先采用本地处理。
