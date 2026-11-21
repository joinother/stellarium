import { worker, MessageEvents, ThreadWorkerGlobalScope } from '@kit.ArkTS'
import nativeEntry from 'libentry.so'
import { DetailModelResources, DetailModelRequest, DetailModelResult } from './DetailModelRenderTypes'
import { renderDetailModel } from './DetailModelRasterizer'

const port: ThreadWorkerGlobalScope = worker.workerPort
let resources: DetailModelResources | undefined = undefined
let cachedParticlesFlat: Float32Array = new Float32Array(0)

function flattenParticles(particles: number[][]): Float32Array {
  const count = particles.length
  const flat = new Float32Array(count * 8)
  for (let i = 0; i < count; i++) {
    const p = particles[i]
    const base = i * 8
    flat[base] = p[0] ?? 0
    flat[base + 1] = p[1] ?? 0
    flat[base + 2] = p[2] ?? 0
    flat[base + 3] = p[3] ?? 0.01
    flat[base + 4] = p[4] ?? 255
    flat[base + 5] = p[5] ?? 255
    flat[base + 6] = p[6] ?? 255
    flat[base + 7] = p[7] ?? 0.8
  }
  return flat
}

function renderWithNative(res: DetailModelResources, request: DetailModelRequest): ArrayBuffer | undefined {
  const frame = request.frame
  try {
    if (res.kind === 'body-mesh' && res.meshData !== undefined) {
      const lighting = frame.lighting
      return nativeEntry.renderDetailModelBodyMesh(
        res.meshData,
        res.texture,
        res.textureWidth,
        res.textureHeight,
        res.textureStride,
        frame.renderSize,
        frame.scale,
        frame.transform,
        lighting !== undefined,
        lighting?.sunDirectionBody[0] ?? -0.45,
        lighting?.sunDirectionBody[1] ?? 0.42,
        lighting?.sunDirectionBody[2] ?? 0.79
      )
    }
    if (res.kind === 'constellation-mesh' && res.meshData !== undefined) {
      return nativeEntry.renderDetailModelConstellation(
        res.meshData,
        frame.renderSize,
        frame.scale,
        frame.transform
      )
    }
    if (res.kind.length === 0 && res.texture !== undefined) {
      const ring = res.ringSpec
      const lighting = frame.lighting
      return nativeEntry.renderDetailModelSphere(
        res.texture,
        res.textureWidth,
        res.textureHeight,
        res.textureStride,
        res.ringTexture,
        res.ringWidth,
        res.ringHeight,
        ring !== undefined,
        ring?.innerRadius ?? 0,
        ring?.outerRadius ?? 0,
        ring?.opacity ?? 0,
        frame.renderSize,
        frame.scale,
        frame.transform,
        lighting !== undefined,
        lighting?.emissive === true,
        lighting?.sunDirectionBody[0] ?? 0,
        lighting?.sunDirectionBody[1] ?? 0,
        lighting?.sunDirectionBody[2] ?? 1
      )
    }
    if (res.kind.length > 0 && res.kind !== 'constellation-mesh' && res.kind !== 'body-mesh') {
      return nativeEntry.renderDetailModelProcedural(
        res.kind,
        res.temperature,
        cachedParticlesFlat,
        frame.renderSize,
        frame.scale,
        frame.transform
      )
    }
  } catch (_nativeErr) {
    return undefined
  }
  return undefined
}

port.onmessage = (event: MessageEvents): void => {
  const request = event.data as DetailModelRequest
  const started = Date.now()
  try {
    if (request.resources !== undefined) {
      resources = request.resources
      cachedParticlesFlat = flattenParticles(resources.particles ?? [])
    }
    if (resources === undefined) throw new Error('model resources unavailable')
    let pixels = renderWithNative(resources, request)
    if (pixels === undefined) {
      pixels = renderDetailModel(resources, request.frame)
    }
    const result: DetailModelResult = { pixels: pixels, computeMs: Date.now() - started }
    port.postMessage(result, [pixels])
  } catch (error) {
    const result: DetailModelResult = { computeMs: Date.now() - started, error: (error as Error).message }
    port.postMessage(result)
  }
}
