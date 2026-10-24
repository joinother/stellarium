import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { Lx200Panel } from '../telescope/Lx200Panel'

// 「望远镜」面板，对应 `activePanel === 'telescope'`：把 Lx200Panel 包进 Scroll + Column
// 并加一行提示文案。
//
// 设备状态来自 TelescopeStore（@ObjectLink），其余为主题色 @Prop；
// 新建/选择/校验/保存/删除/连接测试/GoTo/同步/中止/读取位置/实时位置等动作回调注入宿主。
@Component
export struct TelescopePanel {
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

  build() {
      Scroll() {
        Column({ space: 8 }) {
          Text(I18n.t('telescope_control_hint')).fontSize(10).fontColor(this.c.sub).width('100%')
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
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
