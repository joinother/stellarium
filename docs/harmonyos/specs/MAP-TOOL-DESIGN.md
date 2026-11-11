# 鸿蒙版地图工具设计方案

> 状态：设计提案（2026-11-10）
> 依据：DevEco 本地官方文档（`devecocli docs`）与 `sdk/default/hms/ets/api/@hms.core.map.*.d.ts`
> 关系：本方案扩展并取代 `MAP-KIT-INTEGRATION-PLAN.md` 中“暂不接入在线地点搜索”的旧边界；旧文档保留为历史记录。

## 1. 目标

为位置面板提供一套**在线优先、离线可用、直接选点永不失效**的地图工具：

1. **位置面板（小地图）**：显示当前地点在全球/对应星球上的位置；优先 3D 地球/星球；点击进入全屏地图。
2. **全屏地图**：在线时可搜索地址/POI 并选点；离线时至少可用本地城市/任务地点列表定位；无论在线离线，地图直接布点始终可用。
3. **地球**：在线优先使用花瓣底图与地点搜索；离线按“花瓣离线包 → 自有单瓦片 → ArkUI 自绘”顺序回退。
4. **其他星球**：使用对应星球底图作为全球单瓦片；关闭花瓣在线搜索；保留本地任务地点列表与直接选点。
5. **数据**：以 Stellarium `data/base_locations.txt` 为唯一地点来源；不新增外部地点库。

非目标：

- 不承诺花瓣地图的离线地址/POI 搜索（SDK 没有该能力）。
- 不实现花瓣离线瓦片的程序化下载/读取（SDK 只提供管理页跳转与缺口查询）。
- 不替换星空文化研究地图；文化地图仍走本地资料与独立语义。

## 2. 已确认的能力边界

| 能力 | 在线 | 离线 | 结论 |
|---|---|---|---|
| 花瓣底图 | ✅ `MapComponent` | ⚠️ API 20+，需花瓣地图 App 已下载全球基础包/城市包 | 离线包由用户管理，应用不可下载 |
| 花瓣 3D 地球 | ✅ `sphereEnabled`，zoom <4 清晰 | ⚠️ 取决于离线包与 SDK 初始化 | 需真机验证 |
| 花瓣地形图 | ✅ `MapType.TERRAIN`，约 zoom 5–14 | ⚠️ 同上 | 全球视图仍是标准图/球体 |
| 卫星/混合图 | ✅ 仅中国 | — | 不作为全球底图 |
| 花瓣 POI/地址搜索 | ✅ `site.searchByText` / `queryAutoComplete` / `geocode` | ❌ 无离线接口 | 离线只能本地城市/任务列表 |
| 花瓣离线管理 | — | ✅ `petalMaps.openMapOfflineDataManagement` 拉起管理页 | 不返回下载结果 |
| 离线缺口查询 | — | ✅ `offlineMapData.getRecommendedCityIdsByLatLngs` | 只返回未下载区域 ID |
| 自定义球面纹理 | ✅ | ✅ `MapType.NONE` + `setSphereMapEnabled({ coverageImage })` | 真机已验证：球体表面可替换 |
| 自定义瓦片 | ✅ | ⚠️ `TileOverlayOptions.tileProvider` | 2D/瓦片场景可用；当前不覆盖 3D 球体 |

关键限制：

- 2D Web Mercator 无法显示 ±85.05° 以外区域；月球有 Chandrayaan-1（89.76S）、Lunar Prospector（87.7S）等极区地点，**不能**用 2D Mercator 作为月球唯一底图。
- `sphereEnabled` 的 3D 地球在 zoom <4 最清晰；zoom ≥4 的行为需验证。
- `coverageImage` 是当前可用的球体表面纹理入口；`ImageOverlay`/`TileOverlay` 不覆盖 3D 球体。
- `MapType.NONE` 只是“空底图”，不代表 Map Kit 无网可初始化；必须做飞行模式全新安装测试。

## 3. 总体架构

