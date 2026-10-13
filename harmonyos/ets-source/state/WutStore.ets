import { WutTarget, StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'
import { wutCategoryOptions, wutCategoryKey } from '../common/derive/catalog'
import { celestialTitle, planetZh, zhNameOf } from '../common/derive/labels'
// 今晚观测目标（WUT）面板状态：持有 wut* 字段（目标列表、加载/进度、筛选条件与提示）。
// 消费方（WUT 面板及后续抽出的列表/筛选组件）以 @ObjectLink 观察本 store。
// 自持 CommandPort 与请求序号 wutRequestSequence；loadWutTargets 为长任务加载器。
@Observed
export class WutStore {
  wutTargets: Array<WutTarget> = []
  wutLoading: boolean = false
  wutProgress: string = ''
  wutCategory: string = 'planets'
  wutCategoriesExpanded: boolean = false
  wutPeriod: string = 'midnight'
  wutMinAltitude: number = 20
  wutMaxMagnitude: number = 6
  wutDirection: string = 'all'
  wutLimitAngularSize: boolean = false
  wutMinAngularSizeArcmin: number = 10
  wutMaxAngularSizeArcmin: number = 600
  wutAngularSizeAvailable: boolean = true
  wutObservationTime: string = ''
  wutHint: string = ''
  wutHasResult: boolean = false

  // —— 桥注入 ——
  private port: CommandPort | null = null
  private onChanged: (() => void) | null = null
  private wutRequestSequence: number = 0

  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // Wut 分类按钮的当前标题（读本 store 的 wutCategory + 纯函数模块）。
  wutCategoryTitle(): string {
    const options = wutCategoryOptions()
    for (const option of options) {
      if (wutCategoryKey(option.id) === this.wutCategory) return String(option.label)
    }
    return '天体'
  }

  // 观测目标的显示名：只在 wutTargets 命中时用天体标题，否则回退 planetZh / zhNameOf 纯函数。
  observingDisplayName(englishName: string): string {
    const target = this.wutTargets.find((item: WutTarget) => item.englishName === englishName)
    if (target !== undefined) return celestialTitle(target.name ?? '', target.englishName ?? '')
    return planetZh(englishName) !== englishName ? planetZh(englishName) : zhNameOf(englishName)
  }

  // 今晚观测目标加载：长任务取消槽 900ms；进度与回包均按 wutRequestSequence 作废在途请求。
  loadWutTargets(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const requestId = ++this.wutRequestSequence
    // Drop the previous job first: the engine answers "pending" for a mismatching
    // key instead of discarding the running job, so a deliberate category switch
    // has to cancel explicitly.
    port.fire('getWutTargets', '{"cancel":true}')
    this.wutLoading = true
    this.wutHasResult = false
    this.wutProgress = I18n.t('observing_loading') as string
    this.wutHint = ''
    this.notifyChanged()
    const options = JSON.stringify({
      category: this.wutCategory,
      period: this.wutPeriod,
      minAltitude: this.wutMinAltitude,
      maxMagnitude: this.wutMaxMagnitude,
      limitAngularSize: this.wutLimitAngularSize,
      minAngularSizeArcmin: this.wutMinAngularSizeArcmin,
      maxAngularSizeArcmin: this.wutMaxAngularSizeArcmin,
      direction: this.wutDirection
    })
    port.requestLongRunning('getWutTargets', options, (r: StellariumBridgeResponse) => {
      if (requestId !== this.wutRequestSequence) return
      this.wutLoading = false
      this.wutProgress = ''
      this.wutHasResult = true
      if (r.ok === true && r.wutTargets !== undefined) {
        this.wutTargets = r.wutTargets as Array<WutTarget>
        this.wutObservationTime = r.observationTime ?? ''
        this.wutAngularSizeAvailable = r.angularSizeAvailable !== false
        if (!this.wutAngularSizeAvailable) this.wutLimitAngularSize = false
        if (this.wutTargets.length === 0) this.wutHint = I18n.t('observing_no_matches') + this.wutCategoryTitle() + '。'
      } else {
        this.wutTargets = []
        this.wutHint = (r.error ?? '').toString().includes('twilight')
          ? I18n.t('observing_no_twilight')
          : I18n.t('observing_compute_failed')
      }
      this.notifyChanged()
    }, () => {
      if (requestId !== this.wutRequestSequence) return
      this.wutLoading = false
      this.wutProgress = ''
      this.wutHasResult = true
      this.wutTargets = []
      this.wutHint = I18n.t('observing_compute_unavailable')
      this.notifyChanged()
    }, (progress: StellariumBridgeResponse) => {
      if (requestId !== this.wutRequestSequence) return
      const completed = Number(progress.progress ?? 0)
      const total = Number(progress.totalCandidates ?? 0)
      this.wutProgress = total > 0
        ? I18n.t('observing_filtering') + ' ' + completed.toFixed(0) + ' / ' + total.toFixed(0)
        : I18n.t('observing_filtering')
    }, 900, () => requestId !== this.wutRequestSequence)
  }
}
