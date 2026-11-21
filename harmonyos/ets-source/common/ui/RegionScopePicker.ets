import { LengthMetrics, Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from './UiTokens'
import { panelFontSize } from './UiTypography'
import { uiFadeUpTransition } from './UiMotion'
import {
  FOLLOW_REGION_ID,
  OBSERVER_REGION_PRESETS,
  ObserverRegionPreset,
  findObserverRegionPreset,
  normalizeObserverRegionId,
  regionShortLabel
} from '../../state/ObserverRegionScope'

// Reusable compact geographic region scope picker shared by Astronomy Calendar, Notifications, and Widget Studio.
// Allows switching seamlessly between "Follow current observer location" and an independent geographic region.
@Component
export struct RegionScopePicker {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop title: string = '地理区域'
  @Prop regionId: string = FOLLOW_REGION_ID
  @Prop followLocationName: string = ''
  @Prop language: string = 'zh'
  @Prop disabled: boolean = false
  onSelectRegion: (regionId: string) => void = () => {}

  @State private expanded: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private activeId(): string {
    return normalizeObserverRegionId(this.regionId)
  }

  private summaryText(): string {
    return regionShortLabel(this.activeId(), this.language, this.followLocationName)
  }

  private tzBadgeText(): string {
    const preset = findObserverRegionPreset(this.activeId())
    if (preset === undefined) return this.isZh() ? '跟随星图' : 'Follow'
    return this.isZh() ? preset.tzLabelZh : preset.tzLabelEn
  }

  private pick(id: string): void {
    if (this.disabled) return
    this.onSelectRegion(id)
    this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
      this.expanded = false
    })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.title)
              .fontSize(panelFontSize(12, this.readableUi))
              .fontColor(this.c.sub)
            Text(this.tzBadgeText())
              .fontSize(panelFontSize(10, this.readableUi))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.activeId() === FOLLOW_REGION_ID ? this.c.sub : this.c.onAccent)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.activeId() === FOLLOW_REGION_ID ? this.c.softStrong : this.c.accent)
              .borderRadius(UI_RADIUS_PILL)
          }
          Text(this.summaryText())
            .fontSize(panelFontSize(13, this.readableUi))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

        Text(this.expanded ? (this.isZh() ? '收起 ▴' : 'Hide ▴') : (this.isZh() ? '切换区域 ▾' : 'Region ▾'))
          .fontSize(panelFontSize(12, this.readableUi))
          .fontColor(this.expanded ? this.c.onAccent : this.c.text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.expanded ? this.c.accent : this.c.softStrong)
          .borderRadius(UI_RADIUS_PILL)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            if (this.disabled) return
            this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
              this.expanded = !this.expanded
            })
          })
      }
        .width('100%')
        .alignItems(VerticalAlign.Center)

      if (this.expanded) {
        Column({ space: 8 }) {
          // Follow current location button
          Row({ space: 6 }) {
            Text(this.isZh()
              ? ('✦ 跟随当前星图位置' + (this.followLocationName.trim().length > 0 ? ('（' + this.followLocationName.trim() + '）') : ''))
              : ('✦ Follow sky location' + (this.followLocationName.trim().length > 0 ? (' (' + this.followLocationName.trim() + ')') : '')))
              .fontSize(panelFontSize(12, this.readableUi))
              .fontWeight(this.activeId() === FOLLOW_REGION_ID ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.activeId() === FOLLOW_REGION_ID ? this.c.onAccent : this.c.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.activeId() === FOLLOW_REGION_ID) {
              Text('✓')
                .fontSize(panelFontSize(12, this.readableUi))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.c.onAccent)
            }
          }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(this.activeId() === FOLLOW_REGION_ID ? this.c.accent : this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => this.pick(FOLLOW_REGION_ID))

          Text(this.isZh() ? '或独立指定地理区域（不影响主星图定位）：' : 'Or pick an independent region (keeps sky location unchanged):')
            .fontSize(panelFontSize(10, this.readableUi))
            .fontColor(this.c.sub)
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
            ForEach(OBSERVER_REGION_PRESETS, (preset: ObserverRegionPreset) => {
              Row({ space: 4 }) {
                Text(this.isZh() ? preset.labelZh.split(' · ')[0] : preset.labelEn)
                  .fontSize(panelFontSize(12, this.readableUi))
                  .fontWeight(this.activeId() === preset.id ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.activeId() === preset.id ? this.c.onAccent : this.c.text)
                Text(this.isZh() ? preset.tzLabelZh : preset.tzLabelEn)
                  .fontSize(panelFontSize(9, this.readableUi))
                  .fontColor(this.activeId() === preset.id ? this.c.onAccent : this.c.sub)
              }
                .padding({ left: 9, right: 9, top: 6, bottom: 6 })
                .backgroundColor(this.activeId() === preset.id ? this.c.accent : this.c.bg)
                .borderRadius(UI_RADIUS_PILL)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => this.pick(preset.id))
            }, (preset: ObserverRegionPreset) => preset.id + ':' + (this.activeId() === preset.id ? '1' : '0'))
          }
            .width('100%')
        }
          .width('100%')
          .padding({ top: 4 })
          .transition(uiFadeUpTransition())
      }
    }
      .width('100%')
      .padding({ left: 12, right: 10, top: 9, bottom: 9 })
      .backgroundColor(this.activeId() !== FOLLOW_REGION_ID ? this.c.soft : this.c.bg)
      .border({ width: 1, color: this.activeId() !== FOLLOW_REGION_ID ? this.c.border : this.c.dividerSoft })
      .borderRadius(UI_RADIUS_CARD)
      .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
  }
}