```
LocationMapStore（@Observed）
├─ MapSurfaceController
│  ├─ OnlinePetalSurface       MapComponent + TERRAIN/STANDARD + 3D globe
│  ├─ OfflinePetalSurface      MapComponent + 花瓣离线包
│  ├─ CustomGlobeSurface       MapType.NONE + coverageImage
│  └─ FallbackRasterSurface    ArkUI Image/Canvas 等距圆柱图
├─ SearchProvider
│  ├─ PetalSiteSearch          site.searchByText / queryAutoComplete / geocode
│  ├─ LocalLocationSearch      本地 hierarchy（地球/月球/行星任务）
│  └─ DisabledSearch           非地球或离线无数据
├─ CoordinateService
│  ├─ GCJ02 ↔ WGS84
│  ├─ 行星经度归一化/方向约定
│  └─ 屏幕 ↔ 经纬度（Map Kit 投影或等距圆柱数学）
└─ LocationCatalog
   ├─ Earth hierarchy
   └─ Non-Earth locations（Moon/Mars/Venus/Titan/Bennu）
```

### 3.1 地图表面优先级

1. **在线花瓣**：`MapComponent` + `TERRAIN`/`STANDARD`，地球用 3D 球体，搜索可用。
2. **离线花瓣包**：同一个 `MapComponent`，无网自动使用已下载包；搜索降级本地。
3. **自球星面**：`MapType.NONE` + `setSphereMapEnabled({ coverageImage })`，复用 Map Kit 相机/手势/点选；搜索降级本地。
4. **ArkUI 自绘**：`Image`/`Canvas` 等距圆柱图；保证无网、无 Map Kit 初始化也能直接选点。

启动时先显示第 4 层作为占位，同时异步尝试第 1/2 层；成功后淡入。任何失败都保留占位，不出现空白。

### 3.2 状态机

```
idle
 → fallbackPreview（显示自有底图）
 → petalLoading（创建 MapComponent，15s 超时）
    → petalReady（mapLoad 成功）
       → 在线：PetalSiteSearch + mapClick
       → 离线包：LocalSearch + mapClick
    → petalFailed（error/timeout）
       → customGlobe（MapType.NONE + coverageImage）
       → fallbackPreview（ArkUI 自绘）
```

搜索与选点解耦：`searchMode` 可以是 `petal | local | disabled`；`pickMode` 始终为 `mapClick | imageClick`。

## 4. 地图表面设计

### 4.1 OnlinePetalSurface（地球在线）

- `MapComponent` 初始化：
  - `mapType: STANDARD`（全球视图）
  - `sphereEnabled: true`（面板 globe，zoom 2）
  - `minZoom: 2`，`maxZoom: 20`
  - 面板内禁用旋转/倾斜、关闭我的位置按钮；全屏开启。
- 相机移动到当前观测点；`Marker` 标记当前位置。
- 监听 `mapLoad`、`error`、`mapClick`。
- 在线搜索：`site.searchByText` / `queryAutoComplete` / `geocode`；结果为 WGS84 前先做 GCJ02/WGS84 纠偏。
- 全屏 zoom 5–14 可切换 `TERRAIN`；全球视图/球体用 `STANDARD`。

### 4.2 OfflinePetalSurface（地球离线包）

- 与在线相同的 `MapComponent`；无网时自动使用花瓣地图 App 已下载数据。
- 不调用 `site` 搜索；搜索栏降级 `LocalLocationSearch`。
- 直接 `mapClick` 选点；如果用户未下载当前区域，回退到 `CustomOverlaySurface`。
- 可增加“下载离线地图”入口：`offlineMapData.getRecommendedCityIdsByLatLngs` + `petalMaps.openMapOfflineDataManagement({ scenarios: 'PHONE', recommendedRegionIds })`。

### 4.3 CustomOverlaySurface（自有单瓦片）

用于离线无花瓣包，或非地球底图。

```ts
mapOptions = {
  mapType: mapCommon.MapType.NONE,
  position: { target: { latitude, longitude }, zoom: 2 },
  minZoom: 2,
  maxZoom: 20,
  sphereEnabled: true
}
```

```ts
const source = image.createImageSource(rawfileBytes)
const pixelMap = await source.createPixelMap()
await controller.setSphereMapEnabled(true, {
  sunLightEnabled: false,
  cityLightEnabled: false,
  animateDuration: 0,
  coverageImage: pixelMap
})
```

