import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 天体详情行族的三个纯展示组件：数据行、结构化资料行与段落标题。
//
// 标签与数值以 `@Prop` 传入（带值参数按值捕获后不会随状态刷新，故由父方解析后传入）；
// 组件内不含解析逻辑。

@Component
export struct ObjectDataRow {
  @Prop label: string
  @Prop value: string

  build() {
    Row({ space: 10 }) {
      Text(this.label).fontSize(11).fontColor('#8FBBD6').width(68)
      Text(this.value.length > 0 ? this.value : '--')
        .fontSize(12).fontColor('#E0F1F8').layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .backgroundColor('rgba(255,255,255,0.035)').borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct StructuredDetailRow {
  @Prop label: string
  @Prop value: string
  @Prop tablet: boolean

  build() {
    Row({ space: 12 }) {
      Text(this.label)
        .fontSize(this.tablet ? 11 : 10).fontColor('#91B8CD').width(this.tablet ? 108 : 104)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value)
        .fontSize(this.tablet ? 12 : 11).fontColor('#E1F2FA').layoutWeight(1)
        .textAlign(TextAlign.Start).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.tablet ? 18 : 17)
    }
      .width('100%').height(this.tablet ? 46 : 44).alignItems(VerticalAlign.Center)
  }
}

@Component
export struct DetailSectionTitle {
  @Prop title: string
  @Prop tablet: boolean

  build() {
    if (this.tablet) {
      Text(this.title).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#A7D7EF').width('100%')
        .padding({ top: 4, bottom: 4 }).border({ width: { bottom: 0.5 }, color: { bottom: 'rgba(147,215,255,0.14)' } })
    } else {
      Text(this.title)
        .fontSize(11).fontWeight(FontWeight.Medium).fontColor('#A7D7EF').width('100%')
        .padding({ top: 7, bottom: 4 })
    }
  }
}
