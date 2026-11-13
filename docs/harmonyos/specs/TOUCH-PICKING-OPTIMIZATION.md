# 触控拾取与选择交互优化（对标 Sky Guide）

> **状态：** 设计稿 v6；P0/P1 已实现；v4 增加触控/鼠标共享 `PointerProfile` 与角度上限；v5 修复银心密集星场搜索并完成真机复核；v6 补齐行星渲染态、星官/星群命中，并把 picker 归入 `src/core/`
> **日期：** 2026-11-07
> **基线：** `ohos-dev` HEAD `780d6a3d77`（v5 工作区改动）
> **范围：** 鸿蒙星图触摸点选（`selectAt`）、候选生成与排序、选中反馈；搜索面板与详情卡的信息架构不在本文范围内，仅说明衔接点。
> **相关文档：** `docs/harmonyos/specs/UI-ARCHITECTURE.md`、`docs/harmonyos/CLI.md`、`docs/harmonyos/DEVELOPMENT-MCP-WORKFLOW.md`

---

## 0. 结论摘要

1. **唯一不变量：屏幕上实际绘制的对象才可拾取。** 恒星、行星、深空天体、卫星共用这一条规则；卫星不是例外，只是“是否被绘制”的渲染分支最多。
2. **卫星复用渲染状态，不另写拾取算法。** 把 `Satellite::draw()` 的条件抽成共享的 `SatelliteRenderState`，picker 只问 `pickable()`；禁止用 `getSelectPriority()` 当门槛。§7.4 由 18 项专项缩为 8 项分支验收。
3. **地平线以下不再一刀切。** 删除固定的 `alt > -0.5°`；使用 `core->getVisibleSkyArea()`，与 `StarMgr` 的绘制裁剪同源。地景关闭、淡出中或半透明时，地平线以下可拾取；地景不透明时不可拾取。大气不是遮挡条件。
4. 当前三类结构性问题：星座无条件兜底；`distance(px) + magnitude` 量纲失配；固定半径、缺少视觉足迹与标签命中。仅把 44 px 改成 60 vp 不能解决。
5. 产品已确认：**一次点选即展开完整资料卡**，不采用 Sky Guide 的“先选中、再点 Info”两步式。

## 1. 问题与根因

### 1.1 症状

| # | 现象 | 典型场景 |
|---|------|----------|
| 1 | 高倍率点恒星，选中星座 | FOV 1–2° |
| 2 | 手指稍偏选不中 | 手机单手握持 |
| 3 | 大 FOV 点亮星，选中更暗的星 | FOV 60–120°，密集星场 |
| 4 | 空白误选星座；标签不可点；选中即弹大卡片 | 交互 |

### 1.2 现状审计

| 位置 | 现状 | 影响 |
|------|------|------|
| `src/StelMainView.cpp:6142-6260` | `selectAt` 临时 `setObjectSearchRadius(60)`，随后恢复 25 | 半径与对象渲染尺寸无关 |
| `src/StelMainView.cpp:6200-6240` | 未命中时按点击方向调用 `ConstellationMgr::searchAround`，无条件兜底 | 空白点击、点标签/光晕都可能选中星座 |
| `src/core/modules/ConstellationMgr.cpp:1959-1995` | `searchAround` 忽略 `limitFov`，返回点击点所在 IAU 星座 | 星座成为全天区隐式大目标 |
| `src/core/StelObjectMgr.cpp:461-515` | `cleverFind` 用 `distance(device px)*weight + selectPriority` 排序 | 距离随 DPR 放大，星等不随；亮星输给暗星 |
| `src/core/modules/StarMgr.cpp:1454-1531` | `searchAround` 返回锥内所有恒星，不按星等过滤 | 密集星场候选过多，排序依赖上式 |
| `src/core/StelSkyDrawer.cpp:404-439` | `computeRCMag` 给出恒星实际绘制半径（含 FOV/眼适应） | 拾取未使用 |
| `plugins/Satellites/src/Satellite.cpp:323-333` | `getSelectPriority()` 在视觉过滤时返回 -10/50 | 不检查 `visibility/showLabels/iconicMode/...`，不能当门槛 |
| `harmonyos/ets-source/capability/SkyInputController.ets:185-214` | 800 ms / 28 vp 内第二次点击 = 双击清除 | 与“重复点击循环候选”冲突，需取舍 |
| `harmonyos/ets-source/pages/MainWindowNativeNode.ets:5934-5967` | 选中后自动展开详情并播放 chime | 误选代价高；本方案保留该行为 |

### 1.3 三个根因

**A. 星座兜底。** 找不到天体时，只要星座线/名称图层开启，就把点击点所在星座设为选中。用户以为在点恒星，实际得到一个大而模糊的星座。修复方向是取消隐式兜底：星座只在名称、连线或艺术被直接点中时成为候选。

**B. 量纲失配。** 当前排序是：

```
score = distance_in_device_px * distanceWeight + selectPriority
```

`selectPriority` 对恒星就是星等；距离随 DPR 放大，星等不变。DPR=3 时，距点击点 24 vp（72 px）的 0 等亮星得 `72+0=72`，而 4 vp（12 px）外的 5 等暗星得 `12+5=17`，暗星胜。这不是参数微调问题。

