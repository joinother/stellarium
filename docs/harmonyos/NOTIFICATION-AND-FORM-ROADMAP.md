# 天文通知与桌面卡片预研

## 目标

本预研覆盖两类 HarmonyOS 原生能力：

1. 天文事件通知：月相、日月食、流星雨、关注卫星过境和观测目标升起提醒。
2. 桌面服务卡片：月相月历、今晚可见行星、下一次重要天象倒计时，以及后续的关注卫星过境和离线专题内容。

参考界面的有效设计要点是“先给结论，再给天文细节”：月相月历以日期网格直接展示月面和月相名称；近期天文事件按时间排序，使用图片、事件类型、可见性、地点和发生时间组成紧凑列表。鸿蒙端不照搬截图的固定尺寸，而是在手机、平板和 PC/2in1 上使用同一份数据契约和响应式组件。

本轮只形成离线架构、原生能力边界和数据契约，不注册新的 Ability、不声明代理提醒权限、不修改签名配置。

## 华为官方能力结论

以下结论通过华为开发知识 MCP `harmonyos_developer_knowledge` 检索并读取官方文档确认。

### Notification Kit

- 应用通知默认未授权。只有用户主动开启某类天文提醒时，才调用 `isNotificationEnabled()` 检查状态，并在需要时调用 `requestEnableNotification(context)`。
- 用户拒绝授权后，不应在每次进入页面时反复弹出首次授权框；后续由用户主动点击“前往系统通知设置”再进入系统设置。
- 普通通知适合应用进程运行时的即时提示和提醒预览，不能被当作进程退出后的可靠定时任务系统。
- 通知点击行为使用 WantAgent 返回 `QAbility`，并携带事件、天体、模拟时间和目标页面参数。
- 本项目不接入 Push Kit。当前未备案、离线优先版本不使用远程推送服务器，也不上传位置、关注目标或设备标识。

官方文档：

- [Notification Kit简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-overview)
- [请求通知授权](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-enable)
- [发布文本类型通知](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/text-notification)
- [为通知添加行为意图](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-with-wantagent)

### 后台代理提醒

- `reminderAgentManager` 可以把日历、闹钟或倒计时提醒交给系统代理，因此应用被冻结或进程终止后仍可触发。
- 发布代理提醒前仍然必须先取得通知授权。
- 需要声明 `ohos.permission.PUBLISH_AGENT_REMINDER`，并在 AGC“项目设置 → 开放能力管理”中申请“代理提醒”。官方文档说明审核约需 8 个工作日。
- 开放能力审批后必须重新生成 Profile 并使用包含该能力的 Profile 签名。没有完成审批和 Profile 更新前，不得把普通前台通知描述为可靠后台提醒。
- API 26 起普通应用最多保留 64 个有效代理提醒，API 25 及以下最多 30 个，因此必须采用滚动时间窗口，不一次注册全部未来事件。
- 代理提醒不得用于广告或营销。天文提醒必须由用户主动订阅，并允许按类别关闭、查看下一次触发时间和批量清除。

官方文档：

- [代理提醒](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder)
- [reminderAgentManager API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-reminderagentmanager)

### Form Kit

- 服务卡片需要原生 ArkTS `FormExtensionAbility`、卡片页面、`form_config.json` 和 `module.json5` 中的 `extensionAbilities` 配置。
- 卡片扩展的 metadata 名称固定为 `ohos.extension.form`。
- 首批尺寸使用 `2*4` 和 `4*4`，可补充 `2*2`。卡片组件根据实际宽高重排，不为手机、平板和 PC/2in1 分裂三套业务逻辑。
- `updateDuration` 的单位是 30 分钟；`setFormNextRefreshTime()` 的最短间隔为 5 分钟；每张卡片每天定时刷新最多 50 次。
- 首次定时刷新可能存在系统调度偏差，因此“倒计时”展示的是快照生成时计算的剩余时间和明确的更新时间，不承诺逐分钟精确跳变。
- `postCardAction` 的 `router`、`message` 或 `call` 事件可进入应用或通知卡片扩展处理用户操作。
- API 18 起可通过 `formProvider.openFormManager(want)` 在应用内打开系统“添加到桌面”页面。
- 动态卡片应保持轻量。卡片进程不得初始化 Qt、OpenGL 星图或完整 Stellarium 核心。

官方文档：

