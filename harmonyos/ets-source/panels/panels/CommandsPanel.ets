import { I18n } from '../../pages/I18n'
import { CommandCatalogEntry } from '../../pages/MainWindowModels'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { CommandStore } from '../../state/CommandStore'

// 统一命令控制面板，对应 `activePanel === 'commands'`。
//
// 命令目录 / 搜索框 / 名与 payload / 结果 / 待确认 / 执行中来自 CommandStore（@ObjectLink）；
// 输入与执行动作回调注入宿主；筛选助手 filteredCommandCatalog 为组件内纯计算。
// 输入底色用 inputColor：成员名须避开 CustomComponent 基类的 background 属性方法。

@Component
export struct CommandsPanel {
  @ObjectLink commandStore: CommandStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop inputColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onSearchTextChange: (value: string) => void = () => {}
  onNameInputChange: (value: string) => void = () => {}
  onPayloadInputChange: (value: string) => void = () => {}
  onSelectEntry: (item: CommandCatalogEntry) => void = () => {}
  onRefreshCatalog: () => void = () => {}
  onExecute: (force: boolean) => void = () => {}

  private filteredCommandCatalog(): Array<CommandCatalogEntry> {
    const query = this.commandStore.commandSearchText.trim().toLowerCase()
    if (query.length === 0) return this.commandStore.commandCatalog.slice(0, 40)
    return this.commandStore.commandCatalog.filter((item: CommandCatalogEntry) =>
      item.name.toLowerCase().includes(query) || item.category.includes(this.commandStore.commandSearchText.trim())).slice(0, 40)
  }

  build() {
    Column({ space: 7 }) {
      Text('统一命令控制').fontSize(13).fontColor(this.textColor).width('100%')
      Text('本机命令').fontSize(10).fontColor(this.subColor).width('100%')
      TextInput({ text: this.commandStore.commandSearchText, placeholder: '筛选命令或分类' })
        .height(34).fontSize(11).fontColor(this.textColor).placeholderColor(this.subColor)
        .backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL)
        .onChange((value: string) => { this.onSearchTextChange(value) })
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.filteredCommandCatalog(), (item: CommandCatalogEntry) => {
            Row({ space: 6 }) {
              Text(item.name).fontSize(11).fontColor(this.textColor).layoutWeight(1).maxLines(1)
              Text(item.category).fontSize(10).fontColor(this.subColor)
              if (item.requiresConfirmation) Text('需确认').fontSize(10).fontColor('#FFD38A')
            }
            .width('100%').height(29).padding({ left: 8, right: 8 })
            .backgroundColor(this.commandStore.commandNameInput === item.name ? 'rgba(91,147,191,0.25)' : this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).onClick(() => { this.onSelectEntry(item) })
          }, (item: CommandCatalogEntry) => item.name)
        }.width('100%')
      }.width('100%').height(160).scrollBar(BarState.Auto).scrollBarWidth(4)
      Row({ space: 6 }) {
        TextInput({ text: this.commandStore.commandNameInput, placeholder: '命令名，例如 getTimeInfo' })
          .height(34).fontSize(11).fontColor(this.textColor).placeholderColor(this.subColor)
          .backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL).layoutWeight(1)
          .onChange((value: string) => { this.onNameInputChange(value) })
        Button('刷新').fontSize(10).height(32).padding({ left: 8, right: 8 })
          .fontColor(this.textColor).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onRefreshCatalog() })
      }.width('100%')
      TextInput({ text: this.commandStore.commandPayloadInput, placeholder: 'payload（可留空；对象请填 JSON 字符串）' })
        .height(34).fontSize(11).fontColor(this.textColor).placeholderColor(this.subColor)
        .backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL)
        .onChange((value: string) => { this.onPayloadInputChange(value) })
      Row({ space: 6 }) {
        Button(this.commandStore.commandBusy ? '执行中…' : '执行命令').fontSize(11).height(32).padding({ left: 12, right: 12 })
          .fontColor(this.textColor).backgroundColor(this.accentColor).borderRadius(UI_RADIUS_CONTROL)
          .enabled(!this.commandStore.commandBusy && this.commandStore.commandPendingConfirmation.length === 0)
          .onClick(() => { this.onExecute(false) })
        if (this.commandStore.commandPendingConfirmation.length > 0) {
          Button('确认执行').fontSize(11).height(32).padding({ left: 12, right: 12 })
            .fontColor(this.textColor).backgroundColor('#9B6E39').borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onExecute(true) })
        }
      }.width('100%')
      if (this.commandStore.commandResultText.length > 0) {
        Scroll() {
          Text(this.commandStore.commandResultText).fontSize(10).fontColor(this.subColor).fontFamily('monospace').width('100%')
        }.width('100%').height(150).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).padding(8)
      }
    }.width('100%')
  }
}
