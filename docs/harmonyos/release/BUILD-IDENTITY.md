# HarmonyOS Build Identity

Current review-fix build (2026-09-08): `1.0.9` / `1000050`, after AGC build `1000049`. The Pad test uses an independent Debug-signed project with this same identity; the main generated project's existing Release signing is unchanged. The development metadata examples below describe the older July workflow, not the currently installed September build. Follow `RELEASE-PACKAGING.md` and the tracked AppScope version for this release.

The AppGallery release identity is the tracked source of truth:

- Name: `星象仪` (`Stellarium` fallback)
- Bundle name: `com.joinother.skyinstrument`
- Icon: the unbadged application icon

The DevEco project under `build/libstellarium-harmonyos/` is generated and ignored by Git. Always prepare an identity before a build. Do not edit its app name or icon by hand.

## Development build

```sh
./scripts/prepare-ohos-dev.sh
cd build/libstellarium-harmonyos
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

This produces `星象仪·开发版` with a blue `DEV` badge on its application and start icons. It intentionally keeps the release bundle name because the current signing profile is bound to `com.joinother.skyinstrument`.

The development build is also marked in the package metadata as `1.0.0-dev.20260729` / `versionCode` `1000100`. The current AppGallery build remains `1.0.0` / `versionCode` `1000000`. Since both use the same bundle name, they cannot be installed side by side. Any future release installed after this development build must use a higher `versionCode` (at least `1000101`).

Consequently, the development build replaces the release app on a device. Do not upload it to AppGallery.

## Release build

Current signing, build-mode and upload instructions: [RELEASE-PACKAGING.md](RELEASE-PACKAGING.md). Identity preparation alone does not select release signing or make a package eligible for submission.

```sh
./scripts/prepare-ohos-release.sh
cd build/libstellarium-harmonyos
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode project -p product=default -p buildMode=release assembleApp --no-daemon
```

Store submission requires a Release-mode `.app` with valid distribution signing, not merely a HAP built after identity preparation. App Pack output is under:

```text
build/libstellarium-harmonyos/build/outputs/default/
```

## Side-by-side installation

To install a dev app next to the store app, create `com.joinother.skyinstrument.dev` in AppGallery Connect and generate a separate development signing profile for that bundle name. The existing release profile rejects a different bundle name during `SignHap`, which is expected.