**C. 固定半径、无视觉足迹、无标签命中。** 恒星绘制半径由 `computeRCMag` 决定；行星视圆面、DSO 椭圆、卫星图标/标签都可能被绘制，但旧逻辑只比较对象中心。图层关闭、低于地平线、被地景遮挡的对象也可能进入候选。

### 1.4 量化示例（DPR=3，FOV=60°）

| 候选 | 星等 | 距点击点 | 当前得分 | 用户预期 |
|------|------|----------|----------|----------|
| 亮星 A | 0.0 | 24 vp = 72 px | 72.0 | **应选中** |
| 暗星 B | 5.0 | 4 vp = 12 px | 17.0 | 不应选中 |
| 结果 | | | B 胜 | A 输 |

## 2. 设计原则

Sky Guide 为闭源应用，以下是从官方支持文档与公开评测归纳出的行为约束，不是对其实现的断言：

1. **所见即所点。** 只有当前实际绘制（fader > 0、未被过滤）的星点、圆面、椭圆、标签、连线、图标可点。
2. **缩放即精度。** 宽视场用亮度先验帮助用户；窄视场让屏幕距离主导。不要提供固定魔数半径。
3. **亮度是连续权重，不是硬阈值。** 亮星画得大，命中区也大；但优势随距离衰减，不能击败手指正下方的暗星。
4. **星座是显式目标。** 名称/连线/艺术才能选中星座；空白天区不产生星座选择。
5. **一次选中即展开资料卡**（2026-10-24 产品确认）。因此误选恢复和拾取准确率比“二次确认”更重要。

## 3. 拾取模型

### 3.1 三层目标模型

```
L1 显式目标：名称标签 / 星座连线 / 星座艺术 / 星官标签
   - 矩形或折线距离直接命中
   - 只有实际绘制（fader > 0）时才存在

L2 可见足迹：恒星 sprite / 行星视圆面 / DSO 椭圆 / 卫星图标或点源
   - 点击点落在足迹内 → 直接命中
   - 足迹与渲染管线使用同一套参数

L3 指针容差：触控基准 66 vp（设置可切 48 vp），再按 FOV 夹角度上限
   - 距离 + 连续亮度先验 × FOV 权重 + 类型先验
   - 超过有效半径视为空白
```

有效半径由 `PointerProfile` 统一计算，触控和鼠标共享候选/评分，只改变几何参数：

```text
degPerVp       = FOV / min(viewportWidthVp, viewportHeightVp)
cappedRadiusVp = maxAngleDeg / degPerVp
effectiveRadiusVp = max(1, min(baseRadiusVp, cappedRadiusVp))
```

| 输入 | baseRadiusVp | maxAngleDeg | 说明 |
|------|--------------|-------------|------|
| 触控 | 66 / 48（设置） | 10° | 手机 FOV 80° 时约 45.8 vp，FOV 60° 时约 61 vp；普通 FOV 基本保持 66 vp 手感 |
| 鼠标/触控板 | 25 device px ÷ DPR | 2° | 对应桌面 25 px 精度；超广角时按 2° 截断 |

角度上限只压缩极端宽视场下的小屏触控半径；平板/PC 大视口通常不会触发。搜索锥在有效半径上另加 12 vp 标签余量。

**顺序：L1/L2 直接命中优先于 L3 评分。** 保证“看得见就点得到”，同时保留手指容差。

### 3.2 单位契约

- ArkUI 触摸坐标：`vp`，左上角原点。
- `selectAt` payload：`x|y|skyW|skyH|touch|mouse`，坐标单位 `vp`；缺省 `touch`。
- 投影器 viewport：设备像素，左下角原点。
- picker 内部统一用 `vp`：

```
dpr = clamp(vp[2] / skyW, 1.0, 4.0)
x_dev = vp[0] + x_vp * dpr
y_dev = vp[1] + vp[3] - 1 - y_vp * dpr
x_vp = (x_dev - vp[0]) / dpr
y_vp = (vp[1] + vp[3] - 1 - y_dev) / dpr
```

所有距离、半径、阈值在 vp 下比较；不要混用 `devicePixelsPerPixel` 和 `vp[2]/skyW`。

### 3.3 视觉足迹 `r_visual`

| 类型 | 计算 | 说明 |
|------|------|------|
| 恒星 | `computeRCMag(mag, &rc)` 为 true 时取 `rc.radius / dpr` | 含 FOV/眼适应/屏幕缩放；`radius == 0` 表示未绘制，跳过 |
| 行星/太阳/月球 | `getSpheroidAngularRadius(core)` → 角径转 vp；最小 4 vp | 覆盖行星圆面/标记 |
| 深空天体 | hint 标记尺寸（约 6 px/dpr；`drawHintProportional` 时按角径，封顶 12 vp） | 不要直接用 `getAngularRadius()` 当足迹；4° 暗星云会形成约 50 vp 的不可见命中区，吞掉范围内恒星。标签命中仍走标签矩形 |
| 卫星 | 图标 → `max(11 px/dpr/2, 3 vp)`；点源 → `computeRCMag(magSat, &rc)` 为 true 时取 `rc.radius/dpr`；仅标签 → 无圆形足迹 | 取决于实际绘制的表示，见 §3.6.1 |
| 星座/星官 | 无半径 | 只走标签/连线 |
| 标签 | 矩形 | 见下 |

