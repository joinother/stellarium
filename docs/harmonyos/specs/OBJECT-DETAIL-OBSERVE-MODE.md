# 天体详情卡：天文馆模式 / 观测模式设计

> **状态：** 已实现（2026-10-07，见 §12 实施记录）
> **日期：** 2026-10-07
> **基线：** HEAD `cbc8c5bfae`（宿主 `MainWindowNativeNode.ets` 7,974 行；文中宿主/C++ 行号已对照该基线核验）
> **涉及：** `UnifiedObjectDetailCard` 详情卡体系、`InfoWindowStore` 信息级别域、`QuickPanel` 快捷面板、`SettingsPanel` 设置-信息页

## 1. 目标

为天体详情卡引入两种**显示模式**：


| 模式                          | 定位               | 呈现                                                                            |
| ------------------------------- | -------------------- | --------------------------------------------------------------------------------- |
| **天文馆模式**（planetarium） | 默认；完整浏览体验 | 现有详情卡全量呈现（页头三摘要 + 实时行 + 四页签）                              |
| **观测模式**（observe）       | 户外实测时快速读数 | 极简卡片：仅页头（名称/类型/关闭）+ 三个 tag（星等/星座/距离）+ 居中/展开按钮行 |

具体要求：

1. 模式切换入口放在**快捷面板**——替换卫星显示按钮（卫星功能保留，后续自定义面板布局时可恢复）；
2. 观测模式下星等 tag 以标签 `星等(大气消光)` 注明、**数值行横向**拼接两值（如 `0.03(0.19)`，括号内为**大气消光后星等**），不做三行排布；
3. 观测模式下按钮行左侧为**居中**操作（`moveToSelected`），右侧为**展开全量信息**；按钮行做细、不需要全高；
4. 「更多-设置-信息」页添加「极简观测模式」开关；展开后的全量内容按现有**信息级别**定义渲染；
5. 评估「极简」与现有五个信息级别并列是否引发问题（结论见 §3：**并列有问题，改为正交两轴**）；
6. 不新建布局卡——现有卡片布局已满足需求，只需小改（隐藏/显示分支 + 按钮行）。

## 2. 现状分析

### 2.1 详情卡结构

`UnifiedObjectDetailCard`（`panels/object/UnifiedObjectDetailCard.ets`）由三个壳层渲染，核心结构（`ObjectDetailCardChrome.ets`）：

```
ObjectDetailCardHeader           页头：拖拽柄 + 图标 + 名称 + 类型胶囊 + ✕
  └ Row: 3 × ObjectCompactMetric 星等(i0007) / 星座(i0010) / 距离(i0011)
  └ Row: 实时高度/方位                                    ← 观测模式下隐藏
  └ SelectedLiveInfoRows         实时信息块（infoLevel<=1） ← 观测模式下隐藏
ObjectDetailCardTabs             页签栏：观测/坐标/资料/操作 ← 观测模式下隐藏
Scroll                           四个页组件                 ← 观测模式下隐藏
```

页头三枚 `ObjectCompactMetric` 直接读 `@ObjectLink store`（元素级依赖，切换天体自动刷新）。观测模式只需在 `ObjectDetailCardHeader` 中隐藏实时行/`SelectedLiveInfoRows`、在 `UnifiedObjectDetailCard` 中隐藏页签栏+滚动区，再加一行按钮——**无需新建组件**。

### 2.2 信息级别体系（数据轴）

- C++ 配置键 `gui/selected_object_info` ∈ `{all, default, short, none, custom}`，经 `setInformationSetting mode|xxx` 写入；
- ArkTS `InfoWindowStore.informationMode` 镜像该值，`infoLevel`（0–3）由宿主派生：`all`→0、`default`→1、`short`→2、`none`→3、`custom`→0；
- 宿主按级别门控回包字段落地（L4942–4948）：`showBasicInfo = infoLevel <= 2`，`showObservedInfo = infoLevel <= 1`；
- `custom` 模式下按位掩码清空字段（`ObjectDetailStore.applyCustomInformationMask`，星等/距离/星座均可被关掉）。

### 2.3 桥已提供消光数据（无需 C++ 改动）

`getSelectedObjectInfo` 回包已含（`StelMainView.cpp:3250-3263`）：

- `magnitude` = `vmag` → `selectedMagnitude`；
- `apparentMagnitude` = `vmage`（**大气消光后**）→ `selectedApparentMagnitude`；
- `extinction` = `vmage - vmag`；`airmass` = 气团质量。

### 2.4 快捷面板

