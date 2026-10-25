import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { I18n } from '../../pages/I18n'
import { OcularInstrumentItem } from '../../pages/MainWindowModels'
import { TelescopeStore } from '../../state/TelescopeStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 「目镜（Oculars）」面板的设备选择行。
//
// @Prop 驱动选中态，换目镜/望远镜/镜头/CCD 后选中态与摘要实时刷新。
//
// 原生桥分派 `selectOcularInstrument(kind, index)` 经 onSelect 回调由宿主执行；
// 列表查表与选中判断（ocularInstrumentItems / ocularInstrumentIndex / ocularInstrumentSummary /
// ocularSelInfo）是纯计算，随状态在 TelescopeStore，组件经 @ObjectLink 实时读取。
//
// 视觉：标题 12 号 subColor + 计数 10 号 subColor / 空态 11 号高 42 / 横向 Scroll 高 52 /
// 按钮高 48（minWidth 116、maxWidth 180）/ 选中 #FFFFFF 与 #D8EEFF。
@Component
export struct OcularSelector {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink store: TelescopeStore
  @Prop kind: string
  @Prop label: string
  @State c: ThemeSlots = DEFAULT_SLOTS
  onSelect: (kind: string, index: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.label).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.sub).layoutWeight(1)
        Text(this.store.ocularSelInfo(this.kind).countText).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub)
      }.width('100%').padding({ left: 2, right: 2 })
      if (this.store.ocularInstrumentItems(this.kind).length === 0 && this.kind !== 'Lens') {
        Text(I18n.t('ocular_no_devices')).fontSize(11).fontColor(this.c.sub)
          .width('100%').height(42).textAlign(TextAlign.Center)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      } else {
        Scroll() {
          Row({ space: 7 }) {
            if (this.kind === 'Lens') {
              Button(I18n.t('ocular_no_lens'))
                .fontSize(11).fontColor(this.store.lensIndex < 0 ? this.c.onAccent : this.c.sub)
                .height(48).padding({ left: 14, right: 14 })
                .backgroundColor(this.store.lensIndex < 0 ? this.c.accent : this.c.bg)
                .border({ width: 1, color: this.store.lensIndex < 0 ? this.c.accent : this.c.border })
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSelect(this.kind, -1) })
            }
            ForEach(this.store.ocularInstrumentItems(this.kind), (item: OcularInstrumentItem) => {
              Button() {
                Column({ space: 2 }) {
                  Text(item.name.length > 0 ? item.name : this.label)
                    .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.store.ocularInstrumentIndex(this.kind) === item.index ? this.c.onAccent : this.c.text)
                    .fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.store.ocularInstrumentSummary(this.kind, item))
                    .fontSize(panelFontSize(11, this.readableUi)).fontColor(this.store.ocularInstrumentIndex(this.kind) === item.index ? this.c.chipInactiveText : this.c.sub)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start)
              }
              .height(48).constraintSize({ minWidth: 116, maxWidth: 180 }).padding({ left: 12, right: 12 })
              .backgroundColor(this.store.ocularInstrumentIndex(this.kind) === item.index ? this.c.accent : this.c.bg)
              .border({ width: 1, color: this.store.ocularInstrumentIndex(this.kind) === item.index ? this.c.accent : this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onSelect(this.kind, item.index) })
            }, (item: OcularInstrumentItem) => this.kind + '-' + item.index.toString())
          }.height(50)
        }.width('100%').height(52).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }.width('100%')
  }
}
