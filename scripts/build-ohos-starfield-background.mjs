#!/usr/bin/env node
/**
 * Generate the starfield used as the 3D globe background in the full-screen
 * location picker.
 *
 * Map Kit's `setSphereMapEnabled(..., { backgroundImage })` paints the space
 * around the 3D sphere. Offline Earth and every non-Earth body use
 * `MapType.NONE` + `coverageImage`, so without this image the globe floats on
 * Map Kit's empty-map background instead of a night sky.
 *
 * The image is deterministic (fixed PRNG seed) so regenerating it does not
 * create a spurious diff. It is a 2:1 equirectangular starfield with a faint
 * Milky Way band, matching the mapping of the planet `coverageImage`.
 *
 * Usage:
 *   node scripts/build-ohos-starfield-background.mjs [--force]
 *
 * Output:
 *   harmonyos/ets-source/resources/base/media/space_starfield.png
 */
import { existsSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { deflateSync } from 'node:zlib'

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const ROOT = join(SCRIPT_DIR, '..')
const OUTPUT = join(ROOT, 'harmonyos/ets-source/resources/base/media/space_starfield.png')
const WIDTH = 2048
const HEIGHT = 1024
const FORCE = process.argv.includes('--force')

if (existsSync(OUTPUT) && !FORCE) {
  console.log(`starfield already exists: ${OUTPUT}`)
  console.log('pass --force to regenerate')
  process.exit(0)
}

function mulberry32(seed) {
  let state = seed >>> 0
  return function random() {
    state = (state + 0x6D2B79F5) >>> 0
    let value = state
    value = Math.imul(value ^ (value >>> 15), value | 1)
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61)
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296
  }
}

const random = mulberry32(0x5EED1234)
const pixels = Buffer.alloc(WIDTH * HEIGHT * 3)

// Deep-space base with a very subtle blue gradient. Keep it dark so the planet
// texture stays dominant and night mode's red wash still reads as night.
for (let y = 0; y < HEIGHT; y += 1) {
  const v = y / (HEIGHT - 1)
  for (let x = 0; x < WIDTH; x += 1) {
    const u = x / (WIDTH - 1)
    const index = (y * WIDTH + x) * 3
    const horizon = 1 - Math.abs(v - 0.5) * 2
    pixels[index] = 2 + Math.round(horizon * 2)
    pixels[index + 1] = 3 + Math.round(horizon * 3)
    pixels[index + 2] = 8 + Math.round(horizon * 7 + Math.sin(u * Math.PI * 2) * 1.5)
  }
}

// Faint Milky Way band. The centre line is periodic in x so the left and right
// edges match when the texture is wrapped around the sphere.
for (let y = 0; y < HEIGHT; y += 1) {
  for (let x = 0; x < WIDTH; x += 1) {
    const u = x / WIDTH
    const centre = HEIGHT * (0.53 + 0.09 * Math.sin(u * Math.PI * 4 + 0.7) +
      0.035 * Math.sin(u * Math.PI * 10 + 2.1))
    const dy = y - centre
    const glow = Math.exp(-(dy * dy) / (2 * 95 * 95))
    const lane = Math.exp(-((dy - 8) * (dy - 8)) / (2 * 20 * 20)) * 0.55
    const grain = 0.65 + 0.35 * Math.sin(u * Math.PI * 74 + y * 0.13)
    const strength = glow * grain * (1 - lane)
    const index = (y * WIDTH + x) * 3
    pixels[index] = Math.min(255, pixels[index] + Math.round(9 * strength))
    pixels[index + 1] = Math.min(255, pixels[index + 1] + Math.round(10 * strength))
    pixels[index + 2] = Math.min(255, pixels[index + 2] + Math.round(15 * strength))
  }
}