**已验证（真机）：** `MapType.NONE + sphereEnabled + setSphereMapEnabled({ coverageImage })`
会把 `coverageImage` 作为球体表面纹理渲染，同时保留 Map Kit 的相机、手势、
`mapClick`、Marker 与投影。`backgroundImage` 是球体背后的空间背景，不能用于替换星球表面。
`ImageOverlay` 与 `TileOverlay` 在当前设备上不覆盖 3D 球体，不要再用于此场景。

底图选择：

| 天体 | 首选 | 备选 |
|---|---|---|
| Earth（在线） | 花瓣在线标准地图（`MapType.STANDARD`） | 本地地球球体（`earth_cmap.png` + `MapType.NONE`） |
| Earth（离线） | 本地地球球体（`earth_cmap.png`，Moon 同路径） | 错误态 + 重试（无 raster 兜底） |
| Moon | `stellarium/textures/moon_4k.jpg`（4096×2048） | `moon.png` 1024×512 |
| Mars | `stellarium/textures/mars.png`（512×256） | — |
| Venus/Mercury/Jupiter/Saturn/Uranus/Neptune | `textures/<tex_map>.png` 512×256 | — |
| Titan/Bennu | 无专用图时用占位 | 不加入地图选择器，或仅列表 |

`textures/obs_*.jpg` 是**观测示意图**（星球 + 卫星轨道 + 黑色背景），不是等距圆柱表面图，不能用作球体贴图或 2D 底图。

注意：

- 5400×2700 纹理在 GPU 上约 58MB（RGBA）；面板用 2048×1024，全屏用 4096×2048 降采样版本，避免内存峰值。
- `coverageImage` 是整张球面纹理，没有 LOD；全屏高缩放会像素化，后续可按缩放分级加载不同尺寸纹理。
- Map Kit 在 zoom ≥4 会切到 2D Mercator；此时 `coverageImage` 只画球体，必须由 `cameraIdle` 监听追加/移除 **Web Mercator 预扭曲**的 `ImageOverlay`，否则 2D 底图会显示绿色空背景且与球体位置不一致。当前已实现：≥4 加 Mercator `ImageOverlay`，<4 移除并回到球体；9 张 `<name>_mercator.jpg` 由 `scripts/build-ohos-mercator-textures.mjs` **在资源同步时从 PC 原图生成**（Earth/Moon/Mars 1024²，其余 512²），不再提交 `map_mercator/` 资源目录；未知天体不再回退 Earth 的 `worldmap.jpg`；同时只对 Earth/Moon/Mars/Venus/Mercury/Jupiter/Saturn/Uranus/Neptune 开放 2D，Eris 等小天体固定 maxZoom=3 的 3D 全球视图，完全移除其 2D 效果；`* Observer` 全览点为固定点位，直接隐藏位置编辑器和全屏选点入口。
- 2D Mercator 不能显示极区；月球/行星在 <4 使用 3D 球体，极区地点仍可见；≥4 的极区需要缩回 3D 球体后选取，不再用 raster 保底。

### 4.4 错误态（无 raster 兜底）

- 全屏地图只使用 Map Kit：在线 Earth 用花瓣底图，离线 Earth 与非地球用 `coverageImage` 球体。
- 隐私/前台门禁、纹理缺失、Map Kit 初始化失败、15s 超时或运行时缺少 `setSphereMapEnabled` 时，显示可重试的错误卡片（标题、原因、提示、重试按钮），不切换到等距圆柱 raster。
- 错误原因按 I18n key 区分：`map_unavailable_privacy`、`map_unavailable_texture`、`map_unavailable_sdk`、`map_unavailable_timeout`、`map_unavailable_hint`。
- `setSphereMapEnabled` 是 Map Kit 26.0.0 的 API；必须用 `typeof controller.setSphereMapEnabled === 'function'` 在运行时判断，因为模拟器镜像可能仍安装旧版 `com.huawei.hms.mapservice`。

### 4.5 全屏地图交互（2026-11-11）

