import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { LocationOnlineMap } from '../../pages/LocationOnlineMap'

// 位置面板内的在线地图区块：离线 / 华为地图提供方切换；选 huawei 且已同意隐私时渲染
// 在线地图组件，选点后回调宿主写回坐标。LocationOnlineMap 内部自带隐私门控与超时降级。
@Component
export struct LocationMapSection {
  @Prop provider: string
  @Prop latitude: number
  @Prop longitude: number
  @Prop mapAllowed: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onSelectProvider: (provider: string) => void = () => {}
  onPick: (latitude: number, longitude: number) => void = () => {}
  onFallback: () => void = () => {}

  build() {
    Column({ space: 6 }) {
      Text(I18n.t('i0015')).fontSize(12).fontColor(this.subColor).width('100%')
      Row({ space: 6 }) {
        Text('离线坐标').fontSize(11)
          .fontColor(this.provider === 'offline' ? '#F4FAFF' : '#C8D4E2')
          .textAlign(TextAlign.Center).layoutWeight(1).height(30).padding({ top: 6, bottom: 6 })
          .backgroundColor(this.provider === 'offline' ? this.accentColor : this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onSelectProvider('offline') })
        Text('华为地图').fontSize(11)
          .fontColor(this.provider === 'huawei' ? '#F4FAFF' : '#C8D4E2')
          .textAlign(TextAlign.Center).layoutWeight(1).height(30).padding({ top: 6, bottom: 6 })
          .backgroundColor(this.provider === 'huawei' ? this.accentColor : this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onSelectProvider('huawei') })
      }.width('100%')
      if (this.provider === 'huawei' && this.mapAllowed) {
        LocationOnlineMap({
          latitude: this.latitude,
          longitude: this.longitude,
          onPick: (latitude: number, longitude: number) => { this.onPick(latitude, longitude) },
          onFallback: () => { this.onFallback() }
        })
      } else if (this.provider === 'huawei') {
        Text('在线地图需要隐私同意并在前台使用。').fontSize(10).fontColor(this.subColor).width('100%')
      }
    }.width('100%').padding({ left: 4, right: 4 })
  }
}
