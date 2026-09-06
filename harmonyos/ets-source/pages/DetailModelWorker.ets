import { worker, MessageEvents, ThreadWorkerGlobalScope } from '@kit.ArkTS'
import { DetailModelResources, DetailModelRequest, DetailModelResult } from './DetailModelRenderTypes'
import { renderDetailModel } from './DetailModelRasterizer'

const port: ThreadWorkerGlobalScope = worker.workerPort
let resources: DetailModelResources | undefined = undefined

port.onmessage = (event: MessageEvents): void => {
  const request = event.data as DetailModelRequest
  const started = Date.now()
  try {
    if (request.resources !== undefined) resources = request.resources
    if (resources === undefined) throw new Error('model resources unavailable')
    const pixels = renderDetailModel(resources, request.frame)
    const result: DetailModelResult = { pixels: pixels, computeMs: Date.now() - started }
    port.postMessage(result, [pixels])
  } catch (error) {
    const result: DetailModelResult = { computeMs: Date.now() - started, error: (error as Error).message }
    port.postMessage(result)
  }
}
