# 鸿蒙端多语言架构

## 名称来源

鸿蒙端不维护恒星、行星、彗星、小行星、星座或深空天体的第二套译名表。显示名称由 Stellarium 核心返回，并由官方 Qt 翻译域完成本地化：

- `translations/stellarium/*.qm`：Stellarium 界面及太阳系天体名称。
- `translations/stellarium-sky/*.qm`：恒星、星座、深空天体和天体目录名称。
- `translations/stellarium-skycultures/*.qm`：星空文化名称及相关本地化文本。
- `translations/stellarium-skycultures-descriptions/*.qm`：星空文化描述，按上游 PO 实际存在的目标语言编译并随包同步。

ArkUI 只负责布局和副标题排版。中文主标题与英文名、目录号分开显示，避免把官方名称拼成难以阅读的一行；目录号仅作为识别信息，不冒充天体正式中文名。

## 鸿蒙自定义文字

鸿蒙新增的按钮、面板、提示、插件标签和观测位置字段不属于 Stellarium 的 Qt 翻译域，由 `harmonyos/ets-source/pages/I18n.ets` 的 `UI_STRINGS`、类型标签和功能标签提供。它们的翻译覆盖率不能以 `.qm` 文件数量代替，缺失时按模块既定规则回退英语。

地景、时区和地区名称属于离线数据或位置数据库，不应写入天体译名表。地区数据库的官方中文名称与核心天体翻译是两个独立来源。

## 语言切换

语言选择器使用核心资源实际存在的 43 个语言代码。选择语言时，ArkUI 更新自身显示状态，同时向核心发送同一个 Stellarium 语言代码。系统语言会区分 `zh_CN`、`zh_HK` 与 `zh_TW`；启动时资源引导会把 HAP 内置的 `translations/` 树复制到应用沙箱，核心从 `STELLARIUM_DATA_ROOT` 加载 `.qm`。

## 校验

构建前运行：

```bash
node scripts/build-ohos-official-translations.mjs
bash scripts/sync-ohos-resources.sh
node scripts/check-ohos-i18n.mjs
```

该检查确认 43 个语言包在 `stellarium` 和 `stellarium-sky` 两个核心域中都存在，同时验证官方跨语言搜索索引、每个已选上游 PO 的同名 QM、鸿蒙源文件与构建副本一致、中文地区术语保护有效，并拒绝可执行代码中重新出现的 `PLANET_NAMES`、`STAR_NAMES`、`CONSTELLATION_ABBR` 或 `ALIAS_LIST` 天体译名表。

## 当前覆盖边界

- 恒星、星座、星云、星系、星团、变星、彗星、小行星以及太阳系天体的名称和类型，统一从核心对象的 `getNameI18n()`、`getObjectTypeI18n()` 返回；鸿蒙目录、搜索、详情、位置计算和“今晚可观测”入口均使用这两个字段。
- 天体搜索首先使用当前语言的核心索引、英文名和目录号。没有结果时，再惰性读取 `data/search/multilingual-sky-aliases.tsv`，对照 `po/stellarium-sky/*.po` 的官方译名进行跨语言反查。每个命中都需经 `StelObjectMgr::searchByName()` 再次验证，结果仍以当前语言显示，并标明“跨语言匹配”。
- 该索引由 `scripts/build-ohos-multilingual-search-index.mjs` 生成，`sync-ohos-resources.sh` 会在每次资源同步时重建并随 `data/` 一起写入 HAP 的 rawfile；不允许手工编辑生成文件。
- 英文名是稳定检索键，不再作为中文主标题；需要显示时放在主标题下方，目录号另作为识别信息显示。
- 星空文化及其描述不由鸿蒙自行重译；凡是上游 PO 存在的当前目标语言，构建步骤都会编译为同名 QM。少数附加域没有英文 PO 时使用英语原文，不能把“没有独立英文 PO”误报为资源缺失。
- `UI_STRINGS` 是鸿蒙新增界面文案，不会因为核心 `.qm` 存在而自动翻译。检查脚本会输出仍等于英文的条目；这些条目必须按语言逐项补齐，不能用机器猜译冒充官方译文。
- 地区、地图、民族、历史和天空文化的呈现还需遵循 `LOCALIZATION-POLICY.md`；其中中文界面用项目规定的中国官方表述，非中文界面优先保留上游官方译文和当地语言习惯。

## ArkUI 完整本地化的完成标准

官方天体、星空文化和搜索资源已可使用 43 种界面语言，但 ArkUI 自定义界面尚未完成 43 语言人工审校。不得把核心 `.qm` 的完整度当作 ArkUI 界面完整度，也不得将英语回退或未审校机器翻译标记为“已本地化”。

完成顺序按用户实际路径执行：

1. 搜索、位置选择、目录和天体详情：每个键必须有 43 个明确语言字段；搜索应继续覆盖本地名称、英文、目录号、跨语言官方别名和一字符近似匹配。
2. 设置、时间、天文计算和图层：优先复用可追溯的上游 PO 译文；没有上游条目时进入人工术语表并结合对应语言的界面截图审校。
3. 星空文化、探索、插件和脚本：文化名称与描述使用上游资源，鸿蒙新增说明、错误状态和操作提示逐项翻译，并保留原作者归属。
4. 低频工具、调试和导入导出：最后完成，但不能向正式用户界面暴露内部键名、中文硬编码或未经翻译的英文说明。

每个页面完成时必须运行 `node scripts/check-ohos-i18n.mjs --strict-ui` 并记录待处理数变化；只有严格检查为零、完成各语言方向与长文案的真机截图审查，才可以声明 ArkUI 43 语言完整支持。

## 位置与地点检索

- 国家和地区名称不另建多语言静态表。中文界面使用 `location_countries.ts` 中经审核的官方中文术语；其他界面通过 HarmonyOS `@ohos.i18n.System.getDisplayCountry()` 按当前应用语言显示。
- 地点候选只显示当前语言的一个名称，不把中文、英文和其他语言并列堆叠。离线搜索同时索引 Stellarium 原始地点名、官方中文名和当前显示名称，因此语言切换后仍可用英文或中文定位同一地点。
- 城市数据来自 Stellarium `base_locations.txt`。没有对应官方本地化数据的城市保留其原始地名，不能以机器翻译填充并冒充正式译名。
