// 键盘快捷键控制器。
//
// 列出可编辑的 Stellarium 动作、按搜索词过滤、保存选中项的主/备快捷键、恢复单项或全部默认。
// 本类不 import NAPI/UI：桥调用走 CommandPort，UI 提示经 KeyboardShortcutHostHooks 回注。
import { I18n } from '../pages/I18n'
import { KeyCode } from '@kit.InputKit'
import { CommandPort } from '../bridge/CommandPort'
import { KeyboardShortcutStore } from '../state/KeyboardShortcutStore'
import { KeyboardShortcutItem, StellariumBridgeResponse } from '../common/types/StellariumTypes'

// 宿主 → 控制器回注：UI 提示。
export interface KeyboardShortcutHostHooks {
  flashHint(text: ResourceStr): void
}

export interface KeyboardShortcutInputHooks {
  skyWidth(): number
  skyHeight(): number
  zoomStep(factor: number): void
  centerSelectedObjectFromKeyboard(): void
  moveToSelectedObject(): void
  closeKeyboardOverlay(): void
}

export class KeyboardShortcutController {
  private store: KeyboardShortcutStore
  private port: CommandPort
  private hooks: KeyboardShortcutHostHooks
  private focusRevision: number = 0
  private pressedKeys: Set<number> = new Set<number>()
  private heldKeyPayloads: Map<number, string> = new Map<number, string>()

  constructor(store: KeyboardShortcutStore, port: CommandPort, hooks: KeyboardShortcutHostHooks) {
    this.store = store
    this.port = port
    this.hooks = hooks
  }

  setSkyFocused(focused: boolean): void {
    if (!focused) this.releaseHeldKeys()
    if (this.store.skyKeyboardFocused === focused) return
    this.store.skyKeyboardFocused = focused
    this.focusRevision++
    this.pressedKeys.clear()
  }

  private releaseHeldKeys(): void {
    this.heldKeyPayloads.forEach((payload: string) => {
      this.port.fire('sendKey', payload + '|up')
    })
    this.heldKeyPayloads.clear()
  }

  private releaseKey(keyCode: number): boolean {
    const payload = this.heldKeyPayloads.get(keyCode)
    this.heldKeyPayloads.delete(keyCode)
    if (payload !== undefined) this.port.fire('sendKey', payload + '|up')
    return this.pressedKeys.delete(keyCode)
  }

