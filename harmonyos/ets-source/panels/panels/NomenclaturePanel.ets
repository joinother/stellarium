// 行星表面地貌图集面板（3.8 MB IAU 行星地貌离线数据库 · 月球/火星/水星/金星/谷神星/灶神星/火卫一等一键飞抵）。
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { NomenclatureStore } from '../../state/NomenclatureStore'
import { PlanetaryNomenclatureBody, PlanetaryNomenclatureItem } from '../../common/types/StellariumTypes'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL, UI_RADIUS_TAG } from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'

interface NomCatTab {
  id: string
  label: string
}

const NOM_CATS: NomCatTab[] = [
  { id: 'all', label: '全部' },
  { id: 'crater', label: '撞击坑' },
  { id: 'mare', label: '月海/平原' },
  { id: 'mons', label: '山脉/火山' },
  { id: 'vallis', label: '峡谷/月溪' },
  { id: 'landing', label: '着陆点' }
]

@Component
export struct NomenclaturePanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink store: NomenclatureStore
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private fs(base: number): number {
    return uiFontSize(base, this.readableUi, this.uiFontScale)
  }

  private ch(base: number): number {
    return uiControlHeight(base, this.readableUi, this.controlScale)
  }

  private catCount(id: string): number {
    if (id === 'crater') return this.store.countCrater
    if (id === 'mare') return this.store.countMare
    if (id === 'mons') return this.store.countMons
    if (id === 'vallis') return this.store.countVallis
    if (id === 'landing') return this.store.countLanding
    return this.store.planetFeatureTotal
  }

  private formatCoord(lat: number, lon: number): string {
    const latDir = lat >= 0 ? 'N' : 'S'
    const lonNorm = lon > 180 ? lon - 360 : lon
    const lonDir = lonNorm >= 0 ? 'E' : 'W'
    return Math.abs(lat).toFixed(1) + '°' + latDir + ' · ' + Math.abs(lonNorm).toFixed(1) + '°' + lonDir
  }

  private formatSize(km: number): string {
    if (!Number.isFinite(km) || km <= 0) return ''
    if (km >= 100) return km.toFixed(0) + ' km'
    return km.toFixed(1) + ' km'
  }

  build() {
    Column({ space: 10 }) {
      // 标题栏 + 刷新
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text('行星地貌图集')
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.textStrong)
            InfoTipButton({
              title: 'IAU 行星表面地貌离线库',
              tip: '内置完整 16,000+ 处 IAU 国际天文学联合会行星表面地貌（月球环形山/月海/着陆点、火星奥林帕斯山/水手号峡谷/盖尔与杰泽罗撞击坑、灶神星雷亚希尔维亚盆地、火卫一斯蒂克尼撞击坑等）。点击任意地标即可自动开启标注与环形山轮廓并望远镜级缩放飞抵。'
            })
          }.alignItems(VerticalAlign.Center)
          Text('离线全量 ' + String(this.store.totalAllFeatures) + ' 处 IAU 地貌 · 当前星体 ' + String(this.store.planetFeatureTotal) + ' 处')
            .fontSize(this.fs(11))
            .fontColor(this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('刷新')
          .id('nomenclature-refresh-btn')
          .fontSize(this.fs(12))
          .fontColor(this.c.text)
          .backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(34) })
          .padding({ left: 12, right: 12 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.store.load() })
      }.width('100%').alignItems(VerticalAlign.Center)

      // 标绘显示开关卡片
      Row({ space: 6 }) {
        Button(this.store.showLabels ? '✓ 地貌标注' : '地貌标注')
          .id('nomenclature-toggle-labels')
          .fontSize(this.fs(10.5))
          .fontColor(this.store.showLabels ? this.c.onAccent : this.c.text)
          .backgroundColor(this.store.showLabels ? this.c.accent : this.c.soft)
          .border({ width: 0.6, color: this.store.showLabels ? this.c.accent : this.c.border })
          .borderRadius(UI_RADIUS_PILL)
          .constraintSize({ minHeight: this.ch(32) })
          .padding({ left: 6, right: 6 })
          .layoutWeight(1)
          .onClick(() => { this.store.toggleSetting('showLabels', !this.store.showLabels) })

        Button(this.store.outlineCraters ? '✓ 环形山轮廓' : '环形山轮廓')
          .id('nomenclature-toggle-craters')
          .fontSize(this.fs(10.5))
          .fontColor(this.store.outlineCraters ? this.c.onAccent : this.c.text)
          .backgroundColor(this.store.outlineCraters ? this.c.accent : this.c.soft)
          .border({ width: 0.6, color: this.store.outlineCraters ? this.c.accent : this.c.border })
          .borderRadius(UI_RADIUS_PILL)
          .constraintSize({ minHeight: this.ch(32) })
          .padding({ left: 6, right: 6 })
          .layoutWeight(1)
          .onClick(() => { this.store.toggleSetting('outlineCraters', !this.store.outlineCraters) })

        Button(this.store.terminatorOnly ? '✓ 仅晨昏线' : '仅晨昏线')
          .id('nomenclature-toggle-terminator')
          .fontSize(this.fs(10.5))
          .fontColor(this.store.terminatorOnly ? this.c.onAccent : this.c.text)
          .backgroundColor(this.store.terminatorOnly ? this.c.accent : this.c.soft)
          .border({ width: 0.6, color: this.store.terminatorOnly ? this.c.accent : this.c.border })
          .borderRadius(UI_RADIUS_PILL)
          .constraintSize({ minHeight: this.ch(32) })
          .padding({ left: 6, right: 6 })
          .layoutWeight(1)
          .onClick(() => { this.store.toggleSetting('terminatorOnly', !this.store.terminatorOnly) })
      }
      .width('100%')
      .padding(8)
      .backgroundColor(this.c.rowBg)
      .border({ width: 0.6, color: this.c.border })
      .borderRadius(UI_RADIUS_CARD)

      // 星体切换条
      if (this.store.bodies.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.store.bodies, (b: PlanetaryNomenclatureBody) => {
              Button(b.name + ' ' + String(b.count))
                .id('nomenclature-body-' + b.englishName.toLowerCase())
                .fontSize(this.fs(11))
                .fontWeight(this.store.planet.toLowerCase() === b.englishName.toLowerCase() ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.store.planet.toLowerCase() === b.englishName.toLowerCase() ? this.c.onAccent : this.c.text)
                .backgroundColor(this.store.planet.toLowerCase() === b.englishName.toLowerCase() ? this.c.accent : this.c.rowBg)
                .border({ width: 0.6, color: this.store.planet.toLowerCase() === b.englishName.toLowerCase() ? this.c.accent : this.c.border })
                .borderRadius(UI_RADIUS_PILL)
                .constraintSize({ minHeight: this.ch(32) })
                .padding({ left: 11, right: 11 })
                .onClick(() => { this.store.selectPlanet(b.englishName) })
            }, (b: PlanetaryNomenclatureBody) => b.englishName)
          }.padding({ left: 1, right: 1 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      // 精选地标一键飞抵
      if (this.store.featured.length > 0) {
        Column({ space: 6 }) {
          Text('精选地标 · 一键飞抵')
            .fontSize(this.fs(12))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textStrong)
            .width('100%')
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.store.featured, (f: PlanetaryNomenclatureItem) => {
                Button(f.name)
                  .id('nomenclature-featured-' + f.id)
                  .fontSize(this.fs(11))
                  .fontColor(this.c.accent)
                  .backgroundColor(this.c.accentSoft)
                  .border({ width: 0.6, color: this.c.accent })
                  .borderRadius(UI_RADIUS_PILL)
                  .constraintSize({ minHeight: this.ch(32) })
                  .padding({ left: 11, right: 11 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.store.flyTo(f) })
              }, (f: PlanetaryNomenclatureItem) => f.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.c.rowBg)
        .border({ width: 0.6, color: this.c.border })
        .borderRadius(UI_RADIUS_CARD)
      }

      // 搜索框 + 分类筛选
      Row({ space: 6 }) {
        TextInput({ placeholder: '搜索地貌名称或命名渊源（如 第谷 / Tycho / Olympus）', text: this.store.query })
          .id('nomenclature-search-input')
          .layoutWeight(1)
          .fontSize(this.fs(12))
          .fontColor(this.c.text)
          .placeholderColor(this.c.sub)
          .backgroundColor(this.c.input)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(36) })
          .onChange((val: string) => { this.store.setQuery(val) })
          .onSubmit(() => { this.store.load() })

        Button('筛选')
          .fontSize(this.fs(12))
          .fontColor(this.c.onAccent)
          .backgroundColor(this.c.accent)
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(36) })
          .padding({ left: 12, right: 12 })
          .onClick(() => { this.store.load() })
      }.width('100%')

      Scroll() {
        Row({ space: 6 }) {
          ForEach(NOM_CATS, (cat: NomCatTab) => {
            Button(cat.label + ' ' + String(this.catCount(cat.id)))
              .id('nomenclature-cat-' + cat.id)
              .fontSize(this.fs(11))
              .fontColor(this.store.category === cat.id ? this.c.onAccent : this.c.text)
              .backgroundColor(this.store.category === cat.id ? this.c.accent : this.c.soft)
              .border({ width: 0.6, color: this.store.category === cat.id ? this.c.accent : this.c.border })
              .borderRadius(UI_RADIUS_PILL)
              .constraintSize({ minHeight: this.ch(30) })
              .padding({ left: 10, right: 10 })
              .onClick(() => { this.store.selectCategory(cat.id) })
          }, (cat: NomCatTab) => cat.id)
        }.padding({ left: 1, right: 1 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // 错误 / 加载态 / 地貌列表
      if (this.store.error.length > 0) {
        Text(this.store.error)
          .fontSize(this.fs(12))
          .fontColor(this.c.sub)
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.rowBg)
          .borderRadius(UI_RADIUS_CARD)
      } else if (this.store.loading && this.store.items.length === 0) {
        Text('正在读取 IAU 行星表面地貌库…')
          .fontSize(this.fs(12))
          .fontColor(this.c.sub)
          .width('100%')
          .padding(12)
      } else if (this.store.items.length === 0) {
        Text('当前筛选条件下暂无匹配地貌，请尝试清空关键词或切换星体。')
          .fontSize(this.fs(12))
          .fontColor(this.c.sub)
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.rowBg)
          .borderRadius(UI_RADIUS_CARD)
      } else {
        Column({ space: 8 }) {
          ForEach(this.store.items, (item: PlanetaryNomenclatureItem) => {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(item.name)
                      .fontSize(this.fs(13))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.c.textStrong)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text(item.typeLabel)
                      .fontSize(this.fs(10))
                      .fontColor(this.c.accent)
                      .backgroundColor(this.c.accentSoft)
                      .borderRadius(UI_RADIUS_TAG)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  }.width('100%').alignItems(VerticalAlign.Center)

                  Text((item.englishName !== item.name ? item.englishName + ' · ' : '') +
                    (this.formatSize(item.sizeKm).length > 0 ? '直径 ' + this.formatSize(item.sizeKm) + ' · ' : '') +
                    this.formatCoord(item.latitude, item.longitude))
                    .fontSize(this.fs(11))
                    .fontColor(this.c.sub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button('飞抵')
                  .id('nomenclature-fly-' + item.id)
                  .fontSize(this.fs(11))
                  .fontColor(this.c.onAccent)
                  .backgroundColor(this.c.accent)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .constraintSize({ minHeight: this.ch(30) })
                  .padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.store.flyTo(item) })
              }.width('100%').alignItems(VerticalAlign.Center)

              if (item.origin.length > 0) {
                Text(item.origin)
                  .fontSize(this.fs(11))
                  .fontColor(this.c.sub)
                  .lineHeight(this.fs(16))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .width('100%')
            .padding(10)
            .backgroundColor(this.c.rowBg)
            .border({ width: 0.6, color: this.c.border })
            .borderRadius(UI_RADIUS_CARD)
          }, (item: PlanetaryNomenclatureItem) => item.planet + '|' + item.id)
        }.width('100%')
      }
    }.width('100%')
  }
}