统一加 **3 vp 视觉余量**：`r_hit = r_visual + 3`，`direct_hit = d <= r_hit`。

**标签矩形。** 按渲染锚点/字体计算，外扩 4 vp：

- 恒星名称：`ZoneArray.cpp:562-568`，`offset = rc.radius * 0.7`；
- 深空名称：`Nebula.cpp:1171-1177`，`shift = 15 + hintSize`；
- 星座名称：`Constellation.cpp:447`，以标签点水平居中；
- 卫星名称：`Satellite::draw()` 的 `drawText(..., 10, 10)`。

标签是否绘制由各管理器的私有状态决定（`maxMagStarName`、`flagLabels`、faders 等）。**不要复制阈值**；优先新增只读 helper（`isLabelVisible()` / `getScreenLabelRect()`），或接受 1–2 帧的可点性误差。

### 3.4 评分

```
d_i     = 点击点到候选投影中心的屏幕距离（vp）
r_i     = 视觉足迹半径（vp）
d_eff_i = max(0, d_i - r_i)
σ_i     = clamp(12 + 0.5 * r_i, 12, 32)
m_i     = 视星等（含大气消光；无星等对象不参与）
sal_i   = clamp((6.5 - m_i) / 8.0, 0, 1)
gate_i  = clamp(1 - d_eff_i / (r_i + 20), 0, 1)
β(FOV)  = 见 §3.5
bonus_i = β(FOV) * sal_i * gate_i
typeGate= clamp(1 - d_eff_i / 32, 0, 1)
score_i = d_eff_i²/(2σ_i²) - bonus_i - type_i * typeGate
```

规则：

1. **直接命中优先**：`direct_hit_i || label_hit_i` 进入直接命中集合；集合非空时先按命中层级排序：
   - `0` 天体自身足迹（恒星 sprite、行星圆面、DSO 标记、卫星图标/点源）；
   - `1` 天体名称标签；
   - `2` 星座名称标签；
   - `3` 星座连线。

   同层先按 `d_i`（主体中心距手指最近）排序，再按 `type_i` → `sal_i` 排序。这样点中恒星本体时，星座连线/标签和大视径 DSO 都不会把它抢走；只有没有天体直接命中时才选星座。
2. **近失候选**：`d_i <= effectiveRadiusVp + r_i` 内取 `score` 最小者。
3. **空白判定**：最佳候选非直接命中且 `d_i > effectiveRadiusVp + r_i` → 无选中；有效半径内不再用 `score` 二次截断。否则弱星（`sal_i ≈ 0`）的实际容差会被压到约 25 vp，与“手指容差”矛盾。
4. **歧义**：top-2 分差 `< 0.15` 且均非标签命中 → `ambiguous=true`，返回 top-2 供 P2 候选分页。
5. **确定性**：同分依次比较 `type_i`、`sal_i`、`d_i`、对象 ID，保证 CLI 可复现。

`score` 可理解为负对数后验：高斯似然 + “用户更可能指向亮且近的目标”的先验。无星等对象 `sal_i = 0`。

### 3.5 FOV 自适应亮度先验

| FOV | β | 行为 |
|-----|----|------|
| ≥ 90° | 2.6 | 亮星强优势 |
| 60° | 2.0 | 默认观星视场 |
| 20° | 1.2 | 距离开始主导 |
| 5° | 0.5 | 手指下的暗星通常胜出 |
| ≤ 2° | 0.25 | 几乎纯距离 |

`β(FOV) = interpLog10(FOV, {2°:0.25, 5°:0.5, 20°:1.2, 60°:2.0, 90°:2.6})`，避免视场变化时跳变。

### 3.6 类型先验与可见性不变量

| 类型 | `type_i` | 说明 |
|------|----------|------|
| 太阳系行星/太阳/月球 | 1.0 | 只在足迹/近失范围内生效 |
| 人造卫星（已绘制） | 0.7 | 移动目标；不是可见性门槛 |
| 深空天体（提示开启且实际可绘制） | 0.4 | 提示关闭时 `NebulaMgr` 不绘制 DSO，整类不进入候选 |
| 星座/星官（L1 命中） | 0.6 | 只在标签/连线命中时生效 |
| 自建天体/其它 | 0.4 | 用户主动创建 |
| 恒星 | 0 | 由星等先验处理 |

**可见性不变量（全部满足才进入候选）：**