`QuickPanel` 当前 2×6=12 格开关网格。描述表 `quickActions.ets` 中卫星项为第 10 项（`{ id: 'satellites', labelKey: 'plugin_satellites', icon: 'satellite', kind: 'vector', actionId: '' }`）。卫星项 `actionId` 为空串，由宿主 `quickToggle` 分发时按 id 特殊处理。**替换该格**而非新增，保持 2×6 布局不变。

### 2.5 设置-信息页

`SettingsPanel` `configTab === 1`：信息级别五按钮 + 详情卡指向线开关 + 15 行自定义字段开关。

### 2.6 居中（moveToSelected）命令

已有桥命令 `moveToSelected`（移动视角到选中天体），宿主已有 `navigateSelectedObjectTo` 方法。观测模式的「居中」按钮直接复用，零新增桥。

## 3. 核心设计决策：极简不与五个信息级别并列，改为**正交两轴**

**用户提问：**「极简观测模式」放进信息级别列表、与其它全量模式并列，是否会有问题？

**结论：会有问题，不能作为第六个 `informationMode` 实现。** 论据：

1. **语义不同构。** `informationMode` 是**数据过滤轴**（C++ `InfoStringGroup` 位标志 → 决定回包包含哪些字段）；「极简观测」是**呈现轴**（同一份数据显示多少 UI）。
2. **与「展开看全量」自相矛盾。** 若极简是数据模式，回包字段被裁剪，展开按钮拿不到全量数据——破坏「展开内容按信息级别定义的来」这一要求。
3. **桌面端无此概念。** `gui/selected_object_info` 是桌面版同名配置键；移动端呈现概念不应写进核心配置。
4. **数据本来就在。** 三个 tag 所需字段在任何信息级别下都随选中查询返回，观测模式**无需任何数据层改动**。

**因此设计为两条正交轴：**

```
数据轴（不变，C++ 持久化）   informationMode ∈ {all, default, short, none, custom}
                              ↓ 决定回包字段与全量呈现的内容
呈现轴（新增，ArkTS 持久化） detailDisplayMode ∈ {planetarium, observe}
                              ↓ 决定详情卡打开时的默认形态
```

- 观测模式 = 呈现层的极简外壳，**始终携带全量数据**（受当前信息级别门控）；
- 展开按钮 = 把同一张卡切换到天文馆呈现，其内容自然按当前信息级别渲染；
- 设置页「信息」区仍显示五枚信息级别按钮，在其下方加一**开关行**「极简观测模式」（on = observe / off = planetarium），与快捷面板开关联动。

## 4. 观测模式详情卡设计（基于现有卡片小改）

### 4.1 现有卡片分支渲染

**不新建组件。** 在 `ObjectDetailCardHeader` 与 `UnifiedObjectDetailCard` 中按 `detailDisplayMode` + `observeExpanded` 分支渲染：

```
detailDisplayMode === 'observe' && !observeExpanded 时：

┌──────────────────────────────────────┐
│           ────（拖拽柄）────          │   ← 不变
│  ◉  织女星          [恒星]        ✕  │   ← 不变
├──────────────────────────────────────┤
│ ┌──────────┐ ┌─────────┐ ┌─────────┐ │
│ │星等(大气消光)│ │ 星座     │ │ 距离     │ │   ← 星等标签括注消光
│ │0.03(0.19) │ │ 天琴座    │ │ 25.3 光年 │ │   ← 星等两值横向一行（括号内=消光后）
│ └──────────┘ └─────────┘ └─────────┘ │
│                                      │
│  [◎ 居中]                [⤢ 展开]   │   ← 新增按钮行，紧凑高度 ~28vp
│                                      │
│  （隐藏：实时高度/方位行）             │   ← 原有 live row 不渲染
│  （隐藏：SelectedLiveInfoRows）       │   ← 原有实时信息块不渲染
│  （隐藏：ObjectDetailCardTabs）       │   ← 原有页签栏不渲染
│  （隐藏：Scroll 四页内容）            │   ← 原有页签内容不渲染
└──────────────────────────────────────┘
```

- `ObjectDetailCardHeader` 新增 `@Prop detailDisplayMode: string`、`@Prop observeExpanded: boolean`、`onCenterObject` / `onExpandObserve` 回调；
- 观测极简态（`observe && !expanded`）：隐藏实时高度/方位行 + `SelectedLiveInfoRows`，在三个 tag 下方渲染按钮行；
- 观测展开态（`observe && expanded`）：显示全部内容（与天文馆模式一致），页头 ✕ 左侧多一个「收起」按钮（设置 `observeExpanded = false`）；
- 天文馆模式（`detailDisplayMode === 'planetarium'`）：所有元素照常渲染，按钮行不出现，收起按钮不出现；
- 卡片高度：宿主在观测极简态计算更小的 `cardHeight`（页头 + 三 tag + 按钮行 ≈ 180–200 vp，具体以真机实测为准），展开后恢复全量 `cardHeight`。

