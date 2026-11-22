// 实况窗（Live View Kit）标准一层接入：计时（TIMER）场景。
//
// 严格遵循鸿蒙《实况窗设计规范》计时场景要求：
//  1. 仅端侧前台创建与管理，零服务端依赖、零后台保活；
//  2. 使用系统原生 LiveViewTimer + TimerCapsule + ${placeholder.timer}，
//     应用退后台或锁屏后由系统时钟自动精准倒计时；
//  3. 卡片辅助区（ExtensionData）明确显示「计时中」；
//  4. 卫星过境使用 FlightLayout 左右文本扩展区呈现升起方位/时间、最高仰角、落下方位/时间与亮度；
//     其他天象或暗适应计时使用 PickupLayout 强调倒计时；
//  5. 用户主动取消或计时归零后立即调用 stopLiveView 销毁（keepTime = 0）；
//  6. 未开通正式权限或非调测白名单设备（错误码 1003500004 / 1003500005）静默降级不崩溃。
import { liveViewManager } from '@kit.LiveViewKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AstronomyCalendarEvent } from '../state/AstronomyCalendarEvent'

const LIVE_VIEW_LOG_TAG: string = 'StellariumLiveView'
const MAX_TIMER_WINDOW_MS: number = 8 * 3600 * 1000
const MIN_TIMER_WINDOW_MS: number = 5000

export interface LiveViewCountdownRequest {
  eventId: string
  target: string
  title: string
  shortLabel: string
  kind: string
  startAtMs: number
  endAtMs?: number
  jd?: number
  riseDirection?: string
  setDirection?: string
  maxAltDeg?: number
  magnitude?: number
  visible?: boolean
  summaryText?: string
  language?: string
}

export interface LiveViewStartResult {
  ok: boolean
  error?: string
  code?: number
  unauthorized?: boolean
  disabled?: boolean
}

export interface LiveViewActiveSnapshot {
  running: boolean
  eventId: string
  title: string
  target: string
  kind: string
  endAtMs: number
}

function compassDirectionLabel(azDeg: number, zh: boolean): string {
  const dirsZh: string[] = ['北', '东北', '东', '东南', '南', '西南', '西', '西北']
  const dirsEn: string[] = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
  const norm = ((azDeg % 360) + 360) % 360
  const idx = Math.floor((norm + 22.5) / 45) % 8
  const label = zh ? dirsZh[idx] : dirsEn[idx]
  return `${label} ${Math.round(norm)}°`
}

function formatClockHHMM(ms: number): string {
  const d = new Date(ms)
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return `${hh}:${mm}`
}

function shortCapsuleName(title: string, target: string, kind: string, zh: boolean): string {
  if (kind === 'dark-adapt') return zh ? '暗适应' : 'DarkAdapt'
  const hay = (title + ' ' + target).toUpperCase()
  if (hay.includes('25544') || hay.includes('ISS') || title.includes('国际空间站')) return 'ISS'
  if (hay.includes('48274') || title.includes('天宫') || title.includes('中国空间站') || hay.includes('CSS') || hay.includes('TIANHE')) {
    return zh ? '空间站' : 'CSS'
  }
  if (hay.includes('20580') || title.includes('哈勃') || hay.includes('HST')) return zh ? '哈勃' : 'HST'
  if (kind === 'solar-eclipse') return zh ? '日食' : 'Eclipse'
  if (kind === 'lunar-eclipse') return zh ? '月食' : 'Eclipse'
  if (kind === 'meteor-peak') return zh ? '流星雨' : 'Meteors'
  const clean = title.replace(/\s*过境.*$/, '').trim()
  if (clean.length <= 6) return clean
  return clean.slice(0, 6)
}

export function isEventEligibleForLiveView(event: AstronomyCalendarEvent, nowMs: number = Date.now()): boolean {
  const startMs = event.kind === 'satellite-pass' && event.satStartAt !== undefined ? event.satStartAt : event.at
  const endMs = event.kind === 'satellite-pass' && event.satEndAt !== undefined ? event.satEndAt : event.at
  if (endMs <= nowMs) return false
  const untilStart = startMs - nowMs
  return untilStart <= MAX_TIMER_WINDOW_MS
}

