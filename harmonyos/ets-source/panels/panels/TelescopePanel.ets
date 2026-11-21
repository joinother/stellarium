import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { UI_RADIUS_CARD } from '../../common/ui/UiTokens'
import { uiFontSize } from '../../common/ui/UiTypography'
import { Lx200Panel } from '../telescope/Lx200Panel'

// 「望远镜」面板，对应 `activePanel === 'telescope'`。
// 设备状态来自 TelescopeStore（@ObjectLink）；长提示文案收纳于 InfoTipButton ⓘ。
@Component
export struct TelescopePanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @ObjectLink store: TelescopeStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onBeginNew: () => void = () => {}
  onSelectProfile: (slot: number) => void = () => {}
  onSelectProtocol: (protocol: string) => void = () => {}
  onValidateEditor: () => void = () => {}
  onSave: () => void = () => {}
  onDelete: () => void = () => {}
  onTest: () => void = () => {}
  onGoto: () => void = () => {}
  onSync: () => void = () => {}
  onAbort: () => void = () => {}
  onReadPosition: (center: boolean) => void = () => {}
  onSetLivePosition: (enabled: boolean) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private fs(base: number): number { return uiFontSize(base, this.readableUi, this.uiFontScale) }

  build() {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text(I18n.t('panel_telescope_control'))
            .fontSize(this.fs(15)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
          InfoTipButton({
            title: I18n.t('panel_telescope_control'),
            tip: I18n.t('telescope_control_hint')
          })
        }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
          .alignItems(VerticalAlign.Center)

        Lx200Panel({
          store: this.store,
          onBeginNew: () => { this.onBeginNew() },
          onSelectProfile: (slot: number) => { this.onSelectProfile(slot) },
          onSelectProtocol: (protocol: string) => { this.onSelectProtocol(protocol) },
          onValidateEditor: () => { this.onValidateEditor() },
          onSave: () => { this.onSave() },
          onDelete: () => { this.onDelete() },
          onTest: () => { this.onTest() },
          onGoto: () => { this.onGoto() },
          onSync: () => { this.onSync() },
          onAbort: () => { this.onAbort() },
          onReadPosition: (center: boolean) => { this.onReadPosition(center) },
          onSetLivePosition: (enabled: boolean) => { this.onSetLivePosition(enabled) }
        })
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