### 4.2 按钮行设计

紧凑单行，**不做全高按钮**：

- 行高 ~28vp，左右各一个按钮，中间 `Blank()` 撑开；
- **居中按钮**（左侧）：图标 `◎` + 文案「居中」，字号 11，`#8FBBD6`，点击调 `onCenterObject()` → 宿主 `navigateSelectedObjectTo()`（复用已有 `moveToSelected` 桥命令）；
- **展开按钮**（右侧）：图标 `⤢` + 文案「展开」，字号 11，`#8FBBD6`，点击调 `onExpandObserve()` → 宿主设置 `observeExpanded = true`；
- 按钮无背景色，仅文字+图标；按压态 `opacity(0.6)`；
- 按钮行整体 `padding({ left: 16, right: 16, top: 2, bottom: 6 })`。

### 4.3 星等 tag：两值横向一行 + 标签括注

**不做三行排布**（标签 / 主值 / 括号值）——两个星等在 `ObjectCompactMetric` 的**同一数值行内横向拼接**，标签注明括注含义：

- label = `星等(大气消光)`（`selectedApparentMagnitude` 非空时）；消光后星等不可用时回退 `星等`；
- value = `selectedMagnitude` + `(` + `selectedApparentMagnitude` + `)`，例如 `0.03(0.19)`；括号外＝未消光视星等（`vmag`），括号内＝**大气消光后星等**（`vmage`）；
- 拼接助手放 `ObjectDetailStore`（`observeMagnitudeLabel()` / `observeMagnitudeValue()`）；`ObjectCompactMetric` **无需新增任何 prop**（`label`/`value` 均为其现有 `@Prop`）；
- 可用性门控沿用现状：`apparentMagnitude` 仅在 `infoLevel <= 1`（all/default/custom）且目标有大气消光数据（恒星/行星等；卫星/星座无 `vmage`）时存在——观测模式不另行放宽；不可用时 value 只显示 `0.03`（无括号）、label 回退 `星等`；
- 消光为零时 `vmage == vmag`，仍显示括号（数值相同），保持信息一致性；
- **范围**——本格式仅用于**观测模式**的星等 tag；天文馆模式页头星等 tag 维持现状（单值），保持「天文馆模式＝当前显示方式」。如日后需一并采用，可复用同一组 store 助手扩到页头（一行改动）。

### 4.4 三个 tag 的数据来源与掩码交互


| tag  | 字段                                                         | custom 模式被关时                                                   |
| ------ | -------------------------------------------------------------- | --------------------------------------------------------------------- |
| 星等 | `selectedMagnitude` + `selectedApparentMagnitude`            | `--`（`applyCustomInformationMask` 清空 → 空值回退）               |
| 星座 | `selectedConstellation`（经 `nameOf` 本地化）                | `--`                                                                |
| 距离 | `distanceSummary(selectedDistance, selectedDistanceCompact)` | `objectDistanceSummary` 按 `distanceInformationVisible()` 回退 `--` |

**决策：观测模式不绕过自定义掩码。** 用户在自定义模式显式关掉星等/距离/星座，观测模式同样显示 `--`——设置语义全局一致。

### 4.5 展开与收起状态生命周期

新增两级状态（均放 `InfoWindowStore`）：


| 字段                | 类型                        | 语义                       | 持久化                  |
| --------------------- | ----------------------------- | ---------------------------- | ------------------------- |
| `detailDisplayMode` | `'planetarium' | 'observe'` | 详情卡**默认呈现**         | 是（ArkTS preferences） |
| `observeExpanded`   | `boolean`                   | 当前这张卡是否**临时展开** | 否（会话内瞬态）        |

行为规则：

1. `observe && !expanded` → 卡片极简形态（隐藏页签/实时行，显示按钮行）；否则全量形态；
2. 点「展开」→ `observeExpanded = true`（不写持久化）；全量卡页头 ✕ 左侧出现「收起」按钮 → `observeExpanded = false`；
3. **`observeExpanded` 重置时机**：切换选中目标（`targetChanged`）时置 false；卡片关闭（`onDismiss`）时置 false——保证下次选星仍以极简形态出现；
4. `detailDisplayMode = 'planetarium'` 时 `observeExpanded` 恒无效；
5. 选星弹卡逻辑（`targetChanged` / `reopenDismissedDetail` / `dismissedObjectName`，宿主 L4912-4915）不动。

