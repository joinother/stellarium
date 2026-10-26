<#
.SYNOPSIS
    Windows end-to-end builder for the Stellarium HarmonyOS HAP.

.DESCRIPTION
    Chains the steps that are currently only documented for macOS, using the
    tooling that actually exists on Windows:

      1. cross-compile the engine (qt-cmake + the DevEco OHOS toolchain)
      2. repair path-like DT_NEEDED entries left by CPM dependencies that have
         no SONAME (md4c, md4c-html, nlopt) and stage their libraries
      3. harmonydeployqt -> copy the Qt runtime libraries into the project
      4. fill the rawfile resource tree (sync-ohos-resources-windows.ps1)
      5. mirror the tracked sources into the generated project
      6. hvigorw assembleHap --no-daemon

    Signing material is owned by DevEco Studio. This script never writes
    build-profile.json5, AppScope/app.json5, local.properties or any credential:
    configure "Automatically generate signature" once in DevEco Studio and the
    project stays signed.

    The generated project must already exist. On a fresh machine create it once
    with harmonydeployqt --output <dir> and open it in DevEco Studio; see
    docs/harmonyos/BUILD-WINDOWS.md.

.PARAMETER SkipEngine
    Reuse the existing build/src/libstellarium.so instead of recompiling. Also
    skips the DT_NEEDED repair, which must only run right after a fresh link.

.PARAMETER SkipDeploy
    Keep the existing entry/libs/arm64-v8a instead of re-running harmonydeployqt.

.PARAMETER SkipResources
    Keep the existing rawfile tree instead of refilling it. The 16-bit /
    grayscale PNG normalisation AND the detail-model .model.rgba sidecars are
    produced by that resource sync, so skipping it reuses whatever the previous
    sync generated (and leaves a frozen tree without sidecars).

.PARAMETER Install
    Install the signed HAP on the connected device and start QAbility.

.PARAMETER Device
    Device serial for -Install (for example 192.168.3.95:40565). Defaults to
    the only connected target.

.PARAMETER Bundle
    Bundle name to force-stop / start on the device for -Install. Defaults to
    the bundle name recorded in the packaged pack.info (i.e. whatever the local
    signing config produced), so no signing identity is hardcoded here.

.PARAMETER Release
    Build the release variant instead of debug.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/build-ohos-hap-windows.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/build-ohos-hap-windows.ps1 -SkipEngine -Install -Device 192.168.3.95:40565
#>
[CmdletBinding()]
param(
    [switch]$SkipEngine,
    [switch]$SkipDeploy,
    [switch]$SkipResources,
    [switch]$Install,
    [string]$Device,
    [string]$Bundle,
    [switch]$Release,
    # '' = keep the existing CMake cache; 'online'/'offline' sets
    # STELLARIUM_OHOS_OFFLINE for the engine configure step.
    [ValidateSet('', 'offline', 'online')]
    [string]$NetworkMode = ''
)

$ErrorActionPreference = 'Stop'

# --- locations (override through the environment) -------------------------
$RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ProjectRoot  = Join-Path $RepoRoot 'build\libstellarium-harmonyos'
$EngineBuild  = Join-Path $RepoRoot 'build'

$DevecoHome   = if ($env:DEVECO_HOME)     { $env:DEVECO_HOME }     else { 'E:\code\Huawei\DevEco Studio' }
$QtOhos       = if ($env:QT_OHOS_PREFIX)  { $env:QT_OHOS_PREFIX }  else { 'E:\Qt\6.12.0\harmonyos_arm64_v8a' }
$QtHost       = if ($env:QT_HOST_PATH)    { $env:QT_HOST_PATH }    else { 'E:\Qt\6.12.0\mingw_64' }
$SdkNative    = if ($env:OHOS_NATIVE_ROOT){ $env:OHOS_NATIVE_ROOT }else { Join-Path $DevecoHome 'sdk\default\openharmony\native' }

