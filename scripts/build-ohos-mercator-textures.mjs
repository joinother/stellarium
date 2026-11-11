#!/usr/bin/env node
/**
 * Generate the Web-Mercator square textures used by the full-screen location
 * picker's 2D ImageOverlay phase.
 *
 * Why this exists
 * ---------------
 * The 3D globe consumes an equirectangular (2:1) planet texture: one texel per
 * (longitude, latitude) pair. Map Kit switches to its 2D renderer at zoom >= 4,
 * and ImageOverlay stretches its image linearly in the map's Web Mercator
 * projection. Feeding the equirectangular texture to ImageOverlay therefore
 * makes the 2D surface drift away from the globe as latitude increases.
 *
 * The fix is a per-row inverse-Mercator resample:
 *
 *   normalizedY = 1 - 2 * (y + 0.5) / size          // -1 .. +1
 *   latitude    = atan(sinh(pi * normalizedY))       // +/-85.0511 degrees
 *   sourceY     = (0.5 - latitude / pi) * sourceH
 *
 * The explicit formula keeps the result aligned with the ImageOverlay bounds
 * (+/-85.0511 degrees) on every platform. ffmpeg is used only as the PNG/JPEG
 * codec; no projection filter is involved, so the output does not depend on an
 * ffmpeg build option.
 *
 * Sources are the same textures the 3D globe uses, so the 2D phase always
 * matches the sphere:
 *   Moon   -> moon_4k.jpg    (LocationFullScreenMap.rawMapPath special case)
 *   Mars   -> obs_mars.jpg   (rawMapPath's hires Mars texture)
 *   Others -> <tex_map>.png  (ssystem_major.ini tex_map)
 *
 * Usage
 * -----
 *   node scripts/build-ohos-mercator-textures.mjs \
 *     --source build/.../rawfile/stellarium/textures \
 *     --dest   build/.../rawfile/stellarium/textures \
 *     --ffmpeg /path/to/ffmpeg [--size 1024] [--force]
 *
 *   node scripts/build-ohos-mercator-textures.mjs \
 *     --dest build/.../rawfile/stellarium/textures --check
 *
 * --check exits 1 when any overlay is missing or does not have the expected
 * dimensions. Both resource syncers call it after generation, and
 * sync-ohos-build-sources.sh uses it to detect a tree that predates this step
 * and trigger a full resource sync.
 */
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync } from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const DEFAULT_SIZE = 1024

// These names are the exact paths LocationFullScreenMap.mercatorMapPath()
// requests: Moon has a hard-coded moon_4k_mercator.jpg, every other body uses
// <mapTexture base>_mercator.jpg.
// The output size follows the source width: a 512x256 planet map has no more
// horizontal detail to gain from a 1024 px overlay, while the 1024 px Mars
// source and the 4096 px Moon source benefit from 1024 px. Every output is
// square (Web Mercator); `--size` overrides this for one-off tests.
const TEXTURES = [
  // Earth is only used by the offline local globe (MapType.NONE + coverageImage);
  // the online Petal base map draws its own 2D tiles.
  { source: 'earth_cmap.png', output: 'earth_cmap_mercator.jpg', size: 1024 },
  { source: 'moon_4k.jpg', output: 'moon_4k_mercator.jpg', size: 1024 },
  { source: 'mars.png', output: 'mars_mercator.jpg', size: 512 },
  { source: 'mercury.png', output: 'mercury_mercator.jpg', size: 512 },
  { source: 'venus.png', output: 'venus_mercator.jpg', size: 512 },
  { source: 'jupiter.png', output: 'jupiter_mercator.jpg', size: 512 },
  { source: 'saturn.png', output: 'saturn_mercator.jpg', size: 512 },
  { source: 'uranus.png', output: 'uranus_mercator.jpg', size: 512 },
  { source: 'neptune.png', output: 'neptune_mercator.jpg', size: 512 }
]

function parseArgs(argv) {
  const args = { size: undefined, check: false, force: false, help: false }
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    if (argument === '--source') {
      args.source = argv[++index]
    } else if (argument === '--dest') {
      args.dest = argv[++index]
    } else if (argument === '--ffmpeg') {
      args.ffmpeg = argv[++index]
    } else if (argument === '--size') {
      args.size = Number(argv[++index])
    } else if (argument === '--check') {
      args.check = true
    } else if (argument === '--force') {
      args.force = true
    } else if (argument === '--help' || argument === '-h') {
      args.help = true
    } else {
      throw new Error(`unknown argument: ${argument}`)
    }
  }
  return args
}