export function buildLiveViewRequestFromCalendarEvent(
  event: AstronomyCalendarEvent,
  language: string = 'zh'
): LiveViewCountdownRequest {
  const zh = language.toLowerCase().startsWith('zh')
  const isSat = event.kind === 'satellite-pass'
  const startAtMs = isSat && event.satStartAt !== undefined ? event.satStartAt : event.at
  const endAtMs = isSat && event.satEndAt !== undefined ? event.satEndAt : undefined
  const cleanTitle = isSat
    ? event.title
      .replace(/\s*过境\s*·.*$/, '')
      .replace(/\s*Pass\s*·.*$/, '')
      .replace(/^中国空间站\s+天宫$/, '中国空间站')
      .replace(/^国际空间站\s+ISS$/, '国际空间站')
      .trim()
    : event.title
  let riseDir: string | undefined = undefined
  let setDir: string | undefined = undefined
  if (isSat && event.satStartAz !== undefined && event.satEndAz !== undefined) {
    riseDir = compassDirectionLabel(event.satStartAz, zh)
    setDir = compassDirectionLabel(event.satEndAz, zh)
  } else if (isSat && event.satAzimuthSummary !== undefined && event.satAzimuthSummary.includes('→')) {
    const parts = event.satAzimuthSummary.split('→')
    if (parts.length >= 2) {
      riseDir = parts[0].trim()
      setDir = parts[1].trim()
    }
  }
  return {
    eventId: event.id,
    target: event.target,
    title: cleanTitle.length > 0 ? cleanTitle : event.title,
    shortLabel: shortCapsuleName(cleanTitle, event.target, event.kind, zh),
    kind: event.kind,
    startAtMs: startAtMs,
    endAtMs: endAtMs,
    jd: event.jd,
    riseDirection: riseDir,
    setDirection: setDir,
    maxAltDeg: event.satMaxAlt,
    magnitude: event.satMag ?? event.magnitude,
    visible: event.satVisible,
    summaryText: isSat
      ? undefined
      : (zh ? `${formatClockHHMM(event.at)} 时刻到达 · 点击直达星图` : `Event at ${formatClockHHMM(event.at)} · Tap to view sky`),
    language: language
  }
}

export function buildDarkAdaptLiveViewRequest(minutes: number = 20, language: string = 'zh'): LiveViewCountdownRequest {
  const zh = language.toLowerCase().startsWith('zh')
  const clampedMin = Math.max(1, Math.min(120, Math.round(minutes)))
  const endMs = Date.now() + clampedMin * 60 * 1000
  return {
    eventId: `dark-adapt-${clampedMin}m`,
    target: '',
    title: zh ? '观星暗适应计时' : 'Dark Adaptation Timer',
    shortLabel: zh ? '暗适应' : 'Dark',
    kind: 'dark-adapt',
    startAtMs: endMs,
    endAtMs: endMs,
    summaryText: zh
      ? `弱红光护眼 ${clampedMin} 分钟，避免直视强光`
      : `Stay in dim red light (${clampedMin}m)`,
    language: language
  }
}

export function buildDemoSatellitePassLiveViewRequest(language: string = 'zh'): LiveViewCountdownRequest {
  const zh = language.toLowerCase().startsWith('zh')
  const now = Date.now()
  const riseMs = now + 12 * 60 * 1000
  const setMs = riseMs + 6 * 60 * 1000
  return {
    eventId: 'satellite-pass-48274-preview',
    target: 'CSS (TIANHE)',
    title: zh ? '中国空间站' : 'Tiangong',
    shortLabel: zh ? '空间站' : 'CSS',
    kind: 'satellite-pass',
    startAtMs: riseMs,
    endAtMs: setMs,
    jd: (riseMs + 3 * 60 * 1000) / 86400000 + 2440587.5,
    riseDirection: zh ? '西北 308°' : 'NW 308°',
    setDirection: zh ? '东南 132°' : 'SE 132°',
    maxAltDeg: 72,
    magnitude: -3.2,
    visible: true,
    language: language
  }
}

