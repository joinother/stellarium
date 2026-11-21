import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { NebulaTextureItem } from '../../pages/MainWindowModels'
import { NebulaTextureStore } from '../../state/NebulaTextureStore'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'

// 星云贴图面板，对应 `activePanel === 'nebulaTextures'`。
// 贴图状态与加载/导入态来自 NebulaTextureStore（@ObjectLink）；长说明收纳于 InfoTipButton ⓘ。

@Component
export struct NebulaTexturesPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink store: NebulaTextureStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSetVisible: (enabled: boolean) => void = () => {}
  onRefresh: () => void = () => {}
  onImport: () => void = () => {}
  onSetConflictAvoidance: (value: boolean) => void = () => {}
  onGoto: (imageUrl: string) => void = () => {}
  onRemove: (imageUrl: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private fs(base: number): number { return uiFontSize(base, this.readableUi, this.uiFontScale) }
  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

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
      Column({ space: 10 }) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Row({ space: 6 }) {
              Text(I18n.t('nebula_texture_title'))
                .fontSize(this.fs(15)).fontColor(this.c.textStrong).fontWeight(FontWeight.Medium)
              InfoTipButton({
                title: I18n.t('nebula_texture_title'),
                tip: I18n.t('nebula_texture_hint') + '\n' + I18n.t('nebula_texture_library_hint') + '\n' + I18n.t('nebula_texture_offline_solver')
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)
            Toggle({ type: ToggleType.Switch, isOn: this.store.nebulaTextureStatus?.enabled === true })
              .selectedColor(this.c.accent)
              .enabled(this.store.nebulaTextureStatus !== undefined && !this.store.nebulaTexturePending && !this.store.nebulaTextureLoading && !this.store.nebulaTextureImporting)
              .onChange((enabled: boolean) => { this.onSetVisible(enabled) })
          }.width('100%').constraintSize({ minHeight: this.ch(40) }).alignItems(VerticalAlign.Center)

          if (this.store.nebulaTextureStatus !== undefined) {
            Row().width('100%').height(0.5).backgroundColor(this.c.border)
            Row() {
              Text(I18n.t('nebula_texture_conflict')).fontSize(this.fs(12.5)).fontColor(this.c.text).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.store.nebulaTextureStatus?.avoidAreaConflict === true })
                .selectedColor(this.c.accent)
                .enabled(!this.store.nebulaTexturePending && !this.store.nebulaTextureLoading && !this.store.nebulaTextureImporting)
                .onChange((value: boolean) => { this.onSetConflictAvoidance(value) })
            }.width('100%').constraintSize({ minHeight: this.ch(38) }).alignItems(VerticalAlign.Center)
          }

          Row({ space: 8 }) {
            Button(I18n.t('act_refresh')).fontSize(this.fs(12)).fontColor(this.c.text).backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(36) }).layoutWeight(1)
              .enabled(!this.store.nebulaTextureLoading)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onRefresh() })
            Button(I18n.t('nebula_texture_import')).fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(36) }).layoutWeight(1)
              .enabled(!this.store.nebulaTextureImporting)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onImport() })
            if (this.store.nebulaTextureLoading || this.store.nebulaTextureImporting) {
              LoadingProgress().width(18).height(18).color(this.c.accent)
            }
          }.width('100%').alignItems(VerticalAlign.Center)
        }
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        if (this.store.nebulaTextureActionStatus.length > 0) {
          Text(this.store.nebulaTextureActionStatus).fontSize(this.fs(11)).fontColor(this.c.warning).width('100%').maxLines(2)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 }).backgroundColor(this.c.warningBg).borderRadius(UI_RADIUS_CONTROL)
        }
        if (this.store.nebulaTextureStatus !== undefined) {
          Row({ space: 8 }) {
            Text(I18n.format('nebula_texture_summary', [String(this.store.nebulaTextureStatus?.readyCount ?? 0), String(this.store.nebulaTextureStatus?.count ?? 0)]))
              .fontSize(this.fs(11.5)).fontColor(this.c.text).layoutWeight(1)
            Text(this.store.nebulaTextureStatus?.configLoaded === true ? I18n.t('nebula_texture_config_ok') : I18n.t('nebula_texture_config_invalid'))
              .fontSize(this.fs(10.5)).fontColor(this.c.accent)
          }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 }).backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_CONTROL)
        }
        if ((this.store.nebulaTextureStatus?.items ?? []).length > 0) {
          ForEach(this.store.nebulaTextureStatus?.items ?? [], (item: NebulaTextureItem) => {
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Text(item.imageUrl).fontSize(this.fs(12.5)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
                  .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.nebulaTextureStatusLabel(item.status)).fontSize(this.fs(10.5))
                  .fontColor(item.ready === true ? this.c.success : this.c.warning)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_PILL)
              }.width('100%').alignItems(VerticalAlign.Center)
              if (item.width !== undefined && item.height !== undefined) {
                Text(item.width.toString() + ' × ' + item.height.toString() + ' · RA ' + (item.centerRaDeg ?? 0).toFixed(2) + '° · Dec ' + (item.centerDecDeg ?? 0).toFixed(2) + '°')
                  .fontSize(this.fs(11)).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              if (item.decodeError !== undefined) {
                Text(item.decodeError).fontSize(this.fs(10.5)).fontColor(this.c.warning).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              Row({ space: 8 }) {
                Button(I18n.t('btn_center')).fontSize(this.fs(11.5)).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                  .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(34) }).layoutWeight(1)
                  .enabled(item.ready === true)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.onGoto(item.imageUrl) })
                Button(I18n.t('nebula_texture_remove')).fontSize(this.fs(11.5)).fontColor(this.c.text).backgroundColor(this.c.soft)
                  .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(34) }).layoutWeight(1)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.onRemove(item.imageUrl) })
              }.width('100%')
            }
              .width('100%')
              .padding(12)
              .backgroundColor(this.c.bg)
              .border({ width: 0.5, color: this.c.border })
              .borderRadius(UI_RADIUS_CARD)
          }, (item: NebulaTextureItem) => item.imageUrl)
        } else if (!this.store.nebulaTextureLoading) {
          Text(I18n.t('nebula_texture_empty'))
            .fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').textAlign(TextAlign.Center).padding(18)
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CARD)
        }
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
