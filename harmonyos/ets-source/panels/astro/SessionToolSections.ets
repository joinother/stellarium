import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { TonightPlanetRow } from '../../pages/MainWindowModels'
import { SessionToolStore } from '../../state/SessionToolStore'

// 会话/观测工具区块。
//
// 滑块/输入/结果文案由 store + @Prop 驱动实时刷新。
// 引擎与桥依赖仍在宿主，以回调解入。

// 观测星球：可站立星球标签网格 + 回到地球。
@Component
export struct ObserverPlanetSection {
  @ObjectLink store: SessionToolStore
  @Prop textColor: string
  @Prop borderTint: string
  planetLabel: (en: string) => string = (en: string) => en
  onSelectPlanet: (name: string) => void = () => {}

  build() {
    Column({ space: 8 }) {
      Text(I18n.t('c_observing_planet')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_planet_switch_hint')).fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      Text(I18n.t('m_current_planet') + '：' + this.planetLabel(this.store.observerPlanet)).fontSize(12).fontColor('#E5FFFFFF').width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.store.planetList, (p: string) => {
          Button(this.planetLabel(p))
            .fontSize(12)
            .fontColor(this.store.observerPlanet === p ? '#FFFFFF' : '#CCFFFFFF')
            .backgroundColor(this.store.observerPlanet === p ? '#5B93BF' : this.borderTint)
            .borderRadius(UI_RADIUS_PILL)
            .height(32)
            .margin({ right: 8, bottom: 8 })
            .padding({ left: 14, right: 14 })
            .onClick(() => { this.onSelectPlanet(p) })
        }, (p: string) => p)
      }.width('100%')
      Button(I18n.t('btn_back_to_earth'))
        .fontSize(13).fontColor('#FFFFFF').backgroundColor('#2E7D32')
        .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%').margin({ top: 6 })
        .onClick(() => { this.onSelectPlanet('Earth') })
    }.width('100%').padding({ left: 10, right: 10 })
  }
}

// 虚拟指星笔（多设备联动）目标端测试入口：输入高度角/方位角，调 pointAtSky。
@Component
export struct PointingTestSection {
  @ObjectLink store: SessionToolStore
  @Prop textColor: string
  @Prop borderTint: string
  onPoint: () => void = () => {}

