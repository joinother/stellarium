import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../capability/I18n'
import {
  UI_OPTION_ANIMATION_MS,
  UI_RADIUS_CARD,
  UI_RADIUS_CONTROL,
  UI_RADIUS_MEDIA,
  UI_RADIUS_PILL
} from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { AudioStore } from '../../state/AudioStore'
import { AetherisMaterialPreset, AetherisMoodId } from '../../capability/AudioCatalog'

// 音频控制面板，对应 `activePanel === 'audio'`。
// 背景音乐 / 天体与交互音效 / 主音量 / 星空音景状态来自 AudioStore（@ObjectLink）。
// 详细概念与音色说明统一收敛进 InfoTipButton（ⓘ），保持主界面克制、清晰、一屏完整呈现。
// AudioEngine 是原生桥，经回调注入：组件内不 import AudioEngine。

interface MoodOption {
  id: AetherisMoodId
  zh: string
  en: string
}

interface MaterialOption {
  id: AetherisMaterialPreset
  zh: string
  en: string
}

const MOOD_OPTIONS: MoodOption[] = [
  { id: 'newmoon', zh: '新月', en: 'New' },
  { id: 'fullmoon', zh: '满月', en: 'Full' },
  { id: 'aurora', zh: '极光', en: 'Aurora' },
  { id: 'twilight', zh: '暮光', en: 'Dusk' },
  { id: 'oriental', zh: '古星官', en: 'Ancient' }
]

const MATERIAL_OPTIONS: MaterialOption[] = [
  { id: 'jade', zh: '玉磬', en: 'Jade' },
  { id: 'felt', zh: '毡槌', en: 'Felt' },
  { id: 'tape', zh: '磁带', en: 'Tape' },
  { id: 'bowl', zh: '颂钵', en: 'Bowl' }
]

