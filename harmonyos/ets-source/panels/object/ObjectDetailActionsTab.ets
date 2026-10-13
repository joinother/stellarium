import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 天体详情主卡片的"操作"页。
//
// 读取视角锁定、朗读状态、是否已加入观测清单三个派生值，动作以回调触发；
// 交互与状态由宿主掌握，本组件不持有 store。
// `Column({ space: 8 })` 的间距与详情 Scroll 内层容器保持一致。

@Component
export struct ObjectDetailActionsTab {
  @Prop viewLock: boolean
  @Prop speechStatus: string
  @Prop inObservingList: boolean
  onCenter: () => void = () => {}
  onToggleLock: () => void = () => {}
  onToggleObserving: () => void = () => {}
  onRefresh: () => void = () => {}
  onReselect: () => void = () => {}
  onSpeak: () => void = () => {}

  build() {
    Column({ space: 8 }) {
      Text('目标操作').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#D9F2FF').width('100%')
      Row({ space: 8 }) {
        Button(I18n.t('btn_center'))
          .fontSize(12).fontColor('#E8F8FF').backgroundColor('rgba(91,147,191,0.34)').borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .onClick(() => { this.onCenter() })
        Button(this.viewLock ? I18n.t('btn_unlock_view') : I18n.t('btn_lock_view'))
          .fontSize(12).fontColor('#E8F8FF')
          .backgroundColor(this.viewLock ? 'rgba(91,147,191,0.50)' : 'rgba(255,255,255,0.08)')
          .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .onClick(() => { this.onToggleLock() })
      }.width('100%')
      Button(this.inObservingList ? I18n.t('s0739') : I18n.t('s0738'))
        .fontSize(12).fontColor('#E8F8FF').backgroundColor('rgba(91,147,191,0.28)').borderRadius(UI_RADIUS_CONTROL).height(34).width('100%')
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        .onClick(() => { this.onToggleObserving() })
      Row({ space: 8 }) {
        Button(I18n.t('s0721'))
          .fontSize(12).fontColor('#DDF4FF').backgroundColor('rgba(255,255,255,0.07)').borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .onClick(() => { this.onRefresh() })
        Button(I18n.t('i0134'))
          .fontSize(12).fontColor('#DDF4FF').backgroundColor('rgba(255,255,255,0.07)').borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .onClick(() => { this.onReselect() })
      }.width('100%')
      Button(I18n.t('s0760'))
        .fontSize(12).fontColor('#DDF4FF').backgroundColor('rgba(255,255,255,0.07)').borderRadius(UI_RADIUS_CONTROL).height(34).width('100%')
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        .onClick(() => { this.onSpeak() })
      if (this.speechStatus.length > 0) {
        Text(this.speechStatus).fontSize(11).fontColor('#B9DBEB').lineHeight(16).width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor('rgba(91,147,191,0.08)').borderRadius(UI_RADIUS_CONTROL)
      }
    }
      .width('100%')
  }
}