1. 所属模块/图层可见（`getFlagStars`、`getFlagShow`、`getFlagPlanets`、卫星 hints 等）。
2. **实际被绘制**：
   - 恒星：`computeRCMag` 返回 `true && radius > 0`；
   - 行星：`Planet::getPickState()` 镜像 `Planet::draw()`；`hidden` 或行星星等硬限制不通过时不进入候选；
   - 深空：`Nebula::RenderState` 严格镜像 `NebulaMgr::draw()`、`drawHints()`、`drawLabel()`、`drawOutlines()`；只有 `hintDrawn || labelDrawn || outlineDrawn` 至少一个为真才进入候选；catalog/type/size/showOnlyNamed/custom magnitude 过滤全部生效；
   - 卫星：`SatelliteRenderState.pickable()`（见 §3.6.1）；
   - 标签/连线：fader > 0.05 且实际绘制。IAU 星座由 `ConstellationMgr` 处理；星官/星群由独立的 `AsterismMgr` 处理，两者都只接受实际绘制的标签或连线命中。
3. **地面可见性**：`core->getVisibleSkyArea().contains(objDir)`。
   - 地景关闭、淡出中或启用半透明 → 球冠覆盖全天球，**地平线以下可拾取**；
   - 地景完全显示且不透明 → 球冠截止在地景最小高度（默认 -2°），以下不可拾取；
   - 大气不是遮挡条件；不要用固定的 `alt > -0.5°`。
4. 投影成功且在视口内。

> OHOS 默认开启 `landscapeFadeWithZoom`（`src/StelMainView.cpp:2275-2345`）：俯视/缩放时提高 `landscapeTransparency`，地面 alpha 降低。`StelCore::getVisibleSkyArea()`（`StelCore.cpp:520-530`）在透明度 > 0 时返回全天球，`StarMgr`（`StarMgr.cpp:1363`）已据此绘制地平线以下的星。拾取器沿用同一判定，才能与画面一致。

#### 3.6.1 卫星：同一不变量的复杂实例

卫星不是例外，而是“是否真的被绘制”分支最多的类型。拾取器不复制卫星规则，只调用与 `Satellite::draw()` 共用的 `getRenderState()`：

- **总闸**：`hints` fader > 0.05；`|timeRate| < timeRateLimit`；当前行星为地球；日期在 `isValidRangeDates()` 内。
- **单星**：`displayed && orbitValid`；已过发射日期；高度/星等视觉过滤通过；`projectCheck` 成功。
- **表示**：非图标模式下，点源（`magSat <= limitMag`）或标签（`txtMag <= limitMag && showLabels`）至少一个被绘制；图标模式下，11 px 图标（`hideInvisible` 时仅 `VISIBLE`）或标签至少一个被绘制。仅轨道线不算。
- `pickable = (pointDrawn || labelDrawn || iconDrawn) && 地面可见性通过`。

`getSelectPriority()` 不能作为门槛：双过滤时互相覆盖，且不检查 `visibility/showLabels/iconicMode/hideInvisible/displayed/timeRate/planet/date`。它不参与可见性判定。

评分用的等效星等取实际绘制表示：点源 `magSat`、仅标签 `txtMag`、图标 `magSat`。

| 可见状态 | 点源 | 标签 | 图标模式 |
|----------|------|------|----------|
| `VISIBLE` | 按 `magSat` 绘制 | 正常 | 绘制 |
| `PENUMBRAL` | 通常按 8 等，多半不画 | `magSat-3` | `hideInvisible` 时隐藏 |
| 地影/白天/低于地平线 | 通常不画 | `magSat-10`，可能绘制 | `hideInvisible` 时隐藏 |
| `UNKNOWN` | 不画 | 不画 | 不画 |

非图标模式下“点源不画但灰色标签仍画”是可拾取的合法情况——这是“所见即所点”，不是特殊规则。

**实现：** 把 `draw()` 的判定抽成 `SatelliteRenderState` / `Satellite::getRenderState(core, hintFade, dateRangeOk)`，`draw()` 与 picker 共用。`probeSelectAt` 返回 `visibility/magSat/limitMag/pointDrawn/labelDrawn/iconDrawn/pickable`。

### 3.7 候选与性能

| 模块 | 来源 | 备注 |
|------|------|------|
| 恒星 | `StarMgr::searchAround` | 用 `computeRCMag` 过滤 + `getVisibleSkyArea`；搜索多边形必须使用 `e3,e2,e1,e0` 四个角，`e3,e2,e2,e0` 会漏掉方形搜索区的一侧，在高倍率小测地单元下可返回空。2026-11-07 已在原失败的银心密集星场真机复核修复 |
| 行星 | `SolarSystem::searchAround` | 检查 `getFlagPlanets` |
| 深空 | `NebulaMgr::searchAround` | 检查 `getFlagShow` |
| IAU 星座 | `ConstellationMgr` 当前文化遍历 | 只做标签/连线命中 |
| 星官/星群 | `AsterismMgr::listAllObjects` | 独立于 IAU 星座；只接受实际绘制的标签/连线命中 |
| 卫星 | `Satellites::searchAround` | 粗筛后必须 `getRenderState().pickable()` |
| 自建/其它 | 对应 manager | 按图层可见性 |