- 面板不再渲染“离线坐标 / 华为地图”切换；全屏入口改为面板地图预览右上角的展开按钮。`locationMapProvider` 状态与 CLI 保留兼容，但不再驱动面板 UI。
- 全屏地图保持 Map Kit 全屏挂载，手机使用顶部栏 + 浮动搜索 + 底部操作卡，平板（`expandedLayout`）使用左侧 320–360vp 侧栏；安全区取 `stellariumScreenSafeTopPixels/BottomPixels`，并至少保留 24vp 顶部/底部设计边距，再用 `MapComponentController.setPadding` 让相机中心避开搜索栏、操作卡和侧栏。搜索结果用可滚动列表。
- 进入即显示当前选点：`mapLoad` 后把 WGS84 draft 转成地图坐标系（在线 Earth 为 GCJ02），落 Marker、移动相机。点击/搜索更新的 Marker 也必须使用地图坐标系，不能直接使用 WGS84 draft。
- **Earth 离线**：用与 Moon 相同的 `MapType.NONE + sphereEnabled + setSphereMapEnabled({ coverageImage: earth_cmap.png })`，保留 Map Kit 相机/手势/`mapClick`/Marker；此时坐标就是 WGS84，不做 GCJ02 纠偏。`GET_NETWORK_INFO`（仅判断联网，不发数据）决定在线 Petal 还是本地地球；Map Kit `error` 或 15s 超时也会切到本地地球。本地地球在 zoom ≥4 使用 `earth_cmap_mercator.jpg` 作为 2D 覆盖图。
- **无 raster 兜底**：球体纹理或 Map Kit 不可用时显示可重试错误卡片；`setSphereMapEnabled` 缺失（旧版 HMS 地图服务）单独提示 `map_unavailable_sdk`，不再展示 2D 平面地球。
- 搜索框对所有天体常驻：Earth 并行 Petal 与离线搜索，结果分“在线结果 / 离线地点”；非地球仅离线搜索，按当前 `observerPlanet` 过滤。选中结果后落点并放大。
- 底部主按钮文案为“选此点”；回传 `latitude/longitude/altitude/name/source` 后**立即应用到当前观测点**并关闭全屏（不再需要在位置面板再按一次“应用”）；面板的“应用”按钮保留给手动输入/层级选点。
- **右下侧栏（2026-11-12）**：移除右侧 `+ / − / 回中` 竖排控件，改为右下角竖排三个 40×40 小按钮：“查看当前选点”（两段式回中/放大到 zoom 15）、“GPS 定位”（仅地球）、“地图图层”（仅在线地球）。操作卡保持四个 `UI_RADIUS_CONTROL` 圆角。
- **GPS 蓝点**：经 `LocationPort` 申请精确位置并单次定位；成功后 `setMyLocationStyle({ displayType: TRACK_ROTATE })` + `setMyLocationEnabled(true)`，蓝色定位点随设备方向旋转，不自动移动相机；关闭 Map Kit 自带右下角定位图标。监听 `myLocationClick`，点击蓝点即把当前位置设为草稿点；草稿图钉从红色切换为蓝色（`ic_map_pin_blue.svg`），地图/搜索选点仍用红色图钉。
- **地图类型**：图层按钮展开“地形地图 / 卫星地图”，调用 `setMapType(MapType.TERRAIN|SATELLITE)`；地形层仅在 5<zoom<14 可见，选择地形时 zoom≤5 会移到 6。离线地球和非地球不提供该按钮。
- **海拔来源**：Map Kit 点击不带垂直分量。在线地球先 `site.reverseGeocode` 取 locality/adminLevel2，再查离线城市海拔；失败或离线时用最近离线地点（上限约 150 km）。来源标记为 `GPS / 城市离线 / 离线地点 / 海拔未知`；底部操作卡把经纬度、海拔、来源放在同一行。非地球一律 0，除非离线地点数据自带数值。
- **全览点**：`PlacePanel` 保留 `obs_*.jpg` 概览图，仅禁用所有拾取交互；全屏地图不挂载。
- **标题栏**：返回键为独立 44×44 圆形玻璃按钮；标题为独立 44vp 长药丸，主标题天体名、副标题底图来源，与搜索栏同圆角/底衬。
- 现在共生成 **9** 张 Mercator 底图：Earth/Moon/Mars 1024²，其余 512²。

