import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 天体详情卡里的 LX200 快捷控制条。
//
// 三个命令（GoTo / 同步 / 中止）经原生桥，留在宿主，以回调注入。
//
// 视觉：标题 12 号 #8EA0BD / 按钮高 32 / GoTo #5B93BF、同步 rgba(107,163,214,0.20)、
// 中止 rgba(255,121,121,0.14) / 状态 11 号 #99FFFFFF 高 2 行 / 外框 rgba(107,163,214,0.12)。
@Component
export struct Lx200ObjectControls {
  @ObjectLink store: TelescopeStore
  onGoto: () => void = () => {}
  onSync: () => void = () => {}
  onAbort: () => void = () => {}

  build() {
    Column() {
      Row() {
        Text(I18n.t('i0041'))
          .fontSize(12)
          .fontColor('#8EA0BD')
          .layoutWeight(1)
      }
        .width('100%')
      Row() {
        Button(I18n.t('i0049'))
          .height(32)
          .fontSize(12)
          .fontColor('#FFFFFFFF')
          .backgroundColor('#5B93BF')
          .borderRadius(UI_RADIUS_PILL)
          .margin({ right: 8 })
          .onClick(() => {
            this.onGoto()
          })
        Button(I18n.t('i0050'))
          .height(32)
          .fontSize(12)
          .fontColor('#7FB3DC')
          .backgroundColor('rgba(107, 163, 214, 0.20)')
          .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
          .borderRadius(UI_RADIUS_PILL)
          .margin({ right: 8 })
          .onClick(() => {
            this.onSync()
          })
        Button(I18n.t('i0051'))
          .height(32)
          .fontSize(12)
          .fontColor('#FFD9D9')
          .backgroundColor('rgba(255, 121, 121, 0.14)')
          .border({ width: 1, color: 'rgba(255, 121, 121, 0.26)' })
          .borderRadius(UI_RADIUS_PILL)
          .onClick(() => {
            this.onAbort()
          })
      }
        .width('100%')
        .margin({ top: 8 })
      Text(this.store.lx200Status)
        .fontSize(11)
        .fontColor('#99FFFFFF')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
    }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .backgroundColor('rgba(107, 163, 214, 0.12)')
      .border({ width: 1, color: 'rgba(107, 163, 214, 0.20)' })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 8, bottom: 8 })
  }
}
