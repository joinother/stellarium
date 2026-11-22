import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { SavedLocation } from '../../pages/StellariumTypes'
import { LocationStore } from '../../state/LocationStore'
import { SessionToolStore } from '../../state/SessionToolStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_MEDIA } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 位置面板的「已保存位置 / 最近使用」区。
//
// 已保存位置展示名称 + 坐标·天体，点击应用；长按进入重命名/删除管理。
// 最近使用由 LocationController 在成功应用观测点后写入。旧的硬编码
// “中国城市/世界城市”快捷 chip 已移除，推荐入口改为保存与最近使用。
@Component
export struct CityChipsRow {
  @ObjectLink store: LocationStore
  // 直接观察会话 store：面板打开后才异步加载的星球列表到达时，已保存行要随之刷新。
  @ObjectLink sessionToolStore: SessionToolStore
  @Prop observerPlanet: string = 'Earth'
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private actionKey: string = ''
  @State private renamingKey: string = ''
  @State private renameDraft: string = ''
  @State private renameError: string = ''
  onSaveCurrent: () => void = () => {}
  onApplyLocation: (name: string, lat: number, lon: number, alt: number, planet: string) => void = () => {}
  onDeleteLocation: (key: string) => void = () => {}
  // 已保存地点交给仿系统大弹窗（仅地球地点；外星地点没有外部地图）。
  onShareLocation: (name: string, lat: number, lon: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private coordinateLine(item: SavedLocation): string {
    // 与观测星球下拉共用同一本地化标签；SavedLocation.planet 仍保存英文名。
    return item.lat.toFixed(2) + '° / ' + item.lon.toFixed(2) + '° · ' + this.sessionToolStore.observerPlanetLabel(item.planet)
  }

  // 星球列表在面板打开后才异步加载，标签变化必须让 ForEach 重建该行；
  // 否则列表到达前渲染的英文名会一直保留。
  private rowKey(item: SavedLocation): string {
    return this.store.savedLocationKey(item) + '|' + this.sessionToolStore.observerPlanetLabel(item.planet)
  }

  private openActions(key: string): void {
    this.actionKey = key
    this.renamingKey = ''
    this.renameError = ''
  }

  private actionTarget(): SavedLocation | undefined {
    return this.store.savedLocations.find((s: SavedLocation) =>
      this.store.savedLocationKey(s) === this.actionKey)
  }

  private actionTargetIsEarth(): boolean {
    const target = this.actionTarget()
    return target !== undefined && target.planet === 'Earth'
  }

  // 已保存地点直接打开仿系统大弹窗；地点目标在点按时读取，随后关闭管理行。
  private shareForAction(): void {
    const target = this.actionTarget()
    this.actionKey = ''
    if (target !== undefined) this.onShareLocation(target.name, target.lat, target.lon)
  }

  private startRename(item: SavedLocation, key: string): void {
    this.actionKey = key
    this.renamingKey = key
    this.renameDraft = item.name
    this.renameError = ''
  }

  private confirmRename(key: string): void {
    if (this.store.renameSavedLocation(key, this.renameDraft)) {
      this.renamingKey = ''
      this.actionKey = ''
      this.renameError = ''
    } else {
      this.renameError = I18n.t('loc_rename_failed')
    }
  }

  private confirmDelete(item: SavedLocation, key: string): void {
    this.getUIContext().showAlertDialog({
      title: I18n.t('loc_delete'),
      message: I18n.t('loc_delete_confirm').replace('%s', item.name),
      primaryButton: { value: I18n.t('loc_cancel'), action: () => {} },
      secondaryButton: {
        value: I18n.t('loc_delete'),
        fontColor: this.c.errorText,
        action: () => {
          this.onDeleteLocation(key)
          this.actionKey = ''
          this.renamingKey = ''
        }
      }
    })
  }

  @Builder
  savedRow(item: SavedLocation) {
    Row({ space: 8 }) {
      Column({ space: 1 }) {
        Text(item.name)
          .fontSize(12)
          .fontColor(this.c.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.coordinateLine(item))
          .fontSize(9)
          .fontColor(this.c.tertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(16)
        .fontColor(this.c.tertiary)
    }
      .width('100%')
      .height(46)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.c.softStrong)
      .border({ width: 1, color: this.c.softStrong })
      .borderRadius(UI_RADIUS_CONTROL)
      .accessibilityText(I18n.t('loc_saved_locations') + ': ' + item.name)
      .onClick(() => {
        this.actionKey = ''
        this.onApplyLocation(item.name, item.lat, item.lon, item.alt, item.planet)
      })
      .gesture(LongPressGesture().onAction(() => { this.openActions(this.store.savedLocationKey(item)) }))
  }

  @Builder
  recentChip(item: SavedLocation) {
    Column({ space: 1 }) {
      Text(item.name)
        .fontSize(10)
        .fontColor(this.c.sub)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.coordinateLine(item))
        .fontSize(9)
        .fontColor(this.c.tertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
      .height(38)
      .padding({ left: 9, right: 9 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.c.soft)
      .border({ width: 1, color: this.c.soft })
      .borderRadius(UI_RADIUS_CONTROL)
      .onClick(() => { this.onApplyLocation(item.name, item.lat, item.lon, item.alt, item.planet) })
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(I18n.t('loc_saved_locations'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.text)
        Text(this.store.savedLocations.length.toString())
          .fontSize(9)
          .fontColor(this.c.sub)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .backgroundColor(this.c.softStrong)
          .borderRadius(UI_RADIUS_MEDIA)
        Blank()
        Button(I18n.t('loc_save_current'))
          .fontSize(10).fontColor(this.c.tertiary)
          .height(26).padding({ left: 8, right: 8 })
          .backgroundColor(this.c.soft)
          .border({ width: 1, color: this.c.softStrong })
          .borderRadius(UI_RADIUS_CONTROL)
          .onClick(() => { this.onSaveCurrent() })
      }
      .width('100%')

      if (this.store.savedLocations.length === 0) {
        Text(I18n.t('loc_no_saved')).fontSize(10).fontColor(this.c.tertiary).width('100%').padding({ left: 2 })
      } else {
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.store.savedLocations, (s: SavedLocation) => {
              this.savedRow(s)
            }, (s: SavedLocation) => this.rowKey(s))
          }
          .width('100%')
          .padding({ right: 2 })
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .width('100%')
        .height(Math.min(this.store.savedLocations.length * 52, 168))
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.actionKey !== '') {
        Column({ space: 4 }) {
          if (this.renamingKey === this.actionKey) {
            Row({ space: 6 }) {
              TextInput({ text: this.renameDraft, placeholder: I18n.t('loc_rename_hint') })
                .height(34).fontSize(12).layoutWeight(1)
                .backgroundColor(this.c.input)
                .fontColor(this.c.text)
                .border({ width: 1, color: this.c.inputBorder })
                .borderRadius(UI_RADIUS_CONTROL)
                .onChange((value: string) => { this.renameDraft = value })
                .onSubmit(() => { this.confirmRename(this.actionKey) })
              Button(I18n.t('loc_confirm'))
                .fontSize(11).height(32).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.confirmRename(this.actionKey) })
              Button(I18n.t('loc_cancel'))
                .fontSize(11).height(32).fontColor(this.c.text).backgroundColor(this.c.bg)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.renamingKey = ''; this.renameError = '' })
            }.width('100%')
            if (this.renameError.length > 0) {
              Text(this.renameError).fontSize(10).fontColor(this.c.errorText).width('100%')
            }
          } else {
            Row({ space: 6 }) {
              // 四个按钮在地球地点行会占满宽度，说明文字让位给操作本身。
              Blank()
              if (this.actionTargetIsEarth()) {
                Button(I18n.t('loc_map_actions'))
                  .fontSize(10).height(28).fontColor(this.c.text).backgroundColor(this.c.softStrong)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .id('loc-open-map-saved')
                  .onClick(() => { this.shareForAction() })
              }
              Button(I18n.t('loc_rename'))
                .fontSize(10).height(28).fontColor(this.c.text).backgroundColor(this.c.softStrong)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => {
                  const target = this.store.savedLocations.find((s: SavedLocation) =>
                    this.store.savedLocationKey(s) === this.actionKey)
                  if (target !== undefined) this.startRename(target, this.actionKey)
                })
              Button(I18n.t('loc_delete'))
                .fontSize(10).height(28).fontColor(this.c.errorText).backgroundColor(this.c.softStrong)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => {
                  const target = this.store.savedLocations.find((s: SavedLocation) =>
                    this.store.savedLocationKey(s) === this.actionKey)
                  if (target !== undefined) this.confirmDelete(target, this.actionKey)
                })
              Button(I18n.t('loc_cancel'))
                .fontSize(10).height(28).fontColor(this.c.sub).backgroundColor(this.c.bg)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.actionKey = ''; this.renameError = '' })
            }.width('100%')
          }
        }
          .width('100%')
          .padding({ left: 2, right: 2, top: 2, bottom: 2 })
      }

      if (this.store.recentLocations.length > 0) {
        Row({ space: 6 }) {
          Row().width(2).height(12).backgroundColor(this.c.accent).borderRadius(1)
          Text(I18n.t('loc_recent')).fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.c.sub)
        }
          .width('100%')
          .margin({ top: 6 })
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.store.recentLocations, (s: SavedLocation) => {
              this.recentChip(s)
            }, (s: SavedLocation) => 'recent|' + this.rowKey(s))
          }
          .padding({ left: 2, right: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
    }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .backgroundColor(this.c.soft)
      .border({ width: 1, color: this.c.softStrong })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 2, bottom: 6 })
  }
}
