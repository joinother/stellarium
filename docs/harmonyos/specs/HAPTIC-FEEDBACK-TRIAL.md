# Haptic feedback trial — implemented integration (2026-11-11)

The service, HarmonyOS adapter, host lifecycle/interaction hooks, settings, CLI routes and manifest permission are implemented in source. This is a foreground interaction trial, independent of audio and notifications. This document records source behavior and mock-based tests; the parent task records build and device evidence separately.

## Evidence and original design

Behavior references are local reports under `/Users/jiexuanyang/Documents/Trae-CN/temp_20261014_01/skyguide-rev-eng/assets/analysis/`:

- `audio-system.md:84–87` identifies `supportsHaptics`, `hapticsEnabledKey`, `mainHaptic` (old-build addresses `0x100f13a4c..0x100f15054`) and a settings-controlled feedback subsystem alongside audio.
- `interaction-layer.md` sections 1–3 establish the gesture → successful pick → selection delegate pipeline and distinguish selection from requesting details. They do not establish exact vibration patterns or amplitudes for those actions.
- Searching related local Markdown reports found no additional haptic findings. Symbol inventories confirm `SkyUI.HapticEngineManager.lightTap`, `mediumTap`, `softInteraction`, `supportsHaptics` in `assets/decompiled-source/SkyGuide_swift_types.txt:1520–1523`; build-759 inventories contain capability, preference getter/setter and main-haptic symbols. Symbol presence is not proof of call-site behavior, waveform or timing.

Only behavioral facts and symbol names informed this trial. No proprietary code, waveform, audio or other assets were copied. The semantic mapping, default-off policy, gains and throttles below are this project's original choices, not reconstructed SkyGuide parameters.

Before this trial, `harmonyos/ets-source` had no vibration/haptic hooks. `SettingsRepository.ets` persists UI preferences via a host port; haptics use a separate Preferences namespace. `StellariumLifecycle.ets` has a single listener; the existing host listener forwards lifecycle to the service.

## Public API and lifecycle

Import `HapticFeedback` from `capability/HapticFeedback` and `createHapticFeedback` from `capability/HarmonyHapticFeedback`. Create one instance per active host and retain it across settings and interactions:

```ts
const haptics = createHapticFeedback(context)
haptics.setForeground(true)
await haptics.initialize()
const saved = await haptics.setEnabled(true)
const status = haptics.status()
```

Creation does no I/O. Call initialization only after the existing privacy startup gate allows the page. The service starts with `foreground=false`, `enabled=false`, cached `consent=false`. Forward the actual `applicationInForeground` value; never set it true simply because a command arrived. On background/disappearance/destruction call `setForeground(false)`. On foreground call `setForeground(true)` then `initialize()`: initialization performs one low-frequency privacy refresh (the synchronous `privacyManager` queries cost tens of milliseconds together), then refreshes capability. `emit()` never queries privacy; it reads the cached boolean. On privacy loss call `refreshConsent()` (or `suspend()` immediately); this invalidates pending feedback and ends the ruler session. No polling, background task, lifecycle listener or vibration timer is registered.

`initialize(): Promise<void>` refreshes the cached consent when it is dirty or unknown, loads the setting once and probes presets without vibrating. It joins concurrent initialization in the same epoch and ignores capability results from a prior epoch. When resume calls `initialize()` while an invalidated probe is pending, it waits for that probe to settle, rechecks foreground and the cached consent, then starts a fresh shared probe. The resume promise waits for the fresh results; no second manual initialization is needed. Feedback requested while probing is dropped, not replayed. Native failure clears capability for this instance; explicit `initialize()` retries the probe, never a timer or an interaction retry loop. `refreshConsent(): boolean` is the public low-frequency refresh point for privacy flows; it is never called from `emit()`.

`status(): HapticStatus` returns a snapshot: `enabled`, `loaded`, `saving`, `foreground`, `available`, `probing`, `supportedEffects`, `lastFailure`, `consent`. `available` means at least one tested preset is supported, not that the system touch-feedback setting is on or that a physical pulse was felt. Display per-kind capability from `supportedEffects` if necessary; a device supporting only success/failure will not produce selection/ruler feedback. No system setting is changed or read via private APIs.

