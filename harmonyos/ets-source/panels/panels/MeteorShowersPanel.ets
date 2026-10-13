import { curves } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { MeteorShowerItem } from '../../pages/MainWindowModels'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { MeteorStore } from '../../state/MeteorStore'

// 流星雨面板，对应 `activePanel === 'meteorshowers'`。
//
// 四个开关位、目录来源与活跃流星雨列表来自 MeteorStore（@ObjectLink）；
// 开关动作与“点条目搜索天体”回调注入宿主。开关字段用 msXxx：成员名须避开
// CustomComponent 基类的 enabled 属性方法。

@Component
export struct MeteorShowersPanel {
  @ObjectLink meteorStore: MeteorStore
  @Prop panelColor: string
  onSetFlag: (flag: string, value: boolean) => void = () => {}
  onSearch: (name: string) => void = () => {}

  private fmtIso(iso: string): string {
    if (!iso || iso.length < 16) return '--'
    const parts = iso.split('T')
    const d = parts[0] ?? ''
    const t = parts[1] ?? ''
    return (d.length >= 10 ? d.slice(5) : d) + ' ' + (t.length >= 8 ? t.slice(0, 5) : t)
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row() {
          Text(I18n.t('c_enable_meteor_plugin')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msEnabled })
            .onChange((isOn: boolean) => { this.onSetFlag('enabled', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('c_show_radiant_labels')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msLabels })
            .onChange((isOn: boolean) => { this.onSetFlag('labels', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('c_active_only')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msActiveOnly })
            .onChange((isOn: boolean) => { this.onSetFlag('activeOnly', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('c_show_radiant_markers')).fontSize(13).fontColor('#E5FFFFFF').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.meteorStore.msMarker })
            .onChange((isOn: boolean) => { this.onSetFlag('marker', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        if (this.meteorStore.msCatalogName.length > 0 || this.meteorStore.msCatalogVersion.length > 0 || this.meteorStore.msCatalogSource.length > 0) {
          Column({ space: 2 }) {
            Text('原版流星雨目录' + (this.meteorStore.msCatalogVersion.length > 0 ? ' · v' + this.meteorStore.msCatalogVersion : '')).fontSize(10).fontColor('#88FFFFFF').width('100%')
            if (this.meteorStore.msCatalogSource.length > 0) Text(I18n.t('resource_source') + ': ' + this.meteorStore.msCatalogSource).fontSize(10).fontColor('#66FFFFFF').width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor('rgba(111, 168, 207, 0.08)').borderRadius(UI_RADIUS_CONTROL)
        }
        Text(I18n.t('meteor_radiant_desc'))
          .fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 4, right: 4 }).margin({ top: 4 })
        Text(I18n.t('meteor_active_showers'))
          .fontSize(13).fontColor('#FFE9B0').width('100%').margin({ top: 8, bottom: 2 })
        if (this.meteorStore.msShowerList.length > 0) {
          ForEach(this.meteorStore.msShowerList, (s: MeteorShowerItem) => {
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(s.name).fontSize(14).fontColor('#FFD54F').layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(s.zhr > 0 ? (I18n.t('meteor_zhr_label') + ' ' + s.zhr) : '').fontSize(12)
                  .fontColor('#BBDEFB').padding({ left: 6, right: 6 })
                  .backgroundColor('rgba(30, 60, 100, 0.5)').borderRadius(UI_RADIUS_CONTROL)
                Text(s.status === 'confirmed' ? 'Confirmed' : 'Generic').fontSize(10)
                  .fontColor(s.status === 'confirmed' ? '#81C784' : '#FFB74D')
                  .padding({ left: 4, right: 4 }).backgroundColor('rgba(255, 255, 255, 0.08)').borderRadius(UI_RADIUS_CONTROL)
              }.width('100%')
              if (s.peakDate.length > 0) {
                Row({ space: 8 }) {
                  Text(I18n.t('meteor_peak') + ': ' + this.fmtIso(s.peakDate)).fontSize(11).fontColor('#DDDDDD').layoutWeight(1)
                }.width('100%')
              }
              if (s.activeStart.length > 0 && s.activeEnd.length > 0) {
                Row({ space: 8 }) {
                  Text(I18n.t('meteor_active_range') + ': ' + this.fmtIso(s.activeStart) + ' ~ ' + this.fmtIso(s.activeEnd)).fontSize(11)
                    .fontColor('#AAAAAA').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width('100%')
              }
              Row({ space: 12 }) {
                if (s.speed > 0) {
                  Text(I18n.t('meteor_speed') + ': ' + s.speed + ' km/s').fontSize(11).fontColor('#999999')
                }
                if (s.parent.length > 0) {
                  Text(I18n.t('meteor_parent') + ': ' + s.parent).fontSize(11).fontColor('#999999')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }
              }.width('100%')
            }.width('100%').padding(10).backgroundColor('#1A2330').borderRadius(UI_RADIUS_CONTROL).margin({ top: 2 })
              .stateStyles({ pressed: { backgroundColor: '#27384A' } })
              .onClick(() => {
                if (s.englishName.length > 0) {
                  this.onSearch(s.englishName)
                }
              })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 300, curve: curves.springMotion(0.5, 1.0) })
                  .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 320, curve: curves.springMotion(0.5, 1.0) })),
                TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
                  .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 200, curve: Curve.EaseIn }))
              ))
          }, (s: MeteorShowerItem) => s.englishName)
        } else {
          Text(I18n.t('meteor_no_active'))
            .fontSize(12).fontColor('#666666').width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
        }
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
