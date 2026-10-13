# 离线球体：观测视角、自由检查与光照

## 2026-09-06 修复

旧实现将纵向触摸增量反号，且把相位百分比转换成固定屏幕光照，导致表面旋转、晨昏线不动。新的球体检查器不改变主星图的相机、跟踪、陀螺仪或时间。

- 核心 `getObjectDetailModel` 和选中对象响应返回 `lighting`：当前 JD、天体坐标系中的太阳单位向量、行主序 `viewToBody` 九元素矩阵、观测照明比例和太阳自发光标记。
- 位置来自现有离线星历与观测者位置；纹理旋转复用 `Planet::getRotEquatorialToVsop87()` 和 `axisRotation + 90°`。纹理坐标对应原生球面/Shader 的 `(local.x, local.z, -local.y)`，而不是重新假定零度经线。
- 初始视角朝向观测者，以观测地天顶投影为画面上方；退化时用极轴/备用轴。重置恢复此视角，保留当前模拟时间与位置。
- 手动检查用累积旋转矩阵，水平与纵向均沿手指移动，不限制在 ±83°，经过两极仍可继续旋转。光照和表面法线始终在同一天体坐标系点乘，绕到背面时不能再把地球上看到的相位强行保持在屏幕上。
- 环带与球体共用相机矩阵，环面位于天体赤道面，不再额外添加人为固定倾角。
- 两指与单指切换重新记录起点；Up/Cancel 即使没有触点也释放交互状态并精绘，避免松指突跳。
- 可见资料页按变化阈值更新光照，两次自动渲染至少间隔 250ms；触摸仍沿用合并渲染与松手精绘。纹理 512×256、交互输出 224、静止输出 320 保持原值，不降低星图分辨率或画质。

## 精度边界

这是球面纹理模型，不是实拍相片或完整物理渲染。当前不包含月食遮挡、月面地形自遮挡、环投影/环带光度、大气散射、表面高程和行星扁率；夜侧适度提亮方便检查表面。月相方向与表面朝向采用核心几何，不能据此宣称等同望远镜摄影。光照元数据缺失时明确提示“仅展示纹理”，不伪造固定光源。未来高精度渲染可复用此坐标契约扩展阴影计算。

## CLI 与反馈

先 `searchObject Moon`，再 `setObjectModelView open` 打开资料页。`setObjectModelView reset` 重置，`setObjectModelView '0|-50'` 经过与手势相同的旋转函数。参数单位为触摸位移单位，范围每轴 ±1000，不修改模拟参数。

修改命令返回 `accepted` 仅表示入队；`getObjectModelView` 返回最近完成的一帧：目标英文名、实际旋转矩阵、最终 viewToBody、该帧光照 JD、输出尺寸和渲染时间。测试须核对目标与时间戳，不能把旧帧当作新操作完成。模型不存在时返回错误。原生查询 `getObjectDetailModel` 不依赖 UI 渲染。

触摸事件处理参考通过华为 MCP 查询的 [触摸事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-touch) 与 [触屏交互](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-interaction-development-guide-touch-screen)：区别 touches/changedTouches，局部消费事件并阻止冒泡。

## 验证

`node --test scripts/test-ohos-detail-model-geometry.mjs`：四方向、任意朝向继续拖动、越极整圈、光照随纹理、万次旋转正交性、环面一致性和渲染接线回归。

最终 Native、CompileArkTS、assembleHap 构建与安装通过。`scripts/test-ohos-detail-model-pad.py --device 192.168.1.34:33805 --output docs/harmonyos/detail-model-pad-test-2026-09-06.json` 共 34 项检查通过；另检查上滑触摸注入、月球和土星截图，详见 CHANGELOG。该脚本恢复测试前时间与选择；探针检查必须等待新帧。未验证的摄影精度和双指真机手势不可标成已通过。