## 5. 搜索设计

### 5.1 在线（地球）

- `site.searchByText`：关键字/地理范围。
- `site.queryAutoComplete`：输入建议。
- `site.geocode`：地址 → 经纬度。
- 结果转换成统一 `MapSearchResult { name, address, lat, lon, source: 'petal' }`。
- 坐标纠偏后再写入草稿；不直接提交观测位置。

### 5.2 离线（地球/月球/行星）

- 复用现有 `LocationStore` 的本地搜索：按 `observerPlanet` 过滤，8,116 条地球地点 + 新增非地球任务地点。
- 地球离线只到城市级，不承诺街道/POI。
- 月球/火星/金星提供本地任务地点列表；是否保留本地搜索按产品决定。
- 非地球关闭 `site` 搜索；保留层级列表。

### 5.3 UI

- 一个搜索框，显示当前搜索源：`在线` / `本地` / `该星球不支持在线搜索`。
- 无结果时明确提示“离线仅支持本地城市/任务地点”。
- 在线失败自动降级本地，不阻塞选点。

## 6. 数据模型与迁移

### 6.1 当前缺口

`data/base_locations.txt` 是桌面版 `StelLocationMgr` 的地点来源。当前 ArkUI 层级：

| 天体 | 源数据 | 当前 hierarchy | 缺失 |
|---|---:|---:|---:|
| Moon | 63 | 37 | 26 |
| Mars | 16 | 0 | 16 |
| Venus | 14 | 0 | 14 |
| Titan | 1 | 0 | 1 |
| Bennu | 1 | 0 | 1 |

缺失的 26 条 Moon 全部是 `p=0`，包括 Chang'e 1/3/4/5、Yutu、Yutu-2、Longjiang-2、Chandrayaan-1/2/3、SLIM 等。

### 6.2 迁移步骤

1. 扩展 `scripts/generate-ohos-location-hierarchy.mjs`：
   - 遍历 `base_locations.txt` 中 `planet != Earth` 的行；
   - 按 `(planet, name, lat, lon)` 去重合并；
   - 经度归一化到 `[-180,180]`（如 `Viking 2 225.737W`、`Opportunity 354.4734E`、`Venera 7 351E`）；
   - `province` 保留任务所属方（USA/USSR/China/...），`country='ZZ'`，`planet` 写对应天体。
2. `names_zh.ts`：
   - 在 `generate-ohos-location-zh.mjs` 的 `manualNames` 中补齐非地球任务中文名；
   - 不得让新条目落入 `未收录地点`；
   - 建议人工复核嫦娥/玉兔/龙江/月船/SLIM 等任务名。
3. 任务所属方翻译：
   - USA→美国，USSR→苏联，Russia→俄罗斯，China→中国，Japan→日本，India→印度，Israel→以色列，Europe→欧洲，EU→欧盟。
4. UI：
   - 现有 `LocationPickerPanel` 按 `observerPlanet` 过滤，数据加入后自动出现；
   - Moon 可先保持一个“月面任务地点”分组，63 条；后续按所属方拆分；
   - 结果上下文显示“所属方 · 月球表面地点”。
5. 测试：
   - `verify-ohos-location-search` 的总数从 8,116 更新为 8,174（全部非地球）或 8,142（仅 Moon）；
   - 增加嫦娥四号、玉兔二号、Apollo 11、Chandrayaan-1 极区用例；
   - 真机验证 Moon 列表、搜索、坐标写入。

## 7. UI/UX

### 7.1 位置面板（小地图）

- 顶部：当前地点、坐标、海拔、观测星球选择。
- 小地图：3D 地球/星球，或静态全球图 + 当前地点 Marker。
- 状态徽标：`在线` / `离线` / `本地底图` / `花瓣离线包`。
- 点击小地图 → 全屏地图；不在此处做精细选点。
- 为性能考虑，小地图优先静态快照/图片；`MapComponent` 只在全屏创建（或面板打开时创建、关闭销毁）。

### 7.2 全屏地图

