# 夜间模式主题架构

> 机制四：`WithTheme(Stellarium CustomTheme) → onWillApplyTheme → ThemeSlots`

## 1. 概述

夜间模式主题系统用 ArkUI 原生主题传播机制替换了两层暴力遮罩（zIndex 98 红色 `BlendMode.COLOR` + zIndex 99 黑色压暗）。所有面板、遮罩、壳层与公共 UI 组件仅从 `ThemeSlots` 读取主题色；组件内不得出现主题色字面量。天文可视化固定色集中到 `AstroColors`。

### 设计目标

- 唯一主题切换入口：页面根节点 `WithTheme`
- 颜色零穿透：`onWillApplyTheme` 自动传播
- 唯一颜色来源：`state/StellariumTheme.ets`
- 干净分离：UI 主题令牌（ThemeSlots）vs. 科学固定色（AstroColors）

### 非目标

- 修改 C++ 引擎星空红色渲染
- 修改 `MainWindowModels.ets`、`derive/astro.ets`、`derive/media.ets` 中的天文数据可视化颜色
- 新增功能

## 2. 架构

### 2.1 调用链

```
MainWindowNativeNode.build()
  └─ WithTheme({ theme: stellariumTheme(this.nightModeStore.nightMode) })
       └─ 任意 @Component
            onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }
            build() { .fontColor(this.c.text) ... }
```

- **唯一切换入口**：`pages/MainWindowNativeNode.ets` 在根部包 `WithTheme`，键为 `nightModeStore.nightMode`。
- 主题变化时 ArkUI 重新下发 `Theme`，所有声明了 `onWillApplyTheme` 的组件自动刷新，**无需任何父组件参与**。
- 组件不得再接收颜色 `@Prop`，宿主不得再注入颜色参数。

### 2.2 主题定义（`state/StellariumTheme.ets`）

| 符号 | 作用 |
|---|---|
| `StellariumDayColors implements CustomColors` | 日间令牌，54 个 |
| `StellariumNightColors implements CustomColors` | 夜间令牌，54 个（必须与日间同名同数量） |
| `StellariumCustomTheme implements CustomTheme` | 包装 `CustomColors` |
| `stellariumTheme(nightMode): CustomTheme` | 宿主 `WithTheme` 使用的工厂 |
| `ThemeSlots`（55 字段） | **组件唯一取色类型** |
| `DEFAULT_SLOTS`（55 值，日间） | 首帧兜底 |
| `slotsFromTheme(theme): ThemeSlots` | `Theme.colors` → 槽位；所有字段带 `?? DEFAULT_SLOTS.x` 兜底 |
| `accentForNightMode(nightMode): string` | 宿主回调（非组件）取强调色 |
| `AstroColors`（24+ 常量） | 天文可视化固定色 |

> `CustomColors` 成员在 SDK 中是可选属性，因此 `slotsFromTheme` 必须逐字段 `?? DEFAULT_SLOTS.x`，否则编译报 `ResourceColor | undefined`。

### 2.3 组件标准改造模板

```typescript
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

@Component
export struct XxxPanel {
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Text('...')
      .fontColor(this.c.text)
      .backgroundColor(this.c.bg)
      .border({ width: 1, color: this.c.border })
  }
}
```

改造步骤：

1. 引入 `Theme`（来自 `@kit.ArkUI`）与 `ThemeSlots`/`DEFAULT_SLOTS`/`slotsFromTheme`。
2. 声明 `@State private c: ThemeSlots = DEFAULT_SLOTS`（必须是 `@State`，否则换主题不重绘）。
3. 实现 `onWillApplyTheme`。
4. 删除该组件的所有颜色 `@Prop`，把内部引用改为 `this.c.xxx`。
5. 删除**全部实例化点**的颜色参数注入（含宿主与中间层组件）。
6. 若组件原本不需要 `nightModeStore`，不要新增该 prop。

## 3. ThemeSlots 字段总表（55）

### 文本组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `text` | `fontPrimary` | 主文本 |
| `textStrong` | `fontEmphasize` | 强调文本 |
| `sub` | `fontSecondary` | 辅助文本 |
| `tertiary` | `fontTertiary` | 三级标签 |
| `fourth` | `fontFourth` | 四级值 |
| `detailSub` | `fontOnFourth` | 详情子值 |
| `onAccent` | `fontOnPrimary` | 强调色上的文本 |
| `errorText` | `fontOnSecondary` | 错误文本 |

### 图标组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `icon` | `iconPrimary` | 主图标 |
| `iconSecondary` | `iconSecondary` | 次图标 |
| `iconTertiary` | `iconTertiary` | 三级图标（芯片未选中） |
| `disabled` | `iconOnTertiary` | 禁用态 |

