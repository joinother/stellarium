import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { SkyCultureMakerIssue } from '../../pages/MainWindowModels'
import { SkyCultureMakerStore } from '../../state/SkyCultureMakerStore'

// 星文化制作器「校验收尾」页。
//
// 校验 / 导入 / 导出 / 分享 / 另存为都要碰桥或系统面板，经回调交回宿主；
// 逐条问题的本地化文案由 store.issueText 提供。Column space 9，统计行高 34，按钮高 34/32。
@Component
export struct SkyCultureMakerValidationPanel {
  @ObjectLink store: SkyCultureMakerStore
  @Prop subColor: string
  @Prop textColor: string
  @Prop accentColor: string
  @Prop bgColor: string
  onValidate: () => void = () => {}
  onImport: () => void = () => {}
  onExport: () => void = () => {}
  onShare: () => void = () => {}
  onSaveAs: () => void = () => {}

  build() {
    Column({ space: 9 }) {
      Text(I18n.t('sky_culture_maker_validate_hint')).fontSize(10).lineHeight(15).fontColor(this.subColor).width('100%')
      Button(I18n.t('sky_culture_maker_validate')).fontSize(11).fontColor(this.textColor).backgroundColor(this.accentColor)
        .height(34).width('100%').borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onValidate() })
      if (this.store.validation !== undefined) {
        Row({ space: 8 }) {
          Text(I18n.format('sky_culture_maker_error_count', [this.store.validation.errorCount.toString()]))
            .fontSize(11).fontColor(this.store.validation.errorCount > 0 ? '#FFB7B7' : '#B9E6C4').layoutWeight(1)
          Text(I18n.format('sky_culture_maker_warning_count', [this.store.validation.warningCount.toString()]))
            .fontSize(11).fontColor('#FFD49A')
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.bgColor).borderRadius(UI_RADIUS_CONTROL)
        ForEach(this.store.validation.errors.concat(this.store.validation.warnings), (issue: SkyCultureMakerIssue, index: number) => {
          Column({ space: 3 }) {
            Text(issue.field).fontSize(10).fontWeight(FontWeight.Medium).fontColor(issue.severity === 'error' ? '#FFB7B7' : '#FFD49A').width('100%')
            Text(this.store.issueText(issue.code, issue.message)).fontSize(10).lineHeight(14).fontColor(this.subColor).width('100%')
          }.width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor(this.bgColor).borderRadius(UI_RADIUS_CONTROL)
        }, (issue: SkyCultureMakerIssue, index: number) => issue.field + '/' + issue.code + '/' + index.toString())
      }
      Row({ space: 8 }) {
        Button(I18n.t('sky_culture_maker_import')).fontSize(10).fontColor(this.textColor).backgroundColor(this.bgColor)
          .height(34).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onImport() })
        Button(I18n.t('sky_culture_maker_export')).fontSize(10).fontColor(this.textColor).backgroundColor(this.accentColor)
          .height(34).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onExport() })
      }.width('100%')
      if (this.store.exportPath.length > 0) {
        Row({ space: 8 }) {
          Button(I18n.t('sky_culture_maker_share')).fontSize(10).fontColor(this.textColor).backgroundColor(this.bgColor)
            .height(32).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onShare() })
          Button(I18n.t('sky_culture_maker_save_as')).fontSize(10).fontColor(this.textColor).backgroundColor(this.bgColor)
            .height(32).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSaveAs() })
        }.width('100%')
      }
    }.width('100%')
  }
}
