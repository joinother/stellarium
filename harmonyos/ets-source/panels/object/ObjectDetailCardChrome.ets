import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectCompactMetric, ObjectDetailTab } from './DetailTiles'
import { SelectedLiveInfoRows } from './DetailLiveRows'

// 观测模式「聚焦圈」的描边色（圆环 + 四个斜向短线共用）。
const OBSERVE_RING_COLOR: string = 'rgba(143,187,214,0.88)'

// 详情卡外壳的页头与页签栏。
//
// 页头 = 拖拽柄 + 标题行 + 紧凑指标（+ 天文馆模式下的实时高度方位行 / 实时信息块）；页签栏 = 四个 `ObjectDetailTab`。
// 动态查值与名称本地化由宿主以回调注入。
//
// 观测模式（`detailDisplayMode === 'observe'`）下页头有两处不同：天体类型图标套一个可点的聚焦圈（= 居中），
// 星等 tag 用「两值一行」格式；展开 / 收起不在这里，改到卡片下沿中央的箭头（`UnifiedObjectDetailCard`）。
//
// 页头三枚摘要（星等 / 星座 / 距离）必须**直接读 `@ObjectLink store`**：ArkUI 的局部刷新按元素
// 记录依赖，若取值只经普通成员回调（`resolve` / `distanceSummary`）而不触碰被观察对象，
// 切换天体时该元素不会被标脏，会一直显示上一颗天体的旧值。

@Component
export struct ObjectDetailCardHeader {
  @ObjectLink store: ObjectDetailStore
  @Prop iconName: string
  @Prop liveInfoVisible: boolean
  // 呈现轴（信息窗 store 读后下发）：'planetarium' | 'observe'。
  // 页头只关心「是否观测模式」：展开 / 收起不在此渲染（改到卡片下沿的箭头，见 UnifiedObjectDetailCard）。
  @Prop detailDisplayMode: string
  distanceSummary: (distance: string, compact: string) => string = () => ''
  nameOf: (name: string) => string = () => ''
  typeOf: (type: string) => string = () => ''
  onDragTouch: (event: TouchEvent) => void = () => {}
  onDismiss: () => void = () => {}
  onCenterObject: () => void = () => {}

