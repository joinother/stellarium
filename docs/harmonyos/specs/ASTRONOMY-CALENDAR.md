# Local astronomy calendar

## 2026-11-11 最终界面修订（取代下方初版说明）

- 按用户视频改为图文时间线：月份左右切换，“更多天象”追加下一月，点击卡片显示详情及“查看”。查看后关闭面板并前往星图事件时刻。移除月历格子及普通 UI 的逐条提醒按钮，改由设置按类别订阅；提醒 CLI 保留用于诊断。
- 数据已扩展为节气、主要月相、流星雨预计极大和行星合/冲/大距。流星雨为目录模型估算；日食/月食及卫星过境尚未加入此列表，卫星订阅使用独立预测。全局时刻不等于当地可见。
- `scripts/generate-calendar-art.mjs` 生成原创 SVG 插图，未复制 SkyGuide 私有素材；夜间使用现有主题遮罩与文字色。日历本身不联网。中文/英文，其余语言暂回退英文。
- Controller 增加 `loadMore()`，追加月份并保留已选详情，序号守卫防止陈旧响应覆盖新月份。只由明确“查看”操作改变星图；数据读取/订阅不改模拟时间。
- 语义 CLI 增加 `loadMoreCalendarEvents`、`closeCalendarEvent`。通知传稳定 eventId/eventAt，加载对应月份后打开详情，未找到不得声称成功。
- 当前纯逻辑验证：calendar 16 项、native calendar 14 项通过；集成构建与真机结果见 CHANGELOG。下方保留初版实现背景，不代表最终交互或最终覆盖范围。

## 初版实现背景（已被上述修订部分取代）

Implemented 2026-11-11. Calendar ownership is limited to the new state/model, controller, panel, text helper, this document and `scripts/test-ohos-astronomy-calendar.mjs`. Parent task owns shell/CLI/notification integration and Dirac owns the native endpoint. No build, installation or commit was performed by the calendar task. Existing disabled desktop forms remain disabled.

## Behavioral scope and provenance

Only section 5 of the user-specified `notifications-widgets-tours.md` was consulted for SkyGuide behavior: a local month feed, event navigation and a reusable source. No decompiled implementation, proprietary assets, remote custom feed or remote event imagery is used. There is no runtime network access in this feature.

The calendar displays device-local Gregorian months, previous/next navigation, day selection, full-month event list, event detail, View sky and Remind me. Available groups are native solar terms (including equinoxes/solstices) and the four principal lunar phases. Eclipses, planetary events, meteor peaks, comets and satellite passes are explicitly not offered. Global event instants do not imply local visibility.

## Parent integration contract

- State: `state/AstronomyCalendarStore.ets`, instantiated once as host `@State`; panel receives it as `@ObjectLink calendarStore`.
- Controller: `new AstronomyCalendarController(port, store, hooks)` with the existing `CommandPort`.
- Hooks: `viewSky(event): void`, `remind(event): Promise<AstronomyCalendarReminderResult>`, `feedChanged(events): void`. The result extends `AstronomyReminderResult` with optional localized `message`; `ok`, `error`, `reason`, `code`, reminder IDs and partial replacement metadata come from the service, never from interpreting message text. The calendar blocks past events and duplicate in-flight reminders with explicit failure results.
- Methods: `loadMonth(year, month)` (month 1–12), `reload()`, `previousMonth()`, `nextMonth()`, `selectDay(day)`, `selectEvent(id)`, `showMonthEvents()`, `viewSky(id)`, `remind(id): Promise<AstronomyCalendarReminderResult>`, `setLanguage(language)`, `dispose()`.
- Panel: `AstronomyCalendarPanel({ calendarStore, host, language, panelFontSize })`; host has the corresponding action methods except loadMonth/setLanguage/dispose. `remind` returns the same structured result. Root is a Column: the host provides scrolling. The fixed calendar Grid has both row and column templates and does not create a second scrolling area.
- Theme: `onWillApplyTheme` derives `ThemeSlots`; text/sub/softStrong/accent/onAccent come from theme. The four initially proposed color props remain accepted for source compatibility but are superseded by theme slots. `panelFontSize` is the base size, default 14.
- Route: host panel ID `calendar`. No host builder is passed into this component. Host CLI should call these same controller methods and report store `loading/error/loaded`, selected day/ID and events; do not treat initial command acceptance as load completion.
- Language: pass current language to the panel and call controller `setLanguage` at initialization and on language changes. Chinese uses `zh*`; other languages fall back to English. This regenerates titles/body and feed without native recalculation. It does not modify the general I18n table.
- Lifecycle: call `dispose()` when destroying controller ownership, not simply when closing a panel that will reuse the same instance. Create a fresh controller if ownership restarts. Refresh after device time-zone changes or application resume as appropriate.

