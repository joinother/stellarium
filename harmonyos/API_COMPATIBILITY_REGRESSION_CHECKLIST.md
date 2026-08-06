# HarmonyOS API Compatibility Regression Checklist

Run this on clean Debug installs before creating a Release HAP. Do not mark a
row as passed from a command-line launch alone; verify the visible result on
the device.

| Check | API 22 | API 24 |
| --- | --- | --- |
| Cold start reaches the sky map without `SIGABRT` or `copyDefaultConfigFile` failure | | |
| The system-language Chinese sky labels are present | | |
| Browse: a constellation item locks and centers the constellation | | |
| Browse: a named star item locks and centers the star | | |
| Browse: a variable-star item locks and centers the star | | |
| Browse: a catalog-object item locks and centers the object | | |
| Search for `狮子座` selects the constellation, not Leonids | | |

## Required log checks

On first launch, confirm the application log contains both messages:

```text
Created initial user configuration at .../stellarium_userdir/config.ini
Created initial star catalog configuration at .../stellarium_userdir/stars/hip_gaia3/starsConfig.json
```

For browse selection, the native log must report `catalog-select found=true`.
`catalog-select not found`, a zero candidate count for `StarMgr` or
`ConstellationMgr`, or a navigation target of `Leonids` for `狮子座` is a
release blocker.