export class LiveViewController {
  // 单实例 ID：计时实况窗一次只保留一条，重开自动无缝替换旧任务。
  private static readonly LIVE_VIEW_ID: number = 1001
  private static readonly BUNDLE_NAME: string = 'com.joinother.skyinstrument'
  private static readonly ABILITY_NAME: string = 'QAbility'

  private sequence: number = 1
  private running: boolean = false
  private currentRequest: LiveViewCountdownRequest | undefined = undefined
  private phaseTimerId: number = 0
  private stopTimerId: number = 0
  private onStateChanged?: (snapshot: LiveViewActiveSnapshot) => void

  constructor(onStateChanged?: (snapshot: LiveViewActiveSnapshot) => void) {
    this.onStateChanged = onStateChanged
  }

  public snapshot(): LiveViewActiveSnapshot {
    return {
      running: this.running,
      eventId: this.running && this.currentRequest !== undefined ? this.currentRequest.eventId : '',
      title: this.running && this.currentRequest !== undefined ? this.currentRequest.title : '',
      target: this.running && this.currentRequest !== undefined ? this.currentRequest.target : '',
      kind: this.running && this.currentRequest !== undefined ? this.currentRequest.kind : '',
      endAtMs: this.running && this.currentRequest !== undefined
        ? (this.currentRequest.endAtMs ?? this.currentRequest.startAtMs)
        : 0
    }
  }

  private emitState(): void {
    this.onStateChanged?.(this.snapshot())
  }

  private clearTimers(): void {
    if (this.phaseTimerId !== 0) {
      clearTimeout(this.phaseTimerId)
      this.phaseTimerId = 0
    }
    if (this.stopTimerId !== 0) {
      clearTimeout(this.stopTimerId)
      this.stopTimerId = 0
    }
  }

  public dispose(): void {
    this.clearTimers()
  }

  public async isEnabled(): Promise<boolean> {
    try {
      return await liveViewManager.isLiveViewEnabled()
    } catch (error) {
      const err = error as BusinessError
      hilog.warn(0x0000, LIVE_VIEW_LOG_TAG, 'isLiveViewEnabled failed: %{public}d %{public}s',
        err.code ?? -1, err.message ?? '')
      return false
    }
  }

  public async syncActiveState(): Promise<boolean> {
    try {
      const active = await liveViewManager.getActiveLiveView(LiveViewController.LIVE_VIEW_ID)
      if (active !== undefined) {
        if (typeof active.sequence === 'number' && Number.isFinite(active.sequence) && active.sequence < 2147483000) {
          this.sequence = Math.max(this.sequence, active.sequence + 1)
        }
        this.running = true
        this.emitState()
        return true
      }
    } catch (_error) {
      // 1003500009 (does not exist) is expected when no live view is active.
    }
    if (this.running) {
      this.running = false
      this.currentRequest = undefined
      this.clearTimers()
      this.emitState()
    }
    return false
  }