The feed callback is the currently requested month, cleared immediately when a new query starts. It is not a persistence or reminder-cancellation signal. Notification/card consumers may reuse the model, but must not cancel scheduled reminders because this visible-month feed changes. No desktop form is enabled here.

`state/AstronomyCalendarEvent.ts` exports `AstronomyCalendarEvent` with `{id,kind,title,at,jd,body,target,panel,tab,timeScale?}`. `at` is Unix milliseconds derived from `jd`; `jd` is the native UT instant (application UTC convention), `timeScale` is `UT`. Native IDs are retained across language changes. `kind` is `solar-term` or `moon-phase`. `target` is Sun/Moon; detail destinations are `astro/8` (almanac) and `astro/6` (lunar phases). The shell entry remains `calendar`.

Only the explicit View sky hook may animate simulation time and select a target. Loading, changing month/day, inspecting detail, localizing and scheduling a reminder never perform time/selection writes.

## Native query

The controller uses only `getAstronomyCalendarEvents`, via `requestLongRunning`, with JSON `{year,month,startJD,endJD}`. The bounds represent local midnight at the first of the month and the first of the following month, converted to UT JD. They are half-open and account for daylight saving changes; no fixed 30-day or 24-hour iteration is used. Years 1–3000 are supported independently of the simulation year. The native string `YYYY-MM` form represents UTC months and is intentionally not used by this local-month UI.

Response requires `{ok:true,year,month,startJD,endJD,timeScale:'UT',events:[...]}` matching the request. Rows require native `id`, `kind`, integer `index` (solar 0–23; phase 0–3), and finite `jd`. Unknown groups are ignored, duplicate IDs are suppressed, and rows outside the exact month are excluded. Corrupt supported rows or wrong response context produce an error, not an empty-success claim. `at`, title, body and routing are normalized locally, with Chinese/English explanations of visibility limitations. No fake sample events are used at runtime.

Older `getMoonPhases`, `getEclipses`, `getPhenomena` and even `getAlmanac` (via Planet RTS) temporarily modify shared simulation time. They are not fallback sources. An early seasonal-only prototype was replaced completely. See `NATIVE-ASTRONOMY-CALENDAR.md` for native algorithm and precision constraints.

## Verification

`node --test scripts/test-ohos-astronomy-calendar.mjs scripts/test-ohos-notification-controller.mjs scripts/test-ohos-notification-services.mjs`: 44 passing tests, including 14 calendar tests for date boundaries, DST/offset requests, routing, read-only queries, stale callbacks and structured reminder results. Integration mocks execute NotificationController → calendar → the actual CLI reminder block, checking permission, quiet-hours, quota and partial replacement failures, ID zero, duplicate requests and successful scheduling despite list-refresh failure. Localized text does not determine success. Tests execute TypeScript-stripped source; they do not compile ArkUI or execute production C++ ephemerides.

`node scripts/check-ohos-ui-contract.mjs` passes with the parent's updated baseline (36 panels, 53 ID anchors). The structured-result follow-up changes NotificationController scheduling, calendar controller/panel types, and the host hook/import plus exact CLI reminder block by explicit user authorization. CLI returns top-level `ok`, failure `error`/`reason`/`code`, and the full nested `reminder` result. No build, device action or commit was performed; device behavior and ArkTS compilation remain parent verification.

## Official API evidence

MCP query: `ArkUI Grid columnsTemplate GridItem @Observed @ObjectLink 嵌套对象 数组 V1`. Full documents retrieved before UI implementation:

- `alliance/document/cn/harmonyos-guides/arkts-observed-and-objectlink`: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-observed-and-objectlink — V1 host @State to child @ObjectLink; replace arrays at the observed store's first level, never reassign the ObjectLink itself.
- `alliance/document/cn/harmonyos-references/ts-container-grid`: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-grid — Grid/GridItem and string column/row templates, supported from API 7, compatible with project API 24. No API 26-only container or V2 state is introduced.

Grid keys include event count so asynchronous data updates replace plain-data cells. Event keys include localized titles so language changes rebuild plain-data row content. Selected state is driven by observed store values, including onAccent text for accent backgrounds.