### 强调组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `accent` | `backgroundEmphasize` | 强调/选中 |
| `accentSoft` | `compEmphasizeTertiary` | 强调弱背景 |
| `dockActive` | `iconSubEmphasize` | Dock 激活 |
| `hintPillBg` | `compEmphasizeSecondary` | 提示药丸底 |

### 背景组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `bg` | `compBackgroundTertiary` | 通用浅底 |
| `bgStrong` | `compBackgroundSecondary` | 较强底 |
| `rowBg` | `backgroundFourth` | 菜单行底 |
| `soft` | `backgroundSecondary` | 柔和底 |
| `softStrong` | `compBackgroundPrimaryTran` | 柔和底（强） |
| `input` | `compBackgroundPrimary` | 输入框底 |
| `mediaCard` | `backgroundPrimary` | 媒体卡片底 |

### 边框/分隔组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `border` | `compDivider` | 通用边框 |
| `dividerSoft` | `interactivePressed` | 弱分隔线 |
| `inputBorder` | `interactiveFocus` | 输入边框 |

### 芯片/控件组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `chipActiveBg` | `compBackgroundEmphasize` | 选中芯片底 |
| `chipInactiveBg` | `interactiveHover` | 未选中芯片底 |
| `chipActiveBorder` | `compFocusedPrimary` | 选中芯片边 |
| `chipInactiveBorder` | `compFocusedSecondary` | 未选中芯片边 |
| `chipInactiveText` | `compCommonContrary` | 未选中芯片文本 |
| `thumbBg` | `iconOnFourth` | 滑杆滑块 |
| `scrollbar` | `compForegroundPrimary` | 滚动条 |

### 状态组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `success` | `confirm` | 成功 |
| `warning` | `warning` | 警告 |
| `error` | `alert` | 错误 |
| `errorBg` | `interactiveSelect` | 错误底 |
| `warningBg` | `iconEmphasize` | 警告底 |
| `actionPositive` | `compBackgroundFocus` | 正向操作 |
| `actionLoad` | `iconOnPrimary` | 加载操作 |
| `actionShare` | `iconOnSecondary` | 分享操作 |
| `actionConfirm` | `fontOnTertiary` | 确认操作 |

### 遮罩/媒体组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `overlayScrim` | `compBackgroundPrimaryContrary` | 全屏遮罩底 |
| `overlayPanel` | `compBackgroundGray` | 遮罩面板 |
| `overlayButton` | `interactiveActive` | 遮罩按钮 |
| `panelGlass` | `backgroundTertiary` | 面板空闲玻璃底（宿主） |
| `panelGlassStrong` | `compBackgroundGray` | 面板常态玻璃底（宿主） |
| `mediaOverlay` | `backgroundTertiary` | 媒体叠层 |
| `mediaLabelBar` | `primary` | 媒体标签条 |
| `mediaButton` | `onPrimary` | 媒体按钮 |

### 装饰组

| 槽位 | CustomColors 令牌 | 语义 |
|---|---|---|
| `shadowSoft` | `interactiveClick` | 柔和阴影 |
| `dragHandle` | `compBackgroundNeutral` | 拖拽把手 |
| `ringStroke` | `brand` | 圆环描边 |
| `badgePurple` | `container` | 紫色徽标 |
| `spinner` | `iconFourth` | 加载指示 |

> `compFocusedTertiary` 当前未被任何槽位使用；新增槽位时优先复用未用令牌。

### 特殊槽位

| 槽位 | 语义 |
|---|---|
| `isNight` | 布尔值：夜间模式为 `true`；用于图标资产选择 |
| `metricValue` | 详情参数值颜色（日间 `#E7F7FF`，夜间 `#F00000`） |

## 4. AstroColors（固定色）

24 个基础常量用于天文可视化元素，日/夜恒定：

`ringFill` / `ringStroke` / `cometTail` / `cometCore` / `cometIcon` / `asteroidFill` / `asteroidStroke` / `asteroidIcon` / `crater` / `galaxyFill` / `galaxyStroke` / `galaxyCore` / `galaxyIcon` / `clusterFill` / `clusterPoint` / `clusterIcon` / `nebulaFill` / `nebulaIcon` / `constellationIcon` / `satelliteIcon` / `moonIcon` / `solar` / `solarDim` / `solarText`

扩展常量（状态 store 与表单控件）：

`cultureLine` / `cultureLabel` / `cultureZodiac` / `cultureLunar` / `gyroPending` / `gyroEnabled` / `gyroIdle` / `starPoint` / `altitudeFaded`

### 规则

- 仅用于天体图形、行星轨道、月球/彗星/小行星/星系/星团/星云图标、太阳金色、星表线条等**科学可视化**元素。
- 日间 = 夜间恒定；不得用于面板 UI（文本、背景、边框、按钮）。
- 新增常量必须写明用途。
- 当前消费者：`panels/astro/AstroPanel.ets`、`panels/object/TabletInspectorMedia.ets`、`form/AstronomyCardSurface.ets`、各状态 store。