### 4.6 模式切换不触碰桥

`detailDisplayMode` 是纯 ArkTS 呈现状态：切换时**不调用** `setInformationSetting`，不触发 `refreshSelectedObject`（数据已在 store 中，呈现切换即时生效零延迟）。这是两轴设计的直接收益。

## 5. 快捷面板切换入口

**替换卫星显示按钮**（网格第 10 格），而非新增格/分段行：

- `quickActions.ets` 中将卫星项 `{ id: 'satellites', ... }` 替换为 `{ id: 'observe_mode', labelKey: 'detail_mode_observe', icon: 'observe_mode', kind: 'vector', actionId: '' }`；
- 卫星项**不从代码删除**——注释保留或移入备选表，供后续「自定义快捷面板布局」恢复；
- 宿主 `quickToggle(id, value)` 新增 `id === 'observe_mode'` 分支：`value === true` → `detailDisplayMode = 'observe'`；`value === false` → `detailDisplayMode = 'planetarium'`；
- 开关值来源：`detailDisplayMode === 'observe'`（宿主在渲染时映射到 `values` Record）；
- 图标：新增矢量图标 `observe_mode`（望远镜/目镜剪影，与现有 `satellite`/`gyro` 矢量风格一致；具体设计由实现阶段确定，可暂用占位图标）；
- 提示：切换时 `flashHint`（「已切换为观测模式」/「已切换为天文馆模式」）。

优势：零布局改动（2×6 不变）、零新组件、复用现有开关机制。

## 6. 设置入口（更多-设置-信息）

`SettingsPanel` `configTab === 1`，在五枚信息级别按钮 Flex **之后、「详情卡指向线」之前**插入一个**开关行**：

```
信息级别
[全部] [默认] [简短] [无] [自定义]          ← 现状五按钮，不动
极简观测模式                     [开关]     ← 新增 Toggle
说明：开启后详情卡仅显示星等、星座、距离；
展开后的全量内容按上方信息级别显示。
```

- `Toggle` 样式对齐现有设置开关（`$r('sys.media.ohos_ic_public_switch')` 或系统 Toggle 组件）；
- 值 = `detailDisplayMode === 'observe'`；`onChange` → 宿主 `setDetailDisplayMode(value ? 'observe' : 'planetarium')`；
- 与快捷面板开关联动（同一 store 字段 `detailDisplayMode`）；
- 交互独立性：切换此开关**不改变**信息级别按钮的选中态（两轴正交）；
- 文案明示「展开内容按信息级别显示」。

## 7. 数据与状态流

```
InfoWindowStore（信息窗域，唯一事实源）
  detailDisplayMode: string      // 'planetarium' | 'observe'，preferences 持久化
  observeExpanded: boolean        // 瞬态
  setDetailDisplayMode(mode)      // 写 store + 经 hooks 持久化；不碰桥
  resetObserveExpand()            // 仅写瞬态字段

宿主（MainWindowNativeNode）
  aboutToAppear：restoreStartupSettings 阶段读 preferences → store
  quickToggle('observe_mode', value) → store.setDetailDisplayMode
  settingsToggleObserveMode(value) → store.setDetailDisplayMode
  navigateSelectedObjectTo() → 桥 moveToSelected（已有，居中按钮复用）
  渲染分发：读 store → @Prop 下发三壳层
  卡片高度：observe && !expanded → 紧凑 cardHeight；否则全量 cardHeight
  targetChanged 时 → store.resetObserveExpand()

ObjectDetailCardHeader（现有组件，小改）
  + @Prop detailDisplayMode / observeExpanded
  + onCenterObject / onExpandObserve / onCollapseObserve 回调
  分支：observe && !expanded → 隐藏 live row + liveInfoRows，渲染按钮行
        observe && expanded  → 全量渲染 + 页头「收起」按钮
        planetarium          → 全量渲染（零变化）

UnifiedObjectDetailCard（现有组件，小改）
  + @Prop detailDisplayMode / observeExpanded
  分支：observe && !expanded → 隐藏 ObjectDetailCardTabs + Scroll
        否则                 → 全量渲染（零变化）

ObjectDetailStore（现有 store，小改）
  + observeMagnitudeLabel() / observeMagnitudeValue()：星等标签括注 + 两值横向拼接
ObjectCompactMetric（现有组件，零改动）
  直接接收拼接后的 label / value（均为现有 @Prop）
```

