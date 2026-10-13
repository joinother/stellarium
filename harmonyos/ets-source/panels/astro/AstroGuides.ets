import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 天文面板的两个小展示组件。
//
// 现象关系标记是纯映射（只依赖 type 与资源），故只收一个 @Prop；
// 选择提示则把夜视三色与"打开目标选择器"的动作交给宿主注入。
@Component
export struct AstroSelectionGuide {
  @Prop visible: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  onOpenPicker: () => void = () => {}

  build() {
    Column({ space: 0 }) {
    if (this.visible) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(I18n.t('astro_selection_required')).fontSize(11).fontColor(this.textColor).width('100%')
          Text(I18n.t('astro_selection_required_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(I18n.t('astro_select_on_map')).fontSize(10).fontColor(this.textColor).backgroundColor(this.accentColor)
          .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 9, right: 9 })
          .onClick(() => { this.onOpenPicker() })
      }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor('rgba(91,147,191,0.12)').border({ width: 1, color: 'rgba(143,211,255,0.24)' })
        .borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
    }
    }
  }
}

@Component
export struct PhenomenonRelationMark {
  @Prop type: string

  build() {
    Column({ space: 0 }) {
      if (this.type === '合') {
        Image($r('app.media.ic_phenomenon_conjunction'))
      } else if (this.type === '冲') {
        Image($r('app.media.ic_phenomenon_opposition'))
      } else if (this.type.indexOf('方照') >= 0) {
        if (this.type.indexOf('东') >= 0) {
          Image($r('app.media.ic_phenomenon_quadrature_east'))
        } else {
          Image($r('app.media.ic_phenomenon_quadrature_west'))
        }
      } else if (this.type.indexOf('大距') >= 0) {
        if (this.type.indexOf('东') >= 0) {
          Image($r('app.media.ic_phenomenon_elongation_east'))
        } else {
          Image($r('app.media.ic_phenomenon_elongation_west'))
        }
      } else if (this.type.indexOf('近日点') >= 0) {
        Image($r('app.media.ic_phenomenon_perihelion'))
      } else if (this.type.indexOf('远日点') >= 0) {
        Image($r('app.media.ic_phenomenon_aphelion'))
      } else if (this.type.indexOf('顺行') >= 0) {
        Image($r('app.media.ic_phenomenon_station_direct'))
      } else if (this.type.indexOf('逆行') >= 0) {
        Image($r('app.media.ic_phenomenon_station_retrograde'))
      } else {
        Image($r('app.media.ic_phenomenon_station'))
      }
    }
  }
}