- [创建ArkTS卡片](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-creation)
- [配置ArkTS卡片的配置文件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-configuration)
- [ArkTS卡片被动刷新](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-passive-refresh)
- [ArkTS卡片主动刷新](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-active-refresh)
- [在应用内将ArkTS卡片添加到桌面](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-open-formmanager)
- [ArkTS卡片交互事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-event-router)

## 当前仓库能力审计

### 已有数据来源

现有 C++ 命令桥已经覆盖首批通知和卡片所需的大部分离线计算：

| 命令 | 可复用数据 |
| --- | --- |
| `getTonightEvents` | 今晚月相、日月升落、暮光、行星和流星雨摘要 |
| `getMoonPhases` | 未来月相序列和月相日历 |
| `getEclipses` | 未来日食、月食及可见性信息 |
| `getMeteorShowers` | 内置流星雨活动和峰值信息 |
| `getSatellites` | 内置 TLE 对应卫星及数据有效期状态 |
| `getAlmanac` | 太阳、月球升起、中天、落下和暮光 |
| `getPlanetTimeSeries` | 行星可见性与随时间变化的数据 |
| `getRTS` / `getRTSCalendar` | 选中天体的升起、中天和落下 |

### 当前缺口

- `harmonyos/module.json5` 当前只有 `QAbility`，没有 `FormExtensionAbility`。
- 当前没有 `form_config.json`、卡片页面或卡片本地化资源。
- 当前没有通知授权入口、提醒规则存储、提醒预览和提醒调度器。
- 当前没有面向卡片的轻量 JSON 快照，也没有快照过期、位置变化和数据源版本状态。
- Qt 核心初始化存在严格隐私时序要求，因此卡片和通知扩展不能直接复用 `QAbility` 的 Qt 启动流程。

## 统一离线架构

```text
用户在主应用设置规则或刷新卡片
            │
            ▼
QAbility 已取得隐私同意并完成 Qt 初始化
            │
            ▼
现有 C++ 命令计算未来 30～90 天天象
            │
            ▼
ArkTS 规范化、去重、排序并原子写入 JSON 快照
       ┌────┴──────────┐
       ▼               ▼
提醒调度器          FormExtensionAbility
注册滚动窗口        仅读取轻量快照
       │               │
       ▼               ▼
系统代理提醒        桌面服务卡片
```

关键约束：

- 所有天文计算在主应用已经合法初始化后执行；通知和卡片扩展不初始化 Qt。
- 快照先写临时文件，再原子替换正式文件，避免卡片读取半写入 JSON。
- 快照包含 `generatedAt`、`validUntil`、位置、时区、数据源版本和过期原因。
- 无快照时卡片显示“打开应用准备天文数据”；快照过期时继续展示最后结果，同时明确标注“数据已过期”。
- 位置或时区变化、系统时间变化、TLE/星表更新、用户规则变化、应用升级后，主应用重新计算快照和提醒窗口。
- 太阳活动没有可靠的随包实时数据来源，离线版不得显示“实时太阳活动”。未来若开放联网，必须先登记到 `NETWORK-INVENTORY.md` 并设计国内镜像和隐私边界。

## 数据契约

契约应放在独立 ArkTS 文件中，由主应用、卡片和 CLI 共用。以下字段是预研基线，实施时可增加字段，但不能改变既有字段含义。

```ts
export type AstronomyEventKind =
  'moon-phase' | 'solar-eclipse' | 'lunar-eclipse' |
  'meteor-shower' | 'satellite-pass' | 'object-rise' |
  'planet-visibility';

export interface AstronomyNotificationRule {
  id: string;
  enabled: boolean;
  kind: AstronomyEventKind;
  leadMinutes: number[];
  quietHoursStart?: string;
  quietHoursEnd?: string;
  minimumAltitudeDeg?: number;
  minimumVisibilityScore?: number;
  targetIds?: string[];
  locationId: string;
  updatedAt: string;
}

export interface AstronomyEventSnapshot {
  id: string;
  kind: AstronomyEventKind;
  titleKey: string;
  titleArgs?: Record<string, string | number>;
  startAt: string;
  peakAt?: string;
  endAt?: string;
  timezone: string;
  targetId?: string;
  imageKey?: string;
  visibility: 'visible' | 'partial' | 'not-visible' | 'unknown';
  altitudeDeg?: number;
  azimuthDeg?: number;
  magnitude?: number;
  sourceRevision: string;
}

export interface AstronomyFormSnapshot {
  schemaVersion: number;
  generatedAt: string;
  validUntil: string;
  locationId: string;
  locationName: string;
  timezone: string;
  sourceRevision: string;
  events: AstronomyEventSnapshot[];
  moonCalendar: AstronomyMoonDay[];
  planetVisibility: AstronomyPlanetVisibility[];
  nextEclipse?: AstronomyEventSnapshot;
  staleReason?: 'expired' | 'location-changed' | 'time-changed' |
    'catalog-expired' | 'calculation-failed';
}
```

