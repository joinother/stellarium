# 手动天象提醒服务与父集成契约

> 2026-11-11 更新：通知设置已改为分类订阅；请以 `ASTRONOMY-NOTIFICATION-SUBSCRIPTIONS.md` 为现行 UI、偏好迁移与滚动排程契约。以下手动服务 API 保留兼容，原手动管理器 UI 不再作为主界面。

2026-11-11。仅实现用户主动选择事件后的本地系统提醒，不订阅远程事件、不自动申请授权、不写系统日历、不新增后台任务。Sky Guide 本地行为分析仅作为“待处理请求查重、事件路由、提前量、静默时段”产品行为参考；未使用其代码、资源、端点或私有数据。

## 父集成

- 日历共享类型使用 `state/AstronomyCalendarEvent.ts`：`{id,kind,title,at:number,jd,body,target,panel,tab}`，`at` 是 Unix 毫秒；Controller 的 `scheduleEvent(event): Promise<AstronomyCalendarReminderResult>` 与内部 `scheduleOne` 返回服务的结构化结果，同时更新状态和调用现有 `flashHint`。结果继承 `AstronomyReminderResult`，额外提供 `message?: string` 本地化提示；保留服务实际 `ok/error/reason/code/reminderId/partial/activeReminderIds`，不从文案推断成功。排程路由固定 `panel:'calendar'`，保留 eventId/eventAt 以加载月份并选择事件；事件模型原 panel 只表示原始详情页，不作为提醒落点。父层若消费返回值，不必再次弹出相同提示。
- 日历 hook、`calendar.remind(id)` 和面板 host 的 `remind(id)` 均返回 `Promise<AstronomyCalendarReminderResult>`。CLI `remindCalendarEvent` 返回实际顶层 `ok`、失败的 `error/reason/code` 和完整嵌套 `reminder`；已发生、忙碌、失效、未知事件及异常均返回明确失败。排程后的列表刷新失败单独记录，不能覆盖已经完成的排程结果。
- 保留现有 `refreshStatus`、`requestAccess`、三个旧快捷方法、`scheduleCountdown`、`scheduleAtDateTime`、`scheduleDailyAlarm`、`clearReminders`。三个旧快捷方法只调用可选 `openCalendar?():void` hook，不再读取模拟年份的节气/月相/流星雨快照。新增 `cancelReminder(id): void`、`loadPreferences(): Promise<void>`、`persistPreferences(): void`。
- 初始化/进入通知设置时调用 `loadPreferences` / `refreshStatus`；构造函数不读取、不发布。手动添加会等待偏好加载与保存队列。父层改 Store 后调用 `persistPreferences()`；也可调用 `setDndEnabled`、`setDndStartMinutes`、`setDndEndMinutes`、`changeLeadMinutes(delta)`。
- Store：`astronomyReminders: AstronomyReminderItem[]`、`astronomyReminderListLoaded`、`astronomyReminderListError`、`notificationPreferencesLoaded`、`notificationPreferencesBusy`、`notificationPreferencesError`。列表读取失败保留先前数据，并明确标记错误；不能把失败显示为空列表。
- `NotificationSection` 新增 props：`reminders` ← `astronomyReminders`，`reminderListLoaded` ← `astronomyReminderListLoaded`，`reminderListError` ← `astronomyReminderListError`，`preferencesBusy` ← `notificationPreferencesBusy`，`preferencesError` ← `notificationPreferencesError`。
- `NotificationSection` 新增回调：`onOpenCalendar()`、`onRefreshReminders()`、`onCancelReminder(id)`。其余旧 props/callbacks 保留兼容；卫星/摘要开关不再显示。父层继续绑定现有偏好回调并持久化。宿主可选 hooks：`canInteract?():boolean`（前台且允许当前操作）和 `openCalendar?():void`；父层应提供前者保证离开前台后不发布。
- Main/QAbility 路由消费 `panel/tab/eventId/kind/eventAt/jd/target`。普通通知 URI 为 `skyinstrument://astronomy/notification/<id>`，新提醒 URI 为 `skyinstrument://astronomy/reminder?notificationId=<id>&route=<encoded-json>`，原 parameters 同时保留。URI 只用于本应用 QAbility；查询剥离 parameters 不代表发布/点击不支持它。真实点击交父任务验证。
- QAbility 普通通知调用改为 `publish(payload, context.abilityInfo.bundleName)`；取消需等待 `cancel(id): Promise<boolean>`，ID 0 有效。
- `NotificationText.ets` 使用现有 I18n 语言状态提供中文/英文通知文案，其它语言回退英文；Section 响应 `i18nLang`，用户事件标题与正文不作翻译。Controller 在 requestAccess 前、偏好读写等待后检查 canInteract；宿主门禁/提示回调和系统异步调用异常会被捕获，busy 在 finally 中复位。所有既有接口不变。

## 服务输入与结果