**持久化实现：** `@ohos.data.preferences`（沿用 `BOOKMARK_STORE`/`SEARCH_HISTORY_STORE` 模式：宿主提供 `readDetailModeStorage()`/`writeDetailModeStorage(mode)` 原始助手，store 经 hooks 消费）。键 `detailDisplayMode`，值 `'planetarium'`/`'observe'`，缺省 `'planetarium'`。

## 8. 改动清单

### 8.1 ArkTS（本设计**零 C++ 改动**）


| 文件                                        | 改动                                                                                                                                                                                                                                    |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `state/InfoWindowStore.ets`                 | +`detailDisplayMode` / `observeExpanded` 字段；+ `setDetailDisplayMode()` / `resetObserveExpand()`；hooks 接口 + 持久化助手                                                                                                             |
| `panels/object/ObjectDetailCardChrome.ets`  | `ObjectDetailCardHeader`：+ `@Prop detailDisplayMode` / `observeExpanded` + `onCenterObject` / `onExpandObserve` / `onCollapseObserve`；观测极简态隐藏 live row + liveInfoRows、渲染按钮行（居中+展开）；展开态页头加「收起」按钮       |
| `panels/object/UnifiedObjectDetailCard.ets` | +`@Prop detailDisplayMode` / `observeExpanded`；观测极简态隐藏 `ObjectDetailCardTabs` + `Scroll`                                                                                                                                        |
| `state/ObjectDetailStore.ets`               | +`observeMagnitudeLabel()` / `observeMagnitudeValue()`：星等标签括注 + 两值横向拼接助手（`DetailTiles.ets` 零改动）                                                                                                                       |
| `common/derive/quickActions.ets`            | 卫星项替换为观测模式开关项；卫星项保留注释/移入备选表                                                                                                                                                                                   |
| `panels/panels/QuickPanel.ets`              | 无需改动（仅消费`items`/`values`，开关值由宿主按 id 映射）                                                                                                                                                                              |
| `panels/panels/SettingsPanel.ets`           | `configTab===1`：信息级别按钮下方加「极简观测模式」Toggle + 说明文案；+ 对应 `@Prop`/回调                                                                                                                                               |
| `pages/MainWindowNativeNode.ets`            | ① preferences 读写助手 + 启动恢复；②`quickToggle` 新增 `observe_mode` 分支；③ `targetChanged` 时 `resetObserveExpand()`；④ 卡片高度按呈现分支；⑤ 三壳层 +2 `@Prop` +3 回调下发；⑥ 居中按钮接线（复用 `navigateSelectedObjectTo`） |
| `capability/I18n.ets`                       | + 键（见 §8.2）                                                                                                                                                                                                                        |

### 8.2 I18n 新键


| key                           | zh_CN                                  | en                             |
| ------------------------------- | ---------------------------------------- | -------------------------------- |
| `detail_mode_observe`         | 观测模式                               | Observing                      |
| `detail_observe_magnitude`    | 星等(大气消光)                         | Mag (ext.)                     |
| `detail_observe_center`       | 居中                                   | Center                         |
| `detail_observe_expand`       | 展开                                   | Expand                         |
| `detail_observe_collapse`     | 收起                                   | Collapse                       |
| `detail_observe_toggle`       | 极简观测模式                           | Minimal observing mode         |
| `detail_observe_hint`         | 观测模式：详情卡仅显示星等、星座、距离 | Observing: compact detail card |
| `detail_switched_planetarium` | 已切换为天文馆模式                     | Planetarium mode               |
| `detail_switched_observe`     | 已切换为观测模式                       | Observing mode                 |

### 8.3 契约与护栏

- `scripts/check-ohos-ui-contract.mjs`：若按钮行加 `.id()` 锚点（建议 `object-detail-observe-center`、`object-detail-observe-expand`），须同步登记；
- 现有 id 锚点零改名、零删除。

## 9. 边界与交互细节