- 顶部：返回、搜索框、当前星球/图层状态。
- 中部：地图画布 + Marker + 当前位置。
- 底部：坐标读数、`使用此点`、`取消`。
- 搜索结果显示在搜索框下方；选中后移动相机并放 Marker，不立即提交。
- 离线无搜索时：保留搜索框但显示“离线仅支持本地城市/任务地点”，或隐藏搜索框、保留“地点列表”按钮。
- 非地球：显示星球徽标，关闭在线搜索；保留本地任务列表。

### 7.3 错误/回退状态

- 花瓣加载中：显示自有底图 + “正在连接花瓣地图”。
- 花瓣失败：显示自有底图 + “花瓣地图不可用，使用本地底图”，不阻断选点。
- 隐私未同意/后台：不创建 MapComponent，使用本地底图。
- 无离线包：提示“可在花瓣地图下载离线地图”，提供跳转按钮，但不强制。

## 8. 性能与内存

- 小面板不要长期驻留 `MapComponent`；它是原生图层，和玻璃面板/滚动组合可能重新引入 RS 合成成本。优先静态图/快照。
- 全屏 `MapComponent` 在页面 `show()/hide()` 管理生命周期；退出全屏销毁。
- 纹理：
  - 地球 5400×2700 原始纹理约 58MB GPU；面板用 2048×1024，全屏用 4096×2048 降采样。
  - 月球 4096×2048 约 32MB；面板可用 1024/2048，全屏 4K。
  - Mars/其他 512×256 或 1024×512，成本低。
- 若全屏要高缩放细节，为 `coverageImage` 按缩放分级加载更高分辨率纹理。
- 本地搜索已按唯一字符串 memo 优化，新增非地球条目不会改变 8k 级扫描量级。

## 9. 隐私、网络与合规

- 在线花瓣地图/搜索需要 AGC 开通地图服务、匹配签名/Profile、`ohos.permission.INTERNET` 和隐私同意。
- 在线搜索会外发查询词；地图会外发视口/瓦片请求。更新隐私政策与 `NETWORK-INVENTORY.md`。
- 离线回退不应依赖网络；若 Map Kit 无网无法初始化，必须使用 ArkUI 自绘层。
- 地图审图/行政范围：`miscWorldMap.jpg` 为 NASA Blue Marble 物理底图，无行政边界，但仍需按中国地图展示要求审核；文化地图仍使用本地资料，不能用在线底图替代。
- 非地球使用花瓣 Map Kit 容器时，确认花瓣 Logo/版权/服务条款是否允许非地球自定义底图；如不允许，非地球改用自绘。

## 10. 验证计划（P0 原型先行）

### P0-A：离线单瓦片

- 全新安装/清缓存 → 飞行模式 → `MapType.NONE` → `coverageImage`（月球 4K）。
- 验收：地图能创建、图层可见、点击返回坐标、无网络错误。

### P0-B：3D 球体覆盖物

- `MapType.NONE + sphereEnabled + coverageImage`，zoom 2/3。
- 验收：球体显示贴图、Marker 对齐、Chandrayaan-1（89.76S）可见/可点、zoom 4 行为明确。

### P0-C：花瓣在线/离线

- 在线：`MapComponent` + `TERRAIN` + `site.searchByText`。
- 离线：花瓣地图 App 下载全球基础包 + 城市包，飞行模式。
- 验收：在线搜索/选点；离线底图 + 直接选点；离线搜索按预期不可用。

### P0-D：面板性能

- 小面板静态图 vs 实时 MapComponent，hitrace 对比滚动帧率。
- 验收：不重现位置面板模糊/图层合成卡顿。

### P0-E：数据迁移

- 导入全部非地球地点，补中文名，跑 `verify-ohos-location-search`，真机查看 Moon 63 条、搜索嫦娥四号/玉兔二号。

## 11. 实施阶段

1. **阶段 0（原型/决策）**：P0-A/B/C/D/E；根据结果确定 3D 球体与离线初始化是否可用。
2. **阶段 1（数据）**：非地球地点导入、中文名、所属方翻译、测试更新。
3. **阶段 2（全屏在线）**：全屏 MapComponent、在线搜索、选点、确认。
4. **阶段 3（离线回退）**：花瓣离线包、CustomOverlay、ArkUI 自绘、优先级状态机。
5. **阶段 4（面板与收尾）**：面板 3D 球/静态图、性能、隐私、UI contract、CHANGELOG。