`setEnabled(boolean): Promise<boolean>` applies off immediately, serializes persistence, and enables only after successful flush. Rapid changes are last-request-wins; late initial reads cannot overwrite the user's choice. The result indicates that particular write succeeded, so always refresh UI from `status()` rather than from a captured input value. Use a disabled/busy toggle while saving. Failed writes keep this instance off and expose `preferences-write`; show save failure. The adapter also resets its cache to false on flush failure. A failed off write cannot promise durable disable across process restart; do not report it as saved. Storage is local XML Preferences `stellarium_haptics`, boolean key `enabled_v1`, default false. Settings reset must explicitly `await setEnabled(false)`; existing `SettingsRepository.resetToDefaults()` does not clear this separate store. Do not infer opt-in from music, vibration capability or upgrade.

## Integration calls

| Implemented integration point | Call and condition |
| --- | --- |
| Lifecycle/privacy | `haptics()` retains one host instance. Privacy-approved startup and foreground resume initialize it; the existing application listener forwards foreground state. Page disappearance sets foreground false; privacy revocation suspends feedback. |
| `MainWindowNativeNode.requestSkySelection` | After the request-serial check and applying a successful pick, calls `selection(this.objectDetailStore.selectedName)`. Empty-sky results and double-tap clearing call `selection('')` silently. Stale callbacks cannot reset deduplication. Periodic state refresh does not emit. |
| Time wheel | Touch-down calls `beginRuler(0)`; `TimeWheelController` reports a motion-based tick counter to `rulerTick(index)` during drag with a speed-adaptive cadence (70/100/140 ms; service floor 80 ms), and every 100 ms during inertia; cancel calls `endRuler()`. A jump of 100 detents emits at most one pulse. Programmatic time progression does not call the tick hook. |
| Menu/Dock | `activateDockAction` calls `menu()` only after accepting the action through its 360 ms same-panel debounce. |
| Settings | `SettingsPanel` embeds `HapticSection` with Chinese/English labels, capability status, busy toggle and “Try feedback” button. `changeHapticEnabled` saves through `setEnabled`, refreshes from `status()` and reports failures. Off remains operable on unsupported hardware when enabled. Preview calls `confirmation()`; enabling alone does not pulse. |
| Restore defaults | `exitAppAfterRestore` awaits successful `changeHapticEnabled(false)` before resetting other preferences and terminating. Failed haptic persistence reports failure and prevents termination. |
| Confirmation/error previews | Settings preview uses `confirmation()`; the CLI exposes both `confirmation()` and `error()`. General operation-success/failure and search-selection feedback are not wired by this trial. |

All interaction methods return `Promise<boolean>`: true means the driver accepted the request while guards remained valid; false means suppressed/unsupported/failed. This is not evidence that the motor physically moved (system settings may suppress it). Methods contain driver exceptions. `beginRuler`, `endRuler`, `setForeground` and `suspend` return void.

| Semantic | Preferred preset | Intensity | Minimum same-kind interval |
| --- | --- | --- | --- |
| selection/menu | `haptic.effect.soft` | 30 | 120 ms |
| ruler | `haptic.clock.timer` (fallback `haptic.effect.soft`) | 20 | 80 ms |
| confirmation | `haptic.notice.success` | 40 | 300 ms |
| error | `haptic.notice.fail` | 40 | 600 ms |

There is also an in-flight request gate and a minimum gap between any two pulses (60 ms for ruler, 90 ms for other kinds). Confirmation/error fall back only to queried-supported soft. No timed/raw/full-strength fallback, loop, repeated count or queued replay exists. Every platform request is `type: 'preset', count: 1`, with `usage: 'touch'`. The clock is monotonic uptime, independent of simulated astronomical time and wall-clock changes. Background, privacy loss and off invalidate pending acknowledgements and stop the preset; new requests stay blocked until pending start/stop settles.

## Permission and CLI

The authoritative `harmonyos/module.json5` requestPermissions list includes `{ "name": "ohos.permission.VIBRATE" }`. The permission is required for start and stop; no runtime authorization dialog is requested by this service. Missing permission/device API errors are contained and disable capability until an explicit re-probe.

The command catalog registers these routes. `QAbility` forwards them to `MainWindowNativeNode.executeFeatureCli` through the existing UI event/completion path. All three require the lifecycle-cached privacy consent and actual application foreground, and await `initialize()` before executing; state queries may probe capability but never vibrate.