- 候选搜索锥：触控默认 `66 vp` 基准（设置可切 `48 vp`），经 FOV 角度上限得到 `effectiveRadiusVp`，再加 `12 vp` 标签余量；鼠标使用 25 device px / 2° 上限。更大的锥只会增加投影/标签开销，不能成为候选。
- 恒星先按实际星等上限与 `computeRCMag` 过滤；不再按最亮 256 颗截断，投影后按有效半径预过滤。
- 只对 `mag <= 6.5` 或标签开启的候选计算标签矩形；`QFontMetrics` 每次 pick 构造一次。
- 星座连线只在点击方向落入该星座凸包时检查，避免 88 个星座全量投影。
- 投影失败、视口外、背面直接跳过。
- 单次 pick 实测：Mate 80（366×809 vp、FOV 60°）典型 6–15 ms，密集天区约 15 ms；`selectAt` 端到端仍应 < 80 ms。渲染线程不做 I/O。
- 不在 `selectAt` 内同步收集卫星遥测/详情。

## 4. 交互

### 4.1 选中反馈

- 保留现有选中标记；高倍率下可缩小或改细环。
- 保留 `chimeForSelection`；可选短振动（可关）。
- 命中后立即展开完整资料卡（产品已确认），候选切换只更新同一张卡。
- 单击空白静默清除并关闭详情卡；不弹“未选中天体”提示。
- 双击空白保留为清除快捷键；无选中时不做任何事。
- 点击 UI 面板由 `isUiPoint`/HitTestMode 分流。

### 4.2 候选消歧

- **P2 推荐：候选 chip 分页。** `ambiguous=true` 时在已展开的资料卡顶部/选中标记旁显示 `1/2`，点击切换并刷新同一张卡。
- **P2 可选：重复点击循环。** 若要采用，需把双击清除窗口缩短到 400–600 ms / 24 vp，或仅在 `candidateCount <= 1` 时生效；建议作为设置项。

### 4.3 手势关系

- 拖动超过阈值 → 平移，不选择；捏合 → 缩放，不选择。
- 角度测量优先消费点击，picker 不参与。
- 长按不用于拾取，避免与未来滤镜/校正手势冲突；精确拾取优先放大。

### 4.4 辅助功能

- 标签矩形随系统字体缩放；中文长名称用实际 `QFontMetrics`。
- 选中反馈不只靠颜色：标记 + 资料卡 + 可选触觉。
- 夜间模式使用主题令牌；候选 chip 命中区 ≥ 48 vp。

## 5. 实现

### 5.1 触控/鼠标双拾取器

- `TouchPicker`：共享候选/渲染态/评分引擎，负责 vp 坐标、视觉足迹、标签矩形、FOV 自适应亮度/星等权重、歧义/空白判定；核心代码不依赖 OHOS，不直接 include 插件头。
- `PointerProfile`：输入几何参数。触控使用 66/48 vp 基准 + 10° 上限；鼠标使用 25 device px ÷ DPR + 2° 上限。
- `MousePicker`：同一引擎的鼠标适配器，只构造 mouse profile 并完成选中；不再调用 `cleverFind`，也不维护第二套候选/排序逻辑。
- `StelObjectMgr::cleverFind` 仍保留 `getPickState().pickable` 过滤，作为桌面 legacy 路径的安全网；OHOS 鼠标路径已走共享引擎。
- 输入源显式分流：`selectAt x|y|skyW|skyH|touch|mouse`；缺省 `touch`。`probeSelectAt` 同样接受可选第五段 `touch|mouse`。

### 5.2 文件与职责

```
src/core/TouchPicker.hpp
src/core/TouchPicker.cpp
src/core/MousePicker.hpp
src/core/MousePicker.cpp
```

职责：vp ↔ device px、候选收集、可见性过滤、足迹/标签矩形、评分、直接命中/空白判定、返回 `PickResult`（选中对象 + top-N + 诊断字段）。

接入：

- `src/CMakeLists.txt` 加入源文件；
- `src/StelMainView.cpp` 的 `selectAt` 按 `inputMode` 调用 `TouchPicker` 或 `MousePicker`；
- 保留 `setOhosMousePos`、坐标转换、轻量回包。

### 5.3 `selectAt` 返回契约

保持旧字段，增加诊断字段：

```json
{
  "ok": true, "found": true, "name": "Vega", "type": "恒星",
  "tapX": 540, "tapY": 1200,
  "inputMode": "touch|mouse",
  "baseRadiusVp": 66.0, "effectiveRadiusVp": 61.0,
  "pickMode": "direct|near|label|none",
  "directHit": true, "ambiguous": false, "elapsedMs": 1.2,
  "pickCandidates": [
    { "name": "Vega", "magnitude": 0.03, "screenX": 546, "screenY": 1194,
      "distanceVp": 7.2, "visualRadiusVp": 8.4, "score": -0.59,
      "directHit": true, "labelHit": false }
  ]
}
```

卫星候选额外返回：

```json
{
  "name": "ISS (ZARYA)", "type": "人造卫星",
  "satelliteRender": {
    "hintsFade": 0.82, "displayed": true, "orbitValid": true,
    "visibility": "VISIBLE", "magSat": 0.41, "limitMag": 5.8,
    "pointDrawn": true, "labelDrawn": true, "iconDrawn": false,
    "altitudeFilterPass": true, "magnitudeFilterPass": true,
    "landscapeVisible": true, "pickable": true
  }
}
```

