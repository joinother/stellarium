# 位置搜索本地化审计（2026-08-24）

## 当前实现

- 地点数据来自 Stellarium `data/base_locations.txt`，转换为 `location_hierarchy.ts`，共 7,387 个离线地点；搜索以 4ms 时间片扫描，不请求网络。
- 搜索同时匹配上游拉丁名称、当前界面显示名称、中文显示表、行政区、国家和中国香港特别行政区/中国澳门特别行政区/中国台湾地区规范别名。
- 国家名在中文界面使用 `location_countries.ts` 的审核中文字段，其他语言由 HarmonyOS `System.getDisplayCountry()` 根据当前应用语言提供。
- 2026-08-24 起，检索还会忽略拉丁音标、空格、点、连字符和撇号差异，例如 `Xi'an`/`xi an`/`xian`、`Sao Paulo`/`São Paulo`、`Hong Kong`/`hongkong`。

## 已验证

- `scripts/verify-ohos-location-search.mjs` 验证 7,387 个地点都有中文显示条目，并覆盖北京、西安、中国香港特别行政区、台北、中国台湾地区及圣保罗的 12 组输入变体。
- `scripts/check-ohos-i18n.mjs` 确认 43 种 Stellarium 官方语言资源和鸿蒙位置搜索关键文案完整。

## 质量边界

- `location_names_zh.ts` 的覆盖完整不等同于译名质量。其历史生成脚本 `generate-ohos-location-zh.mjs` 使用过机器翻译缓存，不能作为官方中文地名来源；已发现少量词义误译风险。
- Stellarium 上游 `base_locations.txt` 主要保存原始拉丁地点名，不提供完整的 43 语言城市官方译名。因此，非中文城市目前优先保留上游名称；不得以机器翻译补全后宣称官方本地化。
- 下一阶段应引入可追溯的权威离线地名来源或人工审校表，先校订中国、常用国际城市和已发现误译，再逐步替换无来源译名。
