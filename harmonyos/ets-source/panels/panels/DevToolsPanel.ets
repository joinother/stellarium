import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { SessionToolStore } from '../../state/SessionToolStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { PointingTestSection, WatchGyroSection } from '../astro/SessionToolSections'

// 开发测试面板：只放联调/诊断用的虚拟指星笔与手表陀螺仪模拟器。
// 入口在“更多功能”菜单末尾，并由 DEV_TOOLS_ENABLED 编译开关在正式发布时隐藏。
@Component
export struct DevToolsPanel {
  @ObjectLink sessionToolStore: SessionToolStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onPoint: () => void = () => {}
  onSend: () => void = () => {}
  onStart: () => void = () => {}
  onStop: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 4 }) {
      Text(I18n.t('more_dev_tools_desc'))
        .fontSize(11)
        .fontColor(this.c.sub)
        .width('100%')
        .padding({ left: 10, right: 10, top: 2, bottom: 4 })
      PointingTestSection({ store: this.sessionToolStore, onPoint: () => { this.onPoint() } })
      WatchGyroSection({
        store: this.sessionToolStore,
        onSend: () => { this.onSend() },
        onStart: () => { this.onStart() },
        onStop: () => { this.onStop() }
      })
    }
      .width('100%')
      .padding({ bottom: 12 })
  }
}