每阶段完成构建、静态检查、相关测试和真机验证后再进入下一阶段。

## 12. 风险与未决项

| 风险 | 影响 | 缓解 |
|---|---|---|
| Map Kit 无网无法初始化 | 单瓦片容器方案失效 | 回退 ArkUI 自绘层 |
| 3D 球体不渲染 coverageImage | 行星球体不可用 | 回退等距圆柱/自绘球 |
| 2D Mercator 极区裁剪 | 月球极区地点不可见 | 3D 球体或等距圆柱，不用 2D Mercator |
| 5400/4K 纹理内存 | 面板/全屏 OOM/掉帧 | 降采样、按视图分 LOD、瓦片化 |
| 花瓣 Logo/条款不允许非地球 | 行星方案不合规 | 行星改用自绘；地球保留 Petal |
| 行星经度方向/投影 | 点位偏移 | 用 Stellarium 原图+原坐标，已知点对齐测试 |
| 离线地址搜索不存在 | 用户预期落空 | UI 明确“离线仅本地城市/任务地点” |
| 小面板 MapComponent 性能 | 滚动掉帧 | 静态图优先，MapComponent 只全屏 |

## 13. 验收标准

1. 位置面板打开即显示当前地点全球位置；无空白、无网络等待。
2. 在线全屏地图可搜索地址/POI 并选点；坐标纠偏正确。
3. 离线全屏地图至少可用本地城市/任务地点定位；无搜索时直接点选仍可用。
4. 月球列表包含 63 条任务地点，中文名完整；嫦娥四号/玉兔二号可搜索并写入坐标。
5. 月球极区地点（Chandrayaan-1 89.76S）在选定表面可见/可点。
6. 非地球关闭花瓣在线搜索；本地任务列表可用。
7. 面板滚动/全屏地图帧率不低于现有位置面板基线；无新增长时间卡顿。
8. 隐私、网络清单、地图合规说明更新；UI contract 通过。

## 14. 实施状态（2026-11-10）

已落地：

- `data/base_locations.txt` 非地球地点合并：Moon 63、Mars 16、Venus 14、Titan 1、Bennu 1；总数 8,174；补 57 条中文名，经度归一化。
- 全屏地图覆盖层：宿主根 `Stack` 的 `zIndex(200)` 覆盖层，避免被浮动面板/Dock 遮挡；`bindContentCover` 方案在面板内 z-index 不可靠，已放弃。
- 全屏地图：Petal `site.searchByText` 在线搜索 → 本地城市/任务搜索兜底；`MapType.NONE + setSphereMapEnabled({ coverageImage })` 行星球体；ArkUI 等距圆柱 raster 兜底；直接点选 + Marker + 使用此点。
- 面板入口：位置面板内“全屏选点”按钮；Earth 的在线小地图启用 `sphereEnabled`。
- 模拟器（Mate 90 Pro，x86_64，API 26，UI-only）：
  - HAP 安装/启动成功；全屏覆盖层不再透出下方面板/Dock。
  - 全屏搜索“深圳”返回 Petal 地址结果，应用坐标 `22.5464° / 114.0528°`。
  - raster 直接点选返回并应用 `26.44°N / 95.63°W`。
  - Map Kit 底图在 UI-only 模拟器未完成加载，显示“本地底图”；`site.searchByText` 仍可用。模拟器无法切换观测星球（Select 无候选），Moon 列表以数据测试 + 真机最终验收为准。
- 静态验证：`test-ohos-location-map` 4/4、`test-ohos-location-panel` 6/6、UI contract intact、`verify-ohos-location-search` 8,174 条、i18n 检查通过。

待完成：

- 真机最终验收（按用户要求，全部开发完成后由用户参与执行）。
- 面板 3D 球在无 Map Kit 时的正式回退形态（当前全屏 raster 为等距圆柱；面板仍使用原位置地图）。
- 若需要全屏离线精细缩放，为 `coverageImage` 按缩放分级加载更高分辨率纹理。
