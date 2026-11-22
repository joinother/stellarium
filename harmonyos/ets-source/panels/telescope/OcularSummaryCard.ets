import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 目镜面板顶部的「当前组合」摘要：器材名 + 放大率/视场，切换页签时始终可见。
@Component
export struct OcularSummaryCard {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink store: TelescopeStore
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private lensText(): string {
    if (this.store.lensIndex < 0) return I18n.t('ocular_no_lens')
    return this.store.ocularSelInfo('Lens').name
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(I18n.t('ocular_summary_current')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
        Text(this.store.ocularSelInfo('Ocular').name)
          .fontSize(panelFontSize(13, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if (this.store.ocularMagnification > 0) {
          Text(this.store.ocularMagnification.toFixed(1) + '×')
            .fontSize(panelFontSize(13, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
        }
      }.width('100%').alignItems(VerticalAlign.Center)
      Row({ space: 8 }) {
        Text(this.store.ocularSelInfo('Telescope').name)
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text(this.lensText())
          .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).maxLines(1)
        if (this.store.ocularActualFov > 0) {
          Text(this.store.ocularActualFov.toFixed(2) + '°')
            .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
        }
        if (this.store.ocularCcdFovX > 0) {
          Text('CCD ' + this.store.ocularCcdFovX.toFixed(2) + '° × ' + this.store.ocularCcdFovY.toFixed(2) + '°')
            .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
        }
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .id('oculars-summary')
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.c.soft)
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ bottom: 8 })
  }
}