## 5. 宿主层规则

- 宿主唯一职责：在根部包 `WithTheme`，键为 `nightModeStore.nightMode`。
- 宿主自身的直属 UI（面板玻璃底、状态药丸等）**不通过 `onWillApplyTheme` 取色**——`WithTheme` 只作用于子树，宿主收到的是祖先主题。宿主改用：
  - `nightModeStore.nightMode` 做二选一（如 `SkyCultureArtPreview` 边框），或
  - `accentForNightMode(nightMode)` 取强调色（当前用于 `hecPointColor` 回调）。
- 宿主不得向子组件传递颜色，也不得再传 `nightModeStore`（除非子组件确实还需要 `nightMode` 布尔值）。
- 宿主直属 UI 的剩余硬编码应优先扩展 `ThemeSlots` + `slotsForNightMode` 辅助，而不是继续写三元字面量。

## 6. 夜间模式切换路径

夜间模式开关必须走专用路径：

```
UI 开关 → LayerController.applyNightMode → NightModeStore.applyNightMode
        → 引擎命令 "setNightMode"
        → C++ QAction "actionShow_Night_Mode" setChecked
        → StelApp visionModeNight 属性同步
        → NightModeStore.syncNightModeFromEngine（回执确认）
```

- `LayerController.applyNightMode` 将 `actionShow_Night_Mode` 分流到专用 `applyNightMode` 钩子，**不走**普通 `setLayer` 命令。
- `setNightMode` C++ 实现优先走 `actionShow_Night_Mode->setChecked(on)`，使 QAction 与 `StelApp` 属性始终一致。
- `NightModeStore.applyNightMode` 使用 `requestInteractive` + 失败自动重试一次；用回执里的 `night` 直接回写 store。
- Pending 保护窗口：1 秒（防止旧 `getState` 回包覆盖本地状态）。

## 7. 设置持久化（OHOS 桥接）

从 OHOS UI 切换的引擎标志位 setter 必须调用 `StelApp::immediateSave()` 将变更立即写入 `config.ini`，无需等待应用退后台：

| C++ setter | 配置键 | 说明 |
|---|---|---|
| `NebulaMgr::setFlagHints` | `astro/flag_nebula_name` | 星云标注开关 |
| `NebulaMgr::setFlagShow` | `astro/flag_nebula` | 星云可见开关 |
| `SporadicMeteorMgr::setFlagShow` | `astro/flag_meteor` | 流星渲染开关 |
| `StelSkyCultureMgr::setFlagOverrideUseCommonNames` | `viewing/flag_skyculture_always_fallback_to_international_names` | 常用名覆盖 |
| `MeteorShowersMgr::saveSettings` | （多个键） | 移至 public 供 OHOS 桥接调用 |

模式：`if (oldValue != newValue) { field = newValue; StelApp::immediateSave("key", newValue); emit signal(); }`

## 8. 禁止事项与已知陷阱

1. **禁止**新增 `nightModeStore.nm*()` 调用或 `@StorageProp('stellariumNightMode')` 消费者。
2. **禁止**在组件内写主题色字面量（例外：`StellariumTheme.ets`、`NightModeStore.ets`、`AstroColors`、3 个科学固定色文件）。
3. **禁止**颜色 `@Prop`（当前为 0；不要回退）。
4. **禁止**在 `stateStyles` 里用属性赋值形式引用组件颜色：
   ```typescript
   // ❌ ets-loader 崩溃：Node must have a real position
   .stateStyles({ pressed: { backgroundColor: this.c.rowBg } })
   // ✅
   .stateStyles({ pressed: { .backgroundColor(this.c.rowBg) } })
   ```
5. **禁止** `any` / `unknown` / `as` 断言 / 动态 key 取色 / 结构化类型。
6. `CustomColors` 成员可选 → 新槽位必须写 `?? DEFAULT_SLOTS.x`。
7. **禁止**向子组件传宿主 `@Builder`（真机退出）。
8. **禁止**改动 `.id()` 字串锚点（跨会话契约）。
9. **禁止**用 PowerShell `Get-Content/Set-Content` 编辑 `.ets`（UTF-8 → GBK 二次编码会不可逆损坏中文注释）；一律使用 `edit` 工具。
10. 构建前**必须**先镜像源码（见 §9），否则 hvigor 编译的是旧副本。
11. Toggle 拨杆与 Slider 滑块的默认色令牌是 **`compBackgroundPrimaryContrary`**：日间 `#E5FFFFFF`、夜间中红 `#A03020`；`overlayScrim` 不得映射到该令牌，改用 `compBackgroundGray`。
12. **背景为 `c.accent` 时，选中文字必须用 `c.onAccent`**；`c.textStrong` 夜间为 `#FF2222`，会与亮红背景同色。
13. `@Styles`/`@Extend` 不支持跨文件导出；`AttributeModifier` 仍需逐实例绑定。组件默认色只能通过 `CustomColors` 令牌统一。
14. 快捷开关非触发态图标与 Dock 非激活态一致：`c.icon` + `opacity(0.78)`；raster 的 `tintMatrixFor` 必须取 `#AARRGGBB` 的**末 6 位** RGB。
15. 夜间模式开关必须走 `LayerController.applyNightMode` → `NightModeStore.applyNightMode`，**不得**走普通图层 `setLayer` 命令。