// Reads the dimensions without decoding the image. PNG IHDR is at bytes
// 16..23; JPEG stores them in the first start-of-frame marker.
function imageSize(buffer) {
  if (buffer.length >= 24 && buffer.toString('ascii', 1, 4) === 'PNG') {
    return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) }
  }
  if (buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    let offset = 2
    while (offset + 9 < buffer.length) {
      if (buffer[offset] !== 0xff) {
        offset += 1
        continue
      }
      const marker = buffer[offset + 1]
      if (marker === 0xd8 || marker === 0xd9 || marker === 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
        offset += 2
        continue
      }
      const length = buffer.readUInt16BE(offset + 2)
      if (length < 2 || offset + 2 + length > buffer.length) break
      const startOfFrame = (marker >= 0xc0 && marker <= 0xc3) ||
        (marker >= 0xc5 && marker <= 0xc7) ||
        (marker >= 0xc9 && marker <= 0xcb) ||
        (marker >= 0xcd && marker <= 0xcf)
      if (startOfFrame) {
        return { height: buffer.readUInt16BE(offset + 5), width: buffer.readUInt16BE(offset + 7) }
      }
      offset += 2 + length
    }
  }
  return null
}

function inspect(dest, sizeOverride) {
  const missing = []
  const invalid = []
  for (const texture of TEXTURES) {
    const expected = sizeOverride || texture.size || DEFAULT_SIZE
    const file = join(dest, texture.output)
    if (!existsSync(file)) {
      missing.push(texture.output)
      continue
    }
    const stat = statSync(file)
    if (stat.size === 0) {
      invalid.push(`${texture.output} (empty)`)
      continue
    }
    const dimensions = imageSize(readFileSync(file))
    if (!dimensions || dimensions.width !== expected || dimensions.height !== expected) {
      const actual = dimensions ? `${dimensions.width}x${dimensions.height}` : 'unknown'
      invalid.push(`${texture.output} (${actual}, expected ${expected}x${expected})`)
    }
  }
  return { missing, invalid, ok: missing.length === 0 && invalid.length === 0 }
}

function isUpToDate(input, output, size) {
  if (!existsSync(output)) return false
  const outputStat = statSync(output)
  if (outputStat.size === 0) return false
  if (outputStat.mtimeMs < statSync(input).mtimeMs) return false
  const dimensions = imageSize(readFileSync(output))
  return Boolean(dimensions && dimensions.width === size && dimensions.height === size)
}

function run(ffmpeg, args, options) {
  const result = spawnSync(ffmpeg, args, options)
  if (result.error) {
    throw new Error(`cannot run ffmpeg (${ffmpeg}): ${result.error.message}`)
  }
  return result
}

function stderrText(result) {
  return result.stderr ? result.stderr.toString('utf8').trim().slice(0, 500) : ''
}

// Decodes any format ffmpeg understands (PNG/JPEG) to tightly packed RGBA.
function decode(ffmpeg, source, width, height) {
  const expectedBytes = width * height * 4
  const result = run(ffmpeg, [
    '-v', 'error',
    '-noautorotate',
    '-i', source,
    '-frames:v', '1',
    '-f', 'rawvideo',
    '-pix_fmt', 'rgba',
    '-'
  ], { maxBuffer: Math.max(64 * 1024 * 1024, expectedBytes + 1024 * 1024) })
  if (result.status !== 0) {
    throw new Error(`ffmpeg failed to decode ${basename(source)}: ${stderrText(result)}`)
  }
  if (result.stdout.length !== expectedBytes) {
    throw new Error(`unexpected decoded size for ${basename(source)}: ` +
      `${result.stdout.length} bytes, expected ${expectedBytes}`)
  }
  return result.stdout
}

// Bilinear resample of an equirectangular RGBA buffer into a Web Mercator
// square. The horizontal mapping stays linear; only the vertical mapping is
// non-linear.
function warpEquirectangularToMercator(source, sourceWidth, sourceHeight, size) {
  const output = Buffer.allocUnsafe(size * size * 4)
  for (let y = 0; y < size; y += 1) {
    const normalizedY = 1 - 2 * (y + 0.5) / size
    const latitude = Math.atan(Math.sinh(Math.PI * normalizedY))
    let sourceY = (0.5 - latitude / Math.PI) * sourceHeight - 0.5
    sourceY = Math.min(sourceHeight - 1, Math.max(0, sourceY))
    const y0 = Math.floor(sourceY)
    const y1 = Math.min(sourceHeight - 1, y0 + 1)
    const fy = sourceY - y0
    const row0 = y0 * sourceWidth * 4
    const row1 = y1 * sourceWidth * 4
    const outputRow = y * size * 4
    for (let x = 0; x < size; x += 1) {
      let sourceX = (x + 0.5) / size * sourceWidth - 0.5
      sourceX = Math.min(sourceWidth - 1, Math.max(0, sourceX))
      const x0 = Math.floor(sourceX)
      const x1 = Math.min(sourceWidth - 1, x0 + 1)
      const fx = sourceX - x0
      const i00 = row0 + x0 * 4
      const i10 = row0 + x1 * 4
      const i01 = row1 + x0 * 4
      const i11 = row1 + x1 * 4
      const outputOffset = outputRow + x * 4
      for (let channel = 0; channel < 3; channel += 1) {
        const top = source[i00 + channel] +
          (source[i10 + channel] - source[i00 + channel]) * fx
        const bottom = source[i01 + channel] +
          (source[i11 + channel] - source[i01 + channel]) * fx
        output[outputOffset + channel] = Math.round(top + (bottom - top) * fy)
      }
      output[outputOffset + 3] = 255
    }
  }
  return output
}