  build() {
    Column({ space: 8 }) {
      Text(I18n.t('c_pointing_test')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_pointing_test_desc')).fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      Row({ space: 4 }) {
        TextInput({ text: this.store.pointAlt, placeholder: I18n.t('c_altitude_deg') })
          .width('50%').height(36).backgroundColor(this.borderTint).fontSize(13)
          .onChange((v: string) => { this.store.pointAlt = v })
        TextInput({ text: this.store.pointAz, placeholder: I18n.t('c_azimuth_deg') })
          .width('50%').height(36).backgroundColor(this.borderTint).fontSize(13)
          .onChange((v: string) => { this.store.pointAz = v })
      }.width('100%')
      // 把结果放在按钮上方，避免被 Scroll 底部遮挡而看不到即时反馈
      if (this.store.pointResult !== '') {
        Text(this.store.pointResult).fontSize(12).fontColor('#CCFFCC').width('100%').margin({ top: 2 })
      }
      Row({ space: 4 }) {
        Button(I18n.t('btn_point_select'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#5B93BF')
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .onClick(() => { this.onPoint() })
        Button(I18n.t('btn_example_zenith'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.borderTint)
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .onClick(() => { this.store.pointAlt = '89'; this.store.pointAz = '180'; this.onPoint() })
      }.width('100%').margin({ top: 4 })
    }.width('100%').padding({ left: 10, right: 10 })
  }
}

// 虚拟指星笔 —— 手表当陀螺仪（发射端模拟）：两个滑块模拟手腕转动。
@Component
export struct WatchGyroSection {
  @ObjectLink store: SessionToolStore
  @Prop textColor: string
  onSend: () => void = () => {}
  onStart: () => void = () => {}
  onStop: () => void = () => {}

  build() {
    Column({ space: 8 }) {
      Text(I18n.t('c_watch_gyro_sim')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_watch_gyro_desc'))
        .fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      if (this.store.watchResult !== '') {
        Text(this.store.watchResult).fontSize(12).fontColor(this.store.watchTracking ? '#FFE08A' : '#CCFFCC').width('100%').margin({ top: 2, bottom: 2 })
      }
      Row({ space: 10 }) {
        Text(I18n.t('c_altitude')).fontSize(11).fontColor('#CCCCCC').width(48)
        Slider({ value: this.store.watchAlt, min: 0, max: 90, step: 1 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .onChange((v: number) => { this.store.watchAlt = v; this.onSend() })
      }.width('100%')
      Row({ space: 10 }) {
        Text(I18n.t('c_azimuth')).fontSize(11).fontColor('#CCCCCC').width(48)
        Slider({ value: this.store.watchAz, min: 0, max: 360, step: 1 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .onChange((v: number) => { this.store.watchAz = v; this.onSend() })
      }.width('100%')
      Row({ space: 4 }) {
        Button(this.store.watchTracking ? '指向中…' : '开始指向(跟踪)')
          .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.store.watchTracking ? '#C08020' : '#5B93BF')
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .onClick(() => { this.onStart() })
        Button(I18n.t('btn_stop_lock'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#3A6EA5')
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .onClick(() => { this.onStop() })
      }.width('100%').margin({ top: 4 })
    }.width('100%').padding({ left: 10, right: 10 })
  }
}

// 今晚天象单卡片：标题 + 若干行文本，可点按跳转到对应时刻/对象。
@Component
export struct TonightCard {
  @Prop title: string
  @Prop lines: string[]
  @Prop jd: number = 0
  @Prop lock: string = ''
  onJump: (jd: number, lock: string, title: string) => void = () => {}

  build() {
    Column({ space: 4 }) {
      Text(this.title).fontSize(12).fontColor('#FFE9B0').width('100%')
      ForEach(this.lines, (ln: string) => {
        Text(ln).fontSize(11).fontColor('#DDDDDD').width('100%')
      }, (ln: string) => ln)
    }.width('100%').padding(8).backgroundColor('#1A2330').borderRadius(UI_RADIUS_CONTROL).margin({ top: 4 })
      .stateStyles({
        pressed: { backgroundColor: '#27384A' }
      })
      .onClick(() => {
        if (this.jd > 0 && this.lock !== '') {
          this.onJump(this.jd, this.lock, this.title)
        }
      })
  }
}

// 今晚天象区块：刷新按钮 + 月相/日落后窗/行星/流星雨/卫星卡片。
@Component
export struct TonightEventsSection {
  @ObjectLink store: SessionToolStore
  @Prop textColor: string
  onRefresh: () => void = () => {}
  onJump: (jd: number, lock: string, title: string) => void = () => {}

  build() {
    Column({ space: 8 }) {
      Text(I18n.t('c_tonight_events')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_tonight_events_hint'))
        .fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      Button(I18n.t('btn_refresh_tonight'))
        .fontSize(13).fontColor('#FFFFFF').backgroundColor('#5B93BF')
        .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%')
        .onClick(() => { this.onRefresh() })
      if (this.store.tonightHint !== '') {
        Text(this.store.tonightHint).fontSize(12).fontColor('#CCFFCC').width('100%').margin({ top: 2, bottom: 2 })
      }
      if (this.store.tonightDate !== '') {
        TonightCard({ title: I18n.t('tn_moon_phase'), lines: [this.store.tonightMoon], jd: this.store.tonightMoonJd, lock: 'Moon', onJump: this.onJump })
        TonightCard({ title: I18n.t('tn_sun_dark_window'), lines: [this.store.tonightSun, this.store.tonightDark], jd: this.store.tonightSunJd, lock: 'Moon', onJump: this.onJump })
        ForEach(this.store.tonightPlanetRows, (row: TonightPlanetRow) => {
          TonightCard({ title: row.name, lines: [row.line], jd: row.jd, lock: row.lock, onJump: this.onJump })
        }, (row: TonightPlanetRow) => row.name)
        if (this.store.tonightShowers.length > 0) TonightCard({ title: I18n.t('tn_active_showers'), lines: this.store.tonightShowers, jd: this.store.tonightShowerJd, lock: 'Moon', onJump: this.onJump })
        TonightCard({ title: I18n.t('tn_satellites'), lines: [this.store.tonightSats], onJump: this.onJump })
      }
    }.width('100%').padding({ left: 10, right: 10 })
  }
}
