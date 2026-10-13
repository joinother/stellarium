// 键盘快捷键控制器。
//
// 列出可编辑的 Stellarium 动作、按搜索词过滤、保存选中项的主/备快捷键、恢复单项或全部默认。
// 本类不 import NAPI/UI：桥调用走 CommandPort，UI 提示经 KeyboardShortcutHostHooks 回注。
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'
import { KeyboardShortcutStore } from '../state/KeyboardShortcutStore'
import { KeyboardShortcutItem, StellariumBridgeResponse } from '../common/types/StellariumTypes'

// 宿主 → 控制器回注：UI 提示。
export interface KeyboardShortcutHostHooks {
  flashHint(text: ResourceStr): void
}

export class KeyboardShortcutController {
  private store: KeyboardShortcutStore
  private port: CommandPort
  private hooks: KeyboardShortcutHostHooks

  constructor(store: KeyboardShortcutStore, port: CommandPort, hooks: KeyboardShortcutHostHooks) {
    this.store = store
    this.port = port
    this.hooks = hooks
  }

  // 按当前搜索词拉取动作列表；保留仍存在的选中项。
  load(): void {
    this.store.keyboardShortcutsLoading = true
    this.port.requestInteractive('getKeyboardShortcuts', this.store.keyboardShortcutQuery.trim(), (r: StellariumBridgeResponse) => {
      this.store.keyboardShortcutsLoading = false
      const items = r.items
      if (r.ok !== true || items === undefined) return
      this.store.keyboardShortcuts = items as KeyboardShortcutItem[]
      if (this.store.keyboardShortcutSelectedId.length > 0) {
        const selected = this.store.keyboardShortcuts.find((item: KeyboardShortcutItem): boolean => item.id === this.store.keyboardShortcutSelectedId)
        if (selected !== undefined) this.select(selected)
      }
    }, () => { this.store.keyboardShortcutsLoading = false })
  }

  // 选中动作，回填主/备快捷键草稿。
  select(item: KeyboardShortcutItem): void {
    this.store.keyboardShortcutSelectedId = item.id
    this.store.keyboardShortcutPrimary = item.shortcut
    this.store.keyboardShortcutAlternate = item.alternateShortcut
  }

  // 保存选中动作的主/备快捷键；冲突时提示被占用的动作。
  save(): void {
    if (this.store.keyboardShortcutSelectedId.length === 0) return
    const payload = this.store.keyboardShortcutSelectedId + '|' + this.store.keyboardShortcutPrimary.trim() + '|' + this.store.keyboardShortcutAlternate.trim()
    this.port.requestInteractive('setKeyboardShortcut', payload, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.hooks.flashHint(r.error === 'shortcut conflict' ? '快捷键冲突：' + String(r.conflictAction ?? '') : (r.error ?? I18n.t('msg_apply_failed')))
        return
      }
      this.hooks.flashHint(I18n.t('settings_shortcuts_saved'))
      this.load()
    })
  }

  // 恢复选中动作的默认快捷键。
  resetSelected(): void {
    if (this.store.keyboardShortcutSelectedId.length === 0) return
    this.port.requestInteractive('resetKeyboardShortcuts', this.store.keyboardShortcutSelectedId, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) { this.hooks.flashHint(r.error ?? I18n.t('msg_apply_failed')); return }
      this.hooks.flashHint(I18n.t('settings_shortcuts_restored'))
      this.load()
    })
  }

  // 恢复全部动作的默认快捷键。
  resetAll(): void {
    this.port.requestInteractive('resetKeyboardShortcuts', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) { this.hooks.flashHint(r.error ?? I18n.t('msg_apply_failed')); return }
      this.hooks.flashHint(I18n.t('settings_shortcuts_restored_all'))
      this.load()
    })
  }
}
