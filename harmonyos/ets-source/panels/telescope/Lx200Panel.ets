import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { LX200_DEVICE_MODELS, TelescopeProfile } from '../../pages/MainWindowModels'
import { TelescopeStore } from '../../state/TelescopeStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PANEL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 「望远镜控制」面板主体。
//
// 组件只收一个 store 与一批回调：
//   - 全部 lx200* 展示与编辑状态（设备预设、协议、主机/端口、等分点、命令延迟、视场圆、
//     目标来源、忙/新增标志、连接状态、实时位置）走 @ObjectLink store（TelescopeStore），实时刷新；
//   - 文本/档位/滑块的写回直接落到 store 字段；
//   - 原生桥与轮询（保存/删除/测试连接、GoTo/同步/中止、读取位置、实时位置开关、编辑器校验）
//     留在宿主，以回调注入；
//
// 视觉：设备预设横向 Scroll 高 38、协议/等分点/目标来源分段按钮高 32、
// 命令延迟 Slider 0–2000 步长 50、视场圆输入框高 38、保存/删除/测试按钮高 34、
// 位置按钮高 34、实时位置开关行与状态卡、忙时 LoadingProgress 16×16。
@Component
export struct Lx200Panel {
  @ObjectLink store: TelescopeStore
  @State c: ThemeSlots = DEFAULT_SLOTS
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

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 2 }) {
          Text(I18n.t('m_telescope_devices')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.text)
          Text(I18n.t('m_telescope_devices_hint')).fontSize(10).fontColor(this.c.sub).maxLines(2)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('+')
          .fontSize(20).fontColor(this.c.onAccent).textAlign(TextAlign.Center)
          .width(34).height(34).backgroundColor(this.c.accent).borderRadius(UI_RADIUS_PILL)
          .onClick(() => { this.onBeginNew() })
      }.width('100%')

      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.store.lx200Profiles, (profile: TelescopeProfile) => {
            Row({ space: 6 }) {
              Text(profile.slot.toString()).fontSize(10).fontWeight(FontWeight.Bold)
                .fontColor(profile.slot === this.store.lx200SelectedSlot ? this.c.onAccent : this.c.sub)
              Text(profile.name).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(profile.slot === this.store.lx200SelectedSlot ? this.c.onAccent : this.c.text)
            }
              .height(34).padding({ left: 10, right: 12 })
              .backgroundColor(profile.slot === this.store.lx200SelectedSlot && !this.store.lx200EditingNew ? this.c.accent : this.c.bg)
              .border({ width: 1, color: profile.slot === this.store.lx200SelectedSlot && !this.store.lx200EditingNew ? this.c.accent : this.c.border })
              .borderRadius(UI_RADIUS_PILL)
              .animation({ duration: 160, curve: Curve.EaseOut })
              .onClick(() => { this.onSelectProfile(profile.slot) })
          }, (profile: TelescopeProfile) => profile.slot.toString())
        }.padding({ left: 1, right: 1 })
      }.width('100%').height(38).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

      Column({ space: 8 }) {
        Row() {
          Text(I18n.format('m_telescope_slot_title', [this.store.lx200SelectedSlot.toString()]))
            .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
          Text(this.store.lx200EditingNew ? I18n.t('m_telescope_unsaved') : I18n.t('m_telescope_saved_profile'))
            .fontSize(10).fontColor(this.store.lx200EditingNew ? this.c.warning : this.c.success)
        }.width('100%')
        TextInput({ text: this.store.lx200Name, placeholder: I18n.t('m_telescope_name') })
          .height(38).fontSize(13).fontColor(this.c.text).placeholderColor(this.c.sub)
          .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
          .onChange((value: string) => { this.store.lx200Name = value })
        Row({ space: 8 }) {
          Text(I18n.t('m_telescope_protocol_simulated')).fontSize(10).textAlign(TextAlign.Center)
            .fontColor(this.store.lx200Protocol === 'simulated' ? this.c.onAccent : this.c.sub).height(32).layoutWeight(1).padding({ top: 7 })
            .backgroundColor(this.store.lx200Protocol === 'simulated' ? this.c.accent : this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSelectProtocol('simulated') })
          Text(I18n.t('m_telescope_protocol_lx200_tcp')).fontSize(10).textAlign(TextAlign.Center)
            .fontColor(this.store.lx200Protocol === 'lx200_tcp' ? this.c.onAccent : this.c.sub).height(32).layoutWeight(1).padding({ top: 7 })
            .backgroundColor(this.store.lx200Protocol === 'lx200_tcp' ? this.c.accent : this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSelectProtocol('lx200_tcp') })
        }.width('100%')
        if (this.store.lx200Protocol === 'lx200_tcp') {
          Row({ space: 8 }) {
            TextInput({ text: this.store.lx200Host, placeholder: I18n.t('i0064') })
              .height(38).fontSize(13).fontColor(this.c.text).placeholderColor(this.c.sub).layoutWeight(1)
              .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
              .onChange((value: string) => { this.store.lx200Host = value; this.onValidateEditor() })
            TextInput({ text: this.store.lx200Port, placeholder: I18n.t('i0065') })
              .width(100).height(38).fontSize(13).fontColor(this.c.text).placeholderColor(this.c.sub)
              .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
              .onChange((value: string) => { this.store.lx200Port = value; this.onValidateEditor() })
          }.width('100%')
        } else {
          Text(I18n.t('m_telescope_simulator_hint')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(3)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        }
        Row({ space: 6 }) {
          Text(this.store.lx200Transport).fontSize(10).fontColor(this.c.tertiary)
          Text('·').fontSize(10).fontColor(this.c.detailSub)
          Text(this.store.lx200Scope).fontSize(10).fontColor(this.store.lx200Scope === I18n.t('m_telescope_scope_blocked') ? this.c.errorText : this.c.tertiary)
          Text('·').fontSize(10).fontColor(this.c.detailSub)
          Text(this.store.lx200ConnectionState === 'available' ? I18n.t('m_telescope_state_available') :
            (this.store.lx200ConnectionState === 'unavailable' ? I18n.t('m_telescope_state_unavailable') : I18n.t('m_telescope_state_not_tested')))
            .fontSize(10).fontColor(this.store.lx200ConnectionState === 'available' ? this.c.success :
              (this.store.lx200ConnectionState === 'unavailable' ? this.c.errorText : this.c.warning))
        }.width('100%')

        Row() {
          Column({ space: 2 }) {
            Text(I18n.t('m_telescope_device_model')).fontSize(10).fontColor(this.c.sub)
            Text(this.store.lx200DeviceModel).fontSize(12).fontColor(this.c.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text(this.store.lx200Protocol === 'simulated' ? I18n.t('m_telescope_offline_badge') : 'LX200').fontSize(10).fontColor(this.c.tertiary).padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_PILL)
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        if (this.store.lx200Protocol === 'lx200_tcp') {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(LX200_DEVICE_MODELS, (model: string) => {
                Text(model).fontSize(10).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor(this.store.lx200DeviceModel === model ? this.c.onAccent : this.c.sub)
                  .height(30).padding({ left: 10, right: 10, top: 7 })
                  .backgroundColor(this.store.lx200DeviceModel === model ? this.c.accent : this.c.bg)
                  .borderRadius(UI_RADIUS_PILL)
                  .onClick(() => { this.store.lx200DeviceModel = model })
              }, (model: string) => model)
            }.padding({ left: 1, right: 1 })
          }.width('100%').height(32).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }

        Row({ space: 6 }) {
          Text(I18n.t('m_telescope_coordinate_epoch')).fontSize(11).fontColor(this.c.sub).layoutWeight(1)
          ForEach(['J2000', 'JNow'], (epoch: string) => {
            Text(epoch).fontSize(10).fontColor(this.store.lx200Equinox === epoch ? this.c.onAccent : this.c.sub)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.store.lx200Equinox === epoch ? this.c.accent : this.c.bg).borderRadius(UI_RADIUS_PILL)
              .onClick(() => { this.store.lx200Equinox = epoch })
          }, (epoch: string) => epoch)
        }.width('100%')

        if (this.store.lx200Protocol === 'lx200_tcp') {
          Column({ space: 4 }) {
            Row() {
              Text(I18n.t('m_telescope_command_delay')).fontSize(11).fontColor(this.c.sub).layoutWeight(1)
              Text(this.store.lx200CommandDelayMs.toString() + ' ms').fontSize(10).fontColor(this.c.text)
            }.width('100%')
            Slider({ value: this.store.lx200CommandDelayMs, min: 0, max: 2000, step: 50, style: SliderStyle.OutSet })
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
              .width('100%').trackColor(this.c.bg)
              .onChange((value: number) => { this.store.lx200CommandDelayMs = Math.round(value) })
          }.width('100%')
        }

        TextInput({ text: this.store.lx200Circles, placeholder: I18n.t('m_telescope_fov_circles') })
          .height(38).fontSize(12).fontColor(this.c.text).placeholderColor(this.c.sub)
          .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
          .onChange((value: string) => { this.store.lx200Circles = value })
        Text(I18n.t('m_telescope_fov_hint')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)

        Row({ space: 8 }) {
          Button(I18n.t('m_telescope_save')).fontSize(11).fontColor(this.c.onAccent).height(34).layoutWeight(1)
            .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL).enabled(!this.store.lx200Busy)
            .onClick(() => { this.onSave() })
          Button(this.store.lx200EditingNew ? I18n.t('m_telescope_cancel') : I18n.t('m_telescope_delete'))
            .fontSize(11).fontColor(this.c.errorText).height(34).layoutWeight(1)
            .backgroundColor(this.c.errorBg).borderRadius(UI_RADIUS_CONTROL)
            .enabled(!this.store.lx200Busy && (this.store.lx200EditingNew || this.store.lx200Profiles.length > 1))
            .onClick(() => { this.onDelete() })
          Button(I18n.t('m_telescope_test')).fontSize(11).fontColor(this.c.text).height(34).layoutWeight(1)
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).enabled(!this.store.lx200Busy && !this.store.lx200EditingNew)
            .onClick(() => { this.onTest() })
        }.width('100%')
      }.width('100%').padding(12).backgroundColor(this.c.dividerSoft).borderRadius(UI_RADIUS_PANEL)

      Column({ space: 8 }) {
        Text(I18n.t('m_telescope_target_source')).fontSize(11).fontColor(this.c.sub).width('100%')
        Row({ space: 8 }) {
          Text(I18n.t('m_telescope_selected_target')).fontSize(11)
            .fontColor(this.store.lx200TargetSource === 'selected' ? this.c.onAccent : this.c.sub).textAlign(TextAlign.Center)
            .height(32).layoutWeight(1).padding({ top: 7 })
            .backgroundColor(this.store.lx200TargetSource === 'selected' ? this.c.accent : this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.store.lx200TargetSource = 'selected' })
          Text(I18n.t('m_telescope_screen_center')).fontSize(11)
            .fontColor(this.store.lx200TargetSource === 'screen_center' ? this.c.onAccent : this.c.sub).textAlign(TextAlign.Center)
            .height(32).layoutWeight(1).padding({ top: 7 })
            .backgroundColor(this.store.lx200TargetSource === 'screen_center' ? this.c.accent : this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.store.lx200TargetSource = 'screen_center' })
        }.width('100%')
        Row({ space: 8 }) {
          Button(I18n.t('i0049')).height(34).fontSize(11).fontColor(this.c.onAccent).layoutWeight(1)
            .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_PILL).enabled(!this.store.lx200Busy && !this.store.lx200EditingNew)
            .onClick(() => { this.onGoto() })
          Button(I18n.t('i0050')).height(34).fontSize(11).fontColor(this.c.tertiary).layoutWeight(1)
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_PILL).enabled(!this.store.lx200Busy && !this.store.lx200EditingNew)
            .onClick(() => { this.onSync() })
          Button(I18n.t('i0051')).height(34).fontSize(11).fontColor(this.c.errorText).layoutWeight(1)
            .backgroundColor(this.c.errorBg).borderRadius(UI_RADIUS_PILL).enabled(!this.store.lx200Busy && !this.store.lx200EditingNew)
            .onClick(() => { this.onAbort() })
        }.width('100%')
        Row({ space: 8 }) {
          Button(I18n.t('m_telescope_read_position')).height(34).fontSize(10).fontColor(this.c.text).layoutWeight(1)
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).enabled(!this.store.lx200Busy && !this.store.lx200EditingNew)
            .onClick(() => { this.onReadPosition(false) })
          Button(I18n.t('m_telescope_center_on_scope')).height(34).fontSize(10).fontColor(this.c.tertiary).layoutWeight(1)
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).enabled(!this.store.lx200Busy && !this.store.lx200EditingNew)
            .onClick(() => { this.onReadPosition(true) })
        }.width('100%')
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(I18n.t('m_telescope_live_position')).fontSize(11).fontColor(this.c.text)
            Text(I18n.t('m_telescope_live_position_hint')).fontSize(10).fontColor(this.c.sub).maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.store.lx200LivePositionEnabled })
            .enabled(!this.store.lx200EditingNew)
            .onChange((enabled: boolean) => { this.onSetLivePosition(enabled) })
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        if (this.store.lx200Position.length > 0) {
          Column({ space: 3 }) {
            Text(this.store.lx200Position).fontSize(11).fontColor(this.c.tertiary).width('100%').textAlign(TextAlign.Center)
            Text(this.store.lx200PositionUpdateState === 'error' ? I18n.t('m_telescope_live_failed') :
              (this.store.lx200PositionUpdateState === 'stale' ? I18n.format('m_telescope_live_stale', [this.store.lx200PositionUpdatedAt]) :
                (this.store.lx200PositionUpdateState === 'updating' ? I18n.t('m_telescope_live_updating') :
                  I18n.format('m_telescope_live_updated', [this.store.lx200PositionUpdatedAt]))))
              .fontSize(10).fontColor(this.store.lx200PositionUpdateState === 'error' ? this.c.errorText : this.c.sub)
          }.width('100%').padding({ top: 6, bottom: 6 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        }
        Row({ space: 8 }) {
          if (this.store.lx200Busy) {
            LoadingProgress().width(16).height(16).color(this.c.accent)
          }
          Text(this.store.lx200Status).fontSize(10).fontColor(this.c.sub).layoutWeight(1).maxLines(3)
        }.width('100%').height(30)
      }.width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_PANEL)

      Text(I18n.t('m_telescope_unavailable_protocols')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(3)
      Text(I18n.t('m_telescope_connection_lifecycle')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(3)
    }
      .width('100%')
      .margin({ top: 8, bottom: 8 })
  }
}