  public async start(req: LiveViewCountdownRequest): Promise<LiveViewStartResult> {
    const enabled = await this.isEnabled()
    if (!enabled) {
      return { ok: false, error: '系统实况窗开关未开启', code: 1003500004, disabled: true }
    }
    const now = Date.now()
    const targetEnd = req.endAtMs !== undefined && req.endAtMs > req.startAtMs ? req.endAtMs : req.startAtMs
    if (targetEnd <= now + 1000) {
      return { ok: false, error: '该事件已结束，无需开启实况窗' }
    }
    if (req.startAtMs - now > MAX_TIMER_WINDOW_MS) {
      return { ok: false, error: '仅支持 8 小时内的临近事件开启实况窗倒计时' }
    }

    // 若已有运行中的实况窗，先规范停止再创建新实例（确保同一任务不叠加）。
    if (this.running) {
      await this.stop()
    }
    this.clearTimers()

    try {
      this.sequence += 1
      const inProgress = req.kind === 'satellite-pass' && now >= req.startAtMs && targetEnd > now
      const view = await this.buildLiveView(req, inProgress, false, false)
      await liveViewManager.startLiveView(view)
      this.running = true
      this.currentRequest = req
      this.scheduleLifecycleTimers(req)
      this.emitState()
      hilog.info(0x0000, LIVE_VIEW_LOG_TAG, 'startLiveView ok id=%{public}d event=%{public}s seq=%{public}d',
        LiveViewController.LIVE_VIEW_ID, req.eventId, this.sequence)
      return { ok: true }
    } catch (error) {
      const err = error as BusinessError
      const code = err.code ?? -1
      hilog.warn(0x0000, LIVE_VIEW_LOG_TAG, 'startLiveView failed: %{public}d %{public}s', code, err.message ?? '')
      // 1003500006: 已存在同 ID 实况窗（例如进程重启后残留）→ 走 updateLiveView 接管。
      if (code === 1003500006) {
        try {
          await this.syncActiveState()
          this.sequence += 1
          const inProgress = req.kind === 'satellite-pass' && Date.now() >= req.startAtMs && targetEnd > Date.now()
          const updateView = await this.buildLiveView(req, inProgress, true, false)
          await liveViewManager.updateLiveView(updateView)
          this.running = true
          this.currentRequest = req
          this.scheduleLifecycleTimers(req)
          this.emitState()
          return { ok: true }
        } catch (retryError) {
          const rErr = retryError as BusinessError
          return { ok: false, error: rErr.message ?? '更新实况窗失败', code: rErr.code ?? -1 }
        }
      }
      if (code === 1003500005) {
        return {
          ok: false,
          error: '当前设备尚未生效实况窗权限（调测设备需在 AGC 登记满 24 小时）',
          code: code,
          unauthorized: true
        }
      }
      if (code === 1003500004) {
        return { ok: false, error: '系统实况窗开关未开启', code: code, disabled: true }
      }
      return { ok: false, error: err.message ?? '开启实况窗失败', code: code }
    }
  }

  public async stop(): Promise<void> {
    this.clearTimers()
    const prevReq = this.currentRequest
    this.running = false
    this.currentRequest = undefined
    this.emitState()
    try {
      this.sequence += 1
      const stopReq: LiveViewCountdownRequest = prevReq ?? {
        eventId: 'stopped',
        target: '',
        title: '计时已结束',
        shortLabel: '已结束',
        kind: 'timer',
        startAtMs: Date.now()
      }
      const stopView = await this.buildLiveView(stopReq, false, true, true)
      await liveViewManager.stopLiveView(stopView)
      hilog.info(0x0000, LIVE_VIEW_LOG_TAG, 'stopLiveView ok seq=%{public}d', this.sequence)
    } catch (error) {
      const err = error as BusinessError
      hilog.warn(0x0000, LIVE_VIEW_LOG_TAG, 'stopLiveView notice: %{public}d %{public}s',
        err.code ?? -1, err.message ?? '')
    }
  }

  private scheduleLifecycleTimers(req: LiveViewCountdownRequest): void {
    this.clearTimers()
    const now = Date.now()
    const endMs = req.endAtMs !== undefined && req.endAtMs > req.startAtMs ? req.endAtMs : req.startAtMs
    // 若是卫星过境且尚未升起：升起时刻自动切换为「正在过境 · 距落下」阶段。
    if (req.kind === 'satellite-pass' && req.startAtMs > now + 1000 && endMs > req.startAtMs + 5000) {
      const toRiseMs = Math.min(req.startAtMs - now, MAX_TIMER_WINDOW_MS)
      this.phaseTimerId = setTimeout(() => {
        this.phaseTimerId = 0
        if (!this.running || this.currentRequest?.eventId !== req.eventId) return
        void this.transitionToInProgress(req)
      }, toRiseMs)
    }
    // 过境结束 / 倒计时归零后自动结束实况窗（严格满足官方「每个实况活动必须有结束事件」规范）。
    const toEndMs = Math.max(2000, Math.min(endMs - now + 3000, MAX_TIMER_WINDOW_MS + 15000))
    this.stopTimerId = setTimeout(() => {
      this.stopTimerId = 0
      if (!this.running || this.currentRequest?.eventId !== req.eventId) return
      void this.stop()
    }, toEndMs)
  }

