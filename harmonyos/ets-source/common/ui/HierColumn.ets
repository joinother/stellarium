import { curves } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from './UiTokens'

// 层级列：一列的标题、列表、选中态与点击回调，不含任何位置业务。
//
// 位置面板的「大洲 / 国家 / 地区 / 城市」四列与图层面板的层级列共用本组件：
// items / selected / title 由调用方从 `LocationPickerStore` 计算后传入，行标签经 `labelOf` 注入；
// `Scroller` 以普通成员传入（按协议，Scroller 之类对象不做装饰器传递），由调用方自持，各列独立滚动。
@Component
export struct HierColumn {
  @Prop title: string
  @Prop items: string[]
  @Prop selected: string
  scroller: Scroller = new Scroller()
  labelOf: (item: string) => string = (item: string) => item
  onSelect: (item: string) => void = () => {}

  build() {
    Column() {
      Row({ space: 4 }) {
        Text(this.title)
          .fontSize(11)
          .fontColor('#8EC5E8')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height(26)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('rgba(91, 147, 191, 0.12)')
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 5 })
      Scroll(this.scroller) {
        Column({ space: 4 }) {
          ForEach(this.items, (item: string) => {
            Button() {
              Stack() {
                Text(this.labelOf(item))
                  .fontSize(11)
                  .fontColor(this.selected === item ? '#FFFFFFFF' : '#A8C4E0')
                  .fontWeight(this.selected === item ? FontWeight.Medium : FontWeight.Regular)
                  .width('100%')
                  .height(36)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Clip })
                  .textAlign(TextAlign.Center)
                  .lineHeight(15)
              }
                .width('100%')
                .height(42)
                .alignContent(Alignment.Center)
            }
              .padding({ left: 4, right: 4, top: 3, bottom: 3 })
              .width('100%')
              .height(48)
              .backgroundColor(this.selected === item ? '#2A6694' : 'rgba(255,255,255,0.03)')
              .border({ width: this.selected === item ? 1.5 : 1, color: this.selected === item ? '#9BD8FF' : 'rgba(107,163,214,0.10)' })
              .borderRadius(UI_RADIUS_CONTROL)
              .shadow(this.selected === item ? { radius: 8, color: 'rgba(99, 185, 255, 0.35)', offsetX: 0, offsetY: 1 } : { radius: 0, color: 'transparent', offsetX: 0, offsetY: 0 })
              .stateEffect(true)
              .animation({ duration: 160, curve: curves.springMotion(0.42, 0.86) })
              .onClick(() => { this.onSelect(item) })
          }, (item: string) => item)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .backgroundColor('rgba(8, 14, 28, 0.4)')
      .borderRadius(UI_RADIUS_CONTROL)
      .scrollBarWidth(3)
    }
    .layoutWeight(1)
    .padding(6)
    .backgroundColor('rgba(10, 18, 36, 0.55)')
    .border({ width: 1, color: 'rgba(91, 147, 191, 0.20)' })
    .borderRadius(UI_RADIUS_CONTROL)
    .margin({ right: 5 })
  }
}
