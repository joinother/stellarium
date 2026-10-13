import { image } from '@kit.ImageKit'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { SkyCultureMakerStore } from '../../state/SkyCultureMakerStore'

// 星文化制作器「星座配图（角点绑定）」编辑器。
//
// 角点坐标 / 预览高度等纯几何计算由 store 提供；触屏绑定与导入 / 移除涉及桥与解码，经回调交回宿主。
// 触屏回调命名为 onArtworkTouch，避开 CustomComponent 基类的 `onTouch`。
// Stack 高由 artworkPreviewHeight 决定，角点 24px 圆，锚点按钮高 30。
@Component
export struct SkyCultureMakerArtworkEditor {
  @ObjectLink store: SkyCultureMakerStore
  @Prop panelWidth: number
  @Prop subColor: string
  @Prop textColor: string
  @Prop accentColor: string
  @Prop bgColor: string
  @Prop inputBorderColor: string
  onImport: () => void = () => {}
  onRemove: () => void = () => {}
  onArtworkTouch: (event: TouchEvent) => void = () => {}

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(I18n.t('sky_culture_maker_artwork')).fontSize(11).fontColor(this.textColor).width('100%')
          Text(I18n.t('sky_culture_maker_artwork_hint')).fontSize(10).lineHeight(14).fontColor(this.subColor).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.store.artworkImporting ? I18n.t('sky_culture_maker_artwork_importing') : I18n.t('sky_culture_maker_artwork_choose'))
          .fontSize(10).fontColor(this.textColor).backgroundColor(this.bgColor).height(30).borderRadius(UI_RADIUS_CONTROL)
          .enabled(!this.store.artworkImporting).onClick(() => { this.onImport() })
      }.width('100%')
      if (this.store.selected()?.image !== undefined) {
        Stack() {
          if (this.store.artworkPixelMap !== undefined) {
            Image(this.store.artworkPixelMap as image.PixelMap)
              .width('100%').height('100%').objectFit(ImageFit.Fill)
          } else if (this.store.artworkPreviewState === 'preparing') {
            Column({ space: 7 }) {
              LoadingProgress().width(20).height(20).color(this.accentColor)
              Text(I18n.t('sky_culture_maker_artwork_preparing')).fontSize(10).fontColor(this.subColor)
            }
          } else {
            Text(I18n.t(this.store.artworkPreviewState === 'decodeFailed'
              ? 'sky_culture_maker_artwork_decode_failed' : 'sky_culture_maker_artwork_missing'))
              .fontSize(10).fontColor('#FFB7B7').textAlign(TextAlign.Center).padding({ left: 16, right: 16 })
          }
          ForEach([0, 1, 2], (anchorIndex: number) => {
            if ((this.store.artworkAnchor(anchorIndex)?.hip ?? 0) > 0) {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(24).height(24)
                  .fill(anchorIndex === this.store.artworkAnchorIndex ? '#E6A85B' : '#5B93BF')
                  .stroke('#FFFFFFFF').strokeWidth(1)
                Text((anchorIndex + 1).toString()).fontSize(10).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
              }.width(24).height(24).position({
                x: this.store.artworkAnchorX(anchorIndex),
                y: this.store.artworkAnchorY(anchorIndex)
              })
            }
          }, (anchorIndex: number) => anchorIndex.toString())
        }
          .width('100%').height(this.store.artworkPreviewHeight(this.panelWidth)).clip(true)
          .backgroundColor('#16000000').border({ width: 1, color: this.inputBorderColor }).borderRadius(UI_RADIUS_CONTROL)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.store.artworkRenderWidth = Math.max(1, Number(newArea.width))
            this.store.artworkRenderHeight = Math.max(1, Number(newArea.height))
          })
          .onTouch((event: TouchEvent) => this.onArtworkTouch(event))
        Row({ space: 6 }) {
          ForEach([0, 1, 2], (anchorIndex: number) => {
            Button(I18n.format('sky_culture_maker_anchor', [(anchorIndex + 1).toString(), this.store.artworkAnchorHipText(anchorIndex)]))
              .fontSize(10).fontColor(anchorIndex === this.store.artworkAnchorIndex ? '#FFFFFFFF' : this.subColor)
              .backgroundColor(anchorIndex === this.store.artworkAnchorIndex ? this.accentColor : this.bgColor)
              .height(30).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.store.artworkAnchorIndex = anchorIndex })
          }, (anchorIndex: number) => anchorIndex.toString())
        }.width('100%')
        Text(I18n.t('sky_culture_maker_anchor_instruction')).fontSize(10).lineHeight(14).fontColor(this.subColor).width('100%')
        Button(I18n.t('sky_culture_maker_artwork_remove')).fontSize(10).fontColor('#FFB7B7')
          .backgroundColor('rgba(255,107,107,0.12)').height(30).width('100%').borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onRemove() })
      }
    }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 }).backgroundColor(this.bgColor).borderRadius(UI_RADIUS_CONTROL)
  }
}