| #  | 场景                                   | 行为                                                                           |
| ---- | ---------------------------------------- | -------------------------------------------------------------------------------- |
| 1  | 观测模式 +`short` 信息级别             | 三 tag 正常；星等 label 回退 `星等`、无括号值；展开后按`short` 渲染                                |
| 2  | 观测模式 +`none` 信息级别              | 星等`--`；展开后几乎空卡——与信息级别语义一致                                 |
| 3  | 观测模式 + custom 且关掉星等/距离/星座 | 对应 tag`--`（不绕过掩码）                                                     |
| 4  | 目标无`vmage`（卫星/星座/深空天体）    | 无括号值，label 回退 `星等`，仅显示主星等                                                           |
| 5  | 展开后切换选中目标                     | 卡片回到极简形态（`observeExpanded` 随 `targetChanged` 重置）                  |
| 6  | 展开后点关闭再重选同一目标             | 沿用`dismissedObjectName` 不重弹逻辑；重弹时为极简形态                         |
| 7  | 模式切换时卡片正开着                   | 立即重渲染（观测→天文馆：全量卡；天文馆→观测：极简卡）                       |
| 8  | 指向线（connector）                    | 几何锚点随卡片高度变化自然适配                                                 |
| 9  | 三壳层（手机/平板/悬停观测台）         | 均支持两模式                                                                   |
| 10 | preferences 读失败                     | 回退`'planetarium'`                                                            |
| 11 | 居中按钮无选中目标时                   | 按钮行不渲染（`hasSelectedObject === false` 时卡片本身也不可见，无影响）       |
| 12 | 快捷面板卫星按钮被替换后               | 卫星图层开关仍可通过图层面板操作；`quickToggle` 中卫星分支保留，仅默认列表不含 |

## 10. 实施顺序

1. **P0 — 状态轴与卡片分支**：`InfoWindowStore` 字段/方法 → `ObjectDetailStore` 星等拼接助手 → `ObjectDetailCardHeader` + `UnifiedObjectDetailCard` 分支渲染 + 按钮行 → 宿主下发 + 居中接线 → 手动验证；
2. **P1 — 快捷面板入口**：`quickActions.ets` 替换卫星项 → 宿主 `quickToggle` 新分支 + 开关值映射 → preferences 持久化 + 启动恢复；
3. **P2 — 设置入口**：SettingsPanel Toggle + 说明文案 → 宿主接线；
4. **P3 — 收尾**：展开/收起动画（`Curve.EaseInOut` 180ms）、契约登记、I18n 全语言补齐、CHANGELOG。

## 11. 验收标准

1. 快捷面板（观测模式开关格）与设置-信息页 Toggle 均可切换模式，两入口状态实时同步；切换不产生桥调用（hilog 无 `setInformationSetting`）；
2. 观测模式：选星后卡片仅显示页头 + 三 tag + 居中/展开按钮行；星等 tag 为**两行**（标签 + 单行数值）——标签 `星等(大气消光)`、数值横向一行 `0.03(0.19)`（括号内为消光后星等，仅 all/default/custom 级别；不可用时回退 `星等` / `0.03`）；
3. 居中按钮点击后视角移至选中天体（等价 ActionsTab 居中操作）；
4. 展开按钮 → 全量卡按当前信息级别渲染；收起 → 回到极简卡；切换目标后自动回到极简卡；
5. 信息级别五按钮选中态与观测模式开关互不影响（`观测 + 自定义` 等组合正常）；
6. 重启应用后 `detailDisplayMode` 保持（preferences 持久化）；
7. custom 模式关掉星等/星座/距离时，观测模式对应 tag 显示 `--`；
8. 快捷面板 2×6 布局不变，卫星功能仍可通过图层面板操作；
9. `check-ohos-ui-contract.mjs` 全绿；`arkts_check` + `devecocli build` 通过；真机走查。

## 12. 实施记录（2026-10-07）

### 12.1 落地范围

按 §10 的 P0→P3 顺序一次做完，**零 C++ 改动**，落点与 §8.1 一致（`InfoWindowStore` / `ObjectDetailCardChrome` /
`UnifiedObjectDetailCard` / `ObjectDetailStore` / `quickActions` / `SettingsPanel` / 宿主 / `I18n`），
另外三处壳层（`CompactShell` / `ExpandedShell` / `HoverObservatoryShell`）各透传 2 个 `@Prop` + 3 个回调。

### 12.2 与设计的差异（均已按实际实现修正）

1. **`minimal_hud` 占位被本特性取代。** 二期为「极简 HUD」预留的快捷面板占位项（`minimal_hud` /
   `quick_minimal_hud` / `OverlayStore.minimalHud` / `bt_minimal_hud.png`）就是本设计所描述的能力，
   故全部并入本特性并清理：池项改为 `observe_mode`，图标文件 `git mv` 为 `bt_observe_mode.png`，
   I18n 键换成 `detail_mode_observe` 一族，`OverlayStore.minimalHud` 删除。
