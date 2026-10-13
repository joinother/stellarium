import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 时间面板的快捷跳转按钮组：天文事件 / 二分二至 / 天文时间单位。
//
// 三段都是"纯触发"按钮（只调 triggerAction），因此把按钮表放在组件内部，
// 用嵌套 ForEach 渲染；点击经 onAction 交回宿主。刻意不使用带参数的 @Builder
// （参数化 @Builder 的子树首帧后冻结）。
interface JumpAction {
  labelKey: string
  action: string
}

interface JumpSection {
  titleKey: string
  pill: boolean
  rows: JumpAction[][]
}

const JUMP_SECTIONS: JumpSection[] = [
  {
    titleKey: 'i0111', pill: true, rows: [
      [{ labelKey: 'i0146', action: 'actionNext_Rising' }, { labelKey: 'i0147', action: 'actionNext_Setting' }, { labelKey: 'i0148', action: 'actionNext_Transit' }],
      [{ labelKey: 'i0149', action: 'actionToday_Rising' }, { labelKey: 'i0150', action: 'actionToday_Setting' }, { labelKey: 'i0151', action: 'actionToday_Transit' }],
      [{ labelKey: 'i0152', action: 'actionPrevious_Rising' }, { labelKey: 'i0153', action: 'actionPrevious_Setting' }, { labelKey: 'i0154', action: 'actionPrevious_Transit' }],
      [{ labelKey: 'i0155', action: 'actionNext_MorningTwilight' }, { labelKey: 'i0156', action: 'actionNext_EveningTwilight' }],
      [{ labelKey: 'i0157', action: 'actionPrevious_MorningTwilight' }, { labelKey: 'i0158', action: 'actionPrevious_EveningTwilight' }]
    ]
  },
  {
    titleKey: 'i0112', pill: true, rows: [
      [{ labelKey: 'i0159', action: 'actionNext_March_Equinox' }, { labelKey: 'i0160', action: 'actionNext_June_Solstice' }, { labelKey: 'i0161', action: 'actionNext_September_Equinox' }, { labelKey: 'i0162', action: 'actionNext_December_Solstice' }],
      [{ labelKey: 'i0163', action: 'actionPrevious_March_Equinox' }, { labelKey: 'i0164', action: 'actionPrevious_June_Solstice' }, { labelKey: 'i0165', action: 'actionPrevious_September_Equinox' }, { labelKey: 'i0166', action: 'actionPrevious_December_Solstice' }]
    ]
  },
  {
    titleKey: 'i0113', pill: false, rows: [
      [{ labelKey: 'i0173', action: 'actionAdd_Sidereal_Day' }, { labelKey: 'i0174', action: 'actionSubtract_Sidereal_Day' }, { labelKey: 'i0175', action: 'actionAdd_Sidereal_Year' }, { labelKey: 'i0176', action: 'actionSubtract_Sidereal_Year' }],
      [{ labelKey: 'i0177', action: 'actionAdd_Synodic_Month' }, { labelKey: 'i0178', action: 'actionSubtract_Synodic_Month' }, { labelKey: 'i0179', action: 'actionAdd_Saros' }, { labelKey: 'i0180', action: 'actionSubtract_Saros' }],
      [{ labelKey: 'i0181', action: 'actionAdd_Tropical_Year' }, { labelKey: 'i0182', action: 'actionSubtract_Tropical_Year' }, { labelKey: 'i0183', action: 'actionAdd_Julian_Year' }, { labelKey: 'i0184', action: 'actionSubtract_Julian_Year' }],
      [{ labelKey: 'i0185', action: 'actionAdd_Calendar_Month' }, { labelKey: 'i0186', action: 'actionSubtract_Calendar_Month' }, { labelKey: 'i0187', action: 'actionAdd_Calendar_Year' }, { labelKey: 'i0188', action: 'actionSubtract_Calendar_Year' }],
      [{ labelKey: 'i0189', action: 'actionAdd_Anomalistic_Month' }, { labelKey: 'i0190', action: 'actionAdd_Draconic_Month' }, { labelKey: 'i0191', action: 'actionAdd_Metonic_Cycle' }, { labelKey: 'i0192', action: 'actionAdd_Inex' }],
      [{ labelKey: 'i0193', action: 'actionAdd_Gaussian_Year' }, { labelKey: 'i0194', action: 'actionAdd_Calendar_Decade' }, { labelKey: 'i0195', action: 'actionAdd_Calendar_Century' }, { labelKey: 'i0196', action: 'actionAdd_Julian_Century' }]
    ]
  }
]

@Component
export struct TimeJumpActions {
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop borderColorValue: string
  onAction: (action: string) => void = () => {}

  build() {
    Column() {
      ForEach(JUMP_SECTIONS, (section: JumpSection) => {
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.borderColorValue)
          .margin({ top: 6, bottom: 4 })
        Row() {
          Text(I18n.t(section.titleKey)).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 2 })
        }
        .height(18).width('100%')
        ForEach(section.rows, (row: JumpAction[]) => {
          Row({ space: section.pill ? 6 : 4 }) {
            ForEach(row, (item: JumpAction) => {
              Button(I18n.t(item.labelKey))
                .fontSize(section.pill ? 11 : 10)
                .fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(section.pill ? UI_RADIUS_PILL : UI_RADIUS_CONTROL)
                .height(section.pill ? 30 : 26)
                .padding({ left: section.pill ? 10 : 8, right: section.pill ? 10 : 8 })
                .onClick(() => { this.onAction(item.action) })
            }, (item: JumpAction) => item.action)
          }.width('100%').padding({ left: 4, right: 4 }).margin({ bottom: 4 })
        }, (row: JumpAction[]) => row[0].action)
      }, (section: JumpSection) => section.titleKey)
    }.width('100%')
  }
}
