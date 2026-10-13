// 「信息窗 / 天体信息显示级别」域状态 store：持有富化天体详情浮动窗的可见性与展开态
// （infoWinVisible / infoWinExpanded）、天体信息模式与自定义位掩码（informationMode /
// informationCustomMask / informationSettingPending），以及由 informationMode 派生的
// 显示级别 infoLevel（0–3，驱动详情卡各信息块显示）。
//
// 另持有**正交的呈现轴** detailDisplayMode / observeExpanded（详情卡「天文馆 / 观测」形态），
// 见 specs/OBJECT-DETAIL-OBSERVE-MODE.md §3：数据轴决定内容，呈现轴决定默认形态。
//
// 消费方：三个壳层（CompactShell / ExpandedShell / HoverObservatoryShell）经 @Prop 接收
// infoWinVisible；SettingsPanel 经 @Prop 接收 informationMode / informationSettingPending；
// 宿主读 store 后下发（与 PolarScopeStore 取舍一致）。
//
// 本 store 自持 CommandPort 与 InfoWindowHostHooks：桥动作 setInformationMode /
// setInformationField 在此；派生级别写回与选中详情刷新经 hook 回注宿主。
//
// 约束：字段均为标量、只做整体赋值（informationCustomMask 的读改写也是整体赋值，
// infoLevel 由宿主整体赋值）；informationMaskHas 依赖纯函数 informationMaskBit。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'
import { informationMaskBit } from '../common/derive/skycult'

// 宿主 → InfoWindowStore 回注（store 不触碰 UI / 控制器 / 他 store）。
export interface InfoWindowHostHooks {
  // UI 提示（store 不触碰 UI）。
  flashHint(text: ResourceStr): void
  // 信息模式派生级别 / 选中详情刷新本体留宿主。
  applySelectedInfoMode(mode: string): void
  refreshSelectedObject(): void
  // 跨 store（ObjectDetailStore）：清 selectedDetailLoaded。
  clearSelectedDetailLoaded(): void
  // 呈现轴（观测模式）落盘：preferences 细节留宿主，store 只传值。
  persistDetailDisplayMode(mode: string): void
}

@Observed
export class InfoWindowStore {
  infoWinVisible: boolean = false
  infoWinExpanded: boolean = false
  informationMode: string = 'default'
  informationCustomMask: number = 0
  informationSettingPending: boolean = false
  infoLevel: number = 1

  // ── 呈现轴：详情卡形态（与上面的信息级别**数据轴正交**）──
  // informationMode 决定「回包带哪些字段 / 全量内容显示什么」（C++ 持久化，走桥）；
  // detailDisplayMode 只决定「这张卡默认怎么呈现」（纯 ArkTS，走 preferences，**不碰桥**）。
  // 'planetarium' = 全量卡（现状）；'observe' = 极简观测卡（页头 + 三 tag + 居中/展开按钮行）。
  detailDisplayMode: string = 'planetarium'
  // 观测模式下「本次已展开」的瞬态标志：不落盘，切目标 / 关卡片时复位，
  // 保证下次选星仍以极简形态出现（见 specs/OBJECT-DETAIL-OBSERVE-MODE.md §4.5）。
  observeExpanded: boolean = false

