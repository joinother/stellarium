import { I18n } from '../../pages/I18n'
import { OFFLINE_APPGALLERY_BUILD, StarCatalogItem } from '../../pages/MainWindowModels'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { CatalogStore } from '../../state/CatalogStore'

// 星表面板，对应 `activePanel === 'catalogs'`。
//
// 始终显示 9 级星表（stars0–stars8），每行给出星等范围 / 星数 / 大小与加载状态：
//   - 已加载（checked）        → 绿色 [已加载] 标签
//   - 未加载 + 离线构建        → [手动导入] 标签 + 下载渠道标注（本轮只读，不实装导入）
//   - 未加载 + 在线构建        → [下载] 按钮（走 CatalogStore.startCatalogDownload）
// 列表/加载/下载态来自 CatalogStore（@ObjectLink）；未加载项由 store 桥回包或静态快照给出。
// 卡片描边用 cardBorderColor：成员名须避开 CustomComponent 基类的 borderColor 属性方法。

@Component
export struct CatalogsPanel {
  @ObjectLink catalogStore: CatalogStore
  @Prop cardBorderColor: string
  onDownload: (id: string) => void = () => {}
  onOpenCatalogSource: (url: string) => void = () => {}
  onImportCatalog: () => void = () => {}

  // 极限星等摘要：连续已加载级里最高一级的星等上界 + 级号。
  private loadedSummary(): string {
    let level = -1
    let mag = ''
    for (const item of this.catalogStore.catalogList) {
      if (!item.checked) break
      level += 1
      if (item.magRange.length > 0) mag = item.magRange
    }
    if (level < 0) return I18n.t('catalog_none_loaded')
    const parts = mag.split('~')
    const upper = parts.length > 1 ? parts[1].trim() : mag
    return I18n.format('catalog_loaded_to', [upper, level.toString()])
  }

  build() {
    Scroll() {
      Column({ space: 8 }) {
        Text(I18n.t('catalog_title')).fontSize(13).fontColor('#CCFFFFFF').width('100%')
        Text(this.loadedSummary()).fontSize(11).fontColor('#99FFFFFF').width('100%')
        ForEach(this.catalogStore.catalogList, (c: StarCatalogItem) => {
          Column({ space: 3 }) {
            Row() {
              Text(c.name.length > 0 ? c.name : I18n.t('catalog_fallback'))
                .fontSize(14).fontColor('#E5FFFFFF').fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              if (c.magRange.length > 0) {
                Text(I18n.format('catalog_mag', [c.magRange])).fontSize(11).fontColor('#99FFFFFF').margin({ left: 6 })
              }
              if (c.checked) {
                Text(I18n.t('catalog_loaded'))
                  .fontSize(11).fontColor('#7FB3DC')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor('rgba(91,147,191,0.15)').borderRadius(UI_RADIUS_CONTROL).margin({ left: 8 })
              } else if (!OFFLINE_APPGALLERY_BUILD) {
                Button(this.catalogStore.catalogBusy && this.catalogStore.catalogDownloadingId === c.id ? I18n.t('catalog_downloading') : I18n.t('catalog_download'))
                  .fontSize(12).fontColor('#E5FFFFFF')
                  .backgroundColor(this.catalogStore.catalogBusy ? 'rgba(255,255,255,0.10)' : 'rgba(107,163,214,0.35)')
                  .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 14, right: 14 }).margin({ left: 8 })
                  .enabled(!this.catalogStore.catalogBusy)
                  .onClick(() => { this.onDownload(c.id) })
              } else {
                Button(this.catalogStore.catalogImporting ? I18n.t('catalog_importing') : I18n.t('catalog_import'))
                  .fontSize(11).fontColor('#E5FFFFFF')
                  .backgroundColor(this.catalogStore.catalogImporting ? 'rgba(255,255,255,0.10)' : 'rgba(107,163,214,0.35)')
                  .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 14, right: 14 }).margin({ left: 8 })
                  .enabled(!this.catalogStore.catalogImporting)
                  .onClick(() => { this.onImportCatalog() })
              }
            }.width('100%')
            Row({ space: 10 }) {
              if (c.count.length > 0) {
                Text(I18n.format('catalog_count', [c.count])).fontSize(11).fontColor('#8FB6FF')
              }
              if (c.size.length > 0) {
                Text(c.size).fontSize(11).fontColor('#99FFFFFF')
              }
            }.width('100%')
            if (!c.checked && c.source.length > 0) {
              Row() {
                Text(I18n.format('catalog_source', [c.source])).fontSize(10).fontColor('#66CCCCCC').layoutWeight(1)
                if (c.sourcePage.length > 0) {
                  Text(c.fileName.length > 0 ? c.fileName : I18n.t('catalog_open_source'))
                    .fontSize(10).fontColor('#7FB3DC')
                    .decoration({ type: TextDecorationType.Underline, color: '#7FB3DC' })
                    .onClick(() => { this.onOpenCatalogSource(c.sourcePage) })
                }
              }.width('100%')
            }
            if (this.catalogStore.catalogBusy && this.catalogStore.catalogDownloadingId === c.id && this.catalogStore.catalogMsg.length > 0) {
              Text(this.catalogStore.catalogMsg).fontSize(11).fontColor('#99FFFFFF').width('100%')
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor('rgba(255,255,255,0.04)')
          .borderRadius(UI_RADIUS_CONTROL)
          .border({ width: 1, color: this.cardBorderColor })
        }, (c: StarCatalogItem) => c.id + '|' + (c.checked ? '1' : '0') + '|' + (this.catalogStore.catalogImporting ? '1' : '0') + '|' + (this.catalogStore.catalogDownloadingId))
      }.width('100%').padding({ left: 2, right: 2 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
