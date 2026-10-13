<#
.SYNOPSIS
    Windows port of scripts/sync-ohos-resources.sh.

.DESCRIPTION
    Populates the generated hvigor project's rawfile tree with the Stellarium
    data files the C++ core needs at runtime.

    The bash version relies on rsync and ffmpeg. Neither ships with Git for
    Windows, so this port uses robocopy for the directory mirroring and
    System.Drawing for the image processing:

      * 16-bit PNG textures are re-encoded to 8-bit RGBA
      * detail-model CPU textures are exported as raw RGBA sidecars
        (textures/<name>.png.model.rgba — 512x256 planets, 512x2 ring bands)
      * grayscale / indexed sky-culture illustrations are re-encoded to RGBA

    The detail-model sidecars prefer ffmpeg when it can be found (matching the
    bash syncer byte for byte, including the Lanczos scaler); System.Drawing is
    only the fallback when ffmpeg is unavailable. ffmpeg is resolved as
    $env:FFMPEG -> ffmpeg on PATH -> the WinGet (Gyan.FFmpeg) package layout.

    ArkUI ImageKit on HarmonyOS 7.0 rejects the encodings those files use
    upstream, so the normalisation is mandatory and not merely cosmetic.

    The detail-model sidecar parity matters: the C++ detail-model rasteriser
    (DetailModelRasterizer.ets -> loadObjectInspectorModelRawTexture) reads raw
    R,G,B,A bytes, and the bash syncer produces them with ffmpeg's
    `scale=...,format=rgba -f rawvideo`. Without them the app still works, but
    only through a slower per-selection PNG decode fallback. They are generated
    here, as part of this resource sync — so a build that passes
    -SkipResources keeps whatever sidecars the previous sync produced, and a
    build from a frozen rawfile tree must not expect them to be created.

    It also writes data/ohos/skyculture_art_rgba_v1.txt, the evidence file
    StellariumResourceBootstrap.ets requires before it hands off to Qt.

    Whatever is missing from rawfile/stellarium is simply never available on
    the device: the ArkTS bootstrap copies that tree into the app sandbox and
    points STELLARIUM_DATA_ROOT at it.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent directory of this script.

.PARAMETER Out
    Destination rawfile directory. Defaults to
    build/libstellarium-harmonyos/entry/src/main/resources/rawfile/stellarium.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/sync-ohos-resources-windows.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$Out
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Locates an ffmpeg binary the same way the bash syncer does, plus one Windows
# convenience step:
#   1. $env:FFMPEG — an explicit path or command name (the bash `FFMPEG` var)
#   2. ffmpeg on PATH
#   3. the WinGet Gyan.FFmpeg package layout, which is not always on PATH
# Returns $null when none is usable; the caller then falls back to System.Drawing.
function Resolve-FFmpeg {
    if ($env:FFMPEG) {
        $explicit = Get-Command $env:FFMPEG -ErrorAction SilentlyContinue
        if ($explicit) { return $explicit.Source }
        if (Test-Path -LiteralPath $env:FFMPEG -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:FFMPEG).Path
        }
        Write-Warning "FFMPEG=$($env:FFMPEG) could not be resolved; continuing the search"
    }
    $onPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $wingetPackages) {
        $candidates = Get-ChildItem -LiteralPath $wingetPackages -Directory -Filter 'Gyan.FFmpeg*' -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue } |
            Select-Object -First 1
        if ($candidates) { return $candidates.FullName }
    }
    return $null
}

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'data'))) {
    throw "cannot find Stellarium source data at $RepoRoot\data"
}

if (-not $Out -or $Out -eq '') {
    $Out = Join-Path $RepoRoot 'build\libstellarium-harmonyos\entry\src\main\resources\rawfile\stellarium'
}
New-Item -ItemType Directory -Path $Out -Force | Out-Null

# Compile the upstream cross-language sky alias index first; it lives in data/
# and therefore must exist before data/ is mirrored.
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if ($node) {
    Push-Location $RepoRoot
    try { & node (Join-Path $RepoRoot 'scripts\build-ohos-multilingual-search-index.mjs') }
    finally { Pop-Location }
} else {
    Write-Warning 'node not found; reusing the committed data/search/multilingual-sky-aliases.tsv'
}

function Invoke-Mirror {
    param([string]$Source, [string]$Destination, [string[]]$Extra = @())
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $rcArgs = @($Source, $Destination, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1') + $Extra
    & robocopy @rcArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE) for $Source" }
}

Write-Host '==> mirroring full data directories'
foreach ($dir in @('data', 'textures', 'landscapes', 'stars', 'translations', 'scenery3d')) {
    $source = Join-Path $RepoRoot $dir
    if (-not (Test-Path -LiteralPath $source)) { Write-Host "    SKIP (missing): $dir"; continue }
    Invoke-Mirror $source (Join-Path $Out $dir)
    Write-Host "    $dir"
}