$NodeExe      = Join-Path $DevecoHome 'tools\node\node.exe'
$HvigorJs     = Join-Path $DevecoHome 'tools\hvigor\bin\hvigorw.js'
$JavaHome     = Join-Path $DevecoHome 'jbr'
$HdcExe       = Join-Path $DevecoHome 'sdk\default\openharmony\toolchains\hdc.exe'
$ReadelfExe   = Join-Path $SdkNative 'llvm\bin\llvm-readelf.exe'

$AppLibs      = Join-Path $ProjectRoot 'entry\libs\arm64-v8a'
$BuildMode    = if ($Release) { 'release' } else { 'debug' }
$UnsignedHap  = Join-Path $ProjectRoot "entry\build\default\outputs\default\entry-default-unsigned.hap"
$SignedHap    = Join-Path $ProjectRoot "entry\build\default\outputs\default\entry-default-signed.hap"

# pack.info carries the signed bundle name (whatever the local signing config
# produced) and is the cheapest way to confirm the module was packaged at all.
$PackInfo     = Join-Path $ProjectRoot 'entry\build\default\outputs\default\pack.info'

function Assert-Path {
    param([string]$Path, [string]$What)
    if (-not (Test-Path -LiteralPath $Path)) { throw "$What not found: $Path" }
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ''
    Write-Host "===== $Name =====" -ForegroundColor Cyan
    & $Body
}

Assert-Path $NodeExe   'DevEco node'
Assert-Path $HvigorJs  'hvigorw.js'
Assert-Path $ProjectRoot 'generated hvigor project'
Assert-Path (Join-Path $ProjectRoot 'hvigor\hvigor-config.json5') 'hvigor-config.json5'

# The Qt HarmonyOS kit ships no host tools and hardcodes an /opt/harmonyos
# chainload path, so both variables must be passed explicitly.
Assert-Path (Join-Path $QtOhos 'bin\qt-cmake.bat') 'qt-cmake.bat'
Assert-Path (Join-Path $SdkNative 'build\cmake\ohos.toolchain.cmake') 'ohos.toolchain.cmake'
$SdkInclude = Join-Path $SdkNative 'sysroot\usr\include'

# hvigor spawns java for app_packing_tool.jar / hap-sign-tool.jar. When DevEco
# Studio is open its resident hvigor daemon owns the task graph and its PATH may
# lack java, which surfaces as "spawn java ENOENT". Prepending java and running
# with --no-daemon keeps this build self-contained.
$env:NODE_HOME = Join-Path $DevecoHome 'tools\node'
$env:JAVA_HOME = $JavaHome
$env:DEVECO_SDK_HOME = Join-Path $DevecoHome 'sdk'
$env:OHOS_BASE_SDK_HOME = Join-Path $DevecoHome 'sdk\default\openharmony'
$env:PATH = "$(Join-Path $DevecoHome 'tools\node');$(Join-Path $JavaHome 'bin');$env:PATH"

<#
    cmake records the path a shared library was linked from whenever that
    library has no SONAME. The Qt OHOS toolchain sets
    CMAKE_PLATFORM_NO_VERSIONED_SONAME, and the md4c / nlopt targets come from
    CPM without VERSION or SOVERSION, so libstellarium.so ends up needing
    "_deps/md4c-build/src/libmd4c-html.so" instead of "libmd4c-html.so" and the
    device loader fails with "Error loading shared library". Rewriting the
    string in .dynstr to the bare name (NUL padded, so the entry stays inside
    its original slot) makes the shipped libraries load. Re-run after every
    engine link. The proper fix is to give those targets a SONAME in CMake.
#>
$NeededRewrites = [ordered]@{
    '_deps/md4c-build/src/libmd4c-html.so' = 'libmd4c-html.so'
    '_deps/md4c-build/src/libmd4c.so'      = 'libmd4c.so'
    '_deps/nlopt-build/libnlopt.so'        = 'libnlopt.so'
}

