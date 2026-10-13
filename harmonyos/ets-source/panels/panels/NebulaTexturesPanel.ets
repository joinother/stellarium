import { I18n } from '../../pages/I18n'
import { NebulaTextureItem } from '../../pages/MainWindowModels'
import { NebulaTextureStore } from '../../state/NebulaTextureStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 星云贴图面板，对应 `activePanel === 'nebulaTextures'`。
//
// 贴图状态与加载/导入态来自 NebulaTextureStore（@ObjectLink），状态变更只重绘本面板；
// 刷新/导入/可见性/冲突规避/定位/删除等动作回调注入宿主；nebulaTextureStatusLabel 为组件内纯函数。

@Component
export struct NebulaTexturesPanel {
  @ObjectLink store: NebulaTextureStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onSetVisible: (enabled: boolean) => void = () => {}
  onRefresh: () => void = () => {}
  onImport: () => void = () => {}
  onSetConflictAvoidance: (value: boolean) => void = () => {}
  onGoto: (imageUrl: string) => void = () => {}
  onRemove: (imageUrl: string) => void = () => {}

  private nebulaTextureStatusLabel(status: string | undefined): string {
    if (status === 'ready') return I18n.t('nebula_texture_ready')
    if (status === 'missing_file') return I18n.t('nebula_texture_missing_file')
    if (status === 'decode_failed') return I18n.t('nebula_texture_decode_failed')
    if (status === 'invalid_mapping' || status === 'invalid_world_coords' || status === 'invalid_corner_count' || status === 'corner_out_of_range') return I18n.t('nebula_texture_invalid_mapping')
    if (status === 'remote_blocked') return I18n.t('nebula_texture_remote_blocked')
    if (status === 'config_invalid') return I18n.t('nebula_texture_config_invalid')
    return status ?? I18n.t('nebula_texture_unknown')
  }

  build() {
    Scroll() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(I18n.t('nebula_texture_title')).fontSize(14).fontColor(this.textColor).fontWeight(FontWeight.Medium)
            Text(I18n.t('nebula_texture_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(3)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.store.nebulaTextureStatus?.enabled === true })
            .width(42).height(24).selectedColor(this.accentColor)
            .enabled(this.store.nebulaTextureStatus !== undefined && !this.store.nebulaTexturePending && !this.store.nebulaTextureLoading && !this.store.nebulaTextureImporting)
            .onChange((enabled: boolean) => { this.onSetVisible(enabled) })
        }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
          .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        Row({ space: 8 }) {
          Button(I18n.t('act_refresh')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1).enabled(!this.store.nebulaTextureLoading)
            .onClick(() => { this.onRefresh() })
          Button(I18n.t('nebula_texture_import')).fontSize(10).fontColor(this.textColor).backgroundColor(this.accentColor)
            .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1).enabled(!this.store.nebulaTextureImporting)
            .onClick(() => { this.onImport() })
          if (this.store.nebulaTextureLoading || this.store.nebulaTextureImporting) LoadingProgress().width(18).height(18).color(this.accentColor)
        }.width('100%')
        if (this.store.nebulaTextureActionStatus.length > 0) {
          Text(this.store.nebulaTextureActionStatus).fontSize(10).fontColor('#FFD59A').width('100%').maxLines(2)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor('rgba(194,128,36,0.14)').borderRadius(UI_RADIUS_CONTROL)
        }
        if (this.store.nebulaTextureStatus !== undefined) {
          Text(I18n.t('nebula_texture_library_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
          Row() {
            Text(I18n.t('nebula_texture_conflict')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.nebulaTextureStatus?.avoidAreaConflict === true })
              .width(42).height(24).selectedColor(this.accentColor)
              .enabled(!this.store.nebulaTexturePending && !this.store.nebulaTextureLoading && !this.store.nebulaTextureImporting)
              .onChange((value: boolean) => { this.onSetConflictAvoidance(value) })
          }.width('100%').padding(8)
          Column({ space: 3 }) {
            Text(I18n.format('nebula_texture_summary', [String(this.store.nebulaTextureStatus?.readyCount ?? 0), String(this.store.nebulaTextureStatus?.count ?? 0)]))
              .fontSize(11).fontColor(this.textColor).width('100%')
            Text(this.store.nebulaTextureStatus?.configLoaded === true ? I18n.t('nebula_texture_config_ok') : I18n.t('nebula_texture_config_invalid'))
              .fontSize(10).fontColor(this.subColor).width('100%')
            Text(I18n.t('nebula_texture_offline_solver')).fontSize(10).fontColor('#FFD59A').width('100%').maxLines(2)
          }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor('rgba(111,168,207,0.08)').borderRadius(UI_RADIUS_CONTROL)
        }
        if ((this.store.nebulaTextureStatus?.items ?? []).length > 0) {
          ForEach(this.store.nebulaTextureStatus?.items ?? [], (item: NebulaTextureItem) => {
            Column({ space: 4 }) {
              Row() {
                Text(item.imageUrl).fontSize(11).fontColor(this.textColor).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.nebulaTextureStatusLabel(item.status)).fontSize(10).fontColor(item.ready === true ? '#B9E6C4' : '#FFD59A')
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 }).backgroundColor('rgba(255,255,255,0.06)').borderRadius(UI_RADIUS_PILL)
              }.width('100%')
              if (item.width !== undefined && item.height !== undefined) {
                Text(item.width.toString() + ' × ' + item.height.toString() + ' · RA ' + (item.centerRaDeg ?? 0).toFixed(2) + '° · Dec ' + (item.centerDecDeg ?? 0).toFixed(2) + '°')
                  .fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              if (item.decodeError !== undefined) Text(item.decodeError).fontSize(10).fontColor('#FFD59A').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 6 }) {
                Button(I18n.t('btn_center')).fontSize(10).fontColor(this.textColor).backgroundColor(this.accentColor).borderRadius(UI_RADIUS_CONTROL).height(26).layoutWeight(1)
                  .enabled(item.ready === true).onClick(() => { this.onGoto(item.imageUrl) })
                Button(I18n.t('nebula_texture_remove')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).height(26).layoutWeight(1)
                  .onClick(() => { this.onRemove(item.imageUrl) })
              }.width('100%')
            }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          }, (item: NebulaTextureItem) => item.imageUrl)
        } else if (!this.store.nebulaTextureLoading) {
          Text(I18n.t('nebula_texture_empty')).fontSize(11).fontColor(this.subColor).width('100%').textAlign(TextAlign.Center).padding(18)
        }
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