Write-Host '==> mirroring nebulae (catalogue indexes and images only)'
Invoke-Mirror (Join-Path $RepoRoot 'nebulae') (Join-Path $Out 'nebulae') @('/IF', '*.dat', '*.json', '*.png')

Write-Host '==> mirroring skycultures (excluding CMake scaffolding)'
Invoke-Mirror (Join-Path $RepoRoot 'skycultures') (Join-Path $Out 'skycultures') `
    @('/XF', 'CMakeLists.txt', 'CMakeLists.txt.template', 'TODO.txt', '*.py')

# scripts/ holds Stellarium's .ssc sky tours together with this repository's own
# build helpers. Only the Stellarium assets may enter rawfile, otherwise hvigor
# flags stray sources and StelScriptMgr lists build scripts as sky tours.
Write-Host '==> mirroring scripts (*.ssc / *.inc only)'
$scriptsSource = Join-Path $RepoRoot 'scripts'
$scriptsDestination = Join-Path $Out 'scripts'
if (Test-Path -LiteralPath $scriptsDestination) { Remove-Item -LiteralPath $scriptsDestination -Recurse -Force }
New-Item -ItemType Directory -Path $scriptsDestination -Force | Out-Null
$scriptCount = 0
foreach ($file in (Get-ChildItem -LiteralPath $scriptsSource -Recurse -File -Force)) {
    if ($file.Extension -ne '.ssc' -and $file.Extension -ne '.inc') { continue }
    $relative = $file.FullName.Substring($scriptsSource.Length).TrimStart('\')
    $target = Join-Path $scriptsDestination $relative
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    $scriptCount++
}
Write-Host "    $scriptCount script file(s)"

function Get-PngFormat {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $header = New-Object byte[] 26
        [void]$stream.Read($header, 0, 26)
    } finally { $stream.Close() }
    $isIhdr = $header[12] -eq 0x49 -and $header[13] -eq 0x48 -and $header[14] -eq 0x44 -and $header[15] -eq 0x52
    if (-not $isIhdr) { return @{ BitDepth = -1; ColorType = -1 } }
    return @{ BitDepth = [int]$header[24]; ColorType = [int]$header[25] }
}

function Convert-PngToRgba {
    param([string]$Path)
    $image = [System.Drawing.Image]::FromFile($Path)
    try {
        $bitmap = New-Object System.Drawing.Bitmap($image.Width, $image.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.DrawImage($image, 0, 0, $image.Width, $image.Height)
        } finally { $graphics.Dispose() }
        $temporary = "$Path.rgba.png"
        $bitmap.Save($temporary, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
    } finally { $image.Dispose() }
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

# Preferred sidecar writer: calls ffmpeg with the exact bash-syncer argument
# vector, so the bytes match upstream bit for bit (Lanczos scaler included).
#   ffmpeg -hide_banner -loglevel error -y -i <png> \
#     -vf 'scale=<w>:<h>:flags=lanczos,format=rgba' -frames:v 1 -pix_fmt rgba \
#     -f rawvideo <png>.model.rgba
# The output path has no ffmpeg-recognised extension, hence the explicit
# `-f rawvideo`. Written through "<sidecar>.tmp" so a crash cannot leave a
# truncated sidecar behind.
function Export-RgbaSidecarWithFfmpeg {
    param([string]$Ffmpeg, [string]$SourcePng, [int]$Width, [int]$Height)
    $sidecar = "$SourcePng.model.rgba"
    $temporary = "$sidecar.tmp"
    $filter = "scale=${Width}:${Height}:flags=lanczos,format=rgba"
    & $Ffmpeg -hide_banner -loglevel error -y -i $SourcePng -vf $filter -frames:v 1 -pix_fmt rgba -f rawvideo $temporary
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE) for $SourcePng" }
    if (-not (Test-Path -LiteralPath $temporary -PathType Leaf)) { throw "ffmpeg produced no output for $SourcePng" }
    Move-Item -LiteralPath $temporary -Destination $sidecar -Force
}

# Fallback sidecar writer, used only when ffmpeg is unavailable. Writes
# "<png>.model.rgba": a headerless raw RGBA buffer at $Width x $Height.
# This mirrors the bash syncer's
#   ffmpeg -vf 'scale=<w>:<h>:flags=lanczos,format=rgba' -pix_fmt rgba -f rawvideo
# as closely as GDI+ allows (HighQualityBicubic + TileFlipXY). The consumer
# (DetailModelRasterizer.ets) reads byte 0 as red, so the GDI+
# Format32bppArgb BGRA memory layout is swizzled into R,G,B,A on the way out.
function Export-RgbaSidecar {
    param([string]$SourcePng, [int]$Width, [int]$Height)
    $sidecar = "$SourcePng.model.rgba"
    $image = [System.Drawing.Image]::FromFile($SourcePng)
    $bitmap = $null
    $graphics = $null
    try {
        $bitmap = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)
        # TileFlipXY mirrors at the borders instead of sampling transparent black
        # outside the source, which is what ffmpeg/swscale effectively does. Without
        # it the resampled RGB darkens toward the edges (visible seams on the
        # equirectangular planet maps and the ring bands).
        $attributes = New-Object System.Drawing.Imaging.ImageAttributes
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $destination = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
        $graphics.DrawImage($image, $destination, 0, 0, $image.Width, $image.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $attributes.Dispose()
        $graphics.Dispose()
        $graphics = $null

        $rect = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
        $locked = $bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $stride = $locked.Stride
            $source = New-Object byte[] ($stride * $Height)
            [System.Runtime.InteropServices.Marshal]::Copy($locked.Scan0, $source, 0, $source.Length)
        } finally {
            $bitmap.UnlockBits($locked)
        }

        $rgba = New-Object byte[] ($Width * $Height * 4)
        for ($y = 0; $y -lt $Height; $y++) {
            $sourceRow = $y * $stride
            $targetRow = $y * $Width * 4
            for ($x = 0; $x -lt $Width; $x++) {
                $s = $sourceRow + ($x * 4)
                $d = $targetRow + ($x * 4)
                $rgba[$d] = $source[$s + 2]     # R (BGRA -> RGBA)
                $rgba[$d + 1] = $source[$s + 1] # G
                $rgba[$d + 2] = $source[$s]     # B
                $rgba[$d + 3] = $source[$s + 3] # A
            }
        }

        # Write through a temporary so an interrupted run never leaves a
        # truncated sidecar that the app would read as "unexpected size".
        $temporary = "$sidecar.tmp"
        [System.IO.File]::WriteAllBytes($temporary, $rgba)
        Move-Item -LiteralPath $temporary -Destination $sidecar -Force
    } finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        $image.Dispose()
    }
}

# Generates detail-model sidecars for the given PNG names. Idempotent: a sidecar
# that already has the expected size and is at least as new as its PNG is kept.
# Uses ffmpeg ($FfmpegBin) when available, otherwise the System.Drawing writer.
function Invoke-DetailModelSidecarBatch {
    param([string[]]$Names, [int]$Width, [int]$Height, [string]$FfmpegBin)
    $texturesRoot = Join-Path $Out 'textures'
    $expectedBytes = $Width * $Height * 4
    $generated = 0
    $reused = 0
    $failed = 0
    foreach ($name in $Names) {
        $source = Join-Path $texturesRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $sidecar = "$source.model.rgba"
        if (Test-Path -LiteralPath $sidecar -PathType Leaf) {
            $sidecarItem = Get-Item -LiteralPath $sidecar
            if ($sidecarItem.Length -eq $expectedBytes -and
                $sidecarItem.LastWriteTimeUtc -ge (Get-Item -LiteralPath $source).LastWriteTimeUtc) {
                $reused++
                continue
            }
        }
        try {
            if ($FfmpegBin) {
                Export-RgbaSidecarWithFfmpeg -Ffmpeg $FfmpegBin -SourcePng $source -Width $Width -Height $Height
            } else {
                Export-RgbaSidecar -SourcePng $source -Width $Width -Height $Height
            }
            $generated++
        } catch {
            $failed++
            Write-Warning "detail-model sidecar failed for ${name}: $($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{ Generated = $generated; Reused = $reused; Failed = $failed }
}

Write-Host '==> normalising 16-bit textures'
$textureCount = 0
foreach ($png in (Get-ChildItem -LiteralPath (Join-Path $Out 'textures') -Recurse -File -Filter '*.png')) {
    if ((Get-PngFormat $png.FullName).BitDepth -eq 16) { Convert-PngToRgba $png.FullName; $textureCount++ }
}
Write-Host "    converted $textureCount 16-bit PNG(s)"

# Detail-model CPU textures. The list is the exact parity set of the bash
# syncer's MODEL_TEXTURES / RING_TEXTURES arrays (and of
# StellariumResourceBootstrap.ets DETAIL_MODEL_TEXTURE_FILES /
# DETAIL_MODEL_RING_TEXTURE_FILES): 512x256 RGBA planets and moons, 512x2 RGBA
# ring bands. Missing source PNGs are skipped, matching the bash `[ -f ]` guard.
$detailModelTextures = @(
    'sun.png', 'mercury.png', 'venus.png', 'earth_cmap.png', 'moon.png', 'mars.png', 'jupiter.png', 'saturn.png',
    'uranus.png', 'neptune.png', 'pluto.png', 'charon.png', 'ceres.png', 'vesta.png', 'eros.png', 'bennu.png',
    'gaspra.png', 'ida.png', 'sedna.png', 'eris.png', 'haumea.png', 'dysnomia.png', '2007OR10.png', 'phobos.png',
    'deimos.png', 'io.png', 'europa.png', 'ganymede.png', 'callisto.png', 'amalthea.png', 'mimas.png', 'enceladus.png',
    'tethys.png', 'dione.png', 'rhea.png', 'titan.png', 'hyperion.png', 'iapetus.png', 'phoebe.png', 'janus.png',
    'epimetheus.png', 'prometheus.png', 'ariel.png', 'umbriel.png', 'titania.png', 'oberon.png', 'miranda.png',
    'triton.png', 'nereid.png', 'proteus.png'
)
$detailRingTextures = @('saturn_rings_radial.png', 'uranus_rings.png', 'neptune_rings.png')

Write-Host '==> generating detail-model CPU texture sidecars'
$ffmpegBin = Resolve-FFmpeg
if ($ffmpegBin) {
    Write-Host "    binary: ffmpeg ($ffmpegBin)"
} else {
    Write-Host '    binary: System.Drawing (ffmpeg not found)'
}
$modelSidecars = Invoke-DetailModelSidecarBatch -Names $detailModelTextures -Width 512 -Height 256 -FfmpegBin $ffmpegBin
Write-Host "    planets: generated $($modelSidecars.Generated), reused $($modelSidecars.Reused), failed $($modelSidecars.Failed)"
$ringSidecars = Invoke-DetailModelSidecarBatch -Names $detailRingTextures -Width 512 -Height 2 -FfmpegBin $ffmpegBin
Write-Host "    rings  : generated $($ringSidecars.Generated), reused $($ringSidecars.Reused), failed $($ringSidecars.Failed)"
if (($modelSidecars.Failed + $ringSidecars.Failed) -gt 0) {
    Write-Warning "$($modelSidecars.Failed + $ringSidecars.Failed) detail-model sidecar(s) could not be written; the app will fall back to decoding the PNG at selection time."
}

Write-Host '==> normalising grayscale / indexed sky-culture illustrations'
$artCount = 0
foreach ($png in (Get-ChildItem -LiteralPath (Join-Path $Out 'skycultures') -Recurse -File -Filter '*.png')) {
    if ($png.DirectoryName -notmatch '\\illustrations$') { continue }
    $colorType = (Get-PngFormat $png.FullName).ColorType
    if ($colorType -eq 0 -or $colorType -eq 3 -or $colorType -eq 4) { Convert-PngToRgba $png.FullName; $artCount++ }
}
Write-Host "    converted $artCount grayscale/indexed PNG(s)"

$markerDirectory = Join-Path $Out 'data\ohos'
New-Item -ItemType Directory -Path $markerDirectory -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $markerDirectory 'skyculture_art_rgba_v1.txt'), "sky-culture-art-rgba-v1`n")