`pickCandidates` 最多 5 条，仅在调试/CLI 或 `ambiguous` 时返回；Release 可通过宏关闭。

### 5.4 语义 CLI

```
probeSelectAt x|y|skyW|skyH[|touch|mouse]
getObjectScreenPosition <name>[|skyW|skyH]
```

- `probeSelectAt` 返回与 `selectAt` 相同的候选排名、`inputMode`/`baseRadiusVp`/`effectiveRadiusVp`，但不改变选中、不打开详情卡；第五段缺省为 `touch`，传 `mouse` 可验证共享鼠标 profile。
- `getObjectScreenPosition` 返回 `screenX/screenY`（vp）、`visualRadiusVp`、`magnitude`、`visible`，供测试脚本计算点击点。
- 加入 `src/StelOhosCommandCatalog.hpp` 白名单和 `docs/harmonyos/CLI.md`。
- 建议在现有 `getSatellites` item 中补充 `visibility` 与 `magSat`。

### 5.5 ArkTS 侧

- `requestSkySelection` payload 不变；仍调用 `selectAt`。
- `ambiguous=true` 时，P2 在 `objectDetailStore` 增加 `pickCandidates/pickCandidateIndex`，由资料卡内 chip 消费。
- 保持一次点选即展开；V1/V2 不混用；宿主 `@Builder` 不传入子组件。
- `SkyInputController` 路由不变；若启用循环，在 `isSkyDoubleTap` 前判断，拖动/缩放时重置序列。

### 5.6 持久化

拾取算法只暴露触控基准半径设置（设置 → 附加 → 触控拾取范围，66/48 vp，默认 66）；角度上限固定为触控 10°、鼠标 2°，不增加第二组用户参数。需要持久化的是可见性：恒星/深空/行星/卫星/星座线/名称/艺术图层、卫星 `hints/labels/orbitLines/iconicMode/hideInvisible`/高度星等过滤/单星 `displayed`，以及可选的“严格可见卫星”模式（默认关闭）。用 `getState`/`getSatellites`/`probeSelectAt` 做重启前后对照。

### 5.7 性能与线程

- `selectAt` 在 Qt 主线程执行；picker 短小，不收集详情/遥测。
- 返回 top-5 候选；候选收集不设 256 颗截断，投影后按 `effectiveRadiusVp` 预过滤；标签只算可见项，`QFontMetrics` 复用。
- 不在 picker 内做网络/文件 I/O。
- 用 `probeSelectAt.elapsedMs` 和真机帧率验收；p95 > 20 ms 时先优化候选/标签，不减少可见性检查。

## 6. 实施切片

### P0 正确性

- [ ] 取消星座无条件兜底；星座只在标签命中时成为候选（连线 P1）。
- [ ] 新增 `TouchPicker`，统一 vp。
- [ ] 恒星/行星/深空/卫星使用实际绘制足迹；卫星接入共享 `SatelliteRenderState`。
- [ ] 地面可见性改用 `core->getVisibleSkyArea()`；地平线以下按地面透明度放行。
- [ ] 标签矩形（恒星、星座；深空 P1）。
- [ ] `probeSelectAt` + `getObjectScreenPosition`。
- [ ] 回归拖动/捏合/双击/面板/角度测量。

### P1 亮度与类型先验

- [ ] `salience × gate × β(FOV)`；β 插值。
- [ ] 类型先验表；直接命中集合；空白阈值。
- [ ] 深空标签；星座连线命中（折线 ≤ 6 vp）。
- [ ] 密集星场/银河/FOV 120°/60°/10°/2° 压测。

### P2 反馈与消歧

- [ ] `ambiguous` 候选 chip（刷新同一张卡）。
- [ ] 空白单击静默清除；双击保留。
- [ ] 可选触觉；主题令牌。
- [ ] 可选：`LandscapeMgr::getLandscapeOpacity(altAz)` 采样局部山脊遮挡。
- [ ] 若采用重复点击循环，重定义双击窗口。

### P3 可选

- [ ] 长按/拖动精确拾取放大镜。
- [ ] 星座艺术区域命中（最低优先级）。
- [ ] AR/陀螺仪拾取一致性。

## 7. 验收

### 7.1 功能矩阵

