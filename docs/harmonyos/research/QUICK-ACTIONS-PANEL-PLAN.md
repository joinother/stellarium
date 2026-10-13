# 快捷操作面板（Dock 中间入口）设计与实施计划

状态：一期（§1–§12）已按 §8 切片实施完毕、真机验收通过；**二期（§13：12 格可自定义 + 5 个新按钮）设计完成、待实施**。
适用工程：`harmonyos/`（ArkTS 侧）；不改引擎 C++。

## 0. 目标

1. Dock 栏**中间**按钮由「位置」改为「快捷操作」，点开一个 2×6 = **12 个图标开关**的面板。
2. 12 个图标用 Stellarium **官方图标**（`data/gui/bt*-off.png`）；ON 态按移动端做法 = **用「灭」图标着色高亮**，不使用官方 `-on` 图标。
3. 「位置」入口迁到「更多功能」，位置在**工作区入口与天体数据与扩展入口之间**。
4. 快捷面板标题栏显示当前位置，且该显示框**本身是按钮**，点按直接进入位置设置（细则见 §11）。

参考图（排布样式依据）：`docs/harmonyos/image/com.noctuasoftware.stellarium.jpg`——官方 Stellarium Mobile（Noctua Software）截图，由用户提供；该图片目前**尚未纳入版本控制**。

## 1. 事实勘查（先于设计，逐条有据）

| # | 事实 | 依据 |
| --- | --- | --- |
| 1 | 官方图标 `data/gui/bt*-off.png` ↔ `bt*-on.png` 成对，**160×160 PNG、3–13 KB** | 目录清单 + `System.Drawing` 实测尺寸 |
| 2 | `-off` 是暗灰、`-on` 是白（已看图确认 `btAtmosphere`）→「用灭图标高亮」= 读 `-off` 再着色 | 读 `btAtmosphere-off/on.png` |
| 3 | `data/gui` **未打进 HAP**（`rawfile/` 只有 `stellarium/` 与 `worldmap.jpg`）→ 必须新增资源或改构建 | `build/libstellarium-harmonyos/entry/src/main/resources/rawfile` |
| 4 | 着色官方依据：`colorBlend` 会把**透明背景变白**，ArkUI FAQ 明确「采用 `colorFilter` 替代」（颜色矩阵只改非透明像素、保留 alpha） | `devecocli docs read FAQ/UI框架/组件使用/如何对PNG图标进行着色/faqs-arkui-1328` |
| 5 | 移动端现有图标机制 = 单色 SVG + `.fillColor()`（77 个 `ic_*.svg`）；`getIcon(icon, isActive)` 的 `isActive` 目前未被使用 | `common/ui/ShellIcons.ets` |
| 6 | 12 项状态**全已存在**：`LayerStore`(9 项) / `SatelliteStore.satHints` / `GyroStore.gyroscopeEnabled` / `NightModeStore.nightMode` | 各 store 实读 |
| 7 | Dock = `canonicalDockActions()` = `primaryDockActions()[0..3]` + 更多；中间即 index 2 = `place`；Dock 按钮**无 `.id()` 锚点** | `pages/MainWindowNativeNode.ets` `canonicalDockActions()` |
| 8 | `MorePanel` 按 `item.section` 变化插小标题 → `place` 放进 `moreActions()` 中 `more_workspace_observing` 之后并沿用 `more_section_workspace`，即「工作区」组第 2 行、压在天体数据组标题之前 | `panels/panels/MorePanel.ets` + `common/derive/actions.ets` |
| 9 | 面板路由表须同步 3 处：`panelRouteRoot` 的 `mainPanels`、`inferredPanelRouteDirection` 的 `routeOrder`、`common/derive/skycult.ets` 的面板清单 | `common/derive/actions.ets`、`common/derive/skycult.ets` |
| 10 | 人造卫星官方 action = `actionShow_Satellite_Hints`（插件 `flagHintsVisible`，即"显示人造卫星"总开关）→ 正对应 `SatelliteController.setSatelliteFlag('hints', v)` | `plugins/Satellites/src/*.cpp` |
| 11 | 官方 `data/gui` **没有** `人造卫星` / `陀螺仪` 的 `bt*` 图标 | 目录清单核对 |

## 2. 12 项映射表

| # | 名称（提示文案） | 动作 | 状态源 | 图标 |
| --- | --- | --- | --- | --- |
| 1 | 星座连线 | `actionShow_Constellation_Lines` | `layerStore.constellationLines` | `bt_constellation_lines.png` |
| 2 | 星座标识 | `actionShow_Constellation_Labels` | `constellationLabels` | `bt_constellation_labels.png` |
| 3 | 星座图绘 | `actionShow_Constellation_Art` | `constellationArt` | `bt_constellation_art.png` |
| 4 | 赤道坐标 | `actionShow_Equatorial_Grid` | `equatorialGrid` | `bt_equatorial_grid.png` |
| 5 | 地平坐标 | `actionShow_Azimuthal_Grid` | `azimuthGrid` | `bt_azimuthal_grid.png` |
| 6 | 地景 | `actionShow_Ground` | `ground` | `bt_ground.png` |
| 7 | 大气层 | `actionShow_Atmosphere` | `atmosphere` | `bt_atmosphere.png` |
| 8 | 方位基点 | `actionShow_Cardinal_Points` | `cardinalPoints` | `bt_cardinal_points.png`（内容取自官方 `data/gui/bbtLocation-off.png`，见 §12.6） |
| 9 | 深空天体 | `actionShow_Nebulas` | `nebulas` | `bt_nebula.png` |
| 10 | 人造卫星 | `setSatellitesFlag hints:1/0` | `satelliteStore.satHints` | `ic_satellite.svg`（自研，`kind: vector`） |
| 11 | 陀螺仪 | gyro 启停（`setGyroView` 链路） | `gyroStore.gyroscopeEnabled` | `ic_gyro.svg`（自研，`kind: vector`） |
| 12 | 夜间模式 | `setNightMode` | `nightModeStore.nightMode` | `bt_night_view.png` |

网格排布（与用户截图一致）：**第 1 行 = #1–#6**（星座×3 → 坐标×2 → 地景），**第 2 行 = #7–#12**（大气 → 方位基点 → 深空 → 卫星 → 陀螺仪 → 夜间模式）。

## 3. 图标与着色方案（本次核心）

```
ON :  Image(bt_xxx.png).colorFilter(TINT_ON)    // 矩阵把 RGB 统一压成 #EAF7FF，alpha 保留
OFF:  Image(bt_xxx.png).colorFilter(TINT_OFF)   // 压成暗灰 #7E8896（不再叠加 opacity，见 §12.6）
向量 :  Image(ic_xxx.svg).fillColor(on ? '#EAF7FF' : '#7E8896')   // 沿用既有 SVG 机制
```

- 颜色矩阵形如 `[0,0,0,0,R, 0,0,0,0,G, 0,0,0,0,B, 0,0,0,1,0]`（只改 RGB、保留 alpha）；写成文件级
  `const TINT_ON: number[] = [...]` / `const TINT_OFF: number[] = [...]`，显式定型以符合 ArkTS 禁裸字面量。
- **矩阵值必须归一化到 0.0–1.0**（1.0 对应 255，官方 FAQ `faqs-arkui-1353`）；填 0–255 会被截断成近白 —— 实机踩过，见 §12。
- 10 个官方 PNG 拷入 `harmonyos/ets-source/resources/base/media/` 并改蛇形名（`bt_*.png`），合计约 71 KB。
- 组件按 `kind: 'raster' | 'vector'` 走双路径着色；两种路径都产出同一套 `#EAF7FF` / `#7E8896` 观感。
- 官方 `-off` PNG 自带柔和阴影，`colorFilter` 会把阴影一并着色成半透明同色 → 视觉上是轻微光晕，可接受；
  若真机实测偏脏，退路是 `.brightness()` / 直接调 `TINT_OFF` 的亮度档。