2. **卫星项是「移出默认 12 格」而非删除。** §5/§8.1 要求替换第 10 格并保留卫星开关；三期已有自定义面板，
   因此卫星项**留在池尾**（`quickActionPool` 第 17 项）：默认网格不含它，但用户可在编辑态把它拖回。
   池仍 17 项，候选带仍 1 行（`quickCandidateSlotsFor` 的 2 行上限未触及）。
   副作用：已持久化过自定义顺序的旧安装会保留自己的顺序（含卫星格），需自行把「观测模式」拖入 ——
   这是既有「自定义顺序优先」语义的必然结果，仅对**手动提交过**顺序的用户可见。
3. **§9 边界 4 的前提有误。** `vmage` 是否存在只取决于「目标有星等 + 有气团质量」，与天体类型无关：
   实测 M31 同样返回 `apparentMagnitude`，观测模式显示 `4.36(4.41)` 形态的括号值。
   真正回退成单值 `星等` 的是：`short` / `none` 信息级别（`showObservedInfo = infoLevel <= 1` 门控了
   `selectedApparentMagnitude`）、custom 掩码关掉星等、以及星座等无星等目标。规格正文的边界表按此理解即可。
4. **新增 3 个 `.id()` 锚点并重生成契约基线**（§8.3 建议项）：
   `object-detail-observe-center` / `object-detail-observe-expand` / `object-detail-observe-collapse`。
   契约计数 34 面板 / 26→**29** 静态 id / 18 前缀 / 47→**50** 锚点；既有锚点零改名零删除。

### 12.3 真机走查结果（HUAWEI Mate 80 Pro，`192.168.3.95`）

| 项 | 结果 |
| ---- | ---- |
| 全新安装默认网格第 10 格 | `quick-action-observe_mode` ✓（`satellites` 不在默认网格） |
| 观测模式选星（织女一 Vega，vmag 0.03 / vmage 0.22 / extinction 0.19） | 页头（聚焦圈图标 + 名称 + 类型 + ✕）+ `星等(大气消光)` `0.03(0.22)` + 星座 + 距离 + 卡片下沿中央的向下箭头；实时行、实时块、页签栏、滚动区全部不渲染，且**不画指向线** ✓ |
| 「展开」 | 实时高度/方位 + 四个页签回归，下沿箭头翻转为向上 ✓；点向上箭头收回极简 ✓ |
| 展开后切换目标（Vega → 天狼星） | 自动回到极简形态 ✓（`targetChanged` → `resetObserveExpand`） |
| 快捷面板切回天文馆 | 卡片**立即**变全量；`hilog` 统计 `setInformationSetting` = 0 次，`infoMode` 仍为 `all` ✓（两轴正交） |
| 天文馆模式页头星等 tag | `星等` / `0.03` 单值，与改造前逐字一致 ✓ |
| 设置-信息页 | 「极简观测模式」开关行 + 说明文案在位；打开后卡片立即转极简，与快捷面板同一字段 ✓ |
| `short` 信息级别 + 观测模式 | 标签回退 `星等`、值 `0.03`（无括号）、距离 `--` ✓ |
| 杀进程重启 | 仍是观测模式 ✓（`stellarium_info_window` / key `detailDisplayMode`） |

极简卡高度按内容定：`26（拖拽柄）+ 52（标题行）+ 56（三 tag 行）+ 28（下沿箭头条）= 162vp`，
与实测渲染一致（无空底、无用例要求的「更小 cardHeight」）。

### 12.5 布局细化（同日按用户反馈修订，取代 §4.2 的按钮行）

初版把「居中」与「展开」做成卡片底部一行左右两个按钮（§4.2）。用户反馈：两个按钮都被 `padding` 顶在
卡片左右边缘、太靠边；且「收起」在页头而「展开」在卡片底部，隔了一整张卡。据此改为：

| 动作 | 初版 | 现在 |
| ---- | ---- | ---- |
| 居中 | 底部按钮行左侧 `◎ 居中` | **标题栏最左侧天体类型图标上的「取景器式聚焦圈」**：圆环 + 左上/右上/左下/右下四条斜向短线，点圈即居中。天文馆模式仍是原来的裸图标（零变化） |
| 展开 | 底部按钮行右侧 `展开 ⤢` | **卡片下沿正中一个向下大箭头**（行高 28、占满卡宽，触控区很大） |
| 收起 | 页头 ✕ 左侧的文字按钮「收起」 | **同一个下沿箭头翻转为向上** —— 展开与收回复用同一处，距离问题消失 |