function Repair-NeededPaths {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Host "    SKIP (missing) $(Split-Path -Leaf $Path)"; return }
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $text = $latin1.GetString([System.IO.File]::ReadAllBytes($Path))
    $patched = 0
    foreach ($old in $NeededRewrites.Keys) {
        $new = $NeededRewrites[$old]
        if ($new.Length -gt $old.Length) { throw "replacement longer than original: $new" }
        $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
        if ($count -gt 0) {
            $text = $text.Replace($old, $new + ([string][char]0 * ($old.Length - $new.Length)))
            $patched += $count
            Write-Host "    $old -> $new ($count)"
        }
    }
    if ($patched -gt 0) {
        [System.IO.File]::WriteAllBytes($Path, $latin1.GetBytes($text))
        Write-Host "    patched $patched entry(ies) in $(Split-Path -Leaf $Path)"
    }
}

function Get-PathLikeNeeded {
    param([string]$Directory)
    # Only DT_NEEDED matters here. RPATH / RUNPATH entries also contain paths
    # (Qt's own plugins carry /usr/local/Qt-6.12.0/lib, and the engine carries
    # its build tree) but the loader simply ignores those on device.
    $bad = @()
    foreach ($so in (Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter '*.so')) {
        & $ReadelfExe -d $so.FullName 2>$null | ForEach-Object {
            if ($_ -match '\(NEEDED\).*\[(.+/[^]]+)\]') { $bad += "$($so.Name) -> $($matches[1])" }
        }
    }
    return $bad
}

