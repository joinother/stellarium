#!/usr/bin/env node
/**
 * 将上游 models/*.obj(.gz) 真实探测器 3D 小天体/不规则卫星网格烘焙为鸿蒙
 * DetailModelNative.cpp 可直接光栅化的紧凑二进制 SBM1 格式（models/ohos/*.sbm）。
 *
 * SBM1 二进制布局（小端）：
 *   0..3   : magic "SBM1"
 *   4..7   : uint32 vertexCount
 *   8..11  : uint32 indexCount (3 * triangleCount)
 *   12..15 : uint32 flags (bit 0 = hasUV)
 *   16..27 : float32[3] baseColorRGB (0..1，无贴图时的真实反照率基色)
 *   28..   : vertexCount * 8 float32 [px, py, pz, nx, ny, nz, u, v]
 *            + indexCount * uint32 triangle indices
 *
 * 用法：
 *   node scripts/build-ohos-minor-body-meshes.mjs [--out <dir>] [--check]
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { gunzipSync } from 'node:zlib'

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = resolve(SCRIPT_DIR, '..')
const MODELS_DIR = join(REPO_ROOT, 'models')

export const MINOR_BODY_MESH_SPECS = [
  { key: 'halley',     obj: '1682q1halley_MLfix.obj',    texture: '',               baseColor: [0.46, 0.45, 0.43], credit: '乔托号实测 3D 彗核' },
  { key: '67p',        obj: '67P_lowres.obj',            texture: '',               baseColor: [0.48, 0.46, 0.43], credit: '罗塞塔号实测 3D 彗核' },
  { key: 'vesta',      obj: '4vesta_21_MLfix.obj',       texture: '4vesta.png',     baseColor: [0.78, 0.76, 0.72], credit: '黎明号实测 3D 地形模型' },
  { key: 'phobos',     obj: 'm1phobos.obj.gz',           texture: 'm1phobos.png',   baseColor: [0.66, 0.61, 0.57], credit: '火星快车实测 3D 形态模型' },
  { key: 'deimos',     obj: 'm2deimos.obj.gz',           texture: 'm2deimos.png',   baseColor: [0.70, 0.65, 0.60], credit: '火星探测实测 3D 形态模型' },
  { key: 'ida',        obj: '243ida_MLfix.obj',          texture: '243ida.png',     baseColor: [0.72, 0.69, 0.65], credit: '伽利略号实测 3D 形态模型' },
  { key: 'gaspra',     obj: '951gaspra_MLfix.obj',       texture: '951gaspra.png',  baseColor: [0.74, 0.68, 0.62], credit: '伽利略号实测 3D 形态模型' },
  { key: 'amalthea',   obj: 'j5amalthea_MLfix.obj',      texture: 'j5amalthea.png', baseColor: [0.76, 0.52, 0.42], credit: '伽利略号实测 3D 形态模型' },
  { key: 'hyperion',   obj: 's7hyperion_21_MLfix.obj',   texture: 'hyperion.png',   baseColor: [0.75, 0.70, 0.64], credit: '卡西尼号实测 3D 形态模型' },
  { key: 'janus',      obj: 's10janus_MLfix.obj',        texture: 's10janus.png',   baseColor: [0.78, 0.78, 0.77], credit: '卡西尼号实测 3D 形态模型' },
  { key: 'epimetheus', obj: 's11epimetheus_MLfix.obj',   texture: 's11epimetheus.png', baseColor: [0.76, 0.76, 0.75], credit: '卡西尼号实测 3D 形态模型' },
  { key: 'prometheus', obj: 's16prometheus_MLfix.obj',   texture: 's16prometheus.png', baseColor: [0.78, 0.77, 0.75], credit: '卡西尼号实测 3D 形态模型' },
  { key: 'pandora',    obj: 's17pandora_MLfix.obj',      texture: '',               baseColor: [0.74, 0.73, 0.71], credit: '卡西尼号实测 3D 形态模型' },
  { key: 'larissa',    obj: 'n7larissa_MLfix.obj',       texture: '',               baseColor: [0.65, 0.66, 0.69], credit: '旅行者 2 号实测 3D 形态模型' },
  { key: 'proteus',    obj: 'n8proteus_MLfix.obj',       texture: 'n8proteus.png',  baseColor: [0.62, 0.63, 0.65], credit: '旅行者 2 号实测 3D 形态模型' },
]

function resolveIndex(raw, count) {
  const idx = parseInt(raw, 10)
  if (!Number.isFinite(idx) || idx === 0) return -1
  return idx > 0 ? idx - 1 : count + idx
}

function parseObjToSbm(objText, baseColor) {
  const pos = []
  const uvs = []
  const norms = []
  const vertMap = new Map()
  const outVerts = []
  const outIndices = []
  let hasAnyUv = false
  let hasAnyNorm = false

  const lines = objText.split(/\r?\n/)
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line.length < 2 || line.charCodeAt(0) === 35) continue
    if (line.startsWith('v ')) {
      const p = line.split(/\s+/)
      if (p.length >= 4) {
        pos.push(parseFloat(p[1]), parseFloat(p[2]), parseFloat(p[3]))
      }
    } else if (line.startsWith('vt ')) {
      const p = line.split(/\s+/)
      if (p.length >= 3) {
        uvs.push(parseFloat(p[1]), parseFloat(p[2]))
      }
    } else if (line.startsWith('vn ')) {
      const p = line.split(/\s+/)
      if (p.length >= 4) {
        norms.push(parseFloat(p[1]), parseFloat(p[2]), parseFloat(p[3]))
      }
    } else if (line.startsWith('f ')) {
      const parts = line.split(/\s+/).slice(1)
      if (parts.length < 3) continue
      const polyIdx = []
      for (const tok of parts) {
        let idx = vertMap.get(tok)
        if (idx === undefined) {
          const seg = tok.split('/')
          const vi = resolveIndex(seg[0], pos.length / 3)
          if (vi < 0) continue
          const ti = seg.length > 1 && seg[1].length > 0 ? resolveIndex(seg[1], uvs.length / 2) : -1
          const ni = seg.length > 2 && seg[2].length > 0 ? resolveIndex(seg[2], norms.length / 3) : -1
          const px = pos[vi * 3] ?? 0
          const py = pos[vi * 3 + 1] ?? 0
          const pz = pos[vi * 3 + 2] ?? 0
          let nx = 0, ny = 0, nz = 0
          if (ni >= 0) {
            nx = norms[ni * 3] ?? 0
            ny = norms[ni * 3 + 1] ?? 0
            nz = norms[ni * 3 + 2] ?? 0
            hasAnyNorm = true
          }
          let u = 0, v = 0
          if (ti >= 0) {
            u = uvs[ti * 2] ?? 0
            v = 1.0 - (uvs[ti * 2 + 1] ?? 0)
            hasAnyUv = true
          }
          idx = outVerts.length / 8
          outVerts.push(px, py, pz, nx, ny, nz, u, v)
          vertMap.set(tok, idx)
        }
        polyIdx.push(idx)
      }
      for (let t = 1; t + 1 < polyIdx.length; t++) {
        outIndices.push(polyIdx[0], polyIdx[t], polyIdx[t + 1])
      }
    }
  }

  const vertexCount = outVerts.length / 8
  const indexCount = outIndices.length
  if (vertexCount < 3 || indexCount < 3) {
    throw new Error(`Invalid OBJ mesh: vertices=${vertexCount}, indices=${indexCount}`)
  }

  // Center at bounding-box midpoint and normalize to unit max radius
  let minX = Infinity, maxX = -Infinity
  let minY = Infinity, maxY = -Infinity
  let minZ = Infinity, maxZ = -Infinity
  for (let i = 0; i < vertexCount; i++) {
    const b = i * 8
    const x = outVerts[b], y = outVerts[b + 1], z = outVerts[b + 2]
    if (x < minX) minX = x; if (x > maxX) maxX = x
    if (y < minY) minY = y; if (y > maxY) maxY = y
    if (z < minZ) minZ = z; if (z > maxZ) maxZ = z
  }
  const cx = (minX + maxX) * 0.5
  const cy = (minY + maxY) * 0.5
  const cz = (minZ + maxZ) * 0.5
  let maxR2 = 0
  for (let i = 0; i < vertexCount; i++) {
    const b = i * 8
    const dx = outVerts[b] - cx
    const dy = outVerts[b + 1] - cy
    const dz = outVerts[b + 2] - cz
    outVerts[b] = dx
    outVerts[b + 1] = dy
    outVerts[b + 2] = dz
    const r2 = dx * dx + dy * dy + dz * dz
    if (r2 > maxR2) maxR2 = r2
  }
  const invR = maxR2 > 1e-12 ? 1.0 / Math.sqrt(maxR2) : 1.0
  for (let i = 0; i < vertexCount; i++) {
    const b = i * 8
    outVerts[b] *= invR
    outVerts[b + 1] *= invR
    outVerts[b + 2] *= invR
  }

  // Compute smooth vertex normals if OBJ had none, or normalize existing ones
  if (!hasAnyNorm) {
    for (let i = 0; i + 2 < indexCount; i += 3) {
      const a = outIndices[i] * 8
      const b = outIndices[i + 1] * 8
      const c = outIndices[i + 2] * 8
      const e1x = outVerts[b] - outVerts[a], e1y = outVerts[b + 1] - outVerts[a + 1], e1z = outVerts[b + 2] - outVerts[a + 2]
      const e2x = outVerts[c] - outVerts[a], e2y = outVerts[c + 1] - outVerts[a + 1], e2z = outVerts[c + 2] - outVerts[a + 2]
      const nx = e1y * e2z - e1z * e2y
      const ny = e1z * e2x - e1x * e2z
      const nz = e1x * e2y - e1y * e2x
      outVerts[a + 3] += nx; outVerts[a + 4] += ny; outVerts[a + 5] += nz
      outVerts[b + 3] += nx; outVerts[b + 4] += ny; outVerts[b + 5] += nz
      outVerts[c + 3] += nx; outVerts[c + 4] += ny; outVerts[c + 5] += nz
    }
  }
  for (let i = 0; i < vertexCount; i++) {
    const b = i * 8
    const nx = outVerts[b + 3], ny = outVerts[b + 4], nz = outVerts[b + 5]
    const len = Math.hypot(nx, ny, nz)
    if (len > 1e-8) {
      outVerts[b + 3] = nx / len
      outVerts[b + 4] = ny / len
      outVerts[b + 5] = nz / len
    } else {
      const rl = Math.hypot(outVerts[b], outVerts[b + 1], outVerts[b + 2]) || 1
      outVerts[b + 3] = outVerts[b] / rl
      outVerts[b + 4] = outVerts[b + 1] / rl
      outVerts[b + 5] = outVerts[b + 2] / rl
    }
  }

  const headerBytes = 28
  const vertBytes = vertexCount * 8 * 4
  const idxBytes = indexCount * 4
  const buf = Buffer.allocUnsafe(headerBytes + vertBytes + idxBytes)
  buf.write('SBM1', 0, 4, 'ascii')
  buf.writeUInt32LE(vertexCount, 4)
  buf.writeUInt32LE(indexCount, 8)
  buf.writeUInt32LE(hasAnyUv ? 1 : 0, 12)
  buf.writeFloatLE(baseColor[0], 16)
  buf.writeFloatLE(baseColor[1], 20)
  buf.writeFloatLE(baseColor[2], 24)
  let off = headerBytes
  for (let i = 0; i < outVerts.length; i++) {
    buf.writeFloatLE(outVerts[i], off)
    off += 4
  }
  for (let i = 0; i < indexCount; i++) {
    buf.writeUInt32LE(outIndices[i], off)
    off += 4
  }
  return { buf, vertexCount, indexCount, hasUV: hasAnyUv }
}

function main() {
  const args = process.argv.slice(2)
  let outDir = join(MODELS_DIR, 'ohos')
  let checkOnly = false
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--out' && args[i + 1]) {
      outDir = resolve(args[++i])
    } else if (args[i] === '--check') {
      checkOnly = true
    }
  }

  if (checkOnly) {
    const manifestPath = join(outDir, 'manifest.json')
    if (!existsSync(manifestPath)) {
      console.error(`Missing minor body mesh manifest: ${manifestPath}`)
      process.exit(1)
    }
    for (const spec of MINOR_BODY_MESH_SPECS) {
      const sbmPath = join(outDir, `${spec.key}.sbm`)
      if (!existsSync(sbmPath)) {
        console.error(`Missing baked mesh: ${sbmPath}`)
        process.exit(1)
      }
    }
    console.log(`Minor body SBM1 meshes OK (${MINOR_BODY_MESH_SPECS.length} models in ${outDir})`)
    return
  }

  mkdirSync(outDir, { recursive: true })
  const manifestEntries = []
  let totalBytes = 0

  for (const spec of MINOR_BODY_MESH_SPECS) {
    const srcPath = join(MODELS_DIR, spec.obj)
    if (!existsSync(srcPath)) {
      throw new Error(`Missing source OBJ model: ${srcPath}`)
    }
    const raw = readFileSync(srcPath)
    const text = spec.obj.endsWith('.gz') ? gunzipSync(raw).toString('utf8') : raw.toString('utf8')
    const { buf, vertexCount, indexCount, hasUV } = parseObjToSbm(text, spec.baseColor)
    const destPath = join(outDir, `${spec.key}.sbm`)
    writeFileSync(destPath, buf)
    totalBytes += buf.byteLength
    manifestEntries.push({
      key: spec.key,
      sourceObj: spec.obj,
      sbmPath: `models/ohos/${spec.key}.sbm`,
      texturePath: spec.texture ? `models/${spec.texture}` : '',
      vertexCount,
      triangleCount: indexCount / 3,
      hasUV,
      bytes: buf.byteLength,
      credit: spec.credit,
    })
  }

  const manifest = {
    schemaVersion: 1,
    format: 'sbm1',
    modelCount: manifestEntries.length,
    totalBytes,
    models: manifestEntries,
  }
  writeFileSync(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', 'utf8')
  console.log(`Baked ${manifestEntries.length} minor-body SBM1 3D meshes (${(totalBytes / 1024 / 1024).toFixed(2)} MB) -> ${outDir}`)
}

// `file://${process.argv[1]}` never matches on Windows (drive-letter paths and
// backslashes); pathToFileURL keeps the direct-invocation guard portable.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main()
}