## 4. 结构（按仓库分层，力求零新增 store / 零新增 controller）

| 层 | 文件 | 职责 |
| --- | --- | --- |
| derive | `common/derive/quickActions.ets`（新） | 12 项**纯描述表**（`id` / `labelKey` / `icon` / `kind` / `actionId`），零 store、零 IO、零桥 |
| panel | `panels/quick/QuickActionGrid.ets`（新） | 2×6 网格 + 双路径着色 + 长按 `flashHint(名称)` |
| panel | `panels/panels/QuickPanel.ets`（新） | 只装配图标网格；标题栏由宿主 `PanelHeader` 渲染（`titleAsButton` 显示位置并跳「位置」） |
| 宿主 | `pages/MainWindowNativeNode.ets` | `activePanel === 'quick'` 分支 + `quickToggle(id, value)` 分发到 4 个既有控制器/store |
| 入口 | `common/derive/actions.ets` | Dock 中间项替换、`moreActions()` 插入 place、路由表 2 处 |
| 入口 | `common/derive/skycult.ets` | 面板清单同步 |
| 图标 | `common/ui/ShellIcons.ets` | 注册 `'quick_actions'` → 新增 `ic_quick_actions.svg`（Dock 中间项用） |
| 文案 | `capability/I18n.ets` | 缺失标签键（见 §5）＋ `loc_source_gps` |

关键点：**状态与动作全部已存在**，宿主只做一次 `id → 目标` 的分发，因此不需要新 store、不需要新 controller。

`quickToggle` 分发（宿主内）：
- `layerStore` 系（#1–#9）→ `layerCtl().applyLayerSwitch(actionId, '', value)`（`setLayer` 是 private，公开入口才是它）
- #10 → `satelliteCtl().setSatelliteFlag('hints', value)`
- #11 → 陀螺仪启停（复用位置面板已有的 `gyroCtl()` 入口）
- #12 → `nightModeStore.applyNightMode(value, true)`（与时间面板同一入口）

## 5. 文案

- 面板标题 = **观测点文本**（用户决策：标题栏直接显示观测点），副标题沿用 `timeStore.panelSubtitle()`。
- `common/derive/labels.ets` 的 `panelTitleFor(...)` 增加一个 `locationText` 入参（仅 `quick` 用），保持纯函数。
- 12 个提示文案**全部复用既有键**（零新增项文案，落地后逐条列证见 §12.2）：星座线 `s0522` / 星座标签 `s0523` /
  星座艺术 `s0525` / 赤道网格 `s0323` / 方位网格 `s0324` / 地面 `s0306` / 大气 `s0305` / 方位基点 `s0533` /
  深空天体 `s0320` / 人造卫星 `plugin_satellites` / 陀螺仪 `i0060` / 夜间模式 `s0300`。
- Dock 标签新增 `dock_quick`（zh_CN「快捷开关」）；位置来源标签新增 `loc_source_gps`（`GPS`）。
  注：既有 `i0217` = 「快捷操作」已被帮助面板占用，故 Dock 用「快捷开关」避免重名。

## 6. 布局规格（对齐截图）

| 项 | 值 |
| --- | --- |
| 网格 | 6 列 × 2 行 |
| 图标 | raster 30 vp / vector 26 vp（官方 PNG 留白更多，故取略大） |
| 单元格 | 宽度由行均分（`layoutWeight(1)`）+ `aspectRatio(1)` 成正方形（本机实测 ≈ 52 vp），圆角 `UI_RADIUS_CONTROL` |
| 间距 | 横向 8 vp，纵向 10 vp |
| 面板高度 | **只显示两行**：`quickPanelContentHeight()` = 12 + 30（抓手）+ 头部（有副标题 56 / 无 44）+ 14 + 两行图标 + 16；详见 §12.6 |
| 底色 | **未选中不画底框**（透明；夜间模式下浅底框几乎不可辨）；选中 `rgba(107,163,214,0.12)` + 边框（与 `LayerSwitchRow` 同一套语汇）。边框宽度恒为 1（颜色透明）以免切换时格子尺寸跳动 |
| 文字 | 网格内**不显示**逐项文字（同截图）；长按出 `flashHint` 名称 |
| 无障碍 | `.accessibilityText(名称)` |

## 7. 已确认决策

1. 载体 = **标准面板**（标题栏显示观测点）。
2. `星空连线` = `actionShow_Constellation_Lines`（星座连线）。
3. `人造卫星` / `陀螺仪` 用**现有自研 SVG**（官方无 `bt*` 对）。
4. 官方 PNG **拷入 `resources/base/media/`**（不改构建脚本、不打包整个 `data/gui`）。
5. `陀螺仪` 点按 = **直接启停**（等同位置面板陀螺仪按钮）。
6. 本设计**落成计划文档**（本文件）。
7. Dock 中间入口图标 = 新增 `ic_quick_actions.svg`（Material `dashboard`，4 块**不等大小**方块的面板语汇），经 `ShellIcons` 注册为 `'quick_actions'`。该文件已先期存入 `harmonyos/ets-source/resources/base/media/`（24×24、单行、CRLF、无 BOM，与 `ic_layers.svg` 同规格）。选它的理由：仓库现有 76 枚图标本就是 Material 家族（`ic_search`/`ic_settings`/`ic_layers` 的 path 与官方逐字节一致），新增同族图标零许可面变化（Apache-2.0）、零风格断层。
8. 快捷面板标题栏的**位置显示框本身即按钮**：点按直接跳转「位置」面板；判定按**来源 + 观测星球**而非名称字符串：GPS 且观测星球为地球 → `GPS`；地图点选 → 「自定义位置」（复用既有键 `custom_location`）；其余（含非地球星球）→ 位置名。两处文案与位置面板「位置」行**同源**（都读宿主 `locationText`）。细则见 §11。
9. 「自定义位置」措辞**沿用仓库既有键**（用户确认），不引入「自定义地点」新文案。

## 8. 切片清单（实施）

- **QA1 图标落盘**：从 `data/gui/` 拷 10 个 `bt*-off.png` → `resources/base/media/bt_*.png`；跑 `audit-ohos-resource-coverage`。（Dock 用的 `ic_quick_actions.svg` 已先期存入，见 §7.7。）
- **QA2 描述表 + 文案**：新增 `common/derive/quickActions.ets`；补/复用 12 个文案键与 `dock_quick`。
- **QA3 网格组件**：`panels/quick/QuickActionGrid.ets`（双路径着色、长按提示、无障碍）。
- **QA4 面板 + 宿主分发**：`panels/panels/QuickPanel.ets`；宿主 `activePanel === 'quick'` 分支 + `quickToggle()` + `panelTitleFor` 观测点。
- **QA4b 位置来源与标题栏按钮**：`LocationPickerStore` 增 `locationSource`；`useDeviceLocation` / 地图点选 / 城市与搜索三处分别写 `gps` / `map` / `named`；`ObserverLocationRecord` 增 `source` 字段并由 `restoreObserverLocation` 回读（旧记录缺该字段回落 `named`）；`PanelHeader` 增 `titleAsButton` + `onTitleTap` 与 `panel-title-action` 锚点；宿主按来源推导标题标签，点按走 `openSubPanel('place')`。
- **QA5 入口改造**：Dock 中间项替换为 `quick`；`moreActions()` 插入 `place`（工作区组）；路由表 2 处 + `skycult.ets` 同步。
- **QA6 验证与提交**：`arkts_check` → 构建 → `check-ohos-ui-contract`（新增锚点走 `--update`）→ 资源审计 → 真机 12 项逐一点按 + 引擎侧回读 → CHANGELOG → commit。

## 9. 验证口径