  private keyboardToken(event: KeyEvent, shift: boolean): string {
    const code = event.keyCode
    if (code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z) {
      return String.fromCharCode(65 + code - KeyCode.KEYCODE_A)
    }
    if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) {
      return (code - KeyCode.KEYCODE_0).toString()
    }
    if (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) {
      return 'F' + (code - KeyCode.KEYCODE_F1 + 1).toString()
    }
    switch (code) {
      case KeyCode.KEYCODE_DPAD_UP: return 'UP'
      case KeyCode.KEYCODE_DPAD_DOWN: return 'DOWN'
      case KeyCode.KEYCODE_DPAD_LEFT: return 'LEFT'
      case KeyCode.KEYCODE_DPAD_RIGHT: return 'RIGHT'
      case KeyCode.KEYCODE_PAGE_UP: return 'PAGEUP'
      case KeyCode.KEYCODE_PAGE_DOWN: return 'PAGEDOWN'
      case KeyCode.KEYCODE_MOVE_HOME: return 'HOME'
      case KeyCode.KEYCODE_MOVE_END: return 'END'
      case KeyCode.KEYCODE_PLUS: return 'PLUS'
      case KeyCode.KEYCODE_EQUALS: return shift ? 'PLUS' : 'EQUALS'
      case KeyCode.KEYCODE_MINUS: return 'MINUS'
      case KeyCode.KEYCODE_LEFT_BRACKET: return '['
      case KeyCode.KEYCODE_RIGHT_BRACKET: return ']'
      case KeyCode.KEYCODE_SPACE: return 'SPACE'
      case KeyCode.KEYCODE_ENTER: return 'ENTER'
      case KeyCode.KEYCODE_ESCAPE: return 'ESC'
      case KeyCode.KEYCODE_DEL: return 'BACKSPACE'
      case KeyCode.KEYCODE_FORWARD_DEL: return 'DELETE'
      default: return ''
    }
  }

  private fallbackKeyboardToken(token: string, hooks: KeyboardShortcutInputHooks): void {
    switch (token) {
      case 'PLUS':
      case 'EQUALS': hooks.zoomStep(0.8); return
      case 'MINUS': hooks.zoomStep(1.25); return
      case 'SPACE': hooks.centerSelectedObjectFromKeyboard(); return
      case 'ENTER': hooks.moveToSelectedObject(); return
      default: return
    }
  }

  handleSkyKey(event: KeyEvent, hooks: KeyboardShortcutInputHooks): boolean {
    if (event.type === KeyType.Up) return this.releaseKey(event.keyCode)
    if (!this.store.skyKeyboardFocused || event.type !== KeyType.Down || event.metaKey !== 0) return false
    if (this.pressedKeys.has(event.keyCode)) return true
    const modifiers: string[] = []
    let shift = false
    try {
      if (event.getModifierKeyState === undefined) return false
      if (event.getModifierKeyState(['Ctrl'])) modifiers.push('CTRL')
      if (event.getModifierKeyState(['Alt'])) modifiers.push('ALT')
      shift = event.getModifierKeyState(['Shift'])
      if (shift) modifiers.push('SHIFT')
    } catch (_) { return false }
    const token = this.keyboardToken(event, shift)
    if (token.length === 0 || (token === 'EQUALS' && modifiers.length > 0)) return false
    this.pressedKeys.add(event.keyCode)
    if (token === 'ESC' && modifiers.length === 0) {
      hooks.closeKeyboardOverlay()
      return true
    }
    if (token === 'EQUALS') {
      hooks.zoomStep(0.8)
      return true
    }
    const revision = this.focusRevision
    const payload = modifiers.concat([token]).join('+')
    if (['UP', 'DOWN', 'LEFT', 'RIGHT', 'PAGEUP', 'PAGEDOWN', 'HOME', 'END'].includes(token)) {
      this.heldKeyPayloads.set(event.keyCode, payload)
      this.port.fire('sendKey', payload + '|down')
      return true
    }
    this.port.requestInteractive('sendKey', payload, (result: StellariumBridgeResponse) => {
      if (result.ok === true && result.accepted === false && modifiers.length === 0 &&
        this.store.skyKeyboardFocused && this.focusRevision === revision) {
        this.fallbackKeyboardToken(token, hooks)
      }
    })
    return true
  }

  handlePanelKey(event: KeyEvent, hooks: KeyboardShortcutInputHooks): boolean {
    if (event.keyCode !== KeyCode.KEYCODE_ESCAPE) return false
    if (event.type === KeyType.Up) return this.pressedKeys.delete(event.keyCode)
    if (event.type !== KeyType.Down || event.metaKey !== 0) return false
    try {
      if (event.getModifierKeyState === undefined || event.getModifierKeyState(['Ctrl']) ||
        event.getModifierKeyState(['Alt']) || event.getModifierKeyState(['Shift'])) return false
    } catch (_) { return false }
    if (this.pressedKeys.has(event.keyCode)) return true
    this.pressedKeys.add(event.keyCode)
    hooks.closeKeyboardOverlay()
    return true
  }

  private supportedShortcut(shortcut: string): boolean {
    if (shortcut.trim().length === 0) return true
    const parts = shortcut.trim().toUpperCase().split('+')
    let token = parts.pop() ?? ''
    if (token.length === 0 && parts.length > 0 && parts[parts.length - 1] === '') {
      parts.pop()
      token = '+'
    }
    const modifiers: string[] = []
    for (const part of parts) {
      const modifier = part.trim()
      if (!['CTRL', 'ALT', 'SHIFT'].includes(modifier) || modifiers.includes(modifier)) return false
      modifiers.push(modifier)
    }
    token = token.trim()
    if (token === 'ESC') return modifiers.length > 0
    return /^[A-Z0-9]$/.test(token) || /^F([1-9]|1[0-2])$/.test(token) ||
      ['UP', 'DOWN', 'LEFT', 'RIGHT', 'PGUP', 'PGDOWN', 'HOME', 'END', '-', '[', ']',
        '+', 'SPACE', 'RETURN', 'BACKSPACE', 'DEL'].includes(token)
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
    if (!this.supportedShortcut(this.store.keyboardShortcutPrimary) ||
      !this.supportedShortcut(this.store.keyboardShortcutAlternate)) {
      this.hooks.flashHint('当前键盘桥不支持此快捷键；请使用单组 Ctrl/Alt/Shift 与字母、数字、F1–F12 或导航键。Tab 与单独 Esc 保留给界面。')
      return
    }
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