  // 观测模式：星等 tag 用「两值一行」格式，且天体类型图标套一个可点的聚焦圈（点它 = 居中到该天体）。
  private observeMode(): boolean {
    return this.detailDisplayMode === 'observe'
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(40).height(4).backgroundColor('rgba(225,241,250,0.34)').borderRadius(2)
      }
        .width('100%').height(26)
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => { this.onDragTouch(event) })
      Row() {
        if (this.observeMode()) {
          // 「居中」不再占一行按钮：把天体类型图标做成**准星式聚焦圈** —— 一个圆环，四条斜向短线
          // **横穿**圆环（左上 / 右上 / 左下 / 右下），点它即把视角移到该天体。
          //
          // 短线用与拖拽柄同一套画法（`Row` + `backgroundColor` + `rotate`）。几何（36×36 框、圆心 (18,18)）：
          // 圆环 26×26 → 外径 r=13、描边 1.5 画在框内 → 环带 r 11.5–13；短线长 6、中心 r=14.5
          // → 两端 r 11.5 与 17.5，正好**穿过**环带。短线必须**沿半径**方向（即垂直于该处圆周），
          // 否则两端半径相同就成了与圆环平行的「虚线弧」：NE 用 −45°、NW 用 +45°（`rotate` 顺时针为正）。
          Stack() {
            Image(getIcon(this.iconName, false))
              .width(20).height(20).fillColor('#73C8FF')
            Row()
              .width(26).height(26).borderRadius(13)
              .border({ width: 1.5, color: OBSERVE_RING_COLOR })
            Row().width(6).height(1.5).borderRadius(0.75).backgroundColor(OBSERVE_RING_COLOR)
              .position({ x: 25.3, y: 7.0 }).rotate({ angle: -45 })
            Row().width(6).height(1.5).borderRadius(0.75).backgroundColor(OBSERVE_RING_COLOR)
              .position({ x: 4.7, y: 7.0 }).rotate({ angle: 45 })
            Row().width(6).height(1.5).borderRadius(0.75).backgroundColor(OBSERVE_RING_COLOR)
              .position({ x: 4.7, y: 27.5 }).rotate({ angle: -45 })
            Row().width(6).height(1.5).borderRadius(0.75).backgroundColor(OBSERVE_RING_COLOR)
              .position({ x: 25.3, y: 27.5 }).rotate({ angle: 45 })
          }
            .width(36).height(36)
            .margin({ right: 6 })
            .id('object-detail-observe-center')
            .accessibilityText(I18n.t('detail_observe_center'))
            .onClick(() => {
              this.onCenterObject()
            })
        } else {
          Image(getIcon(this.iconName, false))
            .width(26).height(26).fillColor('#73C8FF').margin({ right: 7 })
        }
        Text(this.nameOf(this.store.selectedName))
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFFFF')
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.typeOf(this.store.selectedType))
          .fontSize(11).fontColor('#BDE8FF')
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .backgroundColor('rgba(91,147,191,0.18)').borderRadius(UI_RADIUS_CONTROL)
        Text('✕')
          .fontSize(15).fontColor('#B8CAD7').padding({ left: 12, right: 4, top: 4, bottom: 4 })
          .onClick(() => {
            this.onDismiss()
          })
      }
      .width('100%').padding({ left: 16, right: 14, top: 10, bottom: 6 })

      Row({ space: 4 }) {
        if (this.observeMode()) {
          // 观测模式的三个读数：视星等 / 大气消光后星等 / 星座。
          // 不再显示距离（用户要求），消光后星等从「括号拼在一格里」升为独立一格。
          ObjectCompactMetric({ label: I18n.t('i0007'), value: this.store.selectedMagnitude })
          ObjectCompactMetric({ label: I18n.t('detail_observe_extinction_magnitude'), value: this.store.selectedApparentMagnitude })
          ObjectCompactMetric({ label: I18n.t('i0010'), value: this.nameOf(this.store.selectedConstellation) })
        } else {
          ObjectCompactMetric({ label: I18n.t('i0007'), value: this.store.selectedMagnitude })
          ObjectCompactMetric({ label: I18n.t('i0010'), value: this.nameOf(this.store.selectedConstellation) })
          ObjectCompactMetric({ label: I18n.t('i0011'), value: this.distanceSummary(this.store.selectedDistance, this.store.selectedDistanceCompact) })
        }
      }
        .width('100%').padding({ left: 16, right: 16, top: 3, bottom: 7 })

      if (!this.observeMode()) {
        Row() {
          // 标签不固定宽度（固定 72 会让 9 字标签自身被截断）；数值已含方位/高度，
          // 无需额外的"已定位/等待定位"标签——它只挤占宽度导致数值被省略号截断。
          Text('实时高度 / 方位').fontSize(10).fontColor('#8FBBD6')
          Text(this.store.selectedCoordAlt.length > 0 ? this.store.selectedCoordAlt : '--')
            .fontSize(11).fontColor('#E2F5FF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 6 })
        }
          .height(24).width('100%').padding({ left: 16, right: 16, bottom: 4 })

        SelectedLiveInfoRows({ store: this.store, compact: true, visible: this.liveInfoVisible })
      }
    }
  }
}

@Component
export struct ObjectDetailCardTabs {
  @Prop activeIndex: number
  onSelect: (index: number) => void = () => {}

  build() {
      Row({ space: 4 }) {
        ObjectDetailTab({ label: '观测', active: this.activeIndex === 0, onSelect: () => { this.onSelect(0) } })
        ObjectDetailTab({ label: '坐标', active: this.activeIndex === 1, onSelect: () => { this.onSelect(1) } })
        ObjectDetailTab({ label: '资料', active: this.activeIndex === 2, onSelect: () => { this.onSelect(2) } })
        ObjectDetailTab({ label: '操作', active: this.activeIndex === 3, onSelect: () => { this.onSelect(3) } })
      }
        .width('100%').padding({ left: 16, right: 16, bottom: 8 })
  }
}