1. 静态：`arkts_check` 0 error；`devecocli build` SUCCESSFUL。
2. 契约：`node scripts/check-ohos-ui-contract.mjs` intact（新增锚点须 `--update` 再生并说明）。
3. 资源：`node scripts/audit-ohos-resource-coverage.mjs` 通过（新增 10 个 media 计入）。
4. 真机（`--bundle <本机调试包名>`，勿用默认发布包名）：
   - Dock 中间按钮打开快捷操作面板，标题显示观测点；
   - 12 项逐一点按 → 图标亮/灭切换正确；
   - 用 `getState` 回读 `actionShow_Constellation_Lines` / `..._Labels` / `..._Art` / `..._Equatorial_Grid` / `..._Azimuthal_Grid` / `..._Ground` / `..._Atmosphere` / `..._Cardinal_Points` / `..._Nebulas` / `nightMode`，用卫星面板或 `setSatellitesFlag` 回执核对 `hints`，陀螺仪看 `gyroscopeEnabled` 与权限提示；
   - 「更多功能」中位置入口位于「观测工作区」与「天体数据与扩展」之间，点按进入位置面板；
   - 标题栏位置按钮：点按进入位置面板；**两处（位置面板「位置」行与快捷面板标题）必须显示同一字符串**；GPS 定位且观测星球为地球时显示 `GPS`，其余星球回落位置名（如「火星表面」），地图点选显示「自定义位置」（见 §11.3），城市选择显示城市名；杀进程重启后标签保持（来源随观测点持久化）。
5. `eol`：新增 `.ets` 与文档一律 CRLF；`write` 工具产物须归一回 CRLF。

## 10. 风险与对策

| 风险 | 对策 |
| --- | --- |
| `colorFilter` 把官方 PNG 的柔阴影一并着色，观感偏脏 | 先按本方案实现，真机看效果；退路 `.brightness()` 或调 `TINT_OFF` |
| 12 项里 `赤道坐标` 等会与图层页既有措辞（`赤道网格`）不一致 | 面板内不显示文字，仅长按提示；文案在 QA2 逐条定稿并记录 |
| 新面板进入 `panelRouteRoot` 主链，返回手势/路由方向可能错位 | QA5 同步 3 处路由表，QA6 真机走查返回栈（含系统返回手势） |
| 陀螺仪启停涉及权限弹窗 | 真机走查权限路径，未授权时保留"提示 + 不改状态"的既有降级 |

## 11. 位置来源与标题栏按钮（补充设计）

### 11.1 现状（事实）

| 事实 | 依据 |
| --- | --- |
| 位置文案当前由引擎回读驱动：`locationText = locationDisplayName(engine.locationName) + ' · ' + planetZh(planet)`，且宿主的 `locationText` **会被轮询覆写** | `MainWindowNativeNode` 引擎状态分支 + `@State locationText` |
| GPS 路径落地的名字 = `I18n.t('m_current_location')`；GPS 与地图点选**共用** `LocationPickerStore.setPickerLocation(name, …)` | `LocationController.useDeviceLocation()`、`LocationPickerStore.setPickerLocation()` |
| 观测点已持久化：`ObserverLocationRecord{ name, latitude, longitude, altitude, planet }`，启动由 `restoreObserverLocation()` 静默重建 | `LocationController.restoreObserverLocation()` |
| 应用**没有**记录"位置来源"，只能从名称字符串猜 | 全仓无 source / tag 字段 |
| 面板跳转入口 = 宿主 `openSubPanel(panel)`（「更多功能」各处都走它） | `MainWindowNativeNode` 的 `onOpenPanel: (panel) => this.openSubPanel(panel)` |

结论：要按来源显示，必须**新增来源标记**；不能靠字符串匹配——`m_current_location` 是本地化文案，切语言即失效。

### 11.2 来源标记

- `state/LocationPickerStore.ets` 新增 `locationSource: 'gps' | 'map' | 'named' = 'named'`。
- 三个写入点：

| 入口 | 写入 | 备注 |
| --- | --- | --- |
| `LocationController.useDeviceLocation()` GPS 成功落地 | `'gps'` | 与 `setPickerLocation(...)` 同一处 |
| `LocationPickerPanel` 地图点选 / 拖动落地 | `'map'` | 与 `setPickerLocation(...)` 同一处 |
| `selectCityByName()` / 搜索点选 / 预设 / 恢复 | `'named'` | 默认值，可省写 |

- 持久化：`ObserverLocationRecord` 增 `source?: string`；`setLocation()` 透传并在写盘时带上；`restoreObserverLocation()` 读回，**非法或缺失一律回落 `named`**（保证旧记录兼容）。

### 11.3 显示规则

判定顺序（最终实现 = 纯函数 `quickLocationLabel(source, displayName, planetName)`）：

| 条件 | 显示 | 文案键 |
| --- | --- | --- |
| 来源 `gps` **且观测星球 = 地球** | `GPS` | 新增 `loc_source_gps`（zh_CN `GPS`）。**不要复用**既有 `gps` 键——它是「GPS导航」，卫星类别名 |
| 来源 `map` | 自定义位置 | 复用既有键 `custom_location`（zh_CN 即「自定义位置」） |
| 其余（含 `gps` + 非地球星球） | 该位置名 | — |

- 「非地球观测点」的位置名由引擎按星球给（实测为 `Mars surface` 这类英文串），在 `LocationPickerStore.surfaceLocationName`
  折到既有 `land_mars` / `land_moon` / `land_jupiter` 键 → 「火星表面」/「月球表面」/「木星表面」。
- 位置面板「位置」行与快捷面板标题**共读宿主 `locationText`**，保证两处逐字一致（见 §12.6）。

**措辞已定（用户确认）**：`map` 来源沿用仓库既有键 `custom_location` = 「自定义位置」，**不引入**「自定义地点」新文案——位置面板头部与保存对话框用的都是「自定义位置」，保持全应用一致。

### 11.4 标题栏按钮

- `panels/shell/PanelHeader.ets` 新增：
  - `@Prop titleAsButton: boolean = false`
  - `onTitleTap: () => void = () => {}`
  - `titleAsButton === true` 时标题文本外包为按钮化容器：`backgroundColor('rgba(255,255,255,0.06)')`、`borderRadius(UI_RADIUS_PILL)`、`height(32)`、`padding({ left: 12, right: 8 })`，右侧配 `getIcon('chevron_right')`（着色 `rgba(184,228,255,0.72)`），并加 `.stateStyles({ pressed: … })` 与 `.accessibilityText(...)`。
  - 新增跨会话静态 id 锚点 **`panel-title-action`**（契约静态 id 24 → 25，须 `--update` 并说明）。
- 宿主：仅 `activePanel === 'quick'` 传 `titleAsButton: true`，`onTitleTap: () => { this.openSubPanel('place') }`。
- 标题文本**直接用宿主的 `locationText`**（`quickPanelLocationLabel()` 就是它的读取器），与位置面板「位置」行完全同源。
  原设计曾担心轮询会把 `GPS` 冲掉，但把取值规则做进轮询分支后该顾虑已不成立（见 §12.6）；取值逻辑在纯函数
  `quickLocationLabel(source, displayName, planetName)`（`common/derive/labels.ets`），`panelTitleFor(...)` 只负责组装标题。
- 副标题沿用 `timeStore.panelSubtitle('quick')`，作为按钮文案的补充（可显示观测坐标）。

## 12. 实施结果（QA1–QA6 全部完成）

### 12.1 切片结论

| 切片 | 结论 |
| --- | --- |
| QA1 图标落盘 | 10 枚 `bt*-off.png` → `resources/base/media/bt_*.png`（~71 KB）；`ic_quick_actions.svg` 先期存入 |
| QA2 描述表与文案 | `common/derive/quickActions.ets` + `ShellIcons` 注册 11 个键 + `dock_quick` / `loc_source_gps` |
| QA3 网格组件 | `panels/quick/QuickActionCell.ets`（双路径着色 + 长按提示 + accessibilityText）、`panels/quick/QuickActionGrid.ets`（两行 Row，每格 `layoutWeight(1)` + `aspectRatio(1)`） |
| QA4 面板与宿主分发 | `panels/panels/QuickPanel.ets` + 宿主 `activePanel === 'quick'` 分支、`quickActionValues()`、`quickToggle()` |
| QA4b 位置来源与标题按钮 | `LocationPickerStore.locationSource` + `ObserverLocationRecord.source`（持久化 / 回读，旧记录回落 `named`）+ `PanelHeader.titleAsButton` / `onTitleTap` / `panel-title-action` + `quickLocationLabel` + `openSubPanel('place')` |
| QA5 入口改造 | Dock 第 3 项改为 `quick` / `quick_actions`；`moreActions()` 在工作区组插入 `place`；路由表两处 + CLI 面板白名单加 `quick` |
| QA6 验证 | 见 §12.3 |

