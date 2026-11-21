import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { MeteorShowerItem } from '../../pages/MainWindowModels'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'
import { MeteorStore } from '../../state/MeteorStore'

// 流星雨面板，对应 `activePanel === 'meteorshowers'`。
// 四个开关位、目录来源与活跃流星雨列表来自 MeteorStore（@ObjectLink）；
// 开关动作与"点条目搜索天体"回调注入宿主。

@Component
export struct MeteorShowersPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink meteorStore: MeteorStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSetFlag: (flag: string, value: boolean) => void = () => {}
  onSearch: (name: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private fs(base: number): number { return uiFontSize(base, this.readableUi, this.uiFontScale) }
  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

  private fmtIso(iso: string): string {
    if (!iso || iso.length < 16) return '--'
    const parts = iso.split('T')
    const d = parts[0] ?? ''
    const t = parts[1] ?? ''
    return (d.length >= 10 ? d.slice(5) : d) + ' ' + (t.length >= 8 ? t.slice(0, 5) : t)
  }

  private catalogTipText(): string {
    const base = I18n.t('meteor_radiant_desc')
    if (this.meteorStore.msCatalogSource.length > 0) {
      return base + '\n目录版本：' + (this.meteorStore.msCatalogVersion || '内置') + ' · 来源：' + this.meteorStore.msCatalogSource
    }
    return base
  }

  build() {
      Column({ space: 10 }) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Row({ space: 6 }) {
              Text(I18n.t('c_enable_meteor_plugin'))
                .fontSize(this.fs(14)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
              InfoTipButton({
                title: I18n.t('plugin_meteor_showers'),
                tip: this.catalogTipText()
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)
            Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msEnabled })
              .selectedColor(this.c.accent)
              .onChange((isOn: boolean) => { this.onSetFlag('enabled', isOn) })
          }.width('100%').constraintSize({ minHeight: this.ch(40) }).alignItems(VerticalAlign.Center)

          Row().width('100%').height(0.5).backgroundColor(this.c.border)

          Row() {
            Text(I18n.t('c_show_radiant_labels')).fontSize(this.fs(13)).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msLabels })
              .selectedColor(this.c.accent)
              .onChange((isOn: boolean) => { this.onSetFlag('labels', isOn) })
          }.width('100%').constraintSize({ minHeight: this.ch(38) }).alignItems(VerticalAlign.Center)

          Row() {
            Text(I18n.t('c_active_only')).fontSize(this.fs(13)).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msActiveOnly })
              .selectedColor(this.c.accent)
              .onChange((isOn: boolean) => { this.onSetFlag('activeOnly', isOn) })
          }.width('100%').constraintSize({ minHeight: this.ch(38) }).alignItems(VerticalAlign.Center)

          Row() {
            Text(I18n.t('c_show_radiant_markers')).fontSize(this.fs(13)).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msMarker })
              .selectedColor(this.c.accent)
              .onChange((isOn: boolean) => { this.onSetFlag('marker', isOn) })
          }.width('100%').constraintSize({ minHeight: this.ch(38) }).alignItems(VerticalAlign.Center)
        }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        Row({ space: 6 }) {
          Text(I18n.t('meteor_active_showers'))
            .fontSize(this.fs(13.5)).fontWeight(FontWeight.Medium).fontColor(this.c.warning).layoutWeight(1)
          Text(String(this.meteorStore.msShowerList.length) + ' 场')
            .fontSize(this.fs(11)).fontColor(this.c.sub)
        }.width('100%').padding({ left: 4, right: 4, top: 2 })

        if (this.meteorStore.msShowerList.length > 0) {
          ForEach(this.meteorStore.msShowerList, (s: MeteorShowerItem) => {
            Column({ space: 5 }) {
              Row({ space: 6 }) {
                Text(s.name).fontSize(this.fs(14)).fontWeight(FontWeight.Medium).fontColor(this.c.warning).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (s.zhr > 0) {
                  Text(I18n.t('meteor_zhr_label') + ' ' + s.zhr).fontSize(this.fs(11))
                    .fontColor(this.c.accent).padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_PILL)
                }
                Text(s.status === 'confirmed' ? '已确认' : '待确认').fontSize(this.fs(10.5))
                  .fontColor(s.status === 'confirmed' ? this.c.success : this.c.warning)
                  .padding({ left: 7, right: 7, top: 2, bottom: 2 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_PILL)
              }.width('100%').alignItems(VerticalAlign.Center)
              if (s.peakDate.length > 0) {
                Text(I18n.t('meteor_peak') + '：' + this.fmtIso(s.peakDate))
                  .fontSize(this.fs(12)).fontColor(this.c.text).width('100%')
              }
              if (s.activeStart.length > 0 && s.activeEnd.length > 0) {
                Text(I18n.t('meteor_active_range') + '：' + this.fmtIso(s.activeStart) + ' ~ ' + this.fmtIso(s.activeEnd))
                  .fontSize(this.fs(11)).fontColor(this.c.sub).width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              Row({ space: 12 }) {
                if (s.speed > 0) {
                  Text(I18n.t('meteor_speed') + ' ' + s.speed + ' km/s').fontSize(this.fs(11)).fontColor(this.c.sub)
                }
                if (s.parent.length > 0) {
                  Text(I18n.t('meteor_parent') + '：' + s.parent).fontSize(this.fs(11)).fontColor(this.c.sub)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }
              }.width('100%')
            }
              .width('100%')
              .padding(12)
              .backgroundColor(this.c.bg)
              .border({ width: 0.5, color: this.c.border })
              .borderRadius(UI_RADIUS_CARD)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
              .stateStyles({ pressed: { .backgroundColor(this.c.rowBg) } })
              .onClick(() => {
                if (s.englishName.length > 0) {
                  this.onSearch(s.englishName)
                }
              })
              .transition(uiFadeUpTransition())
          }, (s: MeteorShowerItem) => s.englishName)
        } else {
          Text(I18n.t('meteor_no_active'))
            .fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').textAlign(TextAlign.Center).padding({ top: 18, bottom: 18 })
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CARD)
        }
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
