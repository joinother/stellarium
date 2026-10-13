import { I18n } from '../../pages/I18n'
import { ConfigurationOption } from '../../pages/MainWindowModels'
import { TimeSettingsStore } from '../../state/TimeSettingsStore'
import { SettingsChoiceButton } from '../../common/ui/SettingsChoiceButton'
import { SettingsSwitchRow } from '../../common/ui/SettingsSwitchRow'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 设置面板「时间」标签页的上半部分：日期格式 / 时间格式 / 启动时间来源。
// 选中态与开关经 store / @Prop 实时刷新。
// ΔT 算法块是独立组件，由宿主紧随本组件之后渲染。
@Component
export struct TimeSettingsSection {
  @ObjectLink store: TimeSettingsStore
  @Prop pending: boolean
  @Prop observationTimeText: string
  @Prop textColor: string
  @Prop subColor: string
  @Prop inputColor: string
  @Prop panelColor: string
  @Prop accentColor: string
  @Prop borderColorValue: string
  onSelectFormat: (group: string, value: string) => void = () => {}
  onSetStartup: (key: string, value: string) => void = () => {}

  private dateFormatLabel(value: string): string {
    return I18n.t('time_date_' + value)
  }

  private timeFormatLabel(value: string): string {
    return I18n.t('time_clock_' + value)
  }

  build() {
    Column() {
      Text(I18n.t('time_format_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
      Text(this.observationTimeText).fontSize(16).fontColor(this.textColor).width('100%')
        .padding(12).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      Text(I18n.t('s0354')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ top: 2, bottom: 4 })
      Text(this.dateFormatLabel(this.store.configDateFormat)).fontSize(12).fontColor(this.textColor).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach([
          { id: 'system_default', label: '系统' }, { id: 'yyyymmdd', label: '年-月-日' },
          { id: 'ddmmyyyy', label: '日-月-年' }, { id: 'mmddyyyy', label: '月-日-年' },
          { id: 'wwyyyymmdd', label: '星期 + 年-月-日' }, { id: 'wwddmmyyyy', label: '星期 + 日-月-年' },
          { id: 'wwmmddyyyy', label: '星期 + 月-日-年' },
        ] as ConfigurationOption[], (option: ConfigurationOption) => {
          SettingsChoiceButton({
            label: this.dateFormatLabel(option.id),
            active: this.store.configDateFormat === option.id,
            canPick: !this.pending,
            textColor: this.textColor,
            subColor: this.subColor,
            activeColor: this.accentColor,
            panelColor: this.panelColor,
            onPick: () => { this.onSelectFormat('date', option.id) }
          })
        }, (option: ConfigurationOption) => option.id)
      }.width('100%').padding({ left: 8, right: 8 })
      Row().width('100%').height(0.5).backgroundColor(this.borderColorValue).margin({ top: 7, bottom: 7 })
      Text(I18n.t('s0353')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ bottom: 4 })
      Text(this.timeFormatLabel(this.store.configTimeFormat)).fontSize(12).fontColor(this.textColor).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach([
          { id: 'system_default', label: '系统' }, { id: '24h', label: '24 小时制' }, { id: '12h', label: '12 小时制' },
        ] as ConfigurationOption[], (option: ConfigurationOption) => {
          SettingsChoiceButton({
            label: this.timeFormatLabel(option.id),
            active: this.store.configTimeFormat === option.id,
            canPick: !this.pending,
            textColor: this.textColor,
            subColor: this.subColor,
            activeColor: this.accentColor,
            panelColor: this.panelColor,
            onPick: () => { this.onSelectFormat('time', option.id) }
          })
        }, (option: ConfigurationOption) => option.id)
      }.width('100%').padding({ left: 8, right: 8 })
      Row().width('100%').height(0.5).backgroundColor(this.borderColorValue).margin({ top: 7, bottom: 7 })
      Text(I18n.t('time_startup_title')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ bottom: 4 })
      Text(I18n.t('time_startup_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
      Text(I18n.t('time_zone_label') + this.store.timeSettingsZone).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach([
          { id: 'actual', label: '系统当前时间' }, { id: 'today', label: '今天指定时刻' }, { id: 'preset', label: '预设时间' }
        ] as ConfigurationOption[], (option: ConfigurationOption) => {
          SettingsChoiceButton({
            label: I18n.t('time_mode_' + option.id),
            active: this.store.startupTimeMode === option.id,
            canPick: !this.pending,
            textColor: this.textColor,
            subColor: this.subColor,
            activeColor: this.accentColor,
            panelColor: this.panelColor,
            onPick: () => { this.onSelectFormat('startup', option.id) }
          })
        }, (option: ConfigurationOption) => option.id)
      }.width('100%').padding({ left: 8, right: 8 }).margin({ bottom: 4 })
      SettingsSwitchRow({
        label: I18n.t('time_startup_pause'),
        isOn: this.store.startupTimeStop,
        canToggle: !this.pending,
        textColor: this.textColor,
        accentColor: this.accentColor,
        panelColor: this.panelColor,
        borderColorValue: this.borderColorValue,
        onToggle: (value: boolean) => { this.onSetStartup('startupStop', value ? '1' : '0') }
      })
      if (this.store.startupTimeMode === 'today') {
        Column({ space: 6 }) {
          Text(I18n.t('time_today_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
          Row({ space: 6 }) {
            TextInput({ text: this.store.startupTodayTime, placeholder: 'HH:mm:ss' }).height(40).layoutWeight(1).fontSize(14).fontColor(this.textColor)
              .enabled(!this.pending)
              .backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL)
              .onChange((value: string) => { this.store.startupTodayTime = value })
            Button(I18n.t('time_save')).fontSize(12).height(40).enabled(!this.pending).padding({ left: 12, right: 12 }).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSetStartup('todayTime', this.store.startupTodayTime) })
          }.width('100%').padding({ left: 10, right: 8 }).margin({ bottom: 6 })
        }.width('100%').transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 6 })))
      }
      if (this.store.startupTimeMode === 'preset') {
        Column({ space: 6 }) {
          Text(I18n.t('time_preset_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
          TextInput({ text: this.store.startupPresetLocalTime, placeholder: 'YYYY-MM-DDTHH:mm:ss' })
            .fontSize(14).height(42).width('100%').fontColor(this.textColor).backgroundColor(this.inputColor)
            .borderRadius(UI_RADIUS_CONTROL).enabled(!this.pending)
            .onChange((value: string) => { this.store.startupPresetLocalTime = value })
          Button(I18n.t('time_save')).fontSize(12).height(40).enabled(!this.pending)
            .fontColor(this.textColor).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSetStartup('presetLocal', this.store.startupPresetLocalTime.replace(' ', 'T')) })
        }.width('100%').transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 6 })))
      }
      Row({ space: 6 }) {
        Text(I18n.t('time_capture_preset')).fontSize(12).fontColor(this.subColor).layoutWeight(1)
        Button(I18n.t('time_save')).fontSize(12).height(40).enabled(!this.pending).padding({ left: 12, right: 12 }).fontColor(this.textColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSetStartup('presetCurrent', '1') })
      }.width('100%').padding({ left: 10, right: 8 }).margin({ bottom: 8 })
      Button(I18n.t('time_apply_startup')).fontSize(14).height(42).width('100%')
        .enabled(!this.pending).fontColor(this.textColor).backgroundColor(this.accentColor).borderRadius(UI_RADIUS_CONTROL)
        .onClick(() => { this.onSetStartup('applyStartup', '1') })
      Text(I18n.t('time_apply_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
    }.width('100%')
  }
}