### 12.2 12 项文案（最终，全部复用既有键）

| # | 项 | 键 | zh_CN |
| --- | --- | --- | --- |
| 1 | 星座连线 | `s0522` | 星座线 |
| 2 | 星座标识 | `s0523` | 星座标签 |
| 3 | 星座图绘 | `s0525` | 星座艺术 |
| 4 | 赤道坐标 | `s0323` | 赤道网格 |
| 5 | 地平坐标 | `s0324` | 方位网格 |
| 6 | 地景 | `s0306` | 地面 |
| 7 | 大气层 | `s0305` | 大气 |
| 8 | 方位基点 | `s0533` | 方位基点 |
| 9 | 深空天体 | `s0320` | 深空天体 |
| 10 | 人造卫星 | `plugin_satellites` | 人造卫星 |
| 11 | 陀螺仪 | `i0060` | 陀螺仪 |
| 12 | 夜间模式 | `s0300` | 夜间模式 |

第 1–6 项与用户清单的措辞差异（星座线 / 星座标签 / 星座艺术、赤道网格 / 方位网格、地面）属仓库既有命名，
按「优先复用仓库既有键」处理；面板内不显示文字，仅长按提示会读到。

### 12.3 实机验证（192.168.3.95:36717 —— 设备换网后的新 IP）

- Dock 中间 = 「快捷开关」+ dashboard 图标；面板 2×6 = 12 图标全部正确（含卫星 / 陀螺仪两枚自研 SVG）。
- 亮 / 灭对比正确：官方 PNG 路（`colorFilter`）与自研 SVG 路（`fillColor`）观感一致。
- 点星云格 → `getState` 回读 `actionShow_Nebulas` false → true；点夜间模式 → `nightMode` true → false（已复原）；
  点卫星格 → 格子点亮，`longClickable` 亦为 true（长按提示已注册）。
- 标题栏位置按钮点按进入「位置」面板；当时标题显示 `GPS ▸`（§12.6 起两处统一为同一字符串，见该节）。
- 「更多功能」顺序：工作区 → 观测工作区 → **位置** → 天体数据与扩展。
- 契约：47 锚点 / 34 面板 / 26 静态 id / 18 动态前缀（已 `--update`）。测试期间改动的开关均已复原。

### 12.4 本片新踩的坑（会重复踩）

1. **`colorFilter` 矩阵值必须归一化到 0.0–1.0**（1.0 = 255，官方 FAQ `faqs-arkui-1353`）：首版填 0–255 被截断，
   「灭」态图标整片发白，只剩格子底色可辨。
2. **`getIcon()` 未命中键会静默回落 `ic_search`**（放大镜）：描述表里误写资源名 `ic_satellite` / `ic_gyro`
   而非映射键 `satellite` / `gyro`，真机上一眼看到两格是放大镜。
3. **`arkts_check` 不查跨文件可见性**：`LayerController.setLayer` 是 private，只有完整 hvigor 构建才报错；
   公开入口是 `applyLayerSwitch`。
4. `scripts/stellarium-cli.mjs` 必须显式 `--bundle <本机调试包名>`（默认是发布身份）。

### 12.5 未纳入本次改动

`node scripts/audit-ohos-resource-coverage.mjs` 已跑过（作为资源校验），但其再生报告同时包含**与本功能无关的既有漂移**
（`stars` 的 rawfile 计数、若干静态入口判定、`src` 体积），故已 `git checkout` 回退该报告文件，避免把无关变化混入本次改动。

### 12.6 验收追加修订（同日第二轮）

用户验收时提出的六点，全部并入同一次提交：

1. **位置面板与快捷面板必须是同一字符串**：改为单一来源 —— 快捷面板标题直接复用宿主 `locationText`
   （引擎轮询在 `handleEngineState` 里按规则持续刷新它），不再各算一份。
2. **`GPS` 需要星球前提**：`quickLocationLabel(source, displayName, planetName)` 仅在「来源 = gps 且观测星球 = 地球」
   时返回 `GPS`；切到火星后自动定位语义不成立，回落位置名。
3. **引擎的星球默认点名称要本地化**：引擎给的是 `Mars surface` 这类英文串（位置面板实测可见），
   在 `LocationPickerStore.surfaceLocationName` 折到既有 `land_mars` / `land_moon` / `land_jupiter` 键 →
   `火星表面` / `月球表面` / `木星表面`。两处最终都显示 `火星表面 · 火星`。
4. **快捷面板高度按内容**：`quickPanelContentHeight()` = 12（面板上内边距）+ 30（PanelHandle）+ 头部
   （有副标题 56 / 无 44）+ 14（头部 margin）+ 两行图标（2 × 单元格 + 10 行距）+ 16（下内边距）；
   单元格宽 =（面板内宽 − 5 × 8 间距）/ 6，由 `QuickActionCell` 的 `layoutWeight(1)` + `aspectRatio(1)` 保证正方。
   同时把该面板 Scroll 内容的下内边距 34 归零，并让 `compactPanelHeight()` 在 `activePanel === 'quick'` 时
   直接返回它 —— 面板定位、面板返回热区、拖拽夹取都跟着一致。
   - **关键机制**：ArkUI 的 `Scroll` 会把「比视口短」的内容**垂直居中**。实测内容 152.3vp、视口 203.3vp、
     内容顶边比视口顶边低 25.5vp（恰好是差值的一半），这也解释了改前图标下方那段空白。
     让容器高度等于内容高度，图标才会贴着标题栏。
    - 修复后实测：`panel-scroll` 高 338px（= 112.7vp ≈ 两行图标 113.3vp），第一行顶边与视口顶边 0 偏移。
    - **后续修正（2026-10-12）**：上面那个「≈」正是隐患 —— 视口 112.7vp 比真实两行 113.3vp 少 0.6vp，
      第二行下沿被 `Scroll` 视口切掉约 2px（真机 Mate 80 Pro 实测内容 350px / 视口 348px，第二行被压成 163px）。
      原因是理论高度没算上「逐项物理像素对齐」：每行 6 格按浮点宽均分后各自对齐（每行最多多占 1px），
      固定 chrome 同理。现 `quickPanelGridCellSize()` 把格子**向上**对齐到整物理像素，
      `quickPanelContentHeight()` 的 `grid` 项再加 4 物理像素取整余量。复核后两行等高 165/165、
      内容 350px < 视口 352px。**结论不变**（容器高度仍等于内容），只是把取整偏差计入了高度。
5. **灭态不画底框**：夜间模式下灭态的浅底框几乎不可辨，改为只有「开」有底色 + 边框；
   边框宽度恒为 1（颜色透明）以免切换时格子尺寸跳动。
6. **方位基点图标**换用官方 `data/gui/bbtLocation-off.png`（真名就是双 b，一枚星形罗盘），仍是 raster + `colorFilter` 路径。

验证：`arkts_check` 0 error、`BUILD SUCCESSFUL`、UI 契约 47 锚点 / 26 静态 id / 34 面板 / 18 动态前缀**不变**
（未增删 id 锚点）；真机实证 —— 地球 + 名称时两处都是 `广州 · 地球`；火星 + GPS 时（修订中间构建）
位置面板已不再显示 `GPS` 而是 `自定义位置 · 火星`，证明星球前提生效；面板高度紧贴两行、灭态无框、
方位基点显示星形罗盘。
说明：最终构建上「火星」分支未再复验（设备当时已切回地球 + 广州），该分支由「同一函数 +
实测确认的引擎串 `Mars surface` + 既有键 `land_mars` = 火星表面」推得。

