# 目镜插件器材管理（2026-11-22）

## 范围

「目镜（Oculars）」面板按 PC 版 `OcularDialog` 的划分改为页签结构：

- **通用**：模拟视图开关、当前光学结果、视图/遮罩、传感器叠加、Telrad 四圈视场、模拟行为、配置管理。
- **目镜 / 增倍镜 / 传感器 / 望远镜**：每页一张器材列表，替代旧面板里的四个横向选择器；列表即当前器材选择器。
- **关于**：说明插件用途、各类器材数量与 `ocular.ini` 存放位置。

顶部保留「当前组合」摘要（目镜、望远镜、增倍镜、放大率、实际视场、传感器视场），六个页签切换时始终可见。

## 器材页交互

- 行点击 = 选择当前器材；选中行用 accent 边框并显示「当前」。
- 行内「编辑」打开居中浮层表单；顶部「新增」以同类默认值创建。
- 底部「删除 / 上移 / 下移」操作当前器材；删除弹系统确认框。
- 增倍镜页提供「不使用增倍镜」行（索引 `-1`），与 PC 版一致。
- 传感器页在当前传感器下方提供实时旋转角与 OAG 棱镜角滑杆（仅 `hasOAG` 时）；目镜页提供十字丝左右旋转。
- 删除保护：目镜、望远镜、传感器各类至少保留一件；增倍镜可全部删除。

表单校验（`common/derive/ocularEquipment.ets`）与原生校验保持一致：

| 类别 | 约束 |
| --- | --- |
| 目镜 | 名称非空；表观视场 1–120°；焦距 1–500 mm；视场光阑 0–200 mm |
| 增倍镜 | 名称非空；倍率 0.01–9 |
| 望远镜 | 名称非空；口径 1–999999 mm；焦距 1–9999999 mm |
| 传感器 | 名称非空；分辨率 1–100000 整数；合并 1–4 整数；芯片 0.1–9999 mm；旋转 −360..360°；OAG 开启时棱镜高/宽/距 ≥0.1 mm |

## 数据流

```
OcularsPanel ── OcularEquipmentTab / OcularGeneralTab
   │                     │
   │                     └─ 表单草稿、校验、JSON payload
   ▼
OcularController (capability/) ── CommandPort ── StelMainView 命令桥
   │                                              │
   └─ TelescopeStore.loadOculars()                └─ Oculars::applyOhosEquipmentAction
                                                        persistEquipmentSettings() → ocular.ini
```

- 表单只持字符串草稿；`equipmentMutationPayload` 生成 `{kind,index,item}`，类别转小写。
- 控制器在请求期间置 `ocularEquipmentBusy`，失败写 `ocularEquipmentError` 并 `flashHint`；成功后重载 `getOculars`，新增项自动选中。
- 文件导入导出由宿主 `HostMediaPort` 执行 `DocumentViewPicker` + `fileIo`；面板只负责编排与浮层确认，不直接 import 设备能力模块。

## 导入导出文档

```json
{
  "format": "stellarium-ohos-oculars-equipment",
  "version": 1,
  "oculars": [],
  "lenses": [],
  "telescopes": [],
  "ccds": [],
  "selected": { "ocular": 0, "telescope": 0, "lens": -1, "ccd": 0 }
}
```

- 原生 `importOhosEquipmentJson` 要求 `format/version` 匹配、四类数组齐全；先构造并校验临时列表，全部通过后才替换或追加，避免半导入。
- 上限：512 KB；每类 500 项。
- 替换模式要求目镜、望远镜、传感器至少各一件（与删除保护一致）；追加模式保留现有条目。
- 导入后重新计算 `maxEyepieceAngle`、刷新列表、持久化并重新应用当前选择。

## 持久化

`persistEquipmentSettings()` 移除并重写 `ocular/`、`telescope/`、`lens/`、`ccd/` 四个分组及 `*_count`、`*_index`，最后 `settings->sync()`。Telrad 视场与传感器中心标记由既有 setter 写入 `telrad_fov`、`show_ccd_center` 并同步。

## 命令

见 `docs/harmonyos/CLI.md`「目镜器材配置与导入导出」。命令目录校验：`node scripts/check-ohos-command-catalog.mjs`（443 条）。UI 语义命令 `setOcularsTab`、`openOcularEquipmentEditor`、`closeOcularEquipmentEditor` 仅用于读屏验证，不进入原生命令目录。

## 回归

- `node --test scripts/test-ohos-oculars-equipment.mjs`：草稿默认值、四类范围校验、OAG 约束、payload 契约、UI 锚点、命令桥接线。
- `node scripts/check-ohos-i18n.mjs`、`check-ohos-ui-contract.mjs`、`check-ohos-command-catalog.mjs`。
- 真机：CLI 增删改/上下移 → `getOculars` 回读；重启后配置保持；导出文件、替换/追加导入；Telrad 四圈与 CCD 中心标记即时生效。
