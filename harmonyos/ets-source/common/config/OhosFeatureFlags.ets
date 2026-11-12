// Build-time feature flags for the HarmonyOS shell.
//
// METERED_MAP_APIS_ENABLED gates only the Map Kit server APIs that are metered
// per call on the HMS Core pricing sheet:
//   1. site.searchByText       (online place search in the full-screen picker)
//   2. site.reverseGeocode     (city lookup used to resolve altitude)
//
// The online Petal basemap, terrain/satellite layers (including the read-only
// terrain preview inside the location panel), GPS and all offline data are
// free and deliberately NOT gated by this switch.
//
// The tracked default is `true`. Packaging scripts may rewrite this constant in
// the generated build tree (see scripts/apply-ohos-feature-flags.mjs) without
// touching the working tree:
//   Windows: powershell scripts/build-ohos-hap-windows.ps1 -DisableMeteredMapApis
//   Bash:    OHOS_METERED_MAP_APIS=0 bash scripts/sync-ohos-build-sources.sh
export const METERED_MAP_APIS_ENABLED: boolean = true

// DEV_TOOLS_ENABLED gates the "Development & testing" panel (virtual pointer
// test and watch gyro simulator) and its More-menu entry. The tracked default
// is `true` so local builds can use it; official release packaging should turn
// it off, which removes the entry and the panel body from the build tree:
//   Windows: powershell scripts/build-ohos-hap-windows.ps1 -DisableDevTools
//   Bash:    OHOS_DEV_TOOLS=0 bash scripts/sync-ohos-build-sources.sh
export const DEV_TOOLS_ENABLED: boolean = true