## 13. 二期：12 格可自定义 + 5 个新按钮（设计，待实施）

### 13.1 需求与已定决策

1. 网格**仍固定 2×6 = 12 格**（用户确认）——自定义**不改变格子数量与格子位置**（位置固定＝肌肉记忆）。
2. 「自定义模式」的语义是**拖动-替换**（用户确认）：进入编辑态后**面板加高、下方露出「当前未列入」的候选图标**，
   把候选**拖动**到某一格上松手即完成替换（被换下的那一项回到候选带）；不增删格子、不改格子位置。
3. 新增 5 个候选按钮：**赤道仪/经纬仪切换**、**左右镜像**、**观测列表入口**、**目镜设置入口**、**极简信息面板模式开关**。
4. 一期体验约束全部沿用：面板内不显示逐项文字（长按 `flashHint`）、ON 态用「灭」图标着色、官方 PNG 走 `colorFilter`、
   自研 SVG 走 `fillColor`、格子 `layoutWeight(1)` + `aspectRatio(1)`。

### 13.2 事实勘查（先于设计，逐条有据）

| # | 事实 | 依据 |
| --- | --- | --- |
| 1 | 「赤道仪/经纬仪」引擎动作 = `actionSwitch_Equatorial_Mount`（bool 性属性 `equatorialMount`） | `src/core/StelMovementMgr.cpp:193` |
| 2 | 「左右/上下镜像」引擎动作 = `actionHorizontal_Flip`（`flipHorz`）/ `actionVertical_Flip`（`flipVert`） | `src/core/StelCore.cpp:402-403` |
| 3 | 桌面版「观测列表」是 `actionShow_ObsList_Window_Global`（Qt 窗口 `ObsListDialog`） | `src/gui/StelGui.cpp:272` |
| 4 | 移动端不跑 Qt GUI，故该 action **不注册**；但应用**已有自己的观测列表面板** `activePanel === 'observing'` | `panels/panels/ObservingPanel.ets`；`common/derive/actions.ets:35`（`more_observe_list` → `observing`） |
| 5 | 目镜面板**已存在** `activePanel === 'oculars'`，`OcularController.setOcularMode` 已接桥 | `panels/panels/OcularsPanel.ets`、`capability/OcularController.ets` |
| 6 | 赤道仪开关**已实现且已持久化**：`TelescopeStore.equatorialMount` ← 启动回写；`LayerController.setLayer` 命中该 action 后 `hooks.persistEquatorialMount()`；现有 UI 在「设置 > 配置」回落面板 | `state/TelescopeStore.ets`、`capability/StartupBridge.ets:172-174`、`capability/LayerController.ets:102`、`panels/panels/ConfigFallbackPanel.ets:154` |
| 7 | 镜像**已接引擎但状态挂在极轴镜**：写入走 `PolarScopeController.setPolarScopeHorizontalFlip/VerticalFlip`（同一个 `setActionChecked`），状态源 `PolarScopeStore.polarScopeHorizontalFlip`，并由引擎 `sessionFlags.horizontalFlip` 回读同步 | `capability/PolarScopeController.ets:105,186-207` |
| 8 | 「极简信息面板模式」**不存在**：全仓无 minimal / hud 类开关；常驻星空 HUD 只有三处，且现仅按「面板打开 / 极轴镜可见」隐藏 | `panels/shell/CompactShell.ets:174,180`、`ExpandedShell.ets:168,172`、`HoverObservatoryShell.ets:27-28,127,133` |
| 9 | 官方 `data/gui` **有** `btEquatorialMount` / `btFlipHorizontal` / `btFlipVertical` / `btObsList` 的 `-off/-on` 对；**没有**目镜与「极简 UI」图标 | `data/gui` 清单（34 组 `bt*-off.png`） |
| 10 | 目镜图标仓库已有：`ShellIcons` 注册 `'oculars'` → `ic_oculars` | `common/ui/ShellIcons.ets:12` |
| 11 | 官方图标池还空着 13 组可用项（`btCompass` / `btEclipticGrid` / `btGalacticGrid` / `btEquatorialJ2000Grid` / `btConstellationBoundaries` / `btAsterismLines` / `btAsterismLabels` / `btPlanets` / `btDSS` / `btHIPS` / `btNebulaeBackground` / `btGotoSelectedObject` / `btFullScreen`）——列为「三期候选」，本次**不进池** | `data/gui` 清单 |
| 12 | 设置持久化通道 = AppStorage `stellariumPrefs`：`StartupBridge` 逐字段回读（已有 `equatorialMount` / `viewCoordinatesVisible` 等 bool 先例），写盘走 `saveAppSettings` | `capability/StartupBridge.ets:168-193` |

### 13.3 结论：5 项里 3 项已存在、1 项需解绑、1 项要新写

| 新增项 | 性质 | 本次工作量 |
| --- | --- | --- |
| N1 赤道仪/经纬仪 | **功能已实现**（状态 + 持久化 + 现有 UI 全在） | 仅**接入**：读 `telescopeStore.equatorialMount`，写 `applyLayerSwitch('actionSwitch_Equatorial_Mount','',v)` |
| N2 左右镜像 | 引擎动作**已接**，但状态被极轴镜语义占用；引擎动作本身是全局的 | **解绑**：状态源提升为全局项（见 §13.6 前注） |
| N3 观测列表 | **面板已存在**（`observing`） | 仅**接入**：`openSubPanel('observing')` |
| N4 目镜设置 | **面板已存在**（`oculars`） | 仅**接入**：`openSubPanel('oculars')` |
| N5 极简信息面板 | **不存在** | **新功能**（§13.7） |

二期的主要风险不是「造功能」，而是**接入点的状态回读一致性**与**自定义项的持久化校验**。

### 13.4 条目模型扩展

```ts
export interface QuickActionItem {
  id: string
  labelKey: string
  icon: string
  kind: string        // 'raster' | 'vector'（一期）
  type: string        // 'toggle' | 'entry'（二期新增）
  actionId: string    // type==='toggle' 且属图层类时使用（一期字段）
  openPanel: string   // type==='entry' 时的目标面板 id（二期新增）
}
```

- `quickActionPool()`（新）= **17 项**候选 = 一期 12 项 + 本次 5 项（N1–N5）。
- `quickActionDefaults()`（新）= 池中前 12 项 = **一期现状**，保证升级后观感与肌肉记忆不变。
- 5 项新增条目的描述（`type` / 动作 / 状态源 / 图标）：

| id | labelKey | icon | kind | type | 动作 / 入口 | 状态源 |
| --- | --- | --- | --- | --- | --- | --- |
| `equatorial_mount` | `quick_mount_mode`（新） | `bt_equatorial_mount` | raster | toggle | `actionSwitch_Equatorial_Mount` | `telescopeStore.equatorialMount` |
| `flip_horizontal` | `quick_flip_horizontal`（新） | `bt_flip_horizontal` | raster | toggle | `actionHorizontal_Flip` | 全局镜像状态（见 §13.6 前注） |
| `observing_list` | `more_observe_list`（复用） | `bt_obs_list` | raster | entry | `openSubPanel('observing')` | —（无开关态） |
| `oculars` | `panel_oculars`（复用） | `oculars` | vector | entry | `openSubPanel('oculars')` | —（无开关态） |
| `minimal_hud` | `quick_minimal_hud`（新） | `bt_minimal_hud` | raster | toggle | 无引擎动作（纯前端） | `overlayStore.minimalHud`（新） |

**`entry` 类的交互约定**：点按 = 跳面板（不切换开关态、不显示 ON 底色）；长按仍出 `flashHint(名称)`。
`QuickActionGrid` 的 `isOn(id)` 对 `entry` 恒返回 false，避免出现「永久点亮」的假开关。