| # | 场景 | FOV | 操作 | 期望 |
|---|------|-----|------|------|
| 1 | 亮星附近有暗星 | 60° | 距亮星 20 vp、距暗星 4 vp | 亮星 |
| 2 | 暗星正下方 | 60° | 点在暗星 sprite 内 | 暗星（直接命中优先） |
| 3 | 高倍率点恒星 | 2° | 点星体/标签 | 恒星；不得选星座 |
| 4 | 空白天区 | 60°/2° | 远离标签/连线 | 无选中 |
| 5 | 星座名称 | 60° | 点名称 | 该星座 |
| 6 | 星座连线 | 60° | 点连线 6 vp 内 | 该星座 |
| 7 | 星座名称关闭 | 60° | 点原位置 | 无选中 |
| 8 | 恒星图层关闭 | 60° | 点原亮星 | 无选中 |
| 9 | 地平线以下，地景不透明 | 任意 | 点地平线下亮星 | 无选中 |
| 10 | 地平线以下，地景半透明/关闭 | 任意 | 俯视或缩放后点地平线下目标 | 选中 |
| 11 | 行星与恒星重叠 | 10° | 点行星圆面 | 行星 |
| 12 | 恒星标签 | 10° | 点名称 | 该恒星 |
| 13 | 中文星空文化 | 60° | 点星官名称/连线 | 该星官，不回退 IAU |
| 14 | 候选重叠 | 60° | 同一位置两次 | 第一次展开资料卡；P2 chip 切换 |
| 15 | 拖动/捏合 | 任意 | 拖动 50 vp / 捏合 | 不选择 |
| 16 | 角度测量 | 任意 | 点击 | 测量，不选中 |
| 17 | 重启后图层状态 | 任意 | 关闭卫星→重启→点击 | 仍关闭且不可选 |
| 18 | 卫星专项 | 60° | 见 §7.4 | 见 §7.4 |
| 19 | 银心密集星场无目标 | 0.8° | 点击任意可见恒星附近 | `found=true`；`starSearchCount>0` 且 `starCandidateCount>0`，不得因搜索多边形漏星返回空 |

### 7.2 量化指标

- 星座误选率：恒星/空白点击 = 0（显式标签/连线除外）。
- 直接命中召回：当前绘制足迹内点击 = 100%。
- 亮星胜率：FOV ≥ 30°、距亮星 ≤ 20 vp、距暗星 ≤ 4 vp，≥ 90%。
- 空白判定：远离候选 > `effectiveRadiusVp`（触控默认 66 vp，宽视场按 10° 上限收缩），无选中 = 100%。
- 性能：`probeSelectAt` 典型 6–15 ms、p95 < 20 ms、p99 < 30 ms（Mate 80，366×809 vp，FOV 60°）；`selectAt` 端到端 p95 < 80 ms。
- 无回归：拖动、捏合、双击、面板、角度测量、陀螺仪。

### 7.3 CLI 验证脚本

新增 `scripts/test-ohos-touch-picking.py`：

1. 固定时间/地点/FOV/星空文化；
2. `searchObject Vega` + `moveToSelected`，用 `getObjectScreenPosition` 取坐标；
3. 选邻近暗星，对偏移 0/5/10/20/30 vp 调用 `probeSelectAt`，断言 top-1；
4. `selectAt` 后用 `getSelectedObjectInfo` 断言实际选中，并断言资料卡已展开；空白点击后关闭；
5. 关闭星座名称/连线与恒星图层，点星座区域，断言 `found=false`；
6. 关闭卫星图层/过滤，断言无候选；
7. 输出 `elapsedMs` 分布与失败用例。

脚本只用语义 CLI，不注入坐标点击；平台差异记录到 `PLATFORM-MATRIX.md`。

### 7.4 卫星分支验收（并入通用模型）

卫星不另写算法；以下只覆盖通用矩阵未触及的渲染分支。每项用 `probeSelectAt.satelliteRender` 解释原因，不能只断言 `found=false`。

| # | 场景 | 预期 |
|---|------|------|
| S1 | `hints` 关，`orbitLines` 开 | 无候选；轨道线不是选择目标 |
| S2 | `timeRate` 超限 / 非地球 / 日期越界 / `displayed=false` / `orbitValid=false` | 无候选 |
| S3 | 高度或星等过滤不通过（含双过滤仅一项失败） | 无候选 |
| S4 | `VISIBLE`，点源/凌日 sprite 绘制，`labels` 关 | 可拾取 |
| S5 | 非 `VISIBLE`（半影/地影/白天），`labels` 开，点源未绘制 | 可拾取（仅标签） |
| S6 | 非 `VISIBLE`，`labels` 关，非图标模式 | 无候选（点源/标签均未绘制） |
| S7 | 图标模式 + `hideInvisible`：非 `VISIBLE` → 无候选；`false` → 可拾取 | 按图标绘制判定 |
| S8 | `BELOW_HORIZON`：地面不透明 → 无候选；地面半透明/关闭 → 可拾取 | 与普通天体同一地面可见性规则 |

## 8. 风险与决策

### 8.1 风险

| 风险 | 缓解 |
|------|------|
| 标签矩形与渲染字体/偏移漂移 | 共享 helper；4 vp 内边距；真机截图回归 |
| 密集星场候选过多 | 按投影后有效半径预过滤；星等/渲染态预过滤；标签只算可见项 |
| 共享 picker 与桌面 `cleverFind` 行为分叉 | OHOS 鼠标路径走共享引擎；`cleverFind` 仅保留 legacy 过滤；共享测试用例 |
| 类型先验过强 | 只在足迹/近失范围生效；直接命中优先；合成用例调参 |
| 双击清除与循环冲突 | P2 chip 优先；循环作为可选设置 |
| 地面透明判定与实际 alpha 偏差 | P0 用 `getVisibleSkyArea`；P2 采样 `getLandscapeOpacity` |
| 折叠屏/分屏 DPR 非整数 | 用 `vp[2]/skyW`，夹在 [1,4] |