@Component
export struct AudioPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @ObjectLink audioStore: AudioStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggleMusic: (enabled: boolean) => void = () => {}
  onToggleSfx: (enabled: boolean) => void = () => {}
  onVolumeChange: (value: number) => void = () => {}
  onSelectMood: (mood: AetherisMoodId) => void = () => {}
  onSelectMaterial: (preset: AetherisMaterialPreset) => void = () => {}
  onRandomizeDna: () => void = () => {}
  onSkipNextAct: () => void = () => {}
  onPlayLogo: () => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private text(zh: string, en: string): string {
    return I18n.getLanguage().startsWith('zh') ? zh : en
  }

  build() {
    Scroll() {
      Column({ space: 8 }) {
        // Card 1: 基础音频开关与主音量
        Column() {
          Row({ space: 6 }) {
            Row({ space: 2 }) {
              Text(I18n.t('audio_toggle')).fontSize(panelFontSize(14, this.readableUi))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.text)
                .maxLines(1)
              InfoTipButton({
                title: I18n.t('audio_toggle'),
                tip: this.text(
                  '实时程序化生成的 8 幕星穹乐章，融合柔琴、玉磬与空间混响，并包含自然静默留白。自动适配耳机空间声场与手机外放低音增强；静置 30 秒后平滑切入低功耗冥想态。',
                  'Real-time procedural 8-act celestial score with natural silence breaths. Adapts automatically to headphones or device speakers, and enters a gentle low-power meditation mode after 30 s idle.'
                )
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)
            Toggle({ type: ToggleType.Switch, isOn: this.audioStore.musicEnabled })
              .selectedColor(this.c.accent)
              .onChange((isOn: boolean) => {
                if (isOn !== this.audioStore.musicEnabled) {
                  this.onToggleMusic(isOn)
                }
              })
          }.width('100%').height(40).alignItems(VerticalAlign.Center)

          Divider().strokeWidth(0.5).color(this.c.dividerSoft)

          Row({ space: 6 }) {
            Row({ space: 2 }) {
              Text(I18n.t('audio_sfx_toggle')).fontSize(panelFontSize(14, this.readableUi))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.text)
                .maxLines(1)
              InfoTipButton({
                title: I18n.t('audio_sfx_toggle'),
                tip: this.text(
                  '点击恒星、行星、深空天体或切换多光谱波段时，依据温度、星等与类型实时合成专属音色；播放时轻柔压低背景乐，并与线性马达触觉协同。',
                  'Synthesizes bespoke celestial timbres from star temperature, magnitude, object type and spectral band, softly ducking the music alongside haptic feedback.'
                )
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)
            Toggle({ type: ToggleType.Switch, isOn: this.audioStore.sfxEnabled })
              .selectedColor(this.c.accent)
              .onChange((isOn: boolean) => {
                if (isOn !== this.audioStore.sfxEnabled) {
                  this.onToggleSfx(isOn)
                }
              })
          }.width('100%').height(40).alignItems(VerticalAlign.Center)

          Divider().strokeWidth(0.5).color(this.c.dividerSoft)

          Row({ space: 8 }) {
            Text(I18n.t('audio_volume')).fontSize(panelFontSize(14, this.readableUi))
              .fontColor(this.c.text)
              .maxLines(1)
            Slider({
              value: this.audioStore.audioVolume,
              min: 0,
              max: 1,
              step: 0.05,
              style: SliderStyle.OutSet
            })
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .minResponsiveDistance(8)
              .selectedColor(this.c.accent)
              .trackColor(this.c.softStrong)
              .showSteps(false)
              .layoutWeight(1)
              .onChange((val: number) => { this.onVolumeChange(val) })
            Text(Math.round(this.audioStore.audioVolume * 100) + '%')
              .fontSize(panelFontSize(13, this.readableUi))
              .fontColor(this.c.sub)
              .width(38)
              .textAlign(TextAlign.End)
              .maxLines(1)
          }.width('100%').height(40).alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })
        .backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CARD)
        .border({ width: 0.5, color: this.c.border })

        // Card 2: 千人千面星空音景
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Row({ space: 2 }) {
              Text(this.text('星空音景', 'Soundscape'))
                .fontSize(panelFontSize(14, this.readableUi))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.textStrong)
                .maxLines(1)
              InfoTipButton({
                title: this.text('千人千面星空音景', 'Generative Soundscape'),
                tip: this.text(
                  '由当前星音签名实时推演专属的旋律动机、调式与配器，做到每次观星都独一无二。点按「换一组」会重新生成新的宇宙音景，也可在下方自由微调。',
                  'Derives a unique melodic motif, harmonic mode and timbre balance from your current sound signature. Tap Shuffle for a fresh cosmos, or fine-tune mode and timbre below.'
                )
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)

            Text(this.text('换一组', 'Shuffle'))
              .fontSize(panelFontSize(12, this.readableUi))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .backgroundColor(this.c.soft)
              .border({ width: 0.5, color: this.c.border })
              .borderRadius(UI_RADIUS_PILL)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
              .onClick(() => { this.onRandomizeDna() })
          }.width('100%').alignItems(VerticalAlign.Center)

          // 天象调式（单行 5 项均分，无折行）
          Column({ space: 4 }) {
            Row({ space: 2 }) {
              Text(this.text('天象调式', 'Celestial mode'))
                .fontSize(panelFontSize(12, this.readableUi))
                .fontColor(this.c.sub)
              InfoTipButton({
                title: this.text('天象调式', 'Celestial mode'),
                iconSize: 14,
                tip: this.text(
                  '决定背景乐的音阶情绪与 8 幕交响弧线色彩：\n• 新月：清澈空灵的利底亚调式\n• 满月：温润圆满的五声调式\n• 极光：流光律动的多利亚调式\n• 暮光：辽阔深远的四度和声\n• 古星官：东方雅正的云井古调',
                  'Shapes the harmonic color across the 8-act celestial arc:\n• New: Luminous Lydian\n• Full: Warm Pentatonic\n• Aurora: Shimmering Dorian\n• Dusk: Open Quartal harmony\n• Ancient: Classical Kumoi scale'
                )
              })
            }.width('100%').alignItems(VerticalAlign.Center)

            Row({ space: 5 }) {
              ForEach(MOOD_OPTIONS, (opt: MoodOption) => {
                Text(this.text(opt.zh, opt.en))
                  .fontSize(panelFontSize(12, this.readableUi))
                  .fontWeight(this.audioStore.audioMood === opt.id ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.audioStore.audioMood === opt.id ? this.c.onAccent : this.c.sub)
                  .backgroundColor(this.audioStore.audioMood === opt.id ? this.c.accent : this.c.soft)
                  .border({
                    width: 0.5,
                    color: this.audioStore.audioMood === opt.id ? this.c.accent : this.c.dividerSoft
                  })
                  .borderRadius(UI_RADIUS_MEDIA)
                  .height(30)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
                  .onClick(() => { this.onSelectMood(opt.id) })
              }, (opt: MoodOption) => opt.id)
            }.width('100%')
          }.width('100%')

          // 音色材质（单行 4 项均分，对称无落单）
          Column({ space: 4 }) {
            Row({ space: 2 }) {
              Text(this.text('音色材质', 'Timbre material'))
                .fontSize(panelFontSize(12, this.readableUi))
                .fontColor(this.c.sub)
              InfoTipButton({
                title: this.text('音色材质', 'Timbre material'),
                iconSize: 14,
                tip: this.text(
                  '切换主旋律与共鸣层的物理建模质感：\n• 玉磬：温润清越的东方石磬泛音\n• 毡槌：柔和亲密的北欧毡槌弱音钢琴\n• 磁带：温暖微颤的模拟磁带弦乐\n• 颂钵：深邃绵长的金属颂钵共鸣',
                  'Selects the physical-modeling timbre for lead & resonance:\n• Jade: Luminous eastern stone chime\n• Felt: Intimate Nordic felt piano\n• Tape: Warm analog tape strings\n• Bowl: Deep singing-bowl overtones'
                )
              })
            }.width('100%').alignItems(VerticalAlign.Center)

            Row({ space: 6 }) {
              ForEach(MATERIAL_OPTIONS, (mat: MaterialOption) => {
                Text(this.text(mat.zh, mat.en))
                  .fontSize(panelFontSize(12, this.readableUi))
                  .fontWeight(this.audioStore.audioMaterial === mat.id ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.audioStore.audioMaterial === mat.id ? this.c.onAccent : this.c.sub)
                  .backgroundColor(this.audioStore.audioMaterial === mat.id ? this.c.accent : this.c.soft)
                  .border({
                    width: 0.5,
                    color: this.audioStore.audioMaterial === mat.id ? this.c.accent : this.c.dividerSoft
                  })
                  .borderRadius(UI_RADIUS_MEDIA)
                  .height(30)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
                  .onClick(() => { this.onSelectMaterial(mat.id) })
              }, (mat: MaterialOption) => mat.id)
            }.width('100%')
          }.width('100%')

          // 操作区：下一乐章 / 试听星音
          Row({ space: 8 }) {
            Text(this.text('下一乐章', 'Next act'))
              .fontSize(panelFontSize(13, this.readableUi))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
              .backgroundColor(this.c.soft)
              .border({ width: 0.5, color: this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)
              .height(34)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
              .onClick(() => { this.onSkipNextAct() })

            Text(this.text('试听星音', 'Preview chime'))
              .fontSize(panelFontSize(13, this.readableUi))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
              .backgroundColor(this.c.soft)
              .border({ width: 0.5, color: this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)
              .height(34)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
              .onClick(() => { this.onPlayLogo() })
          }.width('100%').margin({ top: 2 })

          // 底部星音签名（低干扰展示）
          Row({ space: 8 }) {
            Text(this.text('当前星音签名', 'Signature'))
              .fontSize(panelFontSize(11, this.readableUi))
              .fontColor(this.c.sub)
              .maxLines(1)
            Blank().layoutWeight(1)
            Text(this.audioStore.audioSeed)
              .fontSize(panelFontSize(11, this.readableUi))
              .fontColor(this.c.sub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%').alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CARD)
        .border({ width: 0.5, color: this.c.border })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 2, bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(4)
    .scrollBarColor(this.c.scrollbar)
  }
}
