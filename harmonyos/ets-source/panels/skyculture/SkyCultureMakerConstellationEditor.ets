import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { SkyCultureMakerConstellation } from '../../pages/MainWindowModels'
import { SkyCultureMakerStore } from '../../state/SkyCultureMakerStore'
import { SkyCultureMakerArtworkEditor } from './SkyCultureMakerArtworkEditor'
import { SkyCultureMakerField } from './SkyCultureMakerFields'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 星文化制作器「星座」页。
//
// 选中项写入、增删星座 / 星线、把当前选中星加入线、刷新配图预览都要碰桥或解码，全部经回调交回宿主；
// HIP 输入框只改 store.hipLine，不触发排程。配图编辑器内嵌 `SkyCultureMakerArtworkEditor` 并转发回调。
// Column space 9，星座切条高 34，深色开关行高 24，HIP 输入高 38。
@Component
export struct SkyCultureMakerConstellationEditor {
  @ObjectLink store: SkyCultureMakerStore
  @Prop panelWidth: number
  @State c: ThemeSlots = DEFAULT_SLOTS
  onAdd: () => void = () => {}
  onSelect: (index: number) => void = () => {}
  onUpdate: (updated: SkyCultureMakerConstellation) => void = () => {}
  onRemoveSelected: () => void = () => {}
  onRemoveLine: (lineIndex: number) => void = () => {}
  onAddHipLine: () => void = () => {}
  onAddSelectedStar: () => void = () => {}
  onEdited: () => void = () => {}
  onImportArtwork: () => void = () => {}
  onRemoveArtwork: () => void = () => {}
  onArtworkTouch: (event: TouchEvent) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
        Text(I18n.format('sky_culture_maker_constellation_count', [this.store.constellations.length.toString()]))
          .fontSize(11).fontColor(this.c.sub).layoutWeight(1)
        Button(I18n.t('sky_culture_maker_add_constellation')).fontSize(10).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
          .height(30).borderRadius(UI_RADIUS_CONTROL).padding({ left: 10, right: 10 }).onClick(() => { this.onAdd() })
      }.width('100%')
      if (this.store.constellations.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.store.constellations, (item: SkyCultureMakerConstellation, index: number) => {
              Text(item.native.length > 0 ? item.native : item.id).fontSize(10)
                .fontColor(this.store.selectedConstellation === index ? this.c.onAccent : this.c.sub)
                .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                .backgroundColor(this.store.selectedConstellation === index ? this.c.accent : this.c.bg)
                .borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelect(index) })
            }, (item: SkyCultureMakerConstellation, index: number) => item.id + '/' + index.toString())
          }.padding({ right: 8 })
        }.width('100%').height(34).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.store.selectedConstellation >= 0 && this.store.selectedConstellation < this.store.constellations.length) {
        SkyCultureMakerField({
          label: I18n.t('sky_culture_maker_constellation_id'), value: this.store.constellations[this.store.selectedConstellation].id, placeholder: 'example',
          onChange: (value: string) => {
            const item = this.store.constellations[this.store.selectedConstellation]
            this.onUpdate({ id: value.toLowerCase().replace(/[^a-z0-9_]/g, '_'), english: item.english, native: item.native, pronounce: item.pronounce, transliteration: item.transliteration, IPA: item.IPA, dark: item.dark, lines: item.lines, image: item.image })
          },
          onEdited: () => { this.onEdited() }
        })
        Row({ space: 8 }) {
          Column() {
            SkyCultureMakerField({
              label: I18n.t('sky_culture_maker_english_name'), value: this.store.constellations[this.store.selectedConstellation].english, placeholder: 'Example',
              onChange: (value: string) => {
                const item = this.store.constellations[this.store.selectedConstellation]
                this.onUpdate({ id: item.id, english: value, native: item.native, pronounce: item.pronounce, transliteration: item.transliteration, IPA: item.IPA, dark: item.dark, lines: item.lines, image: item.image })
              },
              onEdited: () => { this.onEdited() }
            })
          }.layoutWeight(1)
          Column() {
            SkyCultureMakerField({
              label: I18n.t('sky_culture_maker_native_name'), value: this.store.constellations[this.store.selectedConstellation].native, placeholder: I18n.t('sky_culture_maker_native_name_hint'),
              onChange: (value: string) => {
                const item = this.store.constellations[this.store.selectedConstellation]
                this.onUpdate({ id: item.id, english: item.english, native: value, pronounce: item.pronounce, transliteration: item.transliteration, IPA: item.IPA, dark: item.dark, lines: item.lines, image: item.image })
              },
              onEdited: () => { this.onEdited() }
            })
          }.layoutWeight(1)
        }.width('100%')
        Row({ space: 8 }) {
          Column() {
            SkyCultureMakerField({
              label: I18n.t('sky_culture_maker_pronunciation'), value: this.store.constellations[this.store.selectedConstellation].pronounce, placeholder: '',
              onChange: (value: string) => {
                const item = this.store.constellations[this.store.selectedConstellation]
                this.onUpdate({ id: item.id, english: item.english, native: item.native, pronounce: value, transliteration: item.transliteration, IPA: item.IPA, dark: item.dark, lines: item.lines, image: item.image })
              },
              onEdited: () => { this.onEdited() }
            })
          }.layoutWeight(1)
          Column() {
            SkyCultureMakerField({
              label: I18n.t('sky_culture_maker_transliteration'), value: this.store.constellations[this.store.selectedConstellation].transliteration, placeholder: '',
              onChange: (value: string) => {
                const item = this.store.constellations[this.store.selectedConstellation]
                this.onUpdate({ id: item.id, english: item.english, native: item.native, pronounce: item.pronounce, transliteration: value, IPA: item.IPA, dark: item.dark, lines: item.lines, image: item.image })
              },
              onEdited: () => { this.onEdited() }
            })
          }.layoutWeight(1)
        }.width('100%')
        SkyCultureMakerField({
          label: 'IPA', value: this.store.constellations[this.store.selectedConstellation].IPA, placeholder: '',
          onChange: (value: string) => {
            const item = this.store.constellations[this.store.selectedConstellation]
            this.onUpdate({ id: item.id, english: item.english, native: item.native, pronounce: item.pronounce, transliteration: item.transliteration, IPA: value, dark: item.dark, lines: item.lines, image: item.image })
          },
          onEdited: () => { this.onEdited() }
        })
        Row({ space: 8 }) {
          Text(I18n.t('sky_culture_maker_dark_constellation')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.store.constellations[this.store.selectedConstellation].dark })
            .width(42).height(24).onChange((enabled: boolean) => {
              const item = this.store.constellations[this.store.selectedConstellation]
              this.onUpdate({ id: item.id, english: item.english, native: item.native, pronounce: item.pronounce, transliteration: item.transliteration, IPA: item.IPA, dark: enabled, lines: item.lines, image: item.image })
            })
        }.width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Text(I18n.t('sky_culture_maker_lines')).fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 4 })
        ForEach(this.store.constellations[this.store.selectedConstellation].lines, (line: number[], lineIndex: number) => {
          Row({ space: 8 }) {
            Text('HIP ' + line.join('  ·  ')).fontSize(10).fontColor(this.c.text).layoutWeight(1).maxLines(2)
            Button(I18n.t('nebula_texture_remove')).fontSize(10).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
              .height(28).borderRadius(UI_RADIUS_CONTROL).padding({ left: 8, right: 8 }).onClick(() => { this.onRemoveLine(lineIndex) })
          }.width('100%').padding({ left: 10, right: 8, top: 6, bottom: 6 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        }, (line: number[], lineIndex: number) => line.join('-') + '/' + lineIndex.toString())
        TextInput({ text: this.store.hipLine, placeholder: I18n.t('sky_culture_maker_hip_hint') })
          .height(38).width('100%').fontSize(11).fontColor(this.c.text).backgroundColor(this.c.input)
          .border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
          .onChange((value: string) => { this.store.hipLine = value })
        Row({ space: 8 }) {
          Button(I18n.t('sky_culture_maker_add_line')).fontSize(10).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
            .height(32).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onAddHipLine() })
          Button(I18n.t('sky_culture_maker_add_selected_star')).fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg)
            .height(32).layoutWeight(1).borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onAddSelectedStar() })
        }.width('100%')
        SkyCultureMakerArtworkEditor({
          store: this.store, panelWidth: this.panelWidth,
          onImport: () => { this.onImportArtwork() },
          onRemove: () => { this.onRemoveArtwork() },
          onArtworkTouch: (event: TouchEvent) => { this.onArtworkTouch(event) }
        })
        Button(I18n.t('sky_culture_maker_delete_constellation')).fontSize(10).fontColor(this.c.errorText).backgroundColor(this.c.errorBg)
          .height(32).width('100%').borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onRemoveSelected() })
      } else {
        Text(I18n.t('sky_culture_maker_no_constellations')).fontSize(11).fontColor(this.c.sub).width('100%')
          .textAlign(TextAlign.Center).padding({ top: 24, bottom: 24 })
      }
    }.width('100%')
  }
}