$total = (Get-ChildItem -LiteralPath $Out -Recurse -File -Force | Measure-Object Length -Sum).Sum
Write-Host ''
Write-Host ('rawfile/stellarium size : {0:N0} MB' -f ($total / 1MB))
Write-Host ('skyculture count        : {0}' -f (Get-ChildItem -LiteralPath (Join-Path $Out 'skycultures') -Directory -ErrorAction SilentlyContinue).Count)
Write-Host ('script count            : {0}' -f (Get-ChildItem -LiteralPath (Join-Path $Out 'scripts') -Recurse -File -Filter '*.ssc' -ErrorAction SilentlyContinue).Count)

# These are the exact paths StellariumResourceBootstrap.hasStartupResourceFiles()
# requires before Qt is allowed to start.
$required = @(
    'stars/hip_gaia3/defaultStarsConfig.json',
    'data/ohos/skyculture_art_rgba_v1.txt',
    'translations/stellarium/zh_CN.qm',
    'translations/stellarium-sky/zh_CN.qm',
    'translations/stellarium-skycultures/zh_CN.qm',
    'translations/stellarium-scripts/zh_CN.qm',
    'skycultures/modern/index.json',
    'skycultures/modern/illustrations/andromeda.png',
    'scripts/constellations_tour.ssc',
    'data/default_cfg.ini'
)
$missing = 0
foreach ($relative in $required) {
    $candidate = Join-Path $Out ($relative -replace '/', '\')
    if (Test-Path -LiteralPath $candidate) {
        Write-Host "    OK   $relative"
    } else {
        Write-Host "    MISS $relative"
        $missing++
    }
}
if ($missing -gt 0) { throw "$missing required startup resource(s) are missing; Qt will refuse to start" }