`titleKey` 使用统一多语言资源键，不能把当前 UI 语言的最终字符串永久写入快照。卡片读取时按系统当前语言格式化，确保应用切换语言或系统语言变化后不会继续显示旧语言。

## 通知产品逻辑

### 规则分类

1. **重要天象**：主要月相、日食、月食、流星雨峰值。
2. **关注卫星**：只提醒用户主动关注的卫星，不为全部卫星生成提醒。
3. **观测目标**：用户加入观测列表的天体升起、达到最低高度或进入最佳观测窗口。

### 授权流程

1. 用户打开“天文提醒”页时只展示能力说明，不立即申请系统授权。
2. 用户首次打开任一规则开关时，调用通知授权检查。
3. 授权成功后保存规则并显示下一次提醒预览。
4. 授权失败时保持规则关闭，解释原因并提供用户主动触发的“系统通知设置”入口。
5. 代理提醒开放能力未通过时，界面明确显示“可靠后台提醒尚未启用”，仅允许普通通知预览。

### 滚动调度窗口

- 每次只注册最近的 30 个提醒，确认目标 API 和开放能力后可在 API 26 设备扩大到 64 个。
- 注册前按事件 ID、提醒提前量和位置 ID 去重。
- 勿扰时段内的提醒默认不注册；用户可选择推迟到勿扰结束，但不能绕过系统勿扰模式。
- 重新计算时先比较新旧规则，只取消已失效提醒，避免全部删除后重建造成通知闪动或重复。
- 卫星提醒必须校验 TLE 有效期；数据过期时停止注册并提示用户，不用过期轨道数据产生误导提醒。

## 桌面卡片方案

### 第一阶段卡片

| 卡片 | 推荐尺寸 | 主要内容 | 点击行为 |
| --- | --- | --- | --- |
| 月相月历 | `4*4`、`2*4` | 本月月相、今日高亮、满月和新月标记 | 打开月相计算页并定位日期 |
| 今晚可见行星 | `2*4`、`2*2` | 行星、升落时间、最佳观测时段 | 打开今晚天象或选中行星 |
| 下一次重要天象 | `2*4`、`2*2` | 最近日月食、流星雨或主要月相 | 打开事件详情并设置模拟时间 |

### 后续卡片

- 关注卫星下一次过境：必须同时显示 TLE 数据日期和过期状态。
- 观测列表：显示最近进入观测窗口的目标。
- 离线专题：只展示随包文章并标记内容版本，不伪装为在线新闻。
- 太阳活动：暂不实现。只有未来具备合规、可审计的数据源和离线回退后再评估。

### 刷新策略

- 主应用前台生成快照后主动刷新已存在的卡片。
- 月相月历默认每天刷新一次；位置、日期或语言环境变化时由主应用主动刷新。
- 今晚可见行星和重要天象默认每 30 分钟到 2 小时刷新一次，具体间隔由数据有效期决定。
- 不使用 5 分钟刷新去模拟秒级倒计时，以免消耗每日 50 次定时刷新额度。
- 卡片页只显示已解码的小图标、月相矢量或低分辨率缩略图，不直接加载深空高清图、行星大纹理或 3D 模型。

## 原生文件布局建议

真正实施时建议新增以下源文件，并继续由同步脚本复制到生成工程：

```text
harmonyos/ets-source/forms/AstronomyFormAbility.ets
harmonyos/ets-source/forms/AstronomyFormStore.ets
harmonyos/ets-source/forms/AstronomyFormTypes.ets
harmonyos/ets-source/forms/AstronomyReminderService.ets
harmonyos/ets-source/forms/pages/MoonCalendarCard.ets
harmonyos/ets-source/forms/pages/PlanetVisibilityCard.ets
harmonyos/ets-source/forms/pages/NextEventCard.ets
harmonyos/resources/base/profile/form_config.json
```

`module.json5` 后续只增加必要的 `extensionAbilities` 和经 AGC 批准后的代理提醒权限。签名、证书、Provision、Debug/Release 方案仍由 DevEco 和现有人工配置管理，任何同步或构建脚本都不得覆盖。

## CLI 契约

