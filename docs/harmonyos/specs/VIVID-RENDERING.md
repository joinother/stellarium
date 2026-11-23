# 绚丽渲染、经典渲染与独立开关

## 背景

`b4a12634d..HEAD` 之间的部分星图渲染增强直接写入通用 C++ 代码，会同时改变上游 Stellarium 经典界面的科学渲染行为。本规格把这些行为分成四层，避免把“看起来更漂亮”误当成“物理更正确”。

## 四层模型

### 1. 经典模式

以 `b4a12634d` 为基准，恢复上游的科学渲染行为：

- 恒星 B-V 颜色表与点光源 shader；
- 彗星 `drawTail()` / `drawComa()` 纹理尾；
- 流星上游星等分布、更新、绘制和颜色；
- 卫星上游点源、标签、星等和拾取语义。

经典模式不读取解析式彗尾的 `fragmentation_*` 参数，不会产生解析式碎片尾。

### 2. 绚丽模式

由既有 `landscape/flag_vivid_atmosphere` 控制，默认关闭：

- 恒星光谱 B-V 色表、点源 core/halo shader；
- 流星多光谱形态、火球/微流星分类、预览 salvo；
- 运行时切换不需要重启；颜色表、shader uniform、彗尾网格按 generation 失效并重建。

恒星/卫星调时拖尾**不属于**绚丽模式门控：`stars/flag_motion_trails` 保持独立开关，经典模式下也可生成，只改变拖尾使用的 B-V 颜色表。

### 3. 独立彗尾开关

`astro/flag_analytical_comet_tail` 独立控制解析式 Finson–Probstein 彗尾：

- 打开绚丽模式时联动打开；
- 关闭绚丽模式不强制关闭；
- 经典模式可手动打开；
- 关闭时 `Comet` 跳过 `ensureShaders()`，重建经典抛物面网格并走 `drawTail()` / `drawComa()`；
- 运行时切换时使 `tailFactors` 失效，下一帧重建，避免读取空网格。

### 4. 独立 UI / 内容层

以下改动不纳入绚丽模式，也不伪装成科学渲染：

- DSO/行星/星座标签边缘留白与淡出；
- Planet/ZoneArray 拾取渲染态校正；
- OHOS 统一选择框；
- 极光、卫星乘组、3D 模型、命名图集；
- 卫星微标记、空间站编组、轨道弧与运动拖尾。

## 恒星光晕与点源

该节记录从 `1a2ad277f8` 起的恒星光晕回溯审计结论。

- `coreHot`（亮核去饱和）与 `haloBoost`（中层光环最多增亮 34%）只存在于 `vivid >= 0.5` 分支；`vivid < 0.5` 先返回上游 `texture2D(tex, texc) * vec4(outColor, 1.0)`，经典模式的点源光晕与上游逐像素一致。
- 这两个 shader 项作用于共享 `drawPointSource()` 的所有点源：恒星、卫星、新星、类星体、超新星；这是“绚丽点源”的统一行为，不是恒星专属。
- “亮星光晕”（`stars/flag_star_halo`，默认开）与“星芒效果”（`stars/flag_star_spiky`）是上游独立开关，不纳入绚丽模式；经典模式下仍可使用。亮星光晕使用 `textures/haloLune.png` 的 150 px 大光晕，阈值为 `radius > (MAX_LINEAR_RADIUS + 5) * screenScale`。
- “现实星等”（`viewing/flag_realistic_star_visibility`，默认 true）是独立教学显示开关：关闭时 `computeStarRCMag()` / `adaptSkyObjectLuminanceScaled()` 走非现实可见性模型，会改变星点半径与极限星等，可能让更多星进入亮星光晕阈值；默认开启时 `computeStarRCMag()` 直接返回上游 `computeRCMag()`。
- “缩放特写淡出”（`landscape/flag_zoom_fade_environment`，默认 false）是独立 OHOS UX 开关：开启后 `atmosphereVisualStrength` 在 FOV 10°→2° 内衰减，经典模式下也会改变消光、闪烁与输入增益；默认关闭时不影响经典渲染。
- `AtmosphereVivid::visualStrength()` 在绚丽关闭时返回 1.0，保证经典模式的星点亮度、消光与闪烁与上游一致。
- 科学评估：`coreHot`/`haloBoost` 是摄影式过曝去饱和与光晕增亮，不是经过标定的 PSF/seeing 模型，也不模拟口径、衍射或人眼中间视觉去饱和。因此归入绚丽渲染；经典模式保留上游点源 PSF。星点纹理 `star16x16.png`、`star16x16_rays.png` 与 `haloLune.png` 自 `1a2ad277f8` 起未改动。

## 卫星标记层边界

卫星 `getVMagnitude()` 是近似可见性模型，不是光度真值：

- `stdMag` 可能来自目视观测或平均截面积估计；
- 无 `stdMag`/`RCS` 时回退 `vmag=7`；
- RCS→光学星等是经验换算；
- 除 Iridium 外没有姿态/镜面 glint 模型；
- 详情卡始终标注 “Approx. magnitude”。

因此：

- **点源、标签、详情卡星等、`getPickState().magnitude`、`getSelectPriority()`、`searchAround()` 恢复上游语义。**
- `pointDrawn = magSat <= limitMag`。
- 标签：半影 `txtMag = magSat - 3`，地影 `txtMag = magSat - 10`，仅 `txtMag <= limitMag` 时显示。
- 标记层使用独立 `Satellites/flag_marker_layer`（OHOS 默认开、桌面默认关），`markerLimit = limitMag + 3.2*zoomReveal` 只供 `markerDrawn`。
- `StelObjectPickState.markerDrawn` 独立暴露；`iconDrawn` 不再写成 `iconDrawn || markerDrawn`；`magnitude` 不包含 marker。
- 标记层不得强制 `labelDrawn`、标签透明度或 `queueSkyLabel()` 星等。
- TouchPicker 用 `markerDrawn` 决定标记命中半径；局部评分夹取不写回 `getPickState().magnitude`。

空间站编组使用 `Satellites/flag_station_complexes`（OHOS 默认开、桌面默认关），只影响对象可见性/编组，不改变光度语义。

## 流星门控

- `SporadicMeteorMgr::draw()` 恢复上游“仅大气层开启时绘制”：
  `!getFlagHasAtmosphere() && !getFlagForcedMeteorsActivity()` → 抑制，诊断返回 `atmosphere-disabled`。
- 预览 salvo 仅在绚丽模式且大气层开启（或强制流星活动）时生成；经典模式不生成预览。
- `Meteor` 经典路径恢复上游星等分布、距离衰减、线性熄灭、10 段和原始颜色；绚丽路径保留当前形态。模式切换时清空活跃流星，避免同帧混合。

## 诊断命令

- `getVividRenderingState`：`vivid`、`vividGeneration`、`starTrails`、`meteorAtmosphereGate`、`cometAnalytical`。
- `getCometAnalyticalTail` / `setCometAnalyticalTail 0|1`。
- `getMeteorDiagnostics`：`drawSuppression=atmosphere-disabled`。
- `getSatellites`：`markerLayer`、`stationComplexes`。
- `setSatellitesFlag markerLayer:0|1` / `stationComplexes:0|1`。

## 非目标

- 不修改卫星星等公式或 TLE 传播。
- 不重新设计彗尾物理模型。
- 不把 UI 平滑/拾取正确性改动纳入绚丽模式。
- 不新增网络、权限或远程素材。
