import { I18n } from '../../pages/I18n'
import { SavedLocation } from '../../pages/StellariumTypes'
import { LocationStore } from '../../state/LocationStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 本组件职责：位置面板的「已保存位置」行 + 中国城市 / 世界城市快捷 chip 行。
//
// 已保存位置列表走 @ObjectLink store 实时刷新；四个宿主方法以回调注入
// （handleChip 是全局快捷键分发，setLocation 走原生桥，均由宿主提供）。
@Component
export struct CityChipsRow {
  @ObjectLink store: LocationStore
  onSaveCurrent: () => void = () => {}
  onApplyLocation: (name: string, lat: number, lon: number, alt: number, planet: string) => void = () => {}
  onDeleteLocation: (name: string) => void = () => {}
  onChip: (id: string) => void = () => {}

  build() {
    Column({ space: 4 }) {
      // 已保存位置
      Row() {
        Text(I18n.t('loc_saved_locations')).fontSize(11).fontColor('#99FFFFFF').layoutWeight(1)
        Button(I18n.t('loc_save_current'))
          .fontSize(10).fontColor('#7FB3DC')
          .height(26).padding({ left: 8, right: 8 })
          .backgroundColor('rgba(107, 163, 214, 0.15)')
          .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
          .borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onSaveCurrent() })
      }
      .width('100%')
      .margin({ top: 6 })

      if (this.store.savedLocations.length === 0) {
        Text(I18n.t('loc_no_saved')).fontSize(10).fontColor('#8EA0BD').width('100%').padding({ left: 2 })
      } else {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.store.savedLocations, (s: SavedLocation) => {
              Row() {
                Button(s.name)
                  .fontSize(10).fontColor('#7FB3DC')
                  .height(28).padding({ left: 8, right: 8 })
                  .backgroundColor('rgba(107, 163, 214, 0.20)')
                  .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
                  .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onApplyLocation(s.name, s.lat, s.lon, s.alt, s.planet) })
                Text('x')
                  .fontSize(10).fontColor('#FF9999')
                  .margin({ left: 2 })
                  .onClick(() => { this.onDeleteLocation(s.name) })
              }
            }, (s: SavedLocation) => s.name)
          }
          .padding({ left: 2, right: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      // 中国城市
      Text('中国城市').fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 2 }).margin({ top: 6 })
      Scroll() {
        Row({ space: 8 }) {
          ForEach([
            { label: '北京', id: 'city_Beijing' }, { label: '上海', id: 'city_Shanghai' },
            { label: '广州', id: 'city_Guangzhou' }, { label: '深圳', id: 'city_Shenzhen' },
            { label: '成都', id: 'city_Chengdu' }, { label: '杭州', id: 'city_Hangzhou' },
            { label: '武汉', id: 'city_Wuhan' }, { label: '西安', id: 'city_Xian' },
            { label: '南京', id: 'city_Nanjing' }, { label: '重庆', id: 'city_Chongqing' },
            { label: '哈尔滨', id: 'city_Harbin' }, { label: '拉萨', id: 'city_Lhasa' },
            { label: '乌鲁木齐', id: 'city_Urumqi' }, { label: '香港', id: 'city_HongKong' },
          ], (c: Record<string, string>) => {
            Button(c.label)
              .fontSize(11).fontColor('#7FB3DC').fontWeight(FontWeight.Medium)
              .height(30).padding({ left: 10, right: 10 })
              .backgroundColor('rgba(107, 163, 214, 0.20)')
              .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
              .borderRadius(UI_RADIUS_PILL)
              .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.18)', offsetX: 0, offsetY: 4 })
              .onClick(() => { this.onChip(c.id) })
          }, (c: Record<string, string>) => c.id)
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      // 世界城市
      Text('世界城市').fontSize(11).fontColor('#99FFFFFF').width('100%').padding({ left: 2 }).margin({ top: 4 })
      Scroll() {
        Row({ space: 8 }) {
          ForEach([
            { label: '东京', id: 'city_Tokyo' }, { label: '首尔', id: 'city_Seoul' },
            { label: '新加坡', id: 'city_Singapore' }, { label: '纽约', id: 'city_NewYork' },
            { label: '伦敦', id: 'city_London' }, { label: '悉尼', id: 'city_Sydney' },
            { label: '巴黎', id: 'city_Paris' }, { label: '柏林', id: 'city_Berlin' },
            { label: '莫斯科', id: 'city_Moscow' }, { label: '迪拜', id: 'city_Dubai' },
            { label: '孟买', id: 'city_Mumbai' }, { label: '开罗', id: 'city_Cairo' },
            { label: '里约', id: 'city_Rio' }, { label: '洛杉矶', id: 'city_LosAngeles' },
            { label: '多伦多', id: 'city_Toronto' }, { label: '墨西哥城', id: 'city_Mexico' },
            { label: '曼谷', id: 'city_Bangkok' }, { label: '伊斯坦布尔', id: 'city_Istanbul' },
            { label: '阿姆斯特丹', id: 'city_Amsterdam' }, { label: '斯德哥尔摩', id: 'city_Stockholm' },
            { label: '雷克雅未克', id: 'city_Reykjavik' }, { label: '开普敦', id: 'city_CapeTown' },
            { label: '布宜诺斯艾利斯', id: 'city_BuenosAires' }, { label: '檀香山', id: 'city_Honolulu' },
          ], (c: Record<string, string>) => {
            Button(c.label)
              .fontSize(11).fontColor('#7FB3DC').fontWeight(FontWeight.Medium)
              .height(30).padding({ left: 10, right: 10 })
              .backgroundColor('rgba(107, 163, 214, 0.20)')
              .border({ width: 1, color: 'rgba(107, 163, 214, 0.25)' })
              .borderRadius(UI_RADIUS_PILL)
              .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.18)', offsetX: 0, offsetY: 4 })
              .onClick(() => { this.onChip(c.id) })
          }, (c: Record<string, string>) => c.id)
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .margin({ top: 12 })
  }
}