| Command | Accepted payload | Host behavior |
| --- | --- | --- |
| `getHapticState` | Empty recommended; host ignores payload | Returns `{ok:true, requestId, state: feedback.status()}`. |
| `setHapticEnabled` | Exactly `true`, `1`, `on` to enable; `false`, `0`, `off` to disable | Awaits `changeHapticEnabled`; returns `{ok: saved, requestId, state}`. Other strings fail with `expected on or off`. |
| `playHapticFeedback` | Exactly `selection`, `menu`, `confirmation`, or `error` | Calls the corresponding method; selection uses `requestId` as its identity. Returns `{ok:true, requestId, played, state}`. `ruler` and other values fail with `unknown feedback kind`. Never enables automatically. |

Payload matching is case-sensitive with no host-side trimming. `played:false` can mean off, unsupported, throttled or failed; command `ok:true` does not prove physical vibration. Handler exceptions return `ok:false` and an `error` string; the QAbility guard may reject before the host runs. Use the semantic CLI, for example:

```sh
node scripts/stellarium-cli.mjs --device <id> --command getHapticState --json
node scripts/stellarium-cli.mjs --device <id> --command setHapticEnabled --payload on --json
node scripts/stellarium-cli.mjs --device <id> --command playHapticFeedback --payload selection --json
node scripts/stellarium-cli.mjs --device <id> --command setHapticEnabled --payload off --json
```

## Official documentation and SDK verification

Official MCP search keywords: `vibrator startVibration isSupportEffect 硬件反馈 系统触感 feedback intensity`, `preferences getPreferencesSync getSync putSync flush systemDateTime getUptime STARTUP`. Full documents retrieved with `getDocumentsById` before implementation:

- `alliance/document/cn/harmonyos-references/js-apis-vibrator`, [@ohos.vibrator](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-vibrator): start/stop-preset API 9+, async effect support API 10+, soft and intensity API 12+, success/failure enum values API 18+. The adapter uses documented string effect IDs with runtime support queries. `SystemCapability.Sensors.MiscDevice`; `touch` explicitly obeys the system touch-feedback switch. Documentation lists phone/tablet API 12+, 2in1 API 13+, wearable API 18+; presence of the kit is not evidence of a motor. Intensity can be ignored by unsupported motors/presets, so gentleness still needs physical validation.
- `alliance/document/cn/harmonyos-references/js-apis-data-preferences`, [Preferences](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-preferences): getPreferencesSync/getSync/putSync API 10+, flush Promise; Stage context and `SystemCapability.DistributedDataManager.Preferences.Core`.
- `alliance/document/cn/harmonyos-references/js-apis-date-time`, [systemDateTime](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-date-time): getUptime/TimeType API 10+, STARTUP and `false` select uptime milliseconds; `SystemCapability.MiscServices.Time`.

Signatures verified against `/Users/jiexuanyang/Library/OpenHarmony/Sdk/26.0.0/ets/api/@ohos.vibrator.d.ts`, `@ohos.data.preferences.d.ts`, `@ohos.systemDateTime.d.ts`, and kit export presence. This is source/API verification, not ArkTS compilation.

## Validation and outstanding device checks

Run `node --test scripts/test-ohos-haptic-feedback.mjs`. Latest focused result: **25/25 passed**. The tests execute the actual service, adapter and extracted host methods with fake motor/Preferences/clock/consent. Coverage includes default-off persistence, capability fallback, guards, throttling, ruler boundaries, delayed start cancellation, serialized writes, write failures and native exceptions; host switch persistence, restore-before-termination, empty-sky/stale-selection deduplication and duplicate Dock suppression; invalidated probe resolution/rejection, coalesced resume and guard rechecks before restart; and the consent-cache regression: no `hasConsent()` query on the pulse path, refresh at foreground/initialize/privacy boundaries, and fail-closed guard exceptions. No vibration hardware, application build or device install is used by this suite.

Build and device evidence is recorded separately by the parent. Device checks include: fresh install off; enable and restart persistence; disable and restart; unsupported tablet/PC; denied/missing VIBRATE; system touch feedback disabled; phone's actual intensity (SDK may ignore gain); repeated taps and fast ruler drag; app background while start/probe pending; privacy revocation; reset settings; no background/inertia pulses. Use the registered semantic CLI for state and preview, and real touch for detent/hit-testing. Node tests cannot validate ArkTS strictness, installed manifest behavior, physical sensation or system suppression.