### 13.5 自定义：拖动-替换（用户确认的交互）与持久化

**入口**：`activePanel === 'quick'` 时，标题栏右侧新增一枚「自定义」图标按钮（`ic_edit`）。
标题本身仍是「位置」跳转按钮（一期 §11.4 行为不变）；两者左右并列，互不干扰。

**编辑态布局：面板加高，露出未列入的图标**

- 上面那 2×6 = 12 格**位置完全不动**（用户视线无需重建）；
- **下方新增一条候选带**，把池中「当前未列入」的项铺成 1 行：本次 17 − 12 = **5 项**，故 5 格 + 1 空格（同一套单元格尺寸，`layoutWeight(1)` + `aspectRatio(1)`）；
- 再下面是一行操作条：「恢复默认」+「完成」。
- 高度按内容重算：编辑态 `quickPanelContentHeight()` = 一期高度 + 分隔线 + 候选带（1 行单元格 + 行距）+ 操作条。
  **一期结论照旧适用**（§12.6 第 4 条）：容器高度必须等于内容高度，否则 `Scroll` 会把比视口短的内容垂直居中。
  宿主 `compactPanelHeight()` 的 `activePanel === 'quick'` 分支须按 `quickPanelEditable` 再分两档，面板定位、返回热区、拖拽夹取才会一致。

**拖动-替换（核心交互）**

1. 在候选带里**长按一枚候选并拖动**。门槛是 ArkUI 统一拖拽的固定门槛：长按 ≥500ms + 移动 ≥10vp（系统规定，不可调）。
2. 拖动过程中，手指所在网格格触发 `onDragEnter` → `setResult(DragResult.DROP_ENABLED)` 并加高亮描边，给出「可以放这里」的反馈；移出则 `onDragLeave` 撤掉。
3. 在某一格松手 → `onDrop`：该格换为被拖的候选，**被换下的那一项回到候选带**（等价于两者互换）——语义正好是「未列入的替换已列入的」。
4. 在空白处松手 → `onDragEnd` 无改动，面板保持原样。
5. 可连续换多格，无需退出编辑态。

**机制选择（为什么用统一拖拽，而不是 `PanGesture`）**

- 面板内容在 `Scroll` 里，`PanGesture` 会与面板滚动抢手势；统一拖拽由长按门槛起手，与滚动天然不冲突。
- 拖拽背板系统默认截取组件本身（也可以 `DragItemInfo.pixelMap` 或 `dragPreview` 自定义），无需自绘浮层与手工命中测试。
- 数据传递：`onDragStart` 里以 `unifiedDataChannel.PlainText` 装入条目 `id`，目标格声明 `allowDrop([PLAIN_TEXT])`，`onDrop` 用 `event.getData()` 取回；宿主另留一个 `dragSourceId` 兜底字段。
- 实施时须确认：`.draggable(true)` + `onDragStart` 与目标格 `allowDrop` + `onDrop` 成对到位，否则长按只会走旧的长按提示路径。

**与一期长按提示的冲突（必须处理）**

一期「长按 = `flashHint(名称)`」与拖拽起手是同一个长按。因此：**编辑态内长按让位给拖拽、不再出提示**；非编辑态行为完全不变。
（`QuickActionCell` 增一个 `editable` 入参，长按分支据此二选一。）

**提交与丢弃**

- 进入编辑态时留一份 `quickActionOrder` 快照；编辑中的替换先在内存生效。
  - 「完成」= 提交（写盘一次并退出）；「恢复默认」= 重置为 `quickActionDefaultOrder()`，**只改内存**，仍需「完成」提交。
    - 刻意不做「恢复默认即写盘」：编辑态里返回 / 点面板外是「丢弃」，若恢复默认已经落盘，丢弃就会半途生效，语义自相矛盾。恢复默认只是把待提交内容改成默认序。
- 返回键 / 点面板外 = **丢弃**并复原快照（编辑态需要一个明确的取消路径，避免误改无法挽回）。
- 编辑中途不逐次写盘，减少写盘次数也让「取消」语义干净。

**持久化**

- 键：`stellariumPrefs.quickActionOrder`，类型 `string[]`，**长度恒为 12**，元素为条目 `id`。
  - 写：仅「完成」一处（`quickPersistOrder()` → `saveQuickActionOrderToStorage()`）；「恢复默认」不写（见上）。
  - 落盘通道是 `@ohos.data.preferences`（store `stellarium_quick_panel`，key `order`，JSON 数组），与书签 / 观测列表同套：
    AppStorage 全仓没有 `PersistentStorage` 兜底，是**内存态**，写进 `stellariumSettings` 杀进程即丢（实测重启回默认）。
- 读：`StartupBridge` 回读时**整体校验** —— 长度必须为 12、元素必须都在 `quickActionPool()` 内、且无重复；
  任一不满足则**整串回落 `quickActionDefaults()`**（不做逐项修补，避免出现半新半旧的网格）。
- 旧版本无该键时天然回落默认，无需迁移。

### 13.6 左右镜像的状态源（先解决 N2 的解绑问题）

- 引擎侧 `actionHorizontal_Flip` 是**全局**开关，但应用当前唯一的布尔镜像只存在于极轴镜语境
  （`PolarScopeStore.polarScopeHorizontalFlip`，由引擎 `sessionFlags.horizontalFlip` 回读）。
- **设计决定**：不新增第二份布尔，而是**把 `polarScopeStore.polarScopeHorizontalFlip` 提升为全局镜像状态**
  （它就是引擎那一位的镜像），快捷面板读它、经 `PolarScopeController.setPolarScopeHorizontalFlip()` 写它。
  这样永远只有一份真值，快捷面板与极轴镜叠层的开关天然同步。
- 命名债记录在此：字段名带 `polarScope` 前缀但语义已是全局；若后续有第三个消费方，再统一改名
  （`OverlayStore.horizontalFlip`），本次不动，避免一期已验收的极轴镜路径回归。
- **实施前须确认**：`sessionFlags` 的回读目前挂在 `loadPolarScopeData()` 上。若该请求只在极轴镜可见时发出，
  则需要在常规状态轮询里补一次该字段（或在切换回包后直接以乐观值落地 + 失败回滚，照 `setPolarScopeHorizontalFlip` 现有写法）。

### 13.7 极简信息面板模式（设计；**本轮只落开关接口，隐藏行为延后**）

**本轮范围（用户确认）**：只落**开关接口** —— 候选项 `minimal_hud`、`OverlayStore.minimalHud` 标志位、
`quickActionValues()` 的 ON/OFF 取值、`quickToggle()` 的写入分支（含 `msg_shown` / `msg_hidden` 提示）。
**界面不得有任何消费方**：三个 shell 的 HUD 隐藏条件本轮**一行都不改**（已用 `git diff` 复核三文件与 HEAD 逐字节一致），
也**不落盘**（没有消费方时持久化只会误导；`quickToggle` 的 `minimal_hud` 分支刻意不调 `saveAppSettings()`）。
下面「语义 / 隐藏对象 / 实现 / 状态与持久化」四段是**设计**，留待后续实现。

**语义（待实现）**：ON = 隐藏常驻星空 HUD，只留星空 + Dock；OFF（默认）= 一期现状。

**隐藏对象（三处，全部是既有实现，逐条有据）**：

| # | 元素 | 现条件 | 依据 |
| --- | --- | --- | --- |
| 1 | 时钟层 `DockClockLayer` | `!panelVisible && !polarScopeVisible && clockText.length > 0` | `CompactShell.ets:174`、`ExpandedShell.ets:168` |
| 2 | 视场角层（`fovText`） | `!panelVisible && !polarScopeVisible && fovText.indexOf('°') >= 0` | `CompactShell.ets:180`、`ExpandedShell.ets:172` |
| 3 | 悬停观测台读数 | 常驻渲染 | `HoverObservatoryShell.ets:127,133`（`observationTimeText` / `currentFovText`） |