`schedule(payload, bundleName = '', preferences?, canInteract?:()=>boolean)` 返回 `Promise<AstronomyReminderResult>`。旧标题、正文、timer/alarm、panel/tab/eventId/kind 调用保持兼容。未传运行时 bundle 时仅提醒服务保留旧包名兜底，集成必须优先传实际 bundle。可选前台回调在队列执行与实际发布前各检查一次，拒绝时 reason 为 `interaction-unavailable`。`panel: 'calendar'` 合法。

新增字段：`eventAt?: string`（ISO 事件时间）、`jd?: number`（UTC Julian Date）、`target?: string`、`leadMinutes?: number`（非负整数，最多一年）、`quietHours?: {enabled:boolean,startMinutes:number,endMinutes:number}`。`at?: string` 原有 ISO 时间兼容：无 eventAt/JD 时作为事件时刻，减去 leadMinutes；有 eventAt/JD 时作为显式触发时间。若同时给 at、eventAt 与 leadMinutes，三者必须一致。推荐父层只传 eventAt/JD + leadMinutes。ISO 支持带时区或设备本地时间，拒绝无时刻日期、无效日历日期和 DST 跳过的本地时间；eventAt/JD 不一致超过一秒返回失败。

`preferences` 接受 `astronomyEventsEnabled? / satellitePassEnabled? / digestEnabled? / dndEnabled? / dndStartMinutes? / dndEndMinutes?`。不传偏好保留旧行为；父层必须显式传偏好才能生效。category 由 kind 的 `satellite-pass`、`digest` 或其它天象决定，仅限制 calendar；timer/alarm 仍受静默时段约束。静默时段起点包含、终点不包含，跨午夜有效，起止相同表示全天。命中返回 `quiet-hours`，不挪动事件。payload 不能关闭已启用的全局静默时段。偏好仅对后续显式排程生效，不自动取消/重排已注册事项。

结果保留 `ok/reminderId/error/code/notificationEnabled/reminderCount`，增加 `reason/unchanged/replaced/partial/activeReminderIds`。常见 reason：`validation`、`too-soon`、`quiet-hours`、`category-disabled`、`privacy-required`、`notification-disabled`、`permission-denied`、`quota-or-entitlement`、`system-error`、`replacement-cleanup-failed`。状态读取失败时 notificationEnabled 可以缺省，不能将其误报为用户拒绝。

列表返回 `ok/items/error/code/reason`，每项保留 `reminderId/title/content/eventId/kind/dateTime`，新增 `eventAt/jd/target/panel/tab/leadMinutes/subscription/ownershipFingerprint`。无法证明归属的旧项返回 `kind:'unknown'`、空 eventId，不分配 subscription。系统的“有效提醒”可能包含已触发但尚未关闭的事项，不等同于未来事件或送达历史。

普通通知 `publish(payload, bundleName = ''): Promise<boolean>` 保持旧 boolean 契约；payload 新增 `route?: {panel?,tab?,eventId?,kind?,eventAt?,jd?,target?}`。有 route 时必须传 runtime bundle；使用真实 `wantAgent.getWantAgent`，固定启动 QAbility，以每个通知 id 的 requestCode/URI 隔离目标。验证失败、授权失败、WantAgent 失败、发布失败均返回 false；无 route 的旧调用继续有效。`status()` 新增结构化只读状态，`isEnabled()` 保持 boolean 兼容。多行最多三行，按官方 UTF-8 字节限制验证；标题/正文不能为空。

## 一致性与失败保证

服务内所有提醒发布/替换/读取/取消使用同一 Promise 队列；普通通知发布/取消使用另一条队列。当前进程内并发同一请求只发布一次。真机已确认查询会丢 parameters，故恢复改用本地持久化记录与实际系统 ID/请求指纹双重核验，不依赖参数回传或纯内存索引。事件身份仍为类型、kind、eventId、事件秒时刻；无 eventId 的 calendar 使用 target+时刻，timer/alarm 无 eventId 不去重。完整持久化、失败恢复、旧项不认领规则见 `ASTRONOMY-NOTIFICATION-SUBSCRIPTIONS.md` 的 Durable reminder ownership。不同年份同名事件不会相互替换。

调用前需 `AstronomyReminderService.configure(context)`，已在 Controller 构造与 QAbility.routeCardWant 接入，不触发读写。元数据独立保存在 `stellarium_reminder_metadata_v1/journal`，发布前先 flush 递增 notificationId/准备记录，发布后查询核验并 flush reminderId 绑定，完成后才清旧项。分类取消使用 `cancelOwned(item)` 再读系统核验，显式用户取消仍用 `cancel(id)`。元数据故障返回 `metadata-unavailable`、`metadata-unverified` 或 `metadata-commit-failed`；发布后的故障为 partial，不伪称没发布，也不取消旧项。旧项精确匹配只阻止重复添加，返回 `legacy-reminder-unverified`，不伪造 subscription 或订阅成功。