- 观测模式下**按钮行整体删除**：页头只剩「拖拽柄 + 标题行 + 三 tag」，下沿只有箭头，比初版更极简。
- 聚焦圈画法沿用既有原语（`Row` + `backgroundColor` + `rotate`），不引入 `Shape`/`Path`，也不新增资源；
  36×36 框、圆心 (18,18)、圆环外径 26（r=13），短线 r 13.5→17.5、45° 投影 0.7071×15.5≈10.96。
- **极简模式不再绘制指向线**（用户要求）。宿主下发的 `connectorVisible` 加 `&& !observeCompact()`；
  **只拦渲染不拦计算**：卡片纵向位置仍由 `detailConnectorCtl().objectDetailCardY()` 决定。
  反向对照不易复现 —— 全量卡高约 420vp 正好盖住目标标记，能看见连线的场景本就只有极简态。
- 星等 tag 的判定由「是否展开」改为「是否观测模式」：展开态页头也保持两值格式，页头形态与展开态解耦
  （展开只改卡体：页签栏 + 滚动区），卡体内容仍按信息级别渲染。
- 三个 `.id()` 锚点随控件搬迁，**数量与名称不变**，故契约仍 50/34/29/18，无需 `--update`。

### 12.6 第二轮细化（同日再按用户反馈修订，取代 §4.3 / §4.4 的星等 tag 设计）

| 项 | 上一版 | 现在 |
| ---- | ---- | ---- |
| 页头三格 | 星等(大气消光) `0.03(0.22)` / 星座 / 距离 | **星等 `0.03` / 大气消光后星等 `0.18` / 星座 `天琴座`** —— 去掉距离，消光后星等从「括号拼一格」升为**独立一格** |
| 下沿箭头条 | 44vp（与返回按钮同盒） | **28vp**（`ic_back` 雪佛龙样式不变，只收盒子）；极简卡高 178 → 162vp |
| 浮窗位置 | 手机基础 Y `max(86, min(126, skyHeight*0.12))` | **安全区顶部** `scriptControlSafeTop()`（= `EDGE_MARGIN` 44vp）；平板展开态分支不变 |
| 状态提示条 | 点星「已选中 XX」、双击「未选中天体」、开面板「已打开面板」 | 全部删除；**错误 / 失败提示保留**（如空处点选「这里没有天体」） |

- 因此 `ObjectDetailStore.observeMagnitudeLabel/observeMagnitudeValue` 两个拼接助手删除，I18n 键
  `detail_observe_magnitude`（"星等(大气消光)"）替换为 `detail_observe_extinction_magnitude`
  （"大气消光后星等"）；§4.3 的「括号内 = 消光后星等」写法作废。
- 天文馆模式页头三格**零变化**（星等 / 星座 / 距离），§4.3 末尾「天文馆维持单值现状」仍然成立。
- 真机复核：卡片顶边上提到 ~44–58vp；三格读数为 `0.03 / 0.18 / 天琴座`；点星与点 Dock 均无状态提示条。

### 12.7 连接线在观测模式下彻底关闭（同日再按用户要求修订 §4.2 / 边界 8）

§12.5 只在**极简态**关掉了指向线；用户随后要求**展开态也一样不画**。故下发三壳层的 `connectorVisible`
改为 `overlayStore.objectDetailConnectorVisible && !infoWindowStore.observeModeEnabled()`：

| 形态 | 指向线 |
| ---- | ---- |
| 观测模式 · 极简 | 不画 |
| 观测模式 · 展开 | **不画**（本次修订） |
| 天文馆模式 | 照旧，仍由「设置 > 信息 > 详情卡指向线」开关控制 |

仍然只拦渲染不拦计算（`detailConnectorCtl().objectDetailCardY()` 继续负责卡片纵向位置）；
`getObjectDetailConnector` 报的仍是**设置值**，不受呈现轴影响。§4.2 的「按钮行」与边界 8 的
「几何锚点随卡片高度变化自然适配」只在天文馆模式下适用。

### 12.4 护栏

`arkts_check` 0 error；`devecocli build` SUCCESSFUL；`check-ohos-ui-contract.mjs` intact；
`check-ohos-i18n.mjs` 0 error（新键 10 语言）；`check-ohos-command-catalog.mjs` 358 命令一致；
`test-ohos-information-policy` / `test-ohos-detail-live-values` / `test-ohos-distance-ui` /
`verify-ohos-object-details` / `test-ohos-satellite-panel` 全部通过。
本轮改动文件按仓库约定统一 CRLF（`docs/harmonyos/**`、`harmonyos/ets-source/**`）。
