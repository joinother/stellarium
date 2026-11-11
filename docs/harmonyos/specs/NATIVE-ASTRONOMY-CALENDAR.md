# Native chronological astronomy event feed (2026-11-11)

`getAstronomyCalendarEvents` is implemented in `src/StelMainView.cpp` and registered by the parent in `src/StelOhosCommandCatalog.hpp`. It supplies a chronological visual event feed, queried one month at a time; it does not prescribe a month-grid UI or manual reminder flow. Parent owns the UI, catalog, builds and device validation. Calendar agent Faraday (`01a1ca96-1c16-7313-a171-68f23f22299b`) received the local-month boundary contract and new event-kind schema directly. This expansion adds catalog-based meteor peaks and ephemeris-based planetary events without changing simulation state.

## Request

Either strict `YYYY-MM` or JSON with integer `year` and `month`:

```json
{"year":2026,"month":11,"startJD":2461345.1666666665,"endJD":2461375.1666666665}
```

The example describes November 2026 at UTC+08:00. Supported years are 1–3000, months 1–12 in the proleptic Gregorian calendar, independent of the current simulated year, observing planet or location. A plain month or JSON without boundaries uses UTC midnight boundaries from `QDate`. JSON may supply both `startJD` and `endJD` as finite numbers to request the exact device-local calendar month (including DST), expressed as UT Julian dates. Each boundary must lie within two days of the UTC month boundary and the span must be 27–33 days. One boundary alone, strings/nulls, fractional year/month, invalid months or huge ranges fail before ephemeris work. Membership is `[startJD,endJD)`.

Faraday converts the local Date month boundaries using `unixMs / 86400000 + 2440587.5` and sends JSON. Do not compute this interval using the observation location timezone or change the simulation date to browse months.

## Response

Success contains `ok:true`, `year`, `month`, `startJD`, `endJD`, `timeScale:"UT"`, chronologically sorted `events`, `supportedKinds:["solar-term","moon-phase","meteor-peak","planetary-event"]`, and `unsupportedKinds:["eclipse","satellite-pass"]`. Failure contains `ok:false,error`; a missing/invalid meteor catalog or missing planetary ephemeris also fails explicitly, rather than returning an incomplete feed as complete.

Each event has:

| Field | Meaning |
| --- | --- |
| `id` | `solar-term-<year>-<index>`, `moon-phase-<roundedUnixSecond>-<index>`, `meteor-peak-<code>-<year>-<peakLongitudeTo4Decimals>`, or `planetary-event-<primary>-<secondary>-<subtype>-<roundedUnixSecond>`; independent of the queried month |
| `kind` | `solar-term`, `moon-phase`, `meteor-peak`, or `planetary-event` |
| `index` | Solar term 0–23 from 小寒 through 冬至; phase 0–3 new / first quarter / full / last quarter; 0 placeholder for the new kinds, which must not use phase/term index localization |
| `phase` | Lunar only: `new-moon`, `first-quarter`, `full-moon`, `last-quarter` |
| `title`, `titleEn` | Display titles; UI may localize terms/phases by index and planetary events by subtype/body IDs. Meteor titles retain the catalog's English designation with a localized suffix; UI may translate by `showerCode`. |
| `jd`, `at`, `timeScale` | UT Julian date, rounded Unix milliseconds, `UT` |
| `body` | Global-event explanation, explicitly not a local visibility promise |
| `target` | `Sun`, `Moon`, meteor catalog designation, or primary planet's English name |
| `panel`, `tab` | Solar terms `astro`/8; lunar phases `astro`/6; meteors `meteorshowers`/0; planetary events `astro`/0 |

Additional fields for the new kinds:

| Kind | Fields and interpretation |
| --- | --- |
| `meteor-peak` | `showerCode` (e.g. `PER`, `GEM`), `solarLongitude` (degrees), `longitudeFrame:"J2000"`, `catalogYear` (0 generic, otherwise the matched annual record), `timingQuality:"catalog-estimate"` |
| `planetary-event` | `subtype:"conjunction"|"opposition"|"greatest-elongation"`, `primary`, `secondary` (English body IDs), `separationDegrees` (geocentric apparent angular separation at the event), `timingQuality:"ephemeris"` |
| Inner-planet solar conjunction | Also `alignment:"inferior"|"superior"`, classified by geocentric distance relative to the Sun |
| Greatest elongation | Also `direction:"east"|"west"`; this is angular orientation relative to the Sun, not a local visibility prediction |

The planetary set includes solar conjunctions for Mercury, Venus, Mars, Jupiter, Saturn, Uranus and Neptune; oppositions for Mars through Neptune; greatest elongations for Mercury/Venus; and pairwise conjunctions among Mercury, Venus, Mars, Jupiter and Saturn. Conjunction/opposition means equal/opposite ecliptic longitude, not necessarily minimum angular separation, occultation or transit. Sun conjunctions are usually poor observing opportunities. Moon–planet and planet–star conjunctions are not included in this expansion.

Times follow Stellarium's UT convention using its configured DeltaT model for the TT ephemeris evaluation. They are not TT/JDE and must not have DeltaT subtracted again. Unix representation follows the app's UTC convention; this is not a leap-second-precise UTC/UT1 conversion. Historical and future accuracy depends on the configured DeltaT and ephemeris; solving to subsecond numerical precision is not a claim of subsecond physical accuracy across 1–3000.

## Computation and state boundaries