**实现（待做）**：三处条件各追加 `&& !this.minimalHud`；`HoverObservatoryShell` 增 `@Prop minimalHud: boolean`。
宿主 3 个 shell 调用点各透传一次 `this.overlayStore.minimalHud`（宿主已在这三处传 `fovText` 等，接线是同一批）。

**状态与持久化（本轮已做一半）**：`state/OverlayStore.ets` 增 `minimalHud: boolean = false` ✅ 已落
（与 `viewCoordinatesVisible` 同类设置字段）；`StartupBridge` 回读 + `saveAppSettings` 写盘 ⏳ **待实现**
（须与上面的消费方同批做，否则「开关能存住但毫无作用」是更差的语义）。

**明确不影响**（避免误伤一期的成果）：

- 面板打开时的 HUD（`panelVisible` 分支照旧）；
- 极轴镜叠层与其自身的翻转开关；
- 「视场中心坐标」叠层（它有自己的 `viewCoordinatesVisible`，与本开关互不牵连）；
- Dock 与快捷面板本身；时钟层消失后仍可从 Dock「时间」进时间面板（该层只是快捷入口，不是唯一入口）。

**命名**：面板内不显示文字，长按提示用新增键 `quick_minimal_hud`（zh_CN「极简信息面板」）。

### 13.8 图标清单

| 用途 | 资源 | 来源 | 路径 |
| --- | --- | --- | --- |
| 赤道仪/经纬仪 | `bt_equatorial_mount.png` | 拷官方 `data/gui/btEquatorialMount-off.png` | raster + `colorFilter` |
| 左右镜像 | `bt_flip_horizontal.png` | 拷官方 `data/gui/btFlipHorizontal-off.png` | raster + `colorFilter` |
| 观测列表 | `bt_obs_list.png` | 拷官方 `data/gui/btObsList-off.png` | raster + `colorFilter` |
| 目镜设置 | `oculars`（既有键） | `ShellIcons` 已注册 → `ic_oculars` | vector + `fillColor` |
| 极简信息面板 | `bt_minimal_hud` | 拷官方 **`data/gui/tabPC.png`**（= 指针坐标页签的**未选中**态，用户指定） | raster + `colorFilter` |
| 自定义入口 | `edit` | **新增自研** `ic_edit.svg` —— Material **`edit`**（铅笔）；仓库既有 `ic_*.svg` 里没有铅笔类图标可复用 | vector + `fillColor` |

- **极简信息面板的图标换过一次**（用户两次反馈）：初版自研 `visibility_off`（眼睛带斜杠）与**夜间模式**撞脸 —— 官方 `bt_night_view` 本身就是眼睛造型；用户随后指定官方 `tabPC` 未选中态。取 `tabPC.png` 而非 `tabPC-selected.png`，与一期「取暗态、由 `colorFilter` 着色」同一约定。
- **遗留提醒**：`tabPC` 是「指针坐标」页签的图标，本仓库该插件面板（`OverlayStore.pointerCoordinates*`）已在应用内。若将来把「指针坐标」也放进候选项池，两者图标会撞脸，届时需给其中之一另选图标。
- 4 枚官方 PNG 合计约 44 KB（单个 2–12 KB），走一期同一条 `colorFilter` 路径，`TINT_ON` / `TINT_OFF` 常量不变。

### 13.9 文案键清单

| 用途 | 键 | 处理 |
| --- | --- | --- |
| 赤道仪/经纬仪（长按名称） | `quick_mount_mode` | **新增**（zh_CN「赤道仪 / 经纬仪」）。状态提示可复用既有 `i0008` 赤道坐标 / `i0009` 地平坐标 |
| 左右镜像 | `quick_flip_horizontal` | **新增**（zh_CN「左右镜像」）。**不复用** `polar_scope_flip_horizontal`——那是极轴镜限定措辞 |
| 观测列表 | `more_observe_list` | 复用（zh_CN「观测列表」） |
| 目镜设置 | `panel_oculars` | 复用（zh_CN「目镜模拟」） |
| 极简信息面板 | `quick_minimal_hud` | **新增**（zh_CN「极简信息面板」） |
| 自定义模式 | `quick_customize` / `quick_customize_hint` / `quick_customize_default` / `quick_customize_done` | **新增 4 键**（进入编辑 / 「长按候选拖到格子上替换」提示 / 恢复默认 / 完成） |

新增键一律按仓库既有 10 语言格式补全（`en` / `zh_CN` / `zh_HK` / `zh_TW` / `ja` / `ko` / `fr` / `de` / `es` / `ru`）。

### 13.10 切片清单（实施）

- **QA7 图标与注册**：拷 3 枚官方 PNG → `resources/base/media/bt_*.png`；新增 `ic_minimal_hud.svg`（与 `ic_edit.svg`，若仓库无铅笔图标）；`ShellIcons` 注册 `minimal_hud` / `edit`；跑 `audit-ohos-resource-coverage`。
- **QA8 池与文案**：`common/derive/quickActions.ets` 增 `type` / `openPanel` 字段、`quickActionPool()`（17 项）、`quickActionDefaults()`（12 项）；补 §13.9 新增 7 个文案键。
- **QA9 宿主分发**：`quickActionValues()` 增 `equatorial_mount` / `flip_horizontal` / `minimal_hud` 三个取值分支；`quickToggle()` 增对应分支 + `type === 'entry'` 分支走 `openSubPanel(item.openPanel)`；`QuickActionGrid.isOn()` 对 `entry` 恒 false。
- **QA10 自定义模式（拖动-替换）**：候选带 = `quickActionPool()` 的「未列入」子集；`QuickActionCell` 增 `editable` / `candidate`；候选格 `.draggable(true)` + `onDragStart`，槽位格 `onDragEnter/Leave`（内置高亮底框）+ `onDrop`（互换并把被换下项回填候选带）；
  被拖条目 id 用宿主字段 `quickDragSourceId` 传递（**不用** `setData`/`allowDrop`，理由见 §13.10.1）；`QuickPanel` 增编辑态布局与操作条；宿主增 `quickActionOrder` @State + 快照 / 提交 / 丢弃；
  `quickPanelContentHeight()` / `compactPanelHeight()` 按 `quickPanelEditable` 分两档。
- **QA11 极简模式（本轮只落开关接口）**：`OverlayStore.minimalHud`（已落）、候选项 `minimal_hud`、`quickActionValues()` 取值、`quickToggle('minimal_hud')` 写入分支（已落）。
  **不做**：三个 shell 的隐藏条件与 `@Prop`、宿主 3 处透传、`StartupBridge` 回读 + 写盘 —— 全部留待后续「消费方」那一批一起做。
- **QA12 验证与提交**：`arkts_check` → 构建 → `check-ohos-ui-contract`（新增锚点/静态 id 须 `--update`）→ 资源审计 → 真机走查（§13.11）→ CHANGELOG → commit。

**UI 锚点（实施结果：零新增，未动契约）**：编辑入口复用 `PanelHeader` 既有的 `panel-header-action`（只把内容换成图标），候选格复用 `quick-action-<id>`（候选与槽位互斥，不会重名），操作条不挂锚点。
实际仍是 **34 面板 / 26 静态 id / 18 动态前缀 / 47 锚点**，无需 `--update`。
> 一次踩坑记录：把 `.id('quick-action-' + this.item.id)` 写成三元表达式后契约脚本直接报「dynamic prefix removed」——该脚本按**字面量**扫描 `.id('前缀' +`，锚点写法不能变换形态，否则语义没丢也会被拦。

### 13.10.1 实施结果（QA7–QA12）与真机才暴露的三个拖拽坑

QA7–QA12 全部完成。其中三个问题是**只有真机才暴露**的（`arkts_check` 与构建全绿，自动化拖拽也复现不出），逐条记下来免得重踩：

