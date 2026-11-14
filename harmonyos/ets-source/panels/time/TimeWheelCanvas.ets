import { Theme, FrameCallback } from '@kit.ArkUI'
import { displaySync } from '@kit.ArkGraphics2D'
import { TimeWheelStore } from '../../state/TimeWheelStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 时间转轴的 Canvas 实现：整条刻度带只占一个 Canvas 节点。
//
// 旧实现为 41 个 tick 各建 Column/Text/Stack，拖动时每个 Move 都要重算
// opacity/scale/height/blur 并走一遍 ArkUI dirty-element 流程；120Hz 下这部分
// 会把单帧推到 9–14ms。Canvas 把刻度、文字和焦点带合成一次绘制，拖动时只
// 重画、不重建组件。
//
// 刷新由 displaySync 驱动：静止时 60fps，按下滑动/惯性期间升到 120fps，
// 回调里只做绘制；offset 未变化时跳过重画，避免空转。
// 刻度以基线为中心上下同时伸长；中心附近的刻度像放大镜一样
// 上下变长、变亮，主刻度和细分小刻度都参与。
const TICK_BASELINE: number = 40
const MAIN_TICK_MAX_HEIGHT: number = 24
// 数值垂直中心位于“上边缘 (0)”与“最高刻度顶端”的正中间，
// 使数值上方的留白 = 数值到最高刻度的间隙。
const LABEL_Y: number = (TICK_BASELINE - MAIN_TICK_MAX_HEIGHT / 2) / 2

class TimeWheelFrameCallback extends FrameCallback {
  private action: () => void

  constructor(action: () => void) {
    super()
    this.action = action
  }

  onFrame(_frameTimeInNano: number): void {
    this.action()
  }
}

@Component
export struct TimeWheelCanvas {
  @ObjectLink store: TimeWheelStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onWheelTouch: (event: TouchEvent) => void = () => {}

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private pump: displaySync.DisplaySync | undefined = undefined
  // displaySync 在系统判定 UI 空闲时可能被降到 0fps，惯性尾部会停在上一次
  // 绘制的位置（表现为高亮停在左侧）。松手后用短时定时器兜底重绘，
  // 保证惯性结束后的最终偏移一定被画出来。
  private settleTimer: number = -1
  private frameRequested: boolean = false
  private widthVp: number = 0
  private heightVp: number = 0
  private ready: boolean = false
  private lastOffset: number = NaN
  private lastLabels: string[] | undefined = undefined
  private idleFrames: number = 0
  private rate: number = 60
  private fonts: Map<number, string> = new Map<number, string>()
  private strongColor: string = '#FFFFFFFF'

  aboutToAppear(): void {
    this.syncTheme()
  }

