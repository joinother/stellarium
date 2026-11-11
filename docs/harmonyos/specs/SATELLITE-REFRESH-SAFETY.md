# Satellite refresh safety and subscription epoch boundary

## Implemented behavior

`plugins/Satellites/src/Satellites.cpp` stages a refresh before changing live objects. Every configured source must download, write completely to its temporary file, open and parse successfully. An empty source, malformed record, incomplete TLE pair, invalid checksum, CSV warning or file read error rejects the batch. A source parser merges its records only after the entire source succeeds. Existing public parser signatures remain unchanged; `QFile` property `tleParseComplete` communicates completeness to batch callers.

Catalog writes use `QSaveFile` with direct-write fallback disabled. Serialization, full write and atomic commit must succeed. Open, write, serialization and commit failures preserve the existing catalog and return false. Refresh callers emit `OtherError` and leave live objects and the successful-update timestamp unchanged on save failure. Added-only refreshes also persist. `saveCatalog()` retains its existing void signature and reports persistence failure through `updateStateChanged(OtherError)`; its GUI callers already mutate their editing state before saving, so those individual edits are not rolled back automatically.

Refreshes retain absent and invalid-orbit objects, including when auto-remove was previously enabled. Current records have no reliable persisted source ownership; a missing record cannot distinguish disappearance from an unrelated feed or manual import. Manual deletion remains available. User-defined objects are protected from overwrite. Existing per-object metadata survives refresh; only changed records are applied after commit. A successful no-change refresh may advance the successful-update timestamp without rewriting the catalog.

The parser accepts complete named three-line and unnamed two-line TLE records, verifies matching IDs, Alpha-5 format, checksums and basic orbital numeric bounds. Unnamed records start with `StatusUnknown`, including after a previous record's status is reset. Space-padded numeric IDs and the bundled line-1 column-34 `0` derivative notation are accepted; checksum validation uses the original lines before compatibility normalization. CSV parsing supports quoted headers, names containing commas and doubled-quote escapes such as `"ISS, ""ZARYA"""`. Malformed quoting, field counts, numeric values or other CSV warnings still invalidate the complete source. CSV epoch conversion calculates January 1 for each record's year rather than retaining the first parsed year.

## Explicit prediction epochs: unavailable, fail closed

The shared `getSatellitePasses` / `getSatelliteDetail` handler preserves its JSON object envelope. Any JSON object containing `startJD` returns:

```json
{
  "ok": false,
  "reason": "explicit_epoch_prediction_unsupported",
  "error": "Explicit satellite prediction epochs require a nonmutating predictor; satellite subscriptions are unavailable"
}
```

This return occurs before selection lookup or prediction. No `startJD` value is silently ignored, including null or invalid values. Legacy UI requests without `startJD` retain their simulation-relative behavior and response shape.

`Satellite::getPassPredictions` currently calls `core->setJD`, `core->update`, and mutates the live satellite before restoring state. `gSatWrapper` also shares observer/epoch/Sun caches. Adding a starting JD parameter would not meet the read-only subscription requirement. `Satellite.cpp/.hpp` remain unchanged. A future implementation needs isolated propagation plus local observer and Sun geometry, followed by numerical and state-preservation tests. Satellite subscriptions must remain unavailable; do not strip `startJD` or relabel legacy predictions as wall-clock calculations. Dalton was informed of the exact error fields.

## Validation and handoff

Final validation on November 11, 2026: `node scripts/test-ohos-satellite-refresh-safety.mjs` passes **20/20** tests. The parent reports the native build succeeded after the parser compatibility fixes and the combined suite passed **73/73**, including these 20 satellite tests (not an additional 20).

The focused tests execute extracted C++ function bodies translated to JavaScript with mocked Qt boundaries: atomic save, source parsing, TLE validation/parsing and CSV tokenization/field mapping. Coverage includes all **3,134 bundled TLE pairs**, including the **166** column-34 compatibility cases, first/subsequent unnamed 2LE status, quoted 17-column CSV input, and whole-source rejection after malformed tails. CSV-to-TLE generation is stubbed in the field-mapping tests. Additional source contracts check complete-batch gating, commit-before-mutation ordering, object retention and explicit-epoch rejection. These tests do not execute native Qt filesystem operations or orbital propagation.

The native build and combined-suite results above are parent-reported; this task did not build or install. No Pad installation or device acceptance result is asserted here. Explicit epoch prediction remains unsupported, with the unchanged JSON object error envelope documented above. Implementation scope is closed for this round; further prediction work is deferred.
