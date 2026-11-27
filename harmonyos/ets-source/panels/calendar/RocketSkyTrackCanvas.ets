import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import {
  RocketFlightEventInfo,
  RocketSimulationData,
  RocketTrajectoryPoint
} from '../../state/RocketLaunchTypes'
import { UI_RADIUS_CARD } from '../../common/ui/UiTokens'

// 观测点天空轨迹图（方位角 Az vs 高度角 Alt）：
// 对标专业航天观测轨迹图，呈现：
// - 时间色带弹道弧线（深靛 → 青绿 → 亮黄）
// - 火箭云日照高亮光晕段（红移金橙 / 银白青光）
// - 地景地平线 + 地球曲率棕褐色遮挡区
// - 首次出现（绿星）/ 最大仰角（橙圆）/ 消失（紫方）与助推/整流罩/一二级分离、MECO/SECO 关键节点

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : (v > hi ? hi : v)
}

function viridisColor(tNorm: number): string {
  const t = clamp(tNorm, 0, 1)
  // 5-stop Viridis-inspired palette for crisp dark-UI readability
  if (t < 0.25) {
    const f = t / 0.25
    const r = Math.round(92 + (68 - 92) * f)
    const g = Math.round(58 + (130 - 58) * f)
    const b = Math.round(168 + (196 - 168) * f)
    return `rgb(${r},${g},${b})`
  }
  if (t < 0.5) {
    const f = (t - 0.25) / 0.25
    const r = Math.round(68 + (42 - 68) * f)
    const g = Math.round(130 + (186 - 130) * f)
    const b = Math.round(196 + (178 - 196) * f)
    return `rgb(${r},${g},${b})`
  }
  if (t < 0.75) {
    const f = (t - 0.5) / 0.25
    const r = Math.round(42 + (122 - 42) * f)
    const g = Math.round(186 + (214 - 186) * f)
    const b = Math.round(178 + (102 - 178) * f)
    return `rgb(${r},${g},${b})`
  }
  const f = (t - 0.75) / 0.25
  const r = Math.round(122 + (250 - 122) * f)
  const g = Math.round(214 + (226 - 214) * f)
  const b = Math.round(102 + (68 - 102) * f)
  return `rgb(${r},${g},${b})`
}

function compassLabel(az: number, isZh: boolean): string {
  const a = ((az % 360) + 360) % 360
  if (Math.abs(a - 0) < 1 || Math.abs(a - 360) < 1) return isZh ? '北' : 'N'
  if (Math.abs(a - 90) < 1) return isZh ? '东' : 'E'
  if (Math.abs(a - 180) < 1) return isZh ? '南' : 'S'
  if (Math.abs(a - 270) < 1) return isZh ? '西' : 'W'
  return `${Math.round(a)}°`
}

