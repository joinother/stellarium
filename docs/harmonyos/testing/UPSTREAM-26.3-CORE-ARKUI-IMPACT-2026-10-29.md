# Stellarium 26.3 合并：src/core 变更 → ArkUI 影响与真机测试清单

日期：2026-10-29
合并分支：`merge/upstream-26.3`（`556bfa45ca` + docs `21f576971d`）

## 1. 真机安装结果

- 设备：HUAWEI Mate 80 Pro，`192.168.1.5:36717`
- HAP：`entry-default-signed.hap`，721 MB
- Bundle：`com.joinother.skyinstrument`
- 版本：`26.3.301-556bfa4 [merge/upstream-26.3]`
- 安装/启动成功，星图正常渲染，命令桥可用，`getAppState` fps≈23，夜间模式 false
- 截图：本机临时目录 `C:\Users\cnchensh\AppData\Local\Temp\stellarium-26.3-real-device.png`

## 2. src/core 变更与 ArkUI 影响

| # | core 变更 | 关键文件 | ArkUI 侧现状 | 影响/优先级 |
|---|---|---|---|---|
| 1 | 十进制度拆成坐标/其它两个开关 | `StelApp.hpp/cpp`、`StelObject.cpp`、`Planet.cpp`、`Comet.cpp`、`Nebula.cpp`、`GridLinesMgr.cpp`、`NomenclatureItem.cpp` | ArkUI 没有引用 `flagShowDecimalDegrees`/新旧配置键；对象资料走引擎结构化字段 | 若设置页暴露“十进制度”需拆成两个开关；否则只测信息格式/旧配置迁移。**P1（验证）/P2（如需 UI）** |
| 2 | 星空文化时间跨度改为从 `territory.geojson` 推导，忽略 `index.json` 的 begin/end | `StelSkyCultureMgr.cpp/hpp`、`StelSkyCultureSkyPartition.cpp` | `SkyCultureViewStore.ets:120-121` 解析 begin/end；`MainWindowNativeNode.ets:6431-6432` 写入 `SkyCultureSettingsStore.skyCultureBeginTime/EndTime`；面板有时间筛选/跟随 | 哨兵值 `-100000`/`9146` 会进入 ArkUI；需要处理“未知/至今”显示，检查时间筛选/跟随。**P1** |
| 3 | HiPS 淘汰未完成的不可见瓦片；HiPS 下载改 HTTP/1.1 | `StelHips.cpp/hpp`、`StelTexture.hpp/cpp` | `SurveyController.ets:35-37` 显示 `hipsLoading`/`hipsVisibleCount`；类型在 `StellariumTypes.ets:870-877` | 加载计数/状态语义变化；通常无需改代码，但需验证状态文字、快速平移/缩放、内存。**P1/P2** |
| 4 | Lightweight atmosphere 成为默认模型 | `LandscapeMgr.cpp:63-69`、`AtmosphereLightweight.*` | ArkUI 未发现大气模型选择器；默认值来自引擎 | 新装默认 lightweight，旧配置可能仍为 preetham/showmysky；测昼夜/日出日落视觉与性能。**P2** |
| 5 | 信息 HTML 表格从内联样式改为 `class='info-string'` | `StelObject.cpp`、`Planet.cpp` | `ObjectDetailStore` 使用 `getObjectInfo`/`getSelectedObjectInfo` 的结构化字段，不直接渲染原始 HTML | 通常无需 ArkUI 改动；若某处渲染原始 HTML，需要补 `.info-string` 样式。**P2（验证）** |
| 6 | 星座新增文化名/暗星座/线段 getter | `Constellation.hpp`、`ConstellationMgr.cpp` | 未发现 ArkUI 暴露 `getCulturalName`/dark constellation；搜索/标签仍走既有命令 | 暂不需要 UI 改动；测星座标签、搜索、天空文化暗星座显示。**P3** |
| 7 | 多处 `Q_UNUSED`/注释/无行为变化 | `StelObjectModule.cpp`、`SolarSystem.cpp`、`EphemWrapper.cpp`、`precession.c`、`TextureAverageComputer.cpp`、`StelSpeechMgr.cpp`、`StelUtils.cpp` | 无 | 无 ArkUI 适配，随回归测试覆盖。**P3** |

### 明确需要关注的 ArkUI 语义

- **天空文化时间**：`SkyCultureViewStore` 会解析 `beginTime/endTime`；26.3 中大量文化为 `-100000 / 9146`（未知/至今哨兵）。如果面板显示这些数值或时间滑块，需要转成“未知/至今”，并避免把 9146 当真实年份。
- **十进制度**：引擎现在有 coords/other 两个 flag；ArkUI 目前没有引用。若设置页有“坐标使用十进制度”，它只能影响坐标/其它之一，需明确产品语义，必要时增加第二个开关。
- **HiPS**：`hipsLoading`/`hipsVisibleCount` 仍由 `SurveyController` 读取；瓦片淘汰后计数可能不再单调增长，需确认 UI 文案不会误报“加载卡住”。
- **大气**：默认 lightweight 是引擎行为变化；如果设置页没有模型选择器，只需要视觉/性能验收，不需要改 ArkUI。

## 3. 真机探测结果

- `getSkyCultureList`：**63 条**。
  - `chinese`：1756–1911
  - `chinese_chenzhuo`：280–589
  - `egyptian_dendera`：-320–30
  - `modern`、`modern_*`、`egyptian`、`chinese_xianglin`：`-100000 / 9146`（新哨兵）
  - **Potawatomi 不在列表中**
