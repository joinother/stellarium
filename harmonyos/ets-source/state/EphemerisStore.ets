// DE 行星历表（JPL 数值星历）配置域状态 store：持有「设置 > 主设置」的 DE 内核开关
// （ephemerisDe430/431/440/441Available / Active）与 AstroPanel 星历表的起始日期
// （ephemerisStartYear / Month / Day）。
//
// 消费方：SettingsPanel 以 @ObjectLink 读 8 个 DE 开关；AstroPanel 经宿主回调读起始日期。
//
// 为何独立成 store（不并入 AstroStore）：AstroStore 里已有一族同名前缀但语义不同的字段
// （ephemerisData / Name / Meta / Error / Days / StepHours / StartOffsetDays / Mode /
// Primary / Secondary / Loading），那是 AstroPanel「星历表」自身的展示数据；本 store 的
// 前缀字段是设置项与起始日期，并入会造成前缀语义混淆与字段名冲突，故独立。
//
// 本 store 自持 CommandPort 与 EphemerisHostHooks；桥动作 setEphemerisEnabled 在此，
// UI 提示经 hooks 回注。
//
// 约束：所有更新必须是"字段整体赋值"，不得对 ephemerisDe4xx 做 push / sort / 属性原地赋值。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → EphemerisStore 回注（store 不触碰 UI 提示，经 hooks 回注）。
export interface EphemerisHostHooks {
  flashHint(text: ResourceStr): void
}

@Observed
export class EphemerisStore {
  ephemerisDe430Available: boolean = false
  ephemerisDe431Available: boolean = false
  ephemerisDe440Available: boolean = false
  ephemerisDe441Available: boolean = false
  ephemerisDe430Active: boolean = false
  ephemerisDe431Active: boolean = false
  ephemerisDe440Active: boolean = false
  ephemerisDe441Active: boolean = false
  ephemerisStartYear: number = new Date().getFullYear()
  ephemerisStartMonth: number = new Date().getMonth() + 1
  ephemerisStartDay: number = new Date().getDate()

  // —— 桥 / 宿主回注 ——
  private port: CommandPort | null = null
  private hooks: EphemerisHostHooks | null = null

  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: EphemerisHostHooks): void {
    this.hooks = hooks
  }

  private ensurePort(): CommandPort | null {
    return this.port
  }

  // DE 内核启用开关：未安装的星历不允许启用；桥经 CommandPort，UI 提示经 hooks.flashHint 回注。
  setEphemerisEnabled(key: string, available: boolean, enabled: boolean): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    if (!available && enabled) {
      hooks.flashHint('该星历文件未安装，无法启用')
      return
    }
    port.requestInteractive('setEphemerisSetting', key + '|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) { hooks.flashHint(r.error ?? I18n.t('msg_apply_failed')); return }
      if (key === 'de430') this.ephemerisDe430Active = enabled
      else if (key === 'de431') this.ephemerisDe431Active = enabled
      else if (key === 'de440') this.ephemerisDe440Active = enabled
      else if (key === 'de441') this.ephemerisDe441Active = enabled
    })
  }

  // 星历表起始日期选项标签：读本 store 的起始日期字段，负偏移显示 YYYY-MM-DD、0 显示"当前"、正偏移显示 +N 天。
  ephemerisStartOptionLabel(offsetDays: number): string {
    if (offsetDays < 0) {
      return this.ephemerisStartYear.toString() + '-' + this.ephemerisStartMonth.toString().padStart(2, '0') + '-' + this.ephemerisStartDay.toString().padStart(2, '0')
    }
    if (offsetDays === 0) return '当前'
    return '+' + offsetDays.toString() + ' 天'
  }
}