# --- 1. engine -------------------------------------------------------------
if (-not $SkipEngine) {
    Invoke-Step 'configure the engine for OHOS' {
        $configureArgs = @(
            '-S', $RepoRoot, '-B', $EngineBuild, '-G', 'Ninja',
            '-DCMAKE_BUILD_TYPE=Release',
            "-DQT_HOST_PATH=$QtHost",
            "-DQT_CHAINLOAD_TOOLCHAIN_FILE=$(Join-Path $SdkNative 'build\cmake\ohos.toolchain.cmake')",
            # find_path() cannot reach the sysroot on a Windows host, so the
            # GLESv3 / EGL include directories are supplied directly. Without
            # them Qt6Gui reports NOT FOUND and the configure aborts.
            "-DGLESv3_INCLUDE_DIR=$SdkInclude",
            "-DEGL_INCLUDE_DIR=$SdkInclude",
            '-DENABLE_NLS=0', '-DENABLE_QTWEBENGINE=0', '-DENABLE_SPEECH=0',
            '-DENABLE_GPS=0', '-DENABLE_INDI=0', '-DENABLE_MEDIA=0',
            '-DENABLE_SHOWMYSKY=0', '-DENABLE_XLSX=0'
        )
        if ($NetworkMode) {
            $offlineFlag = if ($NetworkMode -eq 'online') { 'OFF' } else { 'ON' }
            Write-Host "    network mode: $NetworkMode (STELLARIUM_OHOS_OFFLINE=$offlineFlag)"
            $configureArgs += "-DSTELLARIUM_OHOS_OFFLINE=$offlineFlag"
        }

        # Stellarium pulls md4c, nlopt and (because OHOS libc++ has no floating
        # point std::from_chars) header-only fast_float through CPM/FetchContent.
        # When those sources are already on disk, configure offline: re-cloning
        # is both slow and fatal on networks that cannot reach github.com.
        $depSources = @('fastfloat', 'md4c', 'nlopt') | ForEach-Object { Join-Path $EngineBuild ('_deps\' + $_ + '-src') }
        if (($depSources | Where-Object { Test-Path -LiteralPath $_ }).Count -eq $depSources.Count) {
            Write-Host '    dependency sources already staged; configuring with FETCHCONTENT_FULLY_DISCONNECTED'
            $configureArgs += '-DFETCHCONTENT_FULLY_DISCONNECTED=ON'
        } else {
            Write-Host '    dependency sources incomplete; the configure step needs network access'
        }

        & (Join-Path $QtOhos 'bin\qt-cmake.bat') @configureArgs
        if ($LASTEXITCODE -ne 0) { throw "qt-cmake configure failed ($LASTEXITCODE)" }
    }

    Invoke-Step 'compile the engine' {
        & cmake --build $EngineBuild --parallel
        if ($LASTEXITCODE -ne 0) { throw "engine build failed ($LASTEXITCODE)" }
    }

    Invoke-Step 'repair path-like DT_NEEDED entries' {
        Repair-NeededPaths (Join-Path $EngineBuild 'src\libstellarium.so')
        Repair-NeededPaths (Join-Path $EngineBuild '_deps\md4c-build\src\libmd4c-html.so')
        Repair-NeededPaths (Join-Path $EngineBuild '_deps\md4c-build\src\libmd4c.so')
        Repair-NeededPaths (Join-Path $EngineBuild '_deps\nlopt-build\libnlopt.so')
    }
}

Assert-Path (Join-Path $EngineBuild 'src\libstellarium.so') 'compiled engine (build/src/libstellarium.so)'

# --- 2. Qt runtime libraries ----------------------------------------------
if (-not $SkipDeploy) {
    Invoke-Step 'deploy the Qt runtime libraries' {
        $DeploymentSettings = Join-Path $EngineBuild 'src\stellarium-harmony-deployment-settings.json'
        Assert-Path $DeploymentSettings 'Qt deployment settings'
        $staging = Join-Path $env:TEMP 'stellarium-harmony-deploy'
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
        # --output is a throwaway directory on purpose: pointing it at the
        # generated project would overwrite build-profile.json5 and drop the
        # signing configuration DevEco Studio owns.
        & (Join-Path $QtHost 'bin\harmonydeployqt.exe') --input $DeploymentSettings --output $staging --no-build
        if ($LASTEXITCODE -ne 0) { throw "harmonydeployqt failed ($LASTEXITCODE)" }
        $stagedLibs = Join-Path $staging 'entry\libs\arm64-v8a'
        Assert-Path $stagedLibs 'deployed native libraries'
        if (Test-Path -LiteralPath $AppLibs) { Remove-Item -LiteralPath $AppLibs -Recurse -Force }
        New-Item -ItemType Directory -Path (Split-Path -Parent $AppLibs) -Force | Out-Null
        Copy-Item -LiteralPath $stagedLibs -Destination $AppLibs -Recurse -Force
        Write-Host "    $((Get-ChildItem -LiteralPath $AppLibs -Recurse -File).Count) file(s) -> entry/libs/arm64-v8a"
    }
}

Invoke-Step 'stage the CPM dependency libraries' {
    # harmonydeployqt only knows about Qt and the application binary, so the
    # md4c / nlopt libraries the engine links against must be copied in.
    New-Item -ItemType Directory -Path $AppLibs -Force | Out-Null
    $dependencies = @(
        @((Join-Path $EngineBuild '_deps\md4c-build\src\libmd4c-html.so'), 'libmd4c-html.so'),
        @((Join-Path $EngineBuild '_deps\md4c-build\src\libmd4c.so'),      'libmd4c.so'),
        @((Join-Path $EngineBuild '_deps\nlopt-build\libnlopt.so'),        'libnlopt.so')
    )
    foreach ($pair in $dependencies) {
        Assert-Path $pair[0] $pair[1]
        Copy-Item -LiteralPath $pair[0] -Destination (Join-Path $AppLibs $pair[1]) -Force
        Write-Host "    $($pair[1])"
    }
    $bad = Get-PathLikeNeeded $AppLibs
    if ($bad.Count -gt 0) {
        $bad | ForEach-Object { Write-Host "    UNRESOLVED $_" }
        throw 'path-like DT_NEEDED entries remain; the app will fail to load the engine'
    }
    Write-Host '    every DT_NEEDED entry is a plain library name'
}

# --- 3. rawfile resources --------------------------------------------------
if (-not $SkipResources) {
    Invoke-Step 'fill the rawfile resource tree' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'sync-ohos-resources-windows.ps1') -RepoRoot $RepoRoot
        if ($LASTEXITCODE -ne 0) { throw "resource sync failed ($LASTEXITCODE)" }
    }
}