- Solar terms reuse `SpecificTimeMgr::getSolarTerm(year,index)`, the underlying helper used by `getAlmanac`. It solves apparent solar longitude at 15° intervals using bundled/active Earth ephemerides, precession, nutation and solar aberration. Its implementation brackets on UT and converts each sample to JDE internally. Its header's description of the return as JDE is stale: this endpoint follows the actual implementation and returns the UT root unchanged.
- Four lunar phases reuse the geocentric ecliptic longitude-crossing definition and 0.25-day bracketing from `getMoonPhases`. The new evaluator uses `Planet::computePosition(double, Vec3d&, Vec3d&) const` to obtain Earth heliocentric and Moon geocentric coordinates into local variables at the requested JDE. It applies lunar light time, the same ecliptic-of-date precession transform used by solar terms and solar aberration. Common longitude nutation cancels in the Moon–Sun difference. It never reads the scene's current apparent position or the current observer to compute phases.
- The phase/solar-longitude root finder detects the 360°→0° forward wrap, samples every 0.25 day and refines 25 times. It includes exact start and excludes exact end within 1e-8 day numerical tolerance, covers a shortened final sampling interval and permits repeated same-kind events in a month. Planetary alignments run this kernel in both directions to handle retrograde crossings; a 180° wrap cannot be mistaken for a conjunction. Greatest elongations bracket local maxima of the true angular separation every 0.5 day, including samples beyond both month edges, then refine with 40 ternary-search iterations and filter to the requested half-open interval. Nonfinite samples abort with a calculation error. Event timestamps are global; no rise/set/altitude/azimuth/illumination/visibility fields are fabricated.
- No call to `core->setJD`, `setJDE`, `update`, `setUseTopocentricCoordinates`, location changes, selection changes or camera changes occurs in the new path. Existing `getAlmanac` and `getMoonPhases` command bodies are not invoked, because their RTS/apparent-position paths modify core time. Existing command behavior is unchanged. Ephemeris/math caches used by the existing engine may refresh; the feature does not promise zero internal cache writes.
- Meteor peaks read the bundled `:/MeteorShowers/MeteorShowers.json`, whose source is `plugins/MeteorShowers/resources/MeteorShowers.json`. `MeteorShower::Activity` documents peak longitude as J2000. The endpoint solves the requested year's geocentric solar longitude crossing in that frame using local Earth ephemeris vectors and solar aberration; it does not use the old approximate `JDfromSolarLongitude` calendar formula. Matching annual catalog entries override generic data, inheriting absent/zero peak values as the plugin does. Multiple distinct annual peaks are preserved; identical peak longitudes are deduplicated per shower/year. No entry for the requested year and no generic entry means no event. The continuous Antihelion source (`ANT`) is excluded because it has no discrete annual peak. Calendar-year clipping handles UTC/local month edges independently of the simulated date.
- A meteor timestamp is the calculated passage through a **catalog model's peak longitude**, not a precision forecast of the actual activity maximum or outburst. Generic data is explicitly identified by `catalogYear:0`; even annual data retains `catalog-estimate`. Historical/far-future generic results are extrapolations, not evidence the shower was/will be active. This qualification must remain visible in the feed. No ZHR, observed count, local visibility or year-specific outburst is invented.
- Planetary evaluations use the same const `Planet::computePosition(JDE, localPosition, localVelocity)` API. Earth remains at observation time; the target is evaluated with two light-time iterations and annual aberration (`earthVelocity * lightTime`), following the engine's positional pipeline. Longitude differences use ecliptic-of-date precession; common nutation cancels. Greatest elongation uses the angle between full 3D geocentric vectors. These calculations always use physical light time/aberration, independent of scene display toggles, location and observing planet.
- Existing `MeteorShowers::searchEvents`, `AstroCalcDialog::findDistance`/phenomena searches, `SolarEclipseComputer` and the existing `getEclipses` bridge path use shared core time or mutable current positions. They are not invoked here. Eclipse classification/contact/path calculations require a separately validated read-only implementation; no approximate new/full-moon date is labeled an eclipse. Eclipse and satellite-pass remain explicitly unsupported.

## Validation / parent actions

Run `node --test scripts/test-ohos-native-astronomy-calendar.mjs`. **14 tests pass**. Extracted native numerical search bodies execute with linear/nonlinear longitudes for phases, direct/retrograde/triple conjunctions, exact month boundaries, partial intervals, repeated events and nonfinite failures; angular maxima tests cover boundary extrema and flat/monotonic functions. The extracted meteor activity-selection body executes against bundled data and multi-peak/year-inheritance fixtures, including Leonids 2002 and Geminids 2024. Source contracts verify parsing, direct epoch vectors, no state setters, light time/aberration, UT conversion and extended schema. These tests validate numerical/control behavior, not production ephemeris dates or C++ compilation.

No native/application build, install or commit was run for this expansion. Parent should build, then use:

```sh
node scripts/stellarium-cli.mjs --device <id> --command getAstronomyCalendarEvents --payload 2026-11 --json
node scripts/stellarium-cli.mjs --device <id> --command getAstronomyCalendarEvents --payload '{"year":2026,"month":11,"startJD":2461345.1666666665,"endJD":2461375.1666666665}' --json
```

Verify production ephemeris output against a trusted almanac for phases, terms, Mercury/Venus east/west elongations, inferior/superior conjunctions, Jupiter/Saturn oppositions and direct/retrograde planet conjunctions. Check meteor peak dates around January Quadrantids, August Perseids, November Leonids and December Geminids, including annual overrides; compare the declared J2000 peak-longitude convention, not a fixed calendar date. Measure month-query latency on device before enabling rapid month prefetch. Test February in leap/non-leap years, December→January, local UTC−12/UTC+14 boundaries, DST, months well outside the simulated year, and malformed inputs. Snapshot JD, time rate, location, selected object and topocentric setting before/after calls. Do not hardcode an event count: a month may contain repeated conjunctions or phases and multiple catalog peaks.