function encode(ffmpeg, pixels, size, output) {
  // Keep a .jpg extension on the temporary file: ffmpeg chooses its muxer from
  // the filename, and a bare ".tmp" would fail with "Unable to choose an output
  // format".
  const temporary = `${output}.tmp.jpg`
  rmSync(temporary, { force: true })
  const result = run(ffmpeg, [
    '-v', 'error',
    '-y',
    '-f', 'rawvideo',
    '-pix_fmt', 'rgba',
    '-s', `${size}x${size}`,
    '-i', '-',
    '-frames:v', '1',
    '-q:v', '3',
    '-pix_fmt', 'yuvj420p',
    temporary
  ], { input: pixels, maxBuffer: 8 * 1024 * 1024 })
  if (result.status !== 0) {
    throw new Error(`ffmpeg failed to encode ${basename(output)}: ${stderrText(result)}`)
  }
  if (!existsSync(temporary) || statSync(temporary).size === 0) {
    throw new Error(`ffmpeg produced no output for ${basename(output)}`)
  }
  rmSync(output, { force: true })
  renameSync(temporary, output)
}

function usage() {
  console.log('Usage: node scripts/build-ohos-mercator-textures.mjs ' +
    '--source <textures-dir> --dest <textures-dir> [--ffmpeg <path>] [--size 1024] [--force]')
  console.log('       node scripts/build-ohos-mercator-textures.mjs ' +
    '--dest <textures-dir> --check')
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    usage()
    return 0
  }
  if (args.size !== undefined &&
    (!Number.isInteger(args.size) || args.size < 64 || args.size > 4096)) {
    throw new Error(`invalid --size: ${args.size}`)
  }
  if (!args.dest) throw new Error('--dest is required')
  const dest = resolve(args.dest)

  if (args.check) {
    const state = inspect(dest, args.size)
    if (!state.ok) {
      if (state.missing.length > 0) {
        console.error(`[mercator] missing: ${state.missing.join(', ')}`)
      }
      if (state.invalid.length > 0) {
        console.error(`[mercator] invalid: ${state.invalid.join(', ')}`)
      }
      return 1
    }
    console.log(`[mercator] all ${TEXTURES.length} overlays present in ${dest}`)
    return 0
  }

  if (!args.source) throw new Error('--source is required unless --check is used')
  const source = resolve(args.source)
  const ffmpeg = args.ffmpeg || process.env.FFMPEG || 'ffmpeg'
  mkdirSync(dest, { recursive: true })

  let generated = 0
  let reused = 0
  for (const texture of TEXTURES) {
    const input = join(source, texture.source)
    const output = join(dest, texture.output)
    const size = args.size || texture.size || DEFAULT_SIZE
    if (!existsSync(input)) {
      throw new Error(`source texture is missing: ${input}`)
    }
    if (!args.force && isUpToDate(input, output, size)) {
      reused += 1
      continue
    }
    const sourceBuffer = readFileSync(input)
    const dimensions = imageSize(sourceBuffer)
    if (!dimensions) {
      throw new Error(`unsupported image format: ${input}`)
    }
    const decoded = decode(ffmpeg, input, dimensions.width, dimensions.height)
    const warped = warpEquirectangularToMercator(decoded, dimensions.width, dimensions.height, size)
    encode(ffmpeg, warped, size, output)
    generated += 1
    console.log(`[mercator] ${texture.source} (${dimensions.width}x${dimensions.height}) -> ` +
      `${texture.output} (${size}x${size})`)
    decoded.fill(0)
    warped.fill(0)
  }

  const state = inspect(dest, args.size)
  const failed = state.missing.length + state.invalid.length
  console.log(`[mercator] generated ${generated}, reused ${reused}, failed ${failed}`)
  return state.ok ? 0 : 1
}

try {
  process.exitCode = main()
} catch (error) {
  console.error(`[mercator] ERROR: ${error.message}`)
  process.exitCode = 1
}