@Component
export struct RocketSkyTrackCanvas {
  @Prop @Watch('onDataChange') simulation: RocketSimulationData | undefined = undefined
  @Prop language: string = 'zh'
  @State private c: ThemeSlots = DEFAULT_SLOTS
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private ready: boolean = false

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
    if (this.ready) this.redraw()
  }

  private onDataChange(): void {
    if (this.ready) this.redraw()
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private unwrapAzimuths(pts: RocketTrajectoryPoint[]): number[] {
    if (pts.length === 0) return []
    const out: number[] = [pts[0].az]
    for (let i = 1; i < pts.length; i++) {
      let diff = pts[i].az - pts[i - 1].az
      if (diff > 180) diff -= 360
      if (diff < -180) diff += 360
      out.push(out[i - 1] + diff)
    }
    return out
  }

  private redraw(): void {
    const sim = this.simulation
    const w = this.ctx.width
    const h = this.ctx.height
    if (w <= 10 || h <= 10) return

    this.ctx.clearRect(0, 0, w, h)
    // Deep sky chart background
    this.ctx.fillStyle = this.c.isNight ? '#12080A' : '#0B1324'
    this.ctx.fillRect(0, 0, w, h)

    if (!sim || !Array.isArray(sim.trajectory) || sim.trajectory.length < 2) {
      this.ctx.fillStyle = '#9AA8C2'
      this.ctx.font = '12px sans-serif'
      this.ctx.textAlign = 'center'
      this.ctx.fillText(this.isZh() ? '暂无天空轨迹数据' : 'No sky track data', w * 0.5, h * 0.5)
      return
    }

    const padL = 38
    const padR = 16
    const padT = 22
    const padB = 28
    const plotW = Math.max(40, w - padL - padR)
    const plotH = Math.max(40, h - padT - padB)

    // Filter points near or above horizon (-5° .. 90°) for clean framing
    const visibleOrNear: RocketTrajectoryPoint[] = []
    for (let i = 0; i < sim.trajectory.length; i++) {
      if (sim.trajectory[i].alt >= -6.0) {
        visibleOrNear.push(sim.trajectory[i])
      }
    }
    const pts = visibleOrNear.length >= 2 ? visibleOrNear : sim.trajectory
    const unwrappedAz = this.unwrapAzimuths(pts)

    let minAz = unwrappedAz[0]
    let maxAz = unwrappedAz[0]
    let maxAlt = 15.0
    const maxT = Math.max(10, sim.trajectory[sim.trajectory.length - 1].t)
    for (let i = 0; i < pts.length; i++) {
      if (unwrappedAz[i] < minAz) minAz = unwrappedAz[i]
      if (unwrappedAz[i] > maxAz) maxAz = unwrappedAz[i]
      if (pts[i].alt > maxAlt) maxAlt = pts[i].alt
    }
    const azSpan = Math.max(24, maxAz - minAz)
    minAz -= azSpan * 0.12
    maxAz += azSpan * 0.12
    const minAlt = -3.0
    maxAlt = Math.min(90.0, Math.ceil((maxAlt + 5.0) / 5.0) * 5.0)

    const mapX = (azUnwrapped: number): number => padL + ((azUnwrapped - minAz) / Math.max(1e-3, maxAz - minAz)) * plotW
    const mapY = (alt: number): number => padT + (1.0 - (alt - minAlt) / Math.max(1e-3, maxAlt - minAlt)) * plotH

    // 1. Subtle coordinate grid
    this.ctx.strokeStyle = 'rgba(148, 168, 204, 0.16)'
    this.ctx.lineWidth = 0.8
    const altStep = maxAlt > 50 ? 15 : (maxAlt > 25 ? 10 : 5)
    this.ctx.font = '10px sans-serif'
    this.ctx.fillStyle = '#8FA2C2'
    this.ctx.textAlign = 'right'
    for (let a = 0; a <= maxAlt; a += altStep) {
      const y = mapY(a)
      this.ctx.beginPath()
      this.ctx.moveTo(padL, y)
      this.ctx.lineTo(padL + plotW, y)
      this.ctx.stroke()
      this.ctx.fillText(`${a}°`, padL - 5, y + 3)
    }

    const azStep = (maxAz - minAz) > 120 ? 30 : ((maxAz - minAz) > 60 ? 15 : 10)
    const firstAzTick = Math.ceil(minAz / azStep) * azStep
    this.ctx.textAlign = 'center'
    for (let az = firstAzTick; az <= maxAz; az += azStep) {
      const x = mapX(az)
      this.ctx.beginPath()
      this.ctx.moveTo(x, padT)
      this.ctx.lineTo(x, padT + plotH)
      this.ctx.stroke()
      this.ctx.fillText(compassLabel(az, this.isZh()), x, padT + plotH + 15)
    }

    // 2. Terrain + Earth curvature horizon obstruction shaded region (brown, matching reference)
    const lookupHorizon = (azRaw: number): number => {
      const hp = sim.horizonProfile
      if (!Array.isArray(hp) || hp.length === 0) return 0
      const a = ((azRaw % 360) + 360) % 360
      const idx = Math.floor(a / 2) % hp.length
      return hp[idx][1] ?? 0
    }
    this.ctx.beginPath()
    this.ctx.moveTo(padL, mapY(minAlt))
    const steps = 64
    for (let i = 0; i <= steps; i++) {
      const az = minAz + (i / steps) * (maxAz - minAz)
      const hAlt = lookupHorizon(az)
      this.ctx.lineTo(mapX(az), mapY(hAlt))
    }
    this.ctx.lineTo(padL + plotW, mapY(minAlt))
    this.ctx.closePath()
    this.ctx.fillStyle = this.c.isNight ? 'rgba(92, 42, 32, 0.55)' : 'rgba(130, 94, 62, 0.34)'
    this.ctx.fill()

    // Horizon top ridge line
    this.ctx.beginPath()
    for (let i = 0; i <= steps; i++) {
      const az = minAz + (i / steps) * (maxAz - minAz)
      const x = mapX(az)
      const y = mapY(lookupHorizon(az))
      if (i === 0) this.ctx.moveTo(x, y)
      else this.ctx.lineTo(x, y)
    }
    this.ctx.strokeStyle = this.c.isNight ? '#B86248' : '#A6784E'
    this.ctx.lineWidth = 1.6
    this.ctx.stroke()

    // 3. Luminous rocket plume visibility glow under-stroke along sunlit visible segment
    for (let i = 1; i < pts.length; i++) {
      const p0 = pts[i - 1]
      const p1 = pts[i]
      if (!p1.pVis && !p0.pVis) continue
      const x0 = mapX(unwrappedAz[i - 1]), y0 = mapY(p0.alt)
      const x1 = mapX(unwrappedAz[i]), y1 = mapY(p1.alt)
      const bright = clamp(Math.max(p0.pB, p1.pB), 0.15, 1.0)
      this.ctx.strokeStyle = p1.sun === 'red_twilight'
        ? `rgba(255, 162, 92, ${(0.25 + 0.45 * bright).toFixed(2)})`
        : `rgba(140, 232, 255, ${(0.24 + 0.48 * bright).toFixed(2)})`
      this.ctx.lineWidth = 7.0 + bright * 6.0
      this.ctx.lineCap = 'round'
      this.ctx.beginPath()
      this.ctx.moveTo(x0, y0)
      this.ctx.lineTo(x1, y1)
      this.ctx.stroke()
    }

    // 4. Time-colored trajectory curve
    for (let i = 1; i < pts.length; i++) {
      const p0 = pts[i - 1]
      const p1 = pts[i]
      this.ctx.strokeStyle = viridisColor(p1.t / maxT)
      this.ctx.lineWidth = 2.6
      this.ctx.lineCap = 'round'
      this.ctx.beginPath()
      this.ctx.moveTo(mapX(unwrappedAz[i - 1]), mapY(p0.alt))
      this.ctx.lineTo(mapX(unwrappedAz[i]), mapY(p1.alt))
      this.ctx.stroke()
    }

    // Helper: map any event time to unwrapped trajectory (x, y)
    const locateEventXY = (ev: RocketFlightEventInfo): [number, number] | undefined => {
      let bestIdx = -1
      let bestDiff = 1e9
      for (let i = 0; i < pts.length; i++) {
        const d = Math.abs(pts[i].t - ev.tSec)
        if (d < bestDiff) {
          bestDiff = d
          bestIdx = i
        }
      }
      if (bestIdx < 0 || bestDiff > 15) return undefined
      return [mapX(unwrappedAz[bestIdx]), mapY(pts[bestIdx].alt)]
    }

    // 5. Key flight & visibility milestones (priority-ordered with bounding-box de-overlap)
    const keyCodes = ['FIRST_VISIBLE', 'MAX_ALT', 'LOST_VISIBLE', 'SUNLIT_ENTRY', 'BOOSTER_SEP', 'STAGE_SEP', 'FAIRING_SEP', 'SECO']
    const placedBoxes: number[][] = []
    for (let cIdx = 0; cIdx < keyCodes.length; cIdx++) {
      const code = keyCodes[cIdx]
      const ev = sim.events.find((e: RocketFlightEventInfo) => e.code === code)
      if (!ev) continue
      const xy = locateEventXY(ev)
      if (!xy) continue
      const x = xy[0]
      const y = xy[1]
      if (x < padL - 2 || x > padL + plotW + 2 || y < padT - 4 || y > padT + plotH + 4) continue

      let dotColor = '#F4F7FF'
      let radius = 3.5
      if (ev.code === 'FIRST_VISIBLE') { dotColor = '#46E27E'; radius = 5.0 }
      else if (ev.code === 'MAX_ALT') { dotColor = '#FFA938'; radius = 5.0 }
      else if (ev.code === 'LOST_VISIBLE') { dotColor = '#E65CFF'; radius = 4.5 }
      else if (ev.code === 'SUNLIT_ENTRY') { dotColor = '#7CE8FF'; radius = 4.5 }

      this.ctx.beginPath()
      this.ctx.arc(x, y, radius, 0, Math.PI * 2)
      this.ctx.fillStyle = dotColor
      this.ctx.fill()
      this.ctx.strokeStyle = '#08101E'
      this.ctx.lineWidth = 1.2
      this.ctx.stroke()

      // Smart non-overlapping label placement
      const shortTag = this.isZh() ? ev.labelZh.replace(/观测点/, '').replace(/地球阴影/, '地影') : ev.labelEn
      const labelText = `${shortTag} ${Math.round(ev.tSec)}s`
      const estW = Math.min(110, labelText.length * 6.5 + 8)
      const isPrimary = cIdx < 4
      const candidates: number[][] = [
        [x + 7, y - 6, 0],
        [x - 7, y - 6, 1],
        [x + 7, y + 12, 0],
        [x - 7, y + 12, 1],
        [x + 7, y - 20, 0],
        [x - 7, y - 20, 1],
        [x + 7, y + 25, 0],
        [x - 7, y + 25, 1]
      ]
      let chosenX = x + 7
      let chosenY = y - 6
      let chosenRight = false
      let placed = false
      for (let m = 0; m < candidates.length; m++) {
        const cx = candidates[m][0]
        const cy = clamp(candidates[m][1], padT + 11, padT + plotH - 4)
        const right = candidates[m][2] === 1
        const bx1 = right ? (cx - estW) : cx
        const bx2 = right ? cx : (cx + estW)
        if (bx1 < padL + 2 || bx2 > padL + plotW - 2) continue
        let hit = false
        for (let k = 0; k < placedBoxes.length; k++) {
          const b = placedBoxes[k]
          if (bx1 < b[1] + 4 && bx2 > b[0] - 4 && Math.abs(cy - b[2]) < 13) {
            hit = true
            break
          }
        }
        if (!hit) {
          chosenX = cx
          chosenY = cy
          chosenRight = right
          placedBoxes.push([bx1, bx2, cy])
          placed = true
          break
        }
      }
      if (!placed && !isPrimary) continue
      this.ctx.font = '10px sans-serif'
      this.ctx.fillStyle = ev.code === 'SUNLIT_ENTRY' ? '#9EEFFF' : '#E9F0FF'
      this.ctx.textAlign = chosenRight ? 'right' : 'left'
      this.ctx.fillText(labelText, chosenX, chosenY)
    }

    // 6. Top mini legend
    this.ctx.font = '10px sans-serif'
    this.ctx.textAlign = 'left'
    this.ctx.fillStyle = '#A9B8D4'
    this.ctx.fillText(
      this.isZh() ? '色带=飞行时间 · 光晕=火箭云可见段 · 棕区=地形/曲率遮挡' : 'Color=Time · Glow=Plume Visible · Brown=Horizon Occlusion',
      padL, 14
    )
  }

  build() {
    Column() {
      Canvas(this.ctx)
        .width('100%')
        .height(210)
        .onReady(() => {
          this.ready = true
          this.redraw()
        })
    }
      .width('100%')
      .borderRadius(UI_RADIUS_CARD)
      .clip(true)
      .border({ width: 0.8, color: this.c.border })
  }
}