所有能力必须与 ArkUI 共用同一业务服务，避免“界面能用、CLI 不能用”或两套状态不一致。建议增加：

| 命令 | 作用 | 是否修改状态 |
| --- | --- | --- |
| `getNotificationRules` | 获取全部提醒规则和系统授权状态 | 否 |
| `setNotificationRule` | 新增或更新单条提醒规则 | 是 |
| `previewAstronomyNotifications` | 计算未来提醒但不注册 | 否 |
| `refreshAstronomyReminders` | 重算并注册滚动提醒窗口 | 是 |
| `clearAstronomyReminders` | 清除应用创建的全部提醒 | 是 |
| `getFormSnapshot` | 获取当前卡片快照和过期原因 | 否 |
| `refreshFormSnapshot` | 重算快照并请求刷新卡片 | 是 |

建议 payload 使用 JSON，并返回统一的 `requestId`、`status`、`generatedAt`、`warnings` 和 `data`。修改系统提醒的命令在应用内命令面板和批处理模式中必须标记为需要确认。

## 隐私、联网和审核边界

- 未同意隐私政策前，不初始化 Qt、不读取设备信息、不计算依赖用户位置的天象、不申请通知授权。
- 添加卡片本身不新增联网；卡片只读应用沙箱中的离线快照。
- 不读取 SN、序列号或设备唯一标识，也不把设备型号作为卡片或提醒逻辑条件。
- 位置只保存在应用沙箱，用于本地天文计算；不上传位置、时区、关注对象或提醒规则。
- 若未来接入远程太阳活动、专题内容、TLE 或星表更新，必须先更新 `NETWORK-INVENTORY.md`，说明 URL、外发字段、用户触发方式、国内镜像和离线回退。
- `PUBLISH_AGENT_REMINDER` 只有在 AGC 权益通过后才加入正式配置；本轮预研不提前声明。

## 分阶段实施路线

### 阶段 A：离线快照和预览

1. 增加共享数据契约和原子快照存储。
2. 用现有 C++ 命令生成未来 30～90 天事件。
3. 增加提醒规则页、授权状态说明和“预览未来提醒”。
4. 增加 CLI 查询、预览和快照刷新命令。
5. 在没有代理提醒权益时只测试普通通知，不承诺后台触发。

### 阶段 B：首批桌面卡片

1. 新增 `FormExtensionAbility` 和 `form_config.json`。
2. 实现月相月历、今晚可见行星和下一次重要天象三张卡片。
3. 增加应用内“添加到桌面”入口和卡片跳转参数处理。
4. 验证无快照、快照过期、位置变化、语言变化和应用升级状态。

### 阶段 C：可靠后台提醒

1. 在 AGC 申请代理提醒开放能力。
2. 审批通过后重新生成 Profile，并由用户维护签名配置。
3. 声明权限并实现 30/64 条滚动窗口、去重、取消和过期恢复。
4. 在手机、平板和 PC/2in1 上验证冻结、进程终止、重启、时区变化和通知点击回到应用。

### 阶段 D：扩展卡片

1. 关注卫星过境卡片。
2. 观测列表卡片。
3. 离线专题内容卡片。
4. 仅在联网合规方案落地后评估太阳活动卡片。

## 验收清单

- [ ] 用户未主动开启提醒时不弹通知授权。
- [ ] 未同意隐私政策前不初始化 Qt，不读取设备标识，不申请通知权限。
- [ ] 普通通知、代理提醒和桌面卡片均不依赖 Push Kit。
- [ ] 卡片扩展不初始化 Qt 或 OpenGL，10 秒生命周期内能返回数据。
- [ ] 无快照、计算失败、数据过期和 TLE 过期都有明确 UI，不出现无限加载或空白卡片。
- [ ] 月相、日月食、流星雨和行星可见性与应用内天文计算结果一致。
- [ ] 卡片点击能进入正确页面、事件、天体和模拟时间。
- [ ] 规则、提醒窗口和卡片快照都可通过 CLI 查询。
- [ ] 手机、平板和 PC/2in1 使用同一套数据和交互语义。
- [ ] 没有修改或覆盖用户现有签名配置。

## 当前决策

- 两项能力均可实现。
- 桌面卡片可以完全离线落地，优先实现月相月历、今晚可见行星和下一次重要天象。
- 可靠后台通知依赖 AGC 代理提醒开放能力；审批前先完成规则、预览、快照和普通通知测试。
- 不接 Push Kit，不实现在线新闻，不宣称离线太阳活动数据为实时数据。
