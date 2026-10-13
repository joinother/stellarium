import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectDataRow } from './DetailRows'

// 详情卡片的"活数据行"组件：距离提示条、时角 / 恒星时行与九条坐标行。
//
// 坐标行与时角行以 `@ObjectLink` 观察 `ObjectDetailStore`，数值随状态实时刷新；
// 只有"是否可见 / 是否紧凑"这类判定由宿主以 `@Prop` 传入。

@Component
export struct ObjectDistanceNotice {
  @Prop text: string

  build() {
    if (this.text.length > 0) {
      Text(this.text).fontSize(11).fontColor('#AACADB').width('100%')
        .padding(10).backgroundColor('rgba(91,147,191,0.10)').borderRadius(UI_RADIUS_CONTROL)
    }
  }
}

@Component
export struct SelectedLiveInfoRows {
  @ObjectLink store: ObjectDetailStore
  @Prop compact: boolean
  @Prop visible: boolean

  build() {
    if (this.visible) {
      if (this.compact) {
        Row() {
          Text('时角').fontSize(10).fontColor('#8FBBD6').width(34)
          Text(this.store.selectedHourAngle.length > 0 ? this.store.selectedHourAngle : '--')
            .fontSize(11).fontColor('#E2F5FF').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.store.selectedMeanSiderealTime.length > 0 ? '平恒星时 ' + this.store.selectedMeanSiderealTime : '平恒星时 --')
            .fontSize(10).fontColor('#B9D9E9').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').height(24).padding({ left: 16, right: 16 })
      } else {
        Column({ space: 3 }) {
          ObjectDataRow({ label: '时角', value: this.store.selectedHourAngle })
          ObjectDataRow({ label: '平恒星时', value: this.store.selectedMeanSiderealTime })
          ObjectDataRow({ label: '视恒星时', value: this.store.selectedApparentSiderealTime })
        }.width('100%')
      }
    }
  }
}

@Component
export struct SelectedCoordinateRow {
  @Prop label: string
  @Prop value: string
  @Prop tablet: boolean

  build() {
    Row({ space: 8 }) {
      Text(this.label).fontSize(this.tablet ? 11 : 10).fontColor('#8FBBD6')
        .width(this.tablet ? 100 : 76).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value.length > 0 ? this.value : '--').fontSize(this.tablet ? 12 : 11).fontColor('#E0F1F8')
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').height(this.tablet ? 34 : 32).padding({ left: 10, right: 10 })
      .backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct SelectedCoordinateRows {
  @ObjectLink store: ObjectDetailStore
  @Prop tablet: boolean

  build() {
    Column({ space: 4 }) {
      // 地平坐标：与 selectedDisplayValue('selectedCoordApparentAltAz') 一致，缺值时回落到高度方位。
      SelectedCoordinateRow({
        label: '地平坐标',
        value: this.store.selectedCoordApparentAltAz.length > 0 ? this.store.selectedCoordApparentAltAz : this.store.selectedCoordAlt,
        tablet: this.tablet
      })
      SelectedCoordinateRow({ label: '几何地平', value: this.store.selectedCoordGeometricAltAz, tablet: this.tablet })
      SelectedCoordinateRow({ label: '赤道坐标', value: this.store.selectedCoordEq, tablet: this.tablet })
      SelectedCoordinateRow({ label: 'J2000 赤道', value: this.store.selectedCoordEqJ2000, tablet: this.tablet })
      SelectedCoordinateRow({ label: '当日黄道', value: this.store.selectedCoordEcliptic, tablet: this.tablet })
      SelectedCoordinateRow({ label: 'J2000 黄道', value: this.store.selectedCoordEclipticJ2000, tablet: this.tablet })
      SelectedCoordinateRow({ label: '银道坐标', value: this.store.selectedCoordGalactic, tablet: this.tablet })
      SelectedCoordinateRow({ label: '超银道坐标', value: this.store.selectedCoordSupergalactic, tablet: this.tablet })
      SelectedCoordinateRow({ label: '视差角', value: this.store.selectedCoordParallactic, tablet: this.tablet })
    }.width('100%')
  }
}
