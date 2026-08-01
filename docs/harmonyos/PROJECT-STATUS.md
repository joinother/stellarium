# HarmonyOS Product Development Status

Last updated: 2026-08-01

## Scope

This repository currently contains an active HarmonyOS product port of
Stellarium. It is **not** ready for an upstream pull request or a final store
release. The product port continues in this fork; upstream work, if requested
by maintainers, must start independently from current upstream `master`.

## Branch Policy

| Branch | Purpose | Rules |
| --- | --- | --- |
| `baseline/v1.0.1-tablet-test` | Known tablet-test fallback | Never develop directly. Keep it unchanged. |
| `release/v1.0-offline-candidate` | Frozen release candidate snapshot | Never develop directly. Tag/build only after verification. |
| `develop/harmonyos` | Product integration branch | The only shared integration branch for active product work. |
| `fix/<topic>` | One focused bug or feature | Branch from `develop/harmonyos`; build and test before merging back. |
| `upstream/openharmony-bootstrap` | Clean experiment based on official `master` | No product UI, signing, branding, store files, or command bridge. |

Do not merge `develop/harmonyos` into `upstream/openharmony-bootstrap`, and do
not merge official `master` into the product port as an ad-hoc conflict fix.

## Current Working Tree

The following uncommitted files are active work, not disposable build output:

- `build/libstellarium-harmonyos/entry/src/main/ets/pages/I18n.ets`
- `build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets`
- `build/libstellarium-harmonyos/entry/src/main/ets/qability/StellariumResourceBootstrap.ets`
- `build/libstellarium-harmonyos/entry/src/main/resources/base/media/ic_audio.svg`

The first three ETS files match their corresponding `harmonyos/ets-source/`
files byte-for-byte. Treat `harmonyos/ets-source/` as the editing source and
copy or regenerate it into the build project only as part of a deliberate,
reviewed change. Never use `git clean`, `git reset --hard`, or checkout of
these files while they are uncommitted.

## Priority Queue

### P0: Stabilize the development base

- [ ] Reconcile the active ETS changes into one reviewed commit with a clear
      feature list and a successful HAP build.
- [ ] Establish one repeatable tablet install and log-capture procedure.
- [ ] Push reviewed commits to `myfork/develop/harmonyos` after explicit user
      authorization.

### P1: Core interaction correctness

- [ ] Gyroscope: replace iterative axis tweaks with a documented pose pipeline
      and validate it on the physical tablet across portrait/landscape,
      horizon, zenith, nadir, and roll.
      See [GYROSCOPE-AUDIT.md](GYROSCOPE-AUDIT.md) before modifying it.
- [ ] Prevent ArkUI panel gestures and buttons from passing through to the
      XComponent star-map touch layer.
- [ ] Keep a selected/search target inside the actual visible sky region when
      panels open, close, or resize, with one continuous camera transition.
- [ ] Fix mobile quick-control touch state and feedback before re-enabling any
      mobile zoom controls.

### P2: Product polish after P1

- [ ] Time controls: precise draggable timeline, real-time reset, and stable
      speed feedback.
- [ ] Complete live language refresh and remove unfinished/placeholder panels.
- [ ] Validate screenshots, save permissions, location map rendering, and
      night-mode composition.
- [ ] Profile rendering and gyro-update frame pacing on the tablet.

## Change Workflow

1. Create one `fix/<topic>` branch from `develop/harmonyos`.
2. Change the canonical source under `harmonyos/ets-source/` or the relevant
   native source, not only its copied build output.
3. Build, install, and record device/simulator verification.
4. Commit one logical change with an English subject and concise body.
5. Update `CHANGELOG.md` and this queue when status changes.
6. Push only to `myfork` after the user explicitly authorizes the push.

## Upstream Status

The official maintainers have said the present history and large bridge are not
reviewable as an upstream PR. An English scope question was posted in official
Discussion #5051 on 2026-08-01. No upstream PR is planned until maintainers
identify a small, independently reviewable contribution.