新旧内容相同直接返回旧 ID（包括 0）。更新先发布新提醒，再取消旧提醒；容量满或发布失败保留旧项，不尝试删除后重建，也不自动牺牲其它事件。旧项取消失败时保留新项并返回 `ok:false,partial:true,activeReminderIds`；重复显式提交相同请求会复用新项并重试清理，不再发布副本。取消不存在的提醒（1700003）视为成功。1700002 可能是实际配额或未开通权益，不推断签名必然失效。

系统 API 不提供事务；在发布与清理之间进程被杀仍可能留下副本，下一次同事件的显式请求可修复。无后台自愈写入。队列不提供跨进程锁，父层应保持单服务入口。故意不设置共享 groupId，避免用户关闭一个事件连带取消其它事件；系统提醒通知使用独立 ID，避免默认 notificationId=0 相互覆盖。

发布与授权请求前验证现有 `hasCurrentPrivacyConsent()`，排队/异步后再次校验。无授权自动弹窗、ACL 自动获取、签名修改或隐私兜底。取消可在撤回隐私同意后执行。Preferences 文件为 `stellarium_astronomy_reminders`，单个 JSON key `manual_preferences_v1`，保存成功以 flush 为准；失败回退缓存/Store，禁止后续排程静默使用未确认偏好。

## 官方资料核验

通过 `harmonyos_developer_knowledge.searchDocuments` 后 `getDocumentsById` 读取全文，查询包括 reminderAgentManager publish/getAllValidReminders/quota、notificationManager publish/cancel、WantAgentInfo、Preferences、UIContext 日期时间弹窗。以下文档 ID 均以 `alliance/document/cn/` 开头，对应官方 `https://developer.huawei.com/consumer/cn/doc/` 同路径：

- `harmonyos-references/js-apis-reminderagentmanager`、`harmonyos-guides/agent-powered-reminder`、`harmonyos-references/errorcode-reminderagentmanager`：基础 API 9，getAllValidReminders 与 route parameters/uri 为 API 12；API 25 及以下普通应用 30 个、26 起 64 个，未获权益可能上限 0，实际发布结果为准。
- `harmonyos-references/js-apis-notificationmanager`、`js-apis-inner-notification-notificationrequest`、`js-apis-inner-notification-notificationcontent`：Promise publish/cancel、真实 WantAgent、标题 1024/正文 3072 字节、多行最多三行且每行 1024 字节。
- `harmonyos-references/js-apis-app-ability-wantagent`、`js-apis-inner-wantagent-wantagentinfo`：START_ABILITY、actionType/actionFlags（API 11 起），仅本应用 UIAbility；本地 API 24 SDK 声明同步核对。
- `harmonyos-references/js-apis-data-preferences`：getPreferences/put/get/flush，put 仅更新缓存，flush 才持久化。
- `harmonyos-references/arkts-apis-uicontext-uicontext`、`ts-methods-datepicker-dialog`、`ts-methods-timepicker-dialog`：UIContext 显式上下文，API 10 起 showTime/onDateAccept 返回带所选时分的 Date。当前 API 24 可用，未引入 API 26 功能。

## 验证与交接

- `node --test scripts/test-ohos-astronomy-calendar.mjs scripts/test-ohos-notification-services.mjs scripts/test-ohos-notification-controller.mjs`：44 项通过（14 项日历、30 项通知）。使用实际 .ets/.ts 源码去除类型后注入系统 mock，覆盖并发、重启查重、旧数据迁移、quota/ACL、发布失败、清理失败与重试、ID 0、状态/列表失败、静默边界、隐私拒绝、WantAgent、异步取消、Preferences 读写失败/回退、手动事件映射、前台失效、宿主回调异常、中英文/其它语言回退和旧快捷方式不读模拟时刻快照。新增服务结果经 NotificationController、日历和实际 CLI 分支传递的回归；即使失败文案写着“已交给系统管理”，`ok:false` 仍保持失败。这不是 ArkTS 编译验证。
- `node scripts/test-ohos-reminder-contract.mjs`：契约通过；已改为断言 QAbility 使用真实时钟月份查询 `getAstronomyCalendarEvents`，禁止旧模拟时刻 `currentJD/getAlmanac` 路径。
- `node scripts/check-ohos-ui-contract.mjs`：父集成后的共享工作区通过（36 panels、53 id anchors）；本任务未修改共享基线。
- 按任务边界未构建、签名、安装或提交。父层需运行 ArkTS 编译和设备测试：真实 metadata 往返、通知点击恢复 eventAt/JD/target、配额下替换、拒绝/撤回授权、进程退出后的提醒、跨时区与 DST、日期时间弹窗、偏好重启持久化与列表取消。基础 calendar 提醒使用设备本地 LocalDateTime；无 API 26 固定时区支持，设备时区改变后应明确重新选择/排程。
