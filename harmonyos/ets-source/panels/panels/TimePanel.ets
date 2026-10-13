import { I18n } from '../../pages/I18n'
import { TimeStore } from '../../state/TimeStore'
import { TimeWheelStore } from '../../state/TimeWheelStore'
import { EquationOfTimeStore } from '../../state/EquationOfTimeStore'
import { JulianDateStore } from '../../state/JulianDateStore'
import { NightModeStore } from '../../state/NightModeStore'
import { QuickChipRow } from '../../common/ui/QuickChipRow'
import { LayerSwitchRow } from '../layers/LayerSwitchRow'
import { TimeWheelScrubber } from '../time/TimeWheelScrubber'
import { TimeSpeedChips } from '../time/TimeSpeedChips'
import { SiderealTimeRow } from '../time/SiderealTimeRow'
import { EquationOfTimeBlock } from '../time/EquationOfTimeBlock'
import { JulianDateControls } from '../time/JulianDateControls'
import { ManualTimeBlock } from '../time/ManualTimeBlock'

// 观测时间面板，对应 `activePanel === 'time'`：时间转轴 + 速率档位 + 快捷跳转 + 恒星时 +
// 均时差 + 儒略日 + 手动指定时间 + 夜间模式（末行）。
//
// 五个 store（timeWheel / time / equationOfTime / julian / nightMode）走 @ObjectLink；
// 其余数值/颜色走 @Prop；时间轮控制器与手动时间的读写属宿主私有状态，经回调注入。
//
// 大气折射（气压 / 气温 / 消光）原属本面板，现移入「图层 → 天空 → 观测条件」节；
// 夜间模式复用图层面板的 LayerSwitchRow 行样式并置于面板最末。

@Component
export struct TimePanel {
  @ObjectLink timeWheelStore: TimeWheelStore
  @ObjectLink timeStore: TimeStore
  @ObjectLink equationOfTimeStore: EquationOfTimeStore
  @ObjectLink julianStore: JulianDateStore
  @ObjectLink nightModeStore: NightModeStore
  @Prop manualYear: number
  @Prop manualMonth: number
  @Prop manualDay: number
  @Prop manualHour: number
  @Prop manualMinute: number
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop inputColor: string
  @Prop borderTint: string
  onSelectUnit: (unit: string) => void = () => {}
  onWheelTouch: (event: TouchEvent) => void = () => {}
  onChip: (id: string) => void = () => {}
  onEquationToggle: (setting: string, enabled: boolean) => void = () => {}
  onAdjustJulian: (scale: string, direction: number) => void = () => {}
  onApplyJulian: (scale: string) => void = () => {}
  onNightMode: (enabled: boolean) => void = () => {}
  onPickDate: (year: number, monthIndex: number, day: number) => void = () => {}
  onPickTime: (hour: number, minute: number) => void = () => {}
  onApplyManual: () => void = () => {}
  onResetManual: () => void = () => {}

  build() {
    Column() {
      // Sky Guide 风格时间拖动滑块（-365天 ~ +365天）：置于面板最前，手机端打开即可直接拖动
      TimeWheelScrubber({
        store: this.timeWheelStore,
        onSelectUnit: (unit: string) => { this.onSelectUnit(unit) },
        onWheelTouch: (event: TouchEvent) => { this.onWheelTouch(event) }
      })
      TimeSpeedChips({ store: this.timeStore, onChip: (id: string) => { this.onChip(id) } })
      QuickChipRow({ items: [
        { id: '-12h', label: '-12h' }, { id: '+12h', label: '+12h' },
        { id: 'sunRise', label: '日出' }, { id: 'sunTransit', label: '中天' },
        { id: 'sunSet', label: '日落' }, { id: 'astronomicalSet', label: '天文昏' }
      ], onChip: (id: string) => { this.onChip(id) } })
      SiderealTimeRow({
        store: this.timeStore,
        subColor: this.subColor
      })
      EquationOfTimeBlock({
        store: this.equationOfTimeStore,
        textColor: this.textColor,
        subColor: this.subColor,
        accentColor: this.accentColor,
        panelColor: this.panelColor,
        onToggle: (setting: string, enabled: boolean) => { this.onEquationToggle(setting, enabled) }
      })
      JulianDateControls({
        store: this.julianStore,
        textColor: this.textColor,
        subColor: this.subColor,
        inputColor: this.inputColor,
        onAdjust: (scale: string, direction: number) => { this.onAdjustJulian(scale, direction) },
        onApply: (scale: string) => { this.onApplyJulian(scale) }
      })
      ManualTimeBlock({
        manualYear: this.manualYear,
        manualMonth: this.manualMonth,
        manualDay: this.manualDay,
        manualHour: this.manualHour,
        manualMinute: this.manualMinute,
        textColor: this.textColor,
        subColor: this.subColor,
        inputColor: this.inputColor,
        panelColor: this.panelColor,
        borderColorValue: this.borderTint,
        onPickDate: (year: number, monthIndex: number, day: number) => { this.onPickDate(year, monthIndex, day) },
        onPickTime: (hour: number, minute: number) => { this.onPickTime(hour, minute) },
        onApply: () => { this.onApplyManual() },
        onReset: () => { this.onResetManual() }
      })
      // 夜间模式置于末行，行样式与图层面板一致（共用 LayerSwitchRow）；上间距与上方各行统一为 8px
      Column() {
        LayerSwitchRow({
          label: I18n.t('s0300'),
          isOn: this.nightModeStore.nightMode,
          onToggle: (value: boolean) => { this.onNightMode(value) }
        })
      }.width('100%').margin({ top: 4 })
    }.width('100%')
  }
}