  private async transitionToInProgress(req: LiveViewCountdownRequest): Promise<void> {
    if (!this.running) return
    try {
      this.sequence += 1
      const view = await this.buildLiveView(req, true, true, false)
      await liveViewManager.updateLiveView(view)
      hilog.info(0x0000, LIVE_VIEW_LOG_TAG, 'liveView transitioned to in-progress seq=%{public}d', this.sequence)
    } catch (error) {
      const err = error as BusinessError
      hilog.warn(0x0000, LIVE_VIEW_LOG_TAG, 'transitionToInProgress failed: %{public}d %{public}s',
        err.code ?? -1, err.message ?? '')
    }
  }

  private async buildLiveView(
    req: LiveViewCountdownRequest,
    inProgress: boolean,
    isMute: boolean,
    isStopping: boolean
  ): Promise<liveViewManager.LiveView> {
    const zh = (req.language ?? 'zh').toLowerCase().startsWith('zh')
    const now = Date.now()
    const isSat = req.kind === 'satellite-pass'
    const targetMs = inProgress && req.endAtMs !== undefined && req.endAtMs > now ? req.endAtMs : req.startAtMs
    const remainingMs = isStopping
      ? 0
      : Math.max(MIN_TIMER_WINDOW_MS, Math.min(MAX_TIMER_WINDOW_MS, targetMs - now))

    const compactName = req.title.length > 5 && isSat
      ? req.title.replace(/^中国空间站.*$/, '中国空间站').replace(/^国际空间站.*$/, '国际空间站').slice(0, 6)
      : (req.title.length > 7 ? req.title.slice(0, 7) : req.title)
    const primaryTitle: string = isStopping
      ? (zh ? `${compactName}已结束` : `${compactName} Ended`)
      : (isSat
        ? (inProgress
          ? (zh ? `${compactName}过境中` : `${compactName} Passing`)
          : (zh ? `${compactName}过境` : `${compactName} Pass`))
        : (req.kind === 'dark-adapt' ? (zh ? '观星暗适应' : 'Dark Adapt') : (zh ? `${compactName}倒计时` : `${compactName} Timer`)))

    const phasePrefix: string = isStopping
      ? (zh ? '本次计时已结束' : 'Timer ended')
      : (isSat
        ? (inProgress
          ? (zh ? '正在过境 · 距落下 ' : 'Passing · Sets in ')
          : (zh ? '即将升起 · 倒计时 ' : 'Rising · In '))
        : (zh ? '距离时刻 · 剩余 ' : 'Remaining · '))

    const contentItems: Array<liveViewManager.RichText> = isStopping
      ? [{ text: phasePrefix }]
      : [{ text: phasePrefix }, { text: '${placeholder.timer}' }]

    const clickAction = await this.buildClickAction(req)

    const primary: liveViewManager.PrimaryData = {
      title: primaryTitle,
      content: contentItems,
      keepTime: 0,
      clickAction: clickAction,
      // 官方《实况窗设计规范》TIMER 场景硬性要求：辅助区明确展示「计时中」状态（胶囊标签单行不折行）。
      extensionData: {
        type: liveViewManager.ExtensionType.EXTENSION_TYPE_CAPSULE_TEXT,
        text: isStopping ? (zh ? '已结束' : 'Ended') : (zh ? '计时中' : 'Timing')
      }
    }

    if (!isStopping && isSat && req.riseDirection !== undefined && req.setDirection !== undefined) {
      const riseClock = formatClockHHMM(req.startAtMs)
      const setClock = req.endAtMs !== undefined ? formatClockHHMM(req.endAtMs) : ''
      const maxAlt = req.maxAltDeg !== undefined ? Math.round(req.maxAltDeg) : 0
      const spaceText = maxAlt > 0
        ? (zh ? `仰角${maxAlt}°` : `Max ${maxAlt}°`)
        : (zh ? '过境中' : 'Pass')
      const detailParts: string[] = []
      if (req.magnitude !== undefined && Number.isFinite(req.magnitude)) {
        const magStr = req.magnitude >= 0 ? `+${req.magnitude.toFixed(1)}` : req.magnitude.toFixed(1)
        detailParts.push(zh ? `亮度 ${magStr}等` : `Mag ${magStr}`)
      }
      if (req.visible === true) {
        detailParts.push(zh ? '肉眼可见' : 'Naked-eye visible')
      }
      detailParts.push(zh ? '点击直达星图追踪' : 'Tap to track on sky map')

      const flightLayout: liveViewManager.FlightLayout = {
        layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_FLIGHT,
        style: liveViewManager.FlightLayoutStyle.STYLE_FLIGHT_BALANCE,
        spaceType: liveViewManager.SpaceType.SPACE_TYPE_TEXT,
        spaceText: spaceText,
        firstTitle: req.riseDirection,
        firstContent: zh ? `${riseClock} 升起` : `Rise ${riseClock}`,
        lastTitle: req.setDirection,
        lastContent: setClock.length > 0 ? (zh ? `${setClock} 落下` : `Set ${setClock}`) : (zh ? '过境结束' : 'Pass end'),
        additionalText: detailParts.join(' · '),
        isHorizontalLineDisplayed: true
      }
      primary.layoutData = flightLayout
    } else if (!isStopping) {
      const pickupLayout: liveViewManager.PickupLayout = {
        layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PICKUP,
        title: req.summaryText ?? (zh ? '点击回到星图查看实时天象' : 'Tap to open star map'),
        content: '${placeholder.timer}',
        underlineColor: '#FF4A90E2',
        descPic: 'liveview_star_icon.png'
      }
      primary.layoutData = pickupLayout
    }

    const capsule: liveViewManager.TimerCapsule = {
      type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
      status: isStopping ? -1 : 1,
      icon: isSat ? 'liveview_sat_icon.png' : 'liveview_star_icon.png',
      backgroundColor: '#FF173A7A',
      content: req.shortLabel,
      time: remainingMs,
      isCountdown: true,
      isPaused: isStopping
    }

    const timer: liveViewManager.LiveViewTimer = {
      time: remainingMs,
      isCountdown: true,
      isPaused: isStopping,
      capsuleCountdownPreset: {
        presetTitle: isSat ? (zh ? '过境中' : 'Live') : (zh ? '已到达' : 'Done'),
        presetContent: req.shortLabel
      }
    }
    if (!isStopping && !isSat) {
      timer.countdownPreset = {
        presetTitle: zh ? '时刻已到' : 'Time reached',
        presetContent: zh ? '点击查看星图' : 'Tap to view sky'
      }
    }

    const liveView: liveViewManager.LiveView = {
      id: LiveViewController.LIVE_VIEW_ID,
      event: 'TIMER',
      sequence: this.sequence,
      isMute: isMute,
      timer: timer,
      liveViewData: {
        primary: primary,
        capsule: capsule
      }
    }
    return liveView
  }

  private async buildClickAction(req: LiveViewCountdownRequest): Promise<WantAgent> {
    const params: Record<string, Object> = {
      'panel': req.kind === 'satellite-pass' ? 'sky' : (req.kind === 'dark-adapt' ? 'sky' : 'calendar'),
      'eventId': req.eventId,
      'kind': req.kind,
      'target': req.target,
      'eventAt': new Date(req.startAtMs).toISOString(),
      'landingTitle': req.title,
      'landingSource': 'liveview'
    }
    if (req.jd !== undefined && Number.isFinite(req.jd) && req.jd > 0) {
      params['jd'] = req.jd
    }
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: LiveViewController.BUNDLE_NAME,
          abilityName: LiveViewController.ABILITY_NAME,
          parameters: params
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: LiveViewController.LIVE_VIEW_ID,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    return await wantAgent.getWantAgent(info)
  }
}