1. **组件文件放错目录**：新 `QuickPanel` 写到了 `panels/quick/QuickPanel.ets`，而宿主导入的是 `panels/panels/QuickPanel.ets`
   → 构建报「props 不可赋值」（解析到老组件）。教训：改组件前先确认宿主 import 的实际路径。
2. **拖拽源被格子内的 `Image` 抢走**：`Image` 属 ArkUI 默认可拖组件，触摸命中它（且它自身 `draggable=false`）时系统判
   `frameNode draggable is 0` → `Drag gesture has been canceled`，松手退化成点击（日志里能看到误触发了别的开关）。
   修法：内层容器 `.hitTestBehavior(HitTestMode.None)` + 两路图标都 `.draggable(false)`，把拖拽权交回 `Button`。
3. **编辑态的长按手势掐掉系统拖拽**：系统统一拖拽在触摸场景靠「长按约 500ms」起手，而格子上注册的
   `LongPressGesture` 会在 600ms 赢下手势竞技场 —— 表现就是「按住能按、松手不替换」。
   修法：编辑态把该手势 `duration` 拉到 600000（永不触发），让出竞技场。
4. **应用内拖放不要加 `allowDrop`/`setData`**：按 ArkUI 官方 FAQ（`faqs-arkui-1173`「图标垃圾桶」）的写法
   「拖出方 `.draggable(true)` + `.onDragStart`，接收方 `.onDrop`」即可；加了 `allowDrop([PLAIN_TEXT])` 后系统反而判
   `target data is not allowed to fall into` 而拒收（AceDrag 日志）。被拖 id 用宿主字段传递最简单。
5. **落盘必须走 `@ohos.data.preferences`**：全仓没有 `PersistentStorage`，`AppStorage` 是内存态，
   写进 `stellariumSettings` 杀进程即丢（实测重启回默认）。已改用 store `stellarium_quick_panel` / key `order`。
6. **标题栏动作按钮的语义与尺寸**（用户追加要求）：自定义 = 铅笔图标（`ic_edit.svg`），完成 = 勾图标（新增 `ic_check.svg`），
   **不出文字**；`PanelHeader` 增 `headerActionIcon`（非空即渲染图标），文案仅留作 `accessibilityText`。
   尺寸与右侧关闭按钮**一致**（36×36 / 18px 图标），两个圆形按钮视觉齐平。
7. **编辑逻辑的归属**（用户追加要求）：顺序、编辑态、拖动-替换、提交 / 丢弃 / 恢复默认原本散在宿主的十来个 `quickXxx` 私有方法里，
   不符合封装原则；已整体收进 **`QuickPanelStore`**（`@Observed`，与面板同文件 `panels/panels/QuickPanel.ets`）。
   宿主只剩三件事：持有实例（1 个 `@State` 字段）、注入 `saveOrder` / `hint` hooks、传值 —— 净删 63 行编辑逻辑。
   与 `state/*Store.ets` 同规矩：store 不 import NAPI / UI，落盘与提示一律经 hooks 注入。
8. **行尾统一 CRLF**（用户追加要求）：仓库行尾原本混用（本片改动的 4 个 `.ets` 与计划文档原为 LF，其余为 CRLF），
   本轮把改动到的 12 个文件全部统一为 CRLF（`lone LF = 0`）。

### 13.11 验证口径

1. 静态：`arkts_check` 0 error；`devecocli build` SUCCESSFUL。
2. 契约：`check-ohos-ui-contract.mjs` intact（新增锚点须 `--update` 并说明）。
3. 资源：`audit-ohos-resource-coverage.mjs` 通过（新增 3 枚 media 计入）。
4. 真机（`--bundle <本机调试包名>`，勿用默认发布包名）：
   - **默认网格不变**：升级后首次打开仍是 `quickActionDefaults()` 的 12 项，顺序与一期逐项一致；
   - **N1**：点赤道仪格 → `getState` 回读 `actionSwitch_Equatorial_Mount` 翻转；杀进程重启后保持；
   - **N2**：点镜像格 → 星空左右镜像；打开极轴镜叠层，其「水平翻转」开关与快捷面板**同步为同一状态**；
   - **N3/N4**：点观测列表格 / 目镜格 → 分别进入 `observing` / `oculars` 面板，且格子**不点亮**；
   - **N5（本轮口径：只验开关接口）**：点极简信息面板格 → 图标 ON/OFF 切换、出「已显示 / 已隐藏」提示；**星空 HUD 必须毫无变化**（时钟层与视场角层照常显示），重启后**回落 OFF**（本轮刻意不落盘）；待隐藏行为那一批落地后，本项再改为验「三处常驻 HUD 隐藏 / 恢复 + 重启保持」；
   - **自定义（拖动-替换）**：点「自定义」→ 面板加高、候选带露出 5 项、**12 格位置不动**；长按候选拖到某格 → 拖拽中被悬停格高亮，松手完成互换、被换下项出现在候选带；拖到空白处松手 → 面板无变化；编辑态长按**不再**出 `flashHint`；
     「完成」后重启保持；返回键退出 → 改动丢弃并复原；「恢复默认」回到一期 12 项；手工把 `quickActionOrder` 改成非法串（长度错 / 含未知 id / 有重复，三种各测一次），重启均回落默认且不崩；
   - **编辑态高度**：`ui layout` 复核图标第一行顶边与视口顶边偏移为 0（编辑态同样不能被 `Scroll` 居中）；
   - 逐项长按出 `flashHint` 且文案正确。
5. `eol`：新增 `.ets` 与文档一律 CRLF；`write` 工具产物须归一回 CRLF。

### 13.12 风险与对策

| 风险 | 对策 |
| --- | --- |
| N2 的镜像状态回读挂在 `loadPolarScopeData()`，极轴镜不可见时可能不回读 | 实施时优先确认该路径；必要时切换回包后乐观落地 + 失败回滚（照现有写法），或把该字段并入常规轮询 |
| `TelescopeStore.equatorialMount` 是「设置 > 配置」既有 UI 的状态，快捷面板再写一份可能两处不一致 | 单一真值：快捷面板只读 store、只经 `applyLayerSwitch` 写；`setLayer` 回包后已 `refreshState()`，两处自然同步 |
| 自定义后用户把「夜间模式」等一期项换掉，导致一期验收口径失效 | 这是用户意图内的行为；「恢复默认」随时可回，且默认值即一期 12 项 |
| `quickActionOrder` 长度/内容非法导致网格半空或崩溃 | 回读整体校验 + 整串回落默认（§13.5），不做逐项修补 |
| 极简模式下时钟层消失，用户找不到时间面板 | Dock「时间」入口不受影响；此为「极简」的预期语义，无回归 |
| 「观测列表 / 目镜」用官方 `btObsList` ，而目镜用自研 SVG，观感可能不齐 | 目镜无需官方图标（官方也没有）；沿用一期「卫星 / 陀螺仪用自研 SVG」的既有先例，两路着色的观感已在一期验收过 |
| 统一拖拽的手势门槛固定为长按 ≥500ms，编辑态「按住候选」到「拖起」有半秒延迟，用户可能误以为没反应 | 操作条常驻 `quick_customize_hint`（「长按候选图标拖到格子上替换」）；候选格可加轻微呼吸描边示意可拖 |
| 拖拽与面板 `Scroll` 抢手势 | 用统一拖拽（长按起手）而非 `PanGesture`；QA10 真机专项走查面板滚动仍正常 |
| 编辑态高度算错 → `Scroll` 把内容垂直居中（一期 §12.6 第 4 条已踩过） | 按 §13.5 公式重算，`compactPanelHeight()` 按 `quickPanelEditable` 分档；真机 `ui layout` 复核顶边偏移为 0 |
| `draggable` 未置真或目标格未声明 `allowDrop` → 长按仍走一期提示、根本拖不起来 | QA10 完成后先做「拖不起来」专项走查（§13.11 自定义项第一条），再往下验收 |