# --- 4. mirror tracked sources --------------------------------------------
Invoke-Step 'mirror the tracked sources into the generated project' {
    $gitBash = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $gitBash) { $gitBash = (Get-Command bash -ErrorAction SilentlyContinue).Source }
    if (-not $gitBash) { throw 'bash not found; install Git for Windows or run scripts/sync-ohos-build-sources.sh manually' }
    & $gitBash -c "cd '$($RepoRoot -replace '\\','/')' && bash scripts/sync-ohos-build-sources.sh"
    if ($LASTEXITCODE -ne 0) { throw "source sync failed ($LASTEXITCODE)" }
}

# --- 5. package ------------------------------------------------------------
Invoke-Step "assemble the HAP ($BuildMode)" {
    Push-Location $ProjectRoot
    try {
        & $NodeExe $HvigorJs --mode module -p product=default -p buildMode=$BuildMode assembleHap --analyze=normal --parallel --no-daemon
        if ($LASTEXITCODE -ne 0) { throw "hvigor assembleHap failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
    Assert-Path $PackInfo 'pack.info'
    if (Test-Path -LiteralPath $SignedHap) {
        Write-Host ('    signed HAP: {0:N1} MB' -f ((Get-Item -LiteralPath $SignedHap).Length / 1MB))
    } else {
        Write-Host '    WARNING: no signed HAP produced; configure automatic signing in DevEco Studio'
    }
}

# --- 6. optional install ---------------------------------------------------
if ($Install) {
    Invoke-Step 'install on the device' {
        Assert-Path $HdcExe 'hdc'
        if (-not (Test-Path -LiteralPath $SignedHap)) { throw "signed HAP not found: $SignedHap" }

        if (-not $Device) {
            $first = & $HdcExe list targets 2>$null | Where-Object { $_ -match '\S' } | Select-Object -First 1
            if (-not $first -or $first -match '^\[Empty\]') { throw 'no device connected; pass -Device <serial>' }
            $Device = ($first -split '\s+')[0]
            Write-Host "    using the only connected target: $Device"
        }

        # The bundle name is whatever the local signing config produced; read it
        # from the packaged metadata instead of hardcoding a signing identity.
        $BundleName = $Bundle
        if (-not $BundleName) {
            Assert-Path $PackInfo 'pack.info'
            $BundleName = (Get-Content -LiteralPath $PackInfo -Raw -Encoding UTF8 | ConvertFrom-Json).summary.app.bundleName
        }
        if (-not $BundleName) { throw 'cannot determine the bundle name; pass -Bundle <name>' }
        Write-Host "    bundle: $BundleName"

        & $HdcExe -t $Device shell "aa force-stop $BundleName" | Out-Null
        & $HdcExe -t $Device file send $SignedHap /data/local/tmp/stellarium.hap
        if ($LASTEXITCODE -ne 0) { throw 'hdc file send failed' }
        & $HdcExe -t $Device shell 'bm install -p /data/local/tmp/stellarium.hap -r -w 600'
        if ($LASTEXITCODE -ne 0) { throw 'bm install failed' }

        # The device must be unlocked: in developer mode aa start cannot unlock
        # the screen and fails with 10106102.
        & $HdcExe -t $Device shell "aa start -b $BundleName -a QAbility"
        if ($LASTEXITCODE -ne 0) { throw 'aa start failed; unlock the device and keep the screen awake' }
        Start-Sleep -Seconds 20
        & $HdcExe -t $Device shell "ps -ef | grep $BundleName"
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
