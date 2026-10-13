import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { SkyCultureMakerStore } from '../../state/SkyCultureMakerStore'
import { SkyCultureMakerConstellation } from '../../pages/MainWindowModels'
import { SkyCultureMakerTabs } from './SkyCultureMakerTabs'
import { SkyCultureMakerOverview } from './SkyCultureMakerOverview'
import { SkyCultureMakerConstellationEditor } from './SkyCultureMakerConstellationEditor'
import { SkyCultureMakerValidationPanel } from './SkyCultureMakerValidationPanel'

// 星文化制作器面板主体。
//
// 三步向导的装配：标签页 / 概览 / 星座编辑 / 校验导出 + 底部保存·撤销·重置。
// 可观测状态与纯计算由 `SkyCultureMakerStore` 提供；主题色与 panelWidth 以 @Prop 传入，
// 桥 / 定时器 / 图片解码等宿主职责以回调解入。
@Component
export struct SkyCultureMakerPanel {
  @ObjectLink store: SkyCultureMakerStore
  @Prop panelWidth: number
  @Prop subColor: string
  @Prop textColor: string
  @Prop accentColor: string
  @Prop bgColor: string
  @Prop inputColor: string
  @Prop inputBorderColor: string
  onEdited: () => void = () => {}
  onAdd: () => void = () => {}
  onSelect: (index: number) => void = () => {}
  onUpdate: (updated: SkyCultureMakerConstellation) => void = () => {}
  onRemoveSelected: () => void = () => {}
  onRemoveLine: (lineIndex: number) => void = () => {}
  onAddHipLine: () => void = () => {}
  onAddSelectedStar: () => void = () => {}
  onImportArtwork: () => void = () => {}
  onRemoveArtwork: () => void = () => {}
  onArtworkTouch: (event: TouchEvent) => void = () => {}
  onValidate: () => void = () => {}
  onImport: () => void = () => {}
  onExport: () => void = () => {}
  onShare: () => void = () => {}
  onSaveAs: () => void = () => {}
  onSaveDraft: () => void = () => {}
  onUndo: () => void = () => {}
  onReset: () => void = () => {}

  build() {
    Column({ space: 8 }) {
      SkyCultureMakerTabs({
        store: this.store,
        subColor: this.subColor, accentColor: this.accentColor, bgColor: this.bgColor
      })
      if (this.store.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color(this.accentColor)
          Text(I18n.t('msg_loading')).fontSize(11).fontColor(this.subColor)
        }.width('100%').height(80).justifyContent(FlexAlign.Center)
      } else {
        if (this.store.tab === 0) {
          SkyCultureMakerOverview({
            store: this.store,
            subColor: this.subColor, textColor: this.textColor, accentColor: this.accentColor, bgColor: this.bgColor,
            inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
            onEdited: () => { this.onEdited() }
          })
        } else if (this.store.tab === 1) {
          SkyCultureMakerConstellationEditor({
            store: this.store, panelWidth: this.panelWidth,
            subColor: this.subColor, textColor: this.textColor, accentColor: this.accentColor, bgColor: this.bgColor,
            inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
            onAdd: () => { this.onAdd() },
            onSelect: (index: number) => { this.onSelect(index) },
            onUpdate: (updated: SkyCultureMakerConstellation) => { this.onUpdate(updated) },
            onRemoveSelected: () => { this.onRemoveSelected() },
            onRemoveLine: (lineIndex: number) => { this.onRemoveLine(lineIndex) },
            onAddHipLine: () => { this.onAddHipLine() },
            onAddSelectedStar: () => { this.onAddSelectedStar() },
            onEdited: () => { this.onEdited() },
            onImportArtwork: () => { this.onImportArtwork() },
            onRemoveArtwork: () => { this.onRemoveArtwork() },
            onArtworkTouch: (event: TouchEvent) => { this.onArtworkTouch(event) }
          })
        } else {
          SkyCultureMakerValidationPanel({
            store: this.store,
            subColor: this.subColor, textColor: this.textColor, accentColor: this.accentColor, bgColor: this.bgColor,
            onValidate: () => { this.onValidate() },
            onImport: () => { this.onImport() },
            onExport: () => { this.onExport() },
            onShare: () => { this.onShare() },
            onSaveAs: () => { this.onSaveAs() }
          })
        }
      }
      if (this.store.status.length > 0) {
        Text(this.store.status).fontSize(10).lineHeight(15).fontColor(this.subColor).width('100%')
          .padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor(this.bgColor).borderRadius(UI_RADIUS_CONTROL)
      }
      Row({ space: 8 }) {
        Button(this.store.saving ? I18n.t('sky_culture_maker_saving') : I18n.t('sky_culture_maker_save'))
          .fontSize(10).fontColor(this.textColor).backgroundColor(this.accentColor).height(32).layoutWeight(1)
          .borderRadius(UI_RADIUS_CONTROL).enabled(!this.store.saving).onClick(() => { this.onSaveDraft() })
        Button(I18n.t('sky_culture_maker_undo')).fontSize(10).fontColor(this.textColor).backgroundColor(this.bgColor)
          .height(32).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).enabled(this.store.canUndo).opacity(this.store.canUndo ? 1 : 0.5)
          .onClick(() => { this.onUndo() })
        Button(I18n.t('sky_culture_maker_reset')).fontSize(10).fontColor('#FFB7B7').backgroundColor('rgba(255,107,107,0.12)')
          .height(32).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onReset() })
      }.width('100%').margin({ top: 6, bottom: 8 })
    }.width('100%').padding({ left: 4, right: 4 })
  }
}
