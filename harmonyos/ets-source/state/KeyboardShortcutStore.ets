import { KeyboardShortcutItem } from '../common/types/StellariumTypes'

// 键盘快捷键编辑域状态 store：持有动作列表、搜索词、选中项与其主/备快捷键草稿、加载标志。
// 消费方以 @ObjectLink 订阅；字段随桥回包与用户输入更新，宿主与组件的刷新语义不变。
@Observed
export class KeyboardShortcutStore {
  keyboardShortcuts: Array<KeyboardShortcutItem> = []
  keyboardShortcutQuery: string = ''
  keyboardShortcutSelectedId: string = ''
  keyboardShortcutPrimary: string = ''
  keyboardShortcutAlternate: string = ''
  keyboardShortcutsLoading: boolean = false
  skyKeyboardFocused: boolean = false
}