  // —— 桥 / 宿主回注 ——
  private port: CommandPort | null = null
  private hooks: InfoWindowHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口；字段赋值即驱动宿主重绘（store 无 publish* 发布点）。
  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: InfoWindowHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  // 天体信息模式切换：桥经 CommandPort，UI 提示经 hooks.flashHint，派生级别 / 选中详情刷新经 hooks。
  setInformationMode(mode: string): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    if (this.informationSettingPending || mode === this.informationMode) return
    this.informationSettingPending = true
    port.requestInteractive('setInformationSetting', 'mode|' + mode, (r: StellariumBridgeResponse) => {
      this.informationSettingPending = false
      if (r.ok !== true) { hooks.flashHint(r.error ?? I18n.t('msg_apply_failed')); return }
      this.informationMode = r.infoMode ?? mode
      if (r.customInfoMask !== undefined) this.informationCustomMask = Number(r.customInfoMask)
      hooks.applySelectedInfoMode(this.informationMode)
      hooks.clearSelectedDetailLoaded()
      hooks.refreshSelectedObject()
    }, () => {
      this.informationSettingPending = false
      hooks.flashHint(I18n.t('msg_apply_failed'))
    })
  }

  // 自定义信息模式下单字段开关：置位后桥写入，回包掩码为准；清详情经 hooks。
  setInformationField(key: string, enabled: boolean): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    if (this.informationSettingPending || this.informationMode !== 'custom' || this.informationMaskHas(key) === enabled) return
    const bit = informationMaskBit(key)
    if (bit === 0) return
    const nextMask = enabled ? (this.informationCustomMask | bit) : (this.informationCustomMask & ~bit)
    this.informationSettingPending = true
    port.requestInteractive('setInformationSetting', 'mask|' + nextMask.toString(), (r: StellariumBridgeResponse) => {
      this.informationSettingPending = false
      if (r.ok !== true) { hooks.flashHint(r.error ?? I18n.t('msg_apply_failed')); return }
      this.informationMode = 'custom'
      this.informationCustomMask = r.customInfoMask !== undefined ? Number(r.customInfoMask) : nextMask
      this.infoLevel = 0
      hooks.clearSelectedDetailLoaded()
      hooks.refreshSelectedObject()
    }, () => {
      this.informationSettingPending = false
      hooks.flashHint(I18n.t('msg_apply_failed'))
    })
  }

  // ==== 呈现轴：详情卡形态（观测模式）====
  //
  // 纯 ArkTS 呈现状态：**不调用桥、不刷新选中详情**（数据本来就在 store 里，切换即时生效）。
  // 这是「正交两轴」的直接收益：观测模式始终携带全量数据，只是默认少渲染 UI。

  // 切换详情卡默认呈现（快捷面板开关 / 设置页开关共用）。
  setDetailDisplayMode(mode: string): void {
    const next = mode === 'observe' ? 'observe' : 'planetarium'
    if (next === this.detailDisplayMode) return
    this.detailDisplayMode = next
    // 换轴即重新起算展开态，避免「天文馆展开 → 切回观测」还留着上一轮的展开标志。
    this.observeExpanded = false
    const hooks = this.hooks
    if (hooks !== null) hooks.persistDetailDisplayMode(next)
  }

  // 启动恢复（不走 setDetailDisplayMode：不需要等值短路，也无需回写盘）。
  restoreDetailDisplayMode(mode: string): void {
    this.detailDisplayMode = mode === 'observe' ? 'observe' : 'planetarium'
    this.observeExpanded = false
  }

  // 观测卡「展开 / 收起」只改瞬态标志，不落盘。
  setObserveExpanded(expanded: boolean): void {
    this.observeExpanded = expanded
  }

  // 切换选中目标 / 关闭卡片时复位（宿主在 targetChanged、onDismiss 处调用）。
  resetObserveExpand(): void {
    this.observeExpanded = false
  }

  // 观测模式开关是否开启（快捷面板格子的 ON 态、设置页 Toggle 的值）。
  observeModeEnabled(): boolean {
    return this.detailDisplayMode === 'observe'
  }

  // 当前是否处于**极简观测形态**：隐藏实时行 / 实时信息块 / 页签栏 / 滚动区，改渲染按钮行。
  observeCompact(): boolean {
    return this.detailDisplayMode === 'observe' && !this.observeExpanded
  }

  // ==== 信息显示「取值/判断」助手 ====
  //
  // 均读本 store 的 informationMode / informationCustomMask / infoLevel；
  // informationMaskHas 依赖纯函数 informationMaskBit。

  // 自定义模式下某字段位是否开启。
  informationMaskHas(key: string): boolean {
    const bit = informationMaskBit(key)
    return bit > 0 && (this.informationCustomMask & bit) === bit
  }

  // 距离信息是否可见。
  distanceInformationVisible(): boolean {
    return this.infoLevel <= 1 && (this.informationMode !== 'custom' || this.informationMaskHas('distance'))
  }

  // 实时信息块是否可见。
  selectedLiveInfoVisible(): boolean {
    return this.infoLevel <= 1
  }
}