## 9. 构建与验证

```powershell
# 1) 把 harmonyos/ets-source 镜像到 build/libstellarium-harmonyos/entry/src/main/ets
& "C:\Program Files\Git\bin\bash.exe" -lc "cd /e/code/Stellarium-mobile/stellarium && bash scripts/sync-ohos-build-sources.sh"

# 2) 在生成的 hvigor 工程里编译
devecocli build   # workdir = build\libstellarium-harmonyos
```

### 验证矩阵

| 检查项 | 时机 | 方式 |
|---|---|---|
| `arkts_check` | 每轮编辑后、构建前 | 对本轮全部改动 `.ets` 一次调用 |
| 源码镜像 | 每次构建前 | `scripts/sync-ohos-build-sources.sh` |
| `devecocli build` | 每切片 | `workdir=build/libstellarium-harmonyos` |
| UI 契约 | G/H 收尾 | `node scripts/check-ohos-ui-contract.mjs` |
| 硬编码扫描 | G/H 收尾 | 三模式（含 8 位 hex） |
| 颜色 prop 归零 | 持续 | `@Prop .*(Color|Bg|Border|Tint)` = 0 |
| `nm*()` 归零 | 持续 | `nightModeStore.nm[A-Z]` = 0 |
| 日间回归 | 每切片 | 重点位点人工确认 |
| 夜间可读性 | 每切片 | 开关夜间模式逐面板检查 |

### 审计命令

```powershell
$root = "harmonyos/ets-source"

# 1) 仍未迁移的组件（使用 this.c 但无 onWillApplyTheme）
Get-ChildItem $root -Recurse -Filter *.ets |
  Select-String -Pattern "this\.c\." |
  Select-Object -ExpandProperty Path -Unique

# 2) 硬编码颜色（排除主题/科学固定色）
Get-ChildItem $root -Recurse -Filter *.ets |
  Select-String -Pattern "'#[0-9A-Fa-f]{6,8}'|'rgba\(" |
  Where-Object { $_.Path -notmatch "StellariumTheme|NightModeStore|MainWindowModels|derive\\astro|derive\\media" }

# 3) 禁止回退项
Get-ChildItem $root -Recurse -Filter *.ets |
  Select-String -Pattern "nightModeStore\.nm[A-Z]|@StorageProp\('stellariumNightMode'\)|@Prop\s+\w*(Color|Bg|Border|Tint)"

# 4) stateStyles 崩溃写法
Get-ChildItem $root -Recurse -Filter *.ets |
  Select-String -Pattern "pressed:\s*\{\s*[A-Za-z_]+\s*:"
```

## 10. 风险与兼容性

- **`WithTheme` 缺失**：子树收不到 `stellariumTheme`，`onWillApplyTheme` 下发系统主题或不下发；组件回退 `DEFAULT_SLOTS`（日间色），夜间表现为亮色。根部 `WithTheme` 必须保留。
- **`@State c` 非响应式**：漏写 `@State` 会导致切换主题后不重绘。
- **首帧闪烁**：`DEFAULT_SLOTS` 是日间值；夜间冷启动时组件首帧可能先显示日间色，随后由 `onWillApplyTheme` 纠正。
- **`CustomColors` 可选成员**：新增槽位忘记 `??` 会编译失败。
- **`stateStyles` 属性赋值**：见 §8 第 4 条，ets-loader 会崩溃且不给文件位置。
- **宿主与子树主题不同源**：宿主直属 UI 不能用 `this.c`（自身 `onWillApplyTheme` 收到的是祖先主题），必须用 `nightModeStore.nightMode` 派生。
- **切换动画**：旧遮罩 450ms 渐变；机制四为瞬时换色。如需平滑过渡，可在切换入口用 `animateTo` 包裹（不阻塞）。
- **性能**：主题切换时整棵子树重绘是预期行为（原遮罩层也是全屏重绘）。

## 11. 回滚

- 如夜间模式严重不可用，可从 git 历史恢复 `MainWindowNativeNode` zIndex 98/99 遮罩层作为临时兜底。
