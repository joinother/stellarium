import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS'
import { DetailModelResources, DetailModelFrame, DetailModelRequest, DetailModelResult } from './DetailModelRenderTypes'

export class DetailModelRenderClient {
  private thread: worker.ThreadWorker | undefined = undefined
  private resolveFrame: ((result: DetailModelResult) => void) | undefined = undefined
  private rejectFrame: ((error: Error) => void) | undefined = undefined
  private timeout: number = 0
  private pulseTimer: number = 0
  private lastPulse: number = 0
  private pulseCount: number = 0
  private maxPulseDelay: number = 0
  private suspended: boolean = false

  render(resources: DetailModelResources, frame: DetailModelFrame): Promise<DetailModelResult> {
    if (this.resolveFrame !== undefined) return Promise.reject(new Error('model frame already in flight'))
    return new Promise<DetailModelResult>((resolve, reject) => {
      this.resolveFrame = resolve
      this.rejectFrame = reject
      try {
        const firstFrame = this.thread === undefined
        if (firstFrame) {
          const thread = new worker.ThreadWorker('entry/ets/pages/DetailModelWorker.ets', { name: 'DetailModel' })
          this.thread = thread
          thread.onmessage = (event: MessageEvents): void => {
            if (this.thread !== thread) return
            const result = event.data as DetailModelResult
            const complete = this.resolveFrame
            const fail = this.rejectFrame
            result.uiPulseCount = this.pulseCount
            result.uiMaxDelayMs = Math.max(this.maxPulseDelay, Date.now() - this.lastPulse - 16, 0)
            this.clearPending()
            if (result.error !== undefined || result.pixels === undefined) {
              this.dispose()
              fail?.(new Error(result.error ?? 'model frame missing'))
            } else {
              complete?.(result)
            }
          }
          thread.onerror = (error: ErrorEvent): void => {
            if (this.thread === thread) this.dispose(new Error(error.message))
          }
          thread.onmessageerror = (): void => {
            if (this.thread === thread) this.dispose(new Error('model message failed'))
          }
          thread.onexit = (): void => {
            if (this.thread === thread) this.dispose(new Error('model worker exited'))
          }
        }
        const request: DetailModelRequest = { frame: frame }
        if (firstFrame) request.resources = resources
        this.startWatchdog()
        this.thread?.postMessage(request)
      } catch (error) {
        this.dispose(error as Error)
      }
    })
  }

  setSuspended(suspended: boolean): void {
    if (this.suspended === suspended) return
    this.suspended = suspended
    this.stopWatchdog()
    if (!suspended && this.resolveFrame !== undefined) this.startWatchdog()
  }

  private startWatchdog(): void {
    this.pulseCount = 0
    this.maxPulseDelay = 0
    this.lastPulse = Date.now()
    if (this.suspended) return
    this.pulseTimer = setInterval(() => {
      const now = Date.now()
      this.maxPulseDelay = Math.max(this.maxPulseDelay, now - this.lastPulse - 16)
      this.lastPulse = now
      this.pulseCount++
    }, 16)
    this.timeout = setTimeout(() => {
      this.dispose(new Error('model render timed out'))
    }, 30000)
  }

  private stopWatchdog(): void {
    if (this.timeout !== 0) clearTimeout(this.timeout)
    if (this.pulseTimer !== 0) clearInterval(this.pulseTimer)
    this.timeout = 0
    this.pulseTimer = 0
  }

  private clearPending(): void {
    this.stopWatchdog()
    this.resolveFrame = undefined
    this.rejectFrame = undefined
  }

  dispose(error: Error = new Error('model rendering cancelled')): void {
    const reject = this.rejectFrame
    const thread = this.thread
    this.thread = undefined
    this.clearPending()
    if (thread !== undefined) {
      try { thread.terminate() } catch (terminationError) { }
    }
    reject?.(error)
  }
}