### 8.2 决策

1. 点选后自动展开完整详情卡：**已确认保持**。
2. 候选消歧：推荐 chip；循环可选。
3. “点星座区域选星座”兼容开关：保留但默认关闭，中文星空文化尤其不应默认开启。
4. 行星/卫星类型先验强度：1.0/0.7，真机调参。
5. 卫星可见性：**镜像渲染**（点源/标签/图标任一绘制即可拾取），不再对 `BELOW_HORIZON` 单独设“地景遮挡覆盖”；地面可见性统一由 §3.6 的球冠规则处理。严格模式（只允许 `VISIBLE`/`PENUMBRAL`）作为默认关闭的设置项。

## 9. 附录

### A. 当前代码索引

| 主题 | 位置 |
|------|------|
| `selectAt` / `probeSelectAt` / 输入源 | `src/StelMainView.cpp`（search `commandName == "selectAt"`） |
| `PointerProfile` / 有效半径 | `src/core/TouchPicker.cpp`（`pickAt` 重载、`touchProfile`、`mouseProfile`） |
| `cleverFind`（legacy 路径） | `src/core/StelObjectMgr.cpp:461-515` |
| 星座 `searchAround` | `src/core/modules/ConstellationMgr.cpp:1959-1995` |
| 恒星 `searchAround` | `src/core/modules/StarMgr.cpp:1454-1531` |
| 恒星绘制半径 | `src/core/StelSkyDrawer.cpp:404-439` |
| 行星绘制门控 | `src/core/modules/Planet.cpp`（`draw` / `getPickState`） |
| 星官/星群 | `src/core/modules/AsterismMgr.cpp`、`Asterism.cpp` |
| 恒星名称偏移 | `src/core/modules/ZoneArray.cpp:562-568` |
| 深空名称偏移 | `src/core/modules/Nebula.cpp:1171-1177` |
| 星座名称偏移 | `src/core/modules/Constellation.cpp:447` |
| 可见天空球冠 | `src/core/StelCore.cpp:520-530` |
| 地景最小高度/透明度 | `src/core/modules/LandscapeMgr.cpp:1197-1205`、`1349-1373` |
| OHOS 地景自动淡出 | `src/StelMainView.cpp:2275-2345` |
| 卫星 `searchAround` | `plugins/Satellites/src/Satellites.cpp:788-816` |
| 卫星单星绘制 | `plugins/Satellites/src/Satellite.cpp:1382-1489` |
| 卫星总闸 | `plugins/Satellites/src/Satellites.cpp:3611-3665` |
| 卫星 `getSelectPriority` | `plugins/Satellites/src/Satellite.cpp:323-333` |
| 卫星可见性预测 | `plugins/Satellites/src/gSatWrapper.cpp:203-249`、`gSatWrapper.hpp:44-54` |
| 卫星日期范围 | `plugins/Satellites/src/Satellites.cpp:3817-3825` |
| 对话框路由/双击 | `harmonyos/ets-source/capability/SkyInputController.ets:185-214` |
| 选中后展开详情/chime | `harmonyos/ets-source/pages/MainWindowNativeNode.ets:5934-5967` |

### B. 参数速查

| 参数 | 值 | 说明 |
|------|----|------|
| `baseRadiusVp` | 触控 66 vp（可设 48 vp）；鼠标 25 device px ÷ DPR | 输入基准半径 |
| `maxAngleDeg` | 触控 10°；鼠标 2° | 宽视场角度上限 |
| `effectiveRadiusVp` | `max(1, min(base, maxAngle/degPerVp))` | 实际近失/空白半径 |
| `σ_finger` | 12 vp | 高斯手指抖动 |
| `σ_i` | `clamp(12+0.5r, 12, 32)` | 视觉尺寸越大容差越大 |
| `m_ref` | 6.5 | 亮度先验归零 |
| `m_bright` | -1.5 | 最亮端 |
| `D0` | 20 vp | 亮度距离衰减 |
| `β(FOV)` | 2.6 → 0.25 | 90° → 2°，log10 插值 |
| `type` | 行星 1.0 / 卫星 0.7 / DSO 0.4 / 星座 0.6 | 乘 `typeGate` |
| `D_type` | 32 vp | 类型先验衰减 |
| `S_empty` | `effectiveRadiusVp²/(2·12²)` | 仅作距离门控的 σ=12 保险上限；空白由 `effectiveRadiusVp` 距离判定 |
| `k(FOV)` | `0.5 * β(FOV)` vp/mag | 直接命中的星等权重；DSO 不参与 |
| 歧义阈值 | 0.15 | top-2 分差 |

### C. 参考

- Sky Guide 官方支持：Star sounds / Star brightness / Finding objects / Controlling time — https://support.fifthstarlabs.com/
- SkySafari 选择循环与星座 “Tap to Select”：Simulation Curriculum 支持社区 / Cloudy Nights。
- Apple Human Interface Guidelines：可点击区域至少 44×44 pt。
- Bi, Li & Zhai, “Bayesian Touch”, UIST 2013；FFitts Law, CHI 2013。