function drawStar(cx, cy, radius, red, green, blue) {
  const extent = Math.ceil(radius * 2.4)
  for (let oy = -extent; oy <= extent; oy += 1) {
    const y = cy + oy
    if (y < 0 || y >= HEIGHT) continue
    for (let ox = -extent; ox <= extent; ox += 1) {
      let x = cx + ox
      if (x < 0) x += WIDTH
      if (x >= WIDTH) x -= WIDTH
      const d2 = ox * ox + oy * oy
      const weight = Math.exp(-d2 / (2 * radius * radius))
      if (weight < 0.02) continue
      const index = (y * WIDTH + x) * 3
      pixels[index] = Math.min(255, pixels[index] + Math.round(red * weight))
      pixels[index + 1] = Math.min(255, pixels[index + 1] + Math.round(green * weight))
      pixels[index + 2] = Math.min(255, pixels[index + 2] + Math.round(blue * weight))
    }
  }
}

// 9000 field stars with a steep brightness distribution: many faint points,
// a few bright anchors. Colour runs from warm white to blue-white.
for (let i = 0; i < 9000; i += 1) {
  const x = Math.floor(random() * WIDTH)
  const y = Math.floor(random() * HEIGHT)
  const brightness = 26 + Math.pow(random(), 4.2) * 235
  const radius = 0.55 + Math.pow(random(), 3) * 1.6
  const tint = random()
  drawStar(x, y, radius,
    brightness * (0.78 + tint * 0.22),
    brightness * (0.84 + tint * 0.12),
    brightness * (1.0 - tint * 0.18))
}

// A handful of bright stars with short diffraction spikes.
for (let i = 0; i < 36; i += 1) {
  const x = Math.floor(random() * WIDTH)
  const y = Math.floor(random() * HEIGHT)
  drawStar(x, y, 1.7, 255, 250, 240)
  for (let step = 2; step <= 7; step += 1) {
    const alpha = 0.28 * (1 - (step - 2) / 6)
    drawStar(x + step, y, 0.5, 230 * alpha, 230 * alpha, 240 * alpha)
    drawStar(x - step, y, 0.5, 230 * alpha, 230 * alpha, 240 * alpha)
    drawStar(x, y + step, 0.5, 230 * alpha, 230 * alpha, 240 * alpha)
    drawStar(x, y - step, 0.5, 230 * alpha, 230 * alpha, 240 * alpha)
  }
}

// --- Minimal PNG encoder (RGB, 8-bit, no interlace) ------------------------
const CRC_TABLE = new Int32Array(256)
for (let n = 0; n < 256; n += 1) {
  let c = n
  for (let k = 0; k < 8; k += 1) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1)
  CRC_TABLE[n] = c
}

function crc32(buffer) {
  let crc = 0xFFFFFFFF
  for (let i = 0; i < buffer.length; i += 1) {
    crc = CRC_TABLE[(crc ^ buffer[i]) & 0xFF] ^ (crc >>> 8)
  }
  return (crc ^ 0xFFFFFFFF) >>> 0
}

function chunk(type, data) {
  const length = Buffer.alloc(4)
  length.writeUInt32BE(data.length, 0)
  const typeBuffer = Buffer.from(type, 'ascii')
  const payload = Buffer.concat([typeBuffer, data])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(payload), 0)
  return Buffer.concat([length, payload, crc])
}

const ihdr = Buffer.alloc(13)
ihdr.writeUInt32BE(WIDTH, 0)
ihdr.writeUInt32BE(HEIGHT, 4)
ihdr[8] = 8   // bit depth
ihdr[9] = 2   // colour type: RGB
ihdr[10] = 0  // compression
ihdr[11] = 0  // filter
ihdr[12] = 0  // interlace

const scanlines = Buffer.alloc((WIDTH * 3 + 1) * HEIGHT)
for (let y = 0; y < HEIGHT; y += 1) {
  const target = y * (WIDTH * 3 + 1)
  scanlines[target] = 0
  pixels.copy(scanlines, target + 1, y * WIDTH * 3, (y + 1) * WIDTH * 3)
}

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(scanlines, { level: 9 })),
  chunk('IEND', Buffer.alloc(0))
])

writeFileSync(OUTPUT, png)
console.log(`wrote ${OUTPUT} (${(png.length / 1024 / 1024).toFixed(2)} MiB, ${WIDTH}x${HEIGHT})`)