  aboutToDisappear(): void {
    this.clearSettleTimer()
    this.stopPump()
  }

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
    this.syncTheme()
    this.draw()
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.widthVp = this.ctx.width
        this.heightVp = this.ctx.height
        this.ready = true
        this.lastOffset = NaN
        this.lastLabels = undefined
        this.draw()
        this.startPump()
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        // 以布局后的实际尺寸为准。onReady 的 context.width 在面板展开/
        // 内边距生效前后可能不是最终的 vp 宽度，直接用它会算错中心。
        const width = Number(newValue.width)
        const height = Number(newValue.height)
        if (width > 0 && height > 0 &&
          (Math.abs(width - this.widthVp) > 0.5 || Math.abs(height - this.heightVp) > 0.5)) {
          this.widthVp = width
          this.heightVp = height
          this.draw()
        }
      })
      .onTouch((event: TouchEvent) => this.handleTouch(event))
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.clearSettleTimer()
      this.idleFrames = 0
      this.setRate(120)
    }
    this.onWheelTouch(event)
    // 触摸事件本身已经是 120Hz；同步重画一次，避免显示管线把拖动态
    // 延后到下一次 displaySync 回调。
    this.draw()
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.idleFrames = 0
      this.startSettleTimer()
    }
  }

  private startSettleTimer(): void {
    this.clearSettleTimer()
    let remaining = 90
    this.settleTimer = setInterval(() => {
      this.onFrame()
      remaining -= 1
      if (remaining <= 0) this.clearSettleTimer()
    }, 16) as number
  }

  private clearSettleTimer(): void {
    if (this.settleTimer !== -1) {
      clearInterval(this.settleTimer)
      this.settleTimer = -1
    }
  }

  private requestFrame(): void {
    if (this.frameRequested) return
    this.frameRequested = true
    try {
      this.getUIContext().postFrameCallback(new TimeWheelFrameCallback(() => {
        this.frameRequested = false
        // 在下一帧渲染阶段重画，确保最终内容进入这一帧而不是继续排队。
        this.draw()
      }))
    } catch (_) {
      this.frameRequested = false
    }
  }

  private startPump(): void {
    if (this.pump !== undefined) return
    try {
      const pump = displaySync.create()
      pump.setExpectedFrameRateRange({ expected: 60, min: 0, max: 120 })
      pump.on('frame', () => this.onFrame())
      pump.start()
      this.pump = pump
      this.rate = 60
    } catch (_) {
      this.pump = undefined
    }
  }

  private stopPump(): void {
    const pump = this.pump
    this.pump = undefined
    if (pump === undefined) return
    try {
      pump.stop()
      pump.off('frame')
    } catch (_) {
    }
  }

  private setRate(rate: number): void {
    if (this.pump === undefined || this.rate === rate) return
    this.rate = rate
    try {
      this.pump.setExpectedFrameRateRange({ expected: rate, min: 0, max: 120 })
    } catch (_) {
    }
  }

  private onFrame(): void {
    if (!this.ready) return
    const offset = this.store.timeWheelVisualOffset
    const labels = this.store.timeWheelAllLabels
    if (offset !== this.lastOffset || labels !== this.lastLabels) {
      this.lastOffset = offset
      this.lastLabels = labels
      this.idleFrames = 0
      this.draw()
      this.requestFrame()
      return
    }
    if (!this.store.timeWheelDragging) {
      this.idleFrames += 1
      if (this.idleFrames === 1) {
        // 最后一帧只有绘制指令、没有 UI 变化时，系统可能不提交。
        // 显式请求一次 vsync，把最终画面推上去。
        this.requestFrame()
      }
      // 惯性结束后回到 60fps；再次按下时 handleTouch 会升回 120。
      if (this.idleFrames === 90) this.setRate(60)
    }
  }

  private syncTheme(): void {
    const night = this.c.isNight
    this.strongColor = this.colorOf(this.c.textStrong, night ? '#FF2222' : '#FFFFFFFF')
  }

  // ThemeSlots 在本应用里由自定义 CustomColors 填充，运行时为字符串；
  // 若未来接入系统 Resource 颜色，回退到当前夜间/日间近似值。
  private colorOf(value: ResourceColor, fallback: string): string {
    return typeof value === 'string' ? value : fallback
  }

  private fontFor(size: number, weight: number): string {
    const rounded = Math.round(size * 2) / 2
    const key = rounded * 10 + weight
    let cached = this.fonts.get(key)
    if (cached === undefined) {
      cached = weight.toString() + ' ' + rounded.toString() + 'vp sans-serif'
      this.fonts.set(key, cached)
    }
    return cached
  }

  private glowAt(distance: number, radius: number): number {
    const t = Math.max(0, Math.min(1, 1 - distance / radius))
    return t * t * (3 - 2 * t)
  }

  // 只使用以滚轮物理中心为唯一中心的宽渐变。不要再叠加“离中心最近的
  // 刻度”尖峰：那会让单个刻度成为视觉中心，滚动时看起来高亮在跟着刻度漂移。
  private focusAt(distance: number, spacing: number): number {
    return this.glowAt(distance, spacing * 4.8)
  }

  private draw(): void {
    if (!this.ready || this.widthVp < 1 || this.heightVp < 1) return
    const ctx = this.ctx
    const width = this.widthVp
    const height = this.heightVp
    const centerX = width / 2
    const spacing = this.store.tickSpacing
    const center = this.store.centerTick
    const offset = this.store.timeWheelVisualOffset
    const labels = this.store.timeWheelAllLabels
    const majorLabels = this.store.timeWheelTickLabels
    const count = labels.length
    const baseFont = this.store.timeWheelUnit === 'year' ? 10 : 12

    ctx.clearRect(0, 0, width, height)
    // 数值水平居中到对应刻度，垂直居中对齐 LABEL_Y。
    // 不设置时 Canvas 默认是 left/alphabetic，会表现为“靠左、偏上”。
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'

    // 只有一套连续高亮：亮度、颜色、伸长都来自同一个 focus。
    // 不再单独选“最近刻度”或叠加白色覆盖层。
    for (let index = 0; index < count - 1; index += 1) {
      for (let part = 1; part <= 3; part += 1) {
        const x = centerX + (index - center + part / 4) * spacing + offset
        if (x < -spacing || x > width + spacing) continue
        const distance = Math.abs(x - centerX)
        const focus = this.focusAt(distance, spacing)
        // 亮度与伸长使用同一个归一化比例：亮度降到 8% 时长度也降到 8%。
        // 细分刻度最高 12vp，最暗处约 1vp。
        const alpha = 0.08 + focus * 0.72
        const subHeight = 12 * (alpha / 0.80)
        ctx.fillStyle = this.strongColor
        ctx.globalAlpha = alpha
        ctx.fillRect(x - 0.5, TICK_BASELINE - subHeight / 2, 1, subHeight)
      }
    }

    // 主刻度和单位刻度不再有独立的高度/字号/粗细；最高、最亮的刻度
    // 永远只是离物理中心最近的那个。主刻度仅靠“有完整标签”区分。
    for (let index = 0; index < count; index += 1) {
      const x = centerX + (index - center) * spacing + offset
      if (x < -spacing || x > width + spacing) continue
      const distance = Math.abs(x - centerX)
      const focus = this.focusAt(distance, spacing)
      const major = majorLabels[index].length > 0
      const alpha = 0.10 + focus * 0.80
      const tickHeight = MAIN_TICK_MAX_HEIGHT * (alpha / 0.90)

      ctx.fillStyle = this.strongColor
      ctx.globalAlpha = alpha
      ctx.fillRect(x - 0.5, TICK_BASELINE - tickHeight / 2, 1, tickHeight)

      const label = major ? majorLabels[index] : (distance < spacing * 3.2 ? labels[index] : '')
      if (label.length > 0) {
        const size = baseFont * (1 + focus * 0.18)
        ctx.font = this.fontFor(size, 500)
        ctx.fillStyle = this.strongColor
        ctx.globalAlpha = 0.12 + 0.78 * focus
        ctx.fillText(label, x, LABEL_Y)
      }
    }
    ctx.globalAlpha = 1
  }
}
