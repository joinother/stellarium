# Discussion #5051 简短回复（直接粘贴）

@alex-w

**Positioning**: Desktop QML component removed because HarmonyOS uses `ohos.geoLocationManager` via NAPI bridge directly. World-map picker + city hierarchy included as fallback. Can add it back as toggle if needed.

**No device?** Yes — use DevEco Studio simulator (API 12 phone profile). Full ArkTS + NAPI + OpenGL ES pipeline works. GPS/gyro are simulated.

**Upstream merge**: The C++ command dispatcher in `StelMainView.cpp` is self-contained and could be extracted into an `ENABLE_MOBILE_BRIDGE` compile module. ArkTS/NAPI layer stays in the fork. Happy to send a cleaned-up PR for the dispatcher only.

Current status: 35 bridge commands, full i18n (384 keys), 8 AstroCalc tabs, compact phone shell. All builds green.

Clear skies 🔭