- Potawatomi 已在 HAP 中（21 个 rawfile 条目，含 `index.json`、`description.md`、插图），但设备沙箱未提取：
  - `StellariumResourceBootstrap.ets` 的升级判断只检查 `skycultures/modern/index.json`、modern 插图和 `SKYCULTURE_ART_COMPAT_MARKER`，**不会因为新增文化强制重抽**。
  - 旧安装覆盖安装后 marker 仍在，导致 Potawatomi 留在 HAP rawfile、没有进入 `filesDir/stellarium/skycultures`。
  - 这是 26.3 合并后的升级/资源提取问题，不是 core 逻辑错误。建议：提高资源提取版本 marker（或把 `potawatomi/index.json` 纳入检查），或在测试时清应用数据/全新安装验证。
- `landscape/atmosphere_model` 配置为空，引擎使用默认 `lightweight`。
- `gui/flag_use_decimal_degrees_coords` / `_other` / 旧 `gui/flag_show_decimal_degrees` 在 config 中为空，默认 DMS。
- `getSelectedObjectInfo --payload details` 当前返回 `found:false`（当前没有选中对象），对象资料/坐标格式需手工选中后测试。

## 4. 真机重点测试清单

### P0：安装、升级与基础链路

- [x] HAP 安装、启动、星图渲染、版本 26.3、命令桥、fps（已做基础验证）
- [ ] **全新安装 / 清应用数据后重新启动**，确认 `getSkyCultureList` 包含 Potawatomi（预期 64 条）
- [ ] 旧版本覆盖安装（不清数据）复现 Potawatomi 缺失，确认资源提取 marker/版本修复方案
- [ ] 旧 `config.ini` 迁移：`gui/flag_show_decimal_degrees` → 新 coords/other 键；大气旧模型配置
- [ ] 启动无崩溃、隐私门控、权限、离线资源、中文 UI

### P1：core 变更直接影响

- [ ] 对象资料坐标格式：选中恒星/行星/深空天体，检查 RA/Dec、Alt/Az、黄道/银河坐标、RTS、星等；确认新 coords/other flag 未造成格式回退
- [ ] 对象资料 HTML 信息（表格/RTS/额外信息）显示完整，无错位/丢样式
- [ ] 星空文化列表：`chinese` 1756–1911、`egyptian_dendera` -320–30、`modern*` 哨兵
- [ ] 星空文化时间筛选/跟随：哨兵文化的“未知/至今”显示、时间滑块边界、模拟时间跟随
- [ ] 星空文化领地地图/描述/插图；中文、埃及、Potawatomi 文化
- [ ] HiPS：打开/关闭、快速平移缩放、`hipsLoading`/`hipsVisibleCount`、内存/瓦片淘汰、无 HTTP 420/网络错误
- [ ] 大气默认 lightweight：昼夜、日出日落、地平线/消光、帧率与旧模型对比
- [ ] 星座标签/搜索/文化名；若 UI 暴露暗星座，检查暗星座线段

### P2：26.3 新功能与插件

- [ ] Object Visibility 插件：`getPluginList`/加载、`openPluginFeature ObjectVisibility` → Astro > Observability
- [ ] AstroCalc 日月食/凌日：特定阶段跳转、NASA/Espenak 术语、凌日线
- [ ] Satellites：Alpha-5 TLE、卫星列表/轨道/测光
- [ ] RemoteControl：OpenAPI/SwaggerUI、Scenery3D 端点、host/port、maxRequestSize/maxMultipartSize
- [ ] Oculars CCD 中心隐藏；Planes 斜距/地面距离/海里单位
- [ ] 脚本 dome mode、SCM sky culture loader
- [ ] 新星/彗星/系外行星/卫星数据

### P3：既有 OHOS 回归

- [ ] 夜间模式切换与面板切换竞态（requestEpoch 修复）
- [ ] Dock/面板/搜索/详情/图层/设置持久化/语言切换
- [ ] 触摸、拖动、缩放、陀螺仪/指南针、平板/PC/分屏/折叠屏
- [ ] 帧率、内存、长时间运行、离线/隐私/权限
- [ ] 中文翻译（Object Visibility 新词条、egyptian 描述）

## 5. 结论

- 26.3 合并版已在真机安装并启动，星图/命令桥正常。
- `src/core` 的 26.3 变更中，**最需要 ArkUI 关注的是天空文化时间跨度/哨兵值**；十进制度拆分为可选 UI 适配；HiPS/大气主要是状态与视觉验收；信息 HTML 表格与星座新 getter 暂不需要 ArkUI 代码改动。
- **Potawatomi 缺失是升级资源提取问题**，优先级高于 core 适配：先修复/验证全新安装或资源提取 marker，再做完整的真机功能验收。

## 6. 2026-10-30 适配结果

- **十进制度**：已新增 `setDecimalDegrees` 原生命令与设置-附加页两个开关（坐标 / 其它），带乐观更新、请求序号与失败回退；`getState` 同步返回两个字段。
- **天空文化哨兵**：已按 `-100000` / `9146` 精确识别“未知 / 至今”，不再显示“公元前 100000 年”；时间匹配与筛选语义同步。
- **Potawatomi**：已增加旧安装定向补抽与三项哨兵闸门，修复“异步准备提前返回 → 最终检查抛错 → Qt 不初始化”的启动失败链。
- 构建、静态检查与模拟器 UI 外壳冒烟记录见 `UPSTREAM-26.3-UI-ADAPTATION-SMOKE-2026-10-30.md`；真机仍需复测该文档第 5 节。
