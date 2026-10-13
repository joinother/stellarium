// 目镜（Oculars）/ 拼接相机 / 均时差 / 古天文线写回行为控制器。
//
// 各方法均为「store 写 → 桥调用 → store.load」薄包装，无定时器、无跨域依赖。
// 不 import NAPI/UI：桥经 CommandPort；状态整体写回
// TelescopeStore / MosaicStore / EquationOfTimeStore / ArchaeoStore（面板经 @ObjectLink 消费）。
// 逐帧/草稿字段 equationOfTimeMutationId / archaeoMutationId 由控制器自持。
// 本控制器无 UI 提示（各方法均不调 flashHint），故无 hooks 注入。
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { OcularModeResponse } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'
import { TelescopeStore } from '../state/TelescopeStore'
import { MosaicStore } from '../state/MosaicStore'
import { EquationOfTimeStore } from '../state/EquationOfTimeStore'
import { ArchaeoStore } from '../state/ArchaeoStore'

export class OcularController {
  private port: CommandPort
  private telescopeStore: TelescopeStore
  private mosaicStore: MosaicStore
  private equationOfTimeStore: EquationOfTimeStore
  private archaeoStore: ArchaeoStore
  // 乐观回滚代际（草稿字段由控制器自持）。
  private equationOfTimeMutationId: number = 0
  private archaeoMutationId: number = 0

  constructor(port: CommandPort, telescopeStore: TelescopeStore, mosaicStore: MosaicStore,
    equationOfTimeStore: EquationOfTimeStore, archaeoStore: ArchaeoStore) {
    this.port = port
    this.telescopeStore = telescopeStore
    this.mosaicStore = mosaicStore
    this.equationOfTimeStore = equationOfTimeStore
    this.archaeoStore = archaeoStore
  }

  // 目镜总开关写回（乐观写 store → 桥 → 以回包 applied 修正 → loadOculars）。
  setOcularMode(v: boolean): void {
    this.telescopeStore.ocularMode = v
    this.port.requestWhenReady('setOcularMode', v ? '1' : '0', (r: StellariumBridgeResponse) => {
      const response = r as OcularModeResponse
      this.telescopeStore.ocularMode = response.applied === true
      if (v && response.selectionRequired === true) {
        this.telescopeStore.ocularStatusMessage = I18n.t('ocular_status_select_target')
      }
      this.telescopeStore.loadOculars(false)
    })
  }

  // 拼接相机设置写回（防重入 + 同值短路 + 交互命令，回包后 loadMosaicCamera）。
  setMosaicCamera(setting: string, value: string = ''): void {
    if (this.mosaicStore.mosaicCameraPending || this.mosaicStore.mosaicCameraLoading) return
    if (setting === 'enabled' && (value === '1') === this.mosaicStore.mosaicCameraEnabled) return
    if (setting === 'visible' && (value === '1') === this.mosaicStore.mosaicCameraVisible) return
    if (setting === 'camera' && value === this.mosaicStore.mosaicCameraCurrent) return
    this.mosaicStore.mosaicCameraPending = true
    this.port.requestInteractive('setMosaicCamera', setting + (value.length > 0 ? '|' + value : ''), (result: StellariumBridgeResponse) => {
      if (result.ok !== true) {
        this.mosaicStore.mosaicCameraPending = false
        this.mosaicStore.mosaicCameraStatus = result.error ?? I18n.t('plugin_action_failed')
        return
      }
      this.mosaicStore.loadMosaicCamera(false)
    }, () => {
      this.mosaicStore.mosaicCameraPending = false
      this.mosaicStore.mosaicCameraStatus = I18n.t('plugin_action_failed')
    })
  }

  // 均时差开关写回（乐观写 store + mutationId 代际防抖回滚）。
  setEquationOfTime(setting: string, enabled: boolean): void {
    const mutationId = ++this.equationOfTimeMutationId
    let previous: boolean | undefined
    if (setting === 'enabled') { previous = this.equationOfTimeStore.equationOfTimeEnabled; this.equationOfTimeStore.equationOfTimeEnabled = enabled }
    else if (setting === 'msFormat') { previous = this.equationOfTimeStore.equationOfTimeMsFormat; this.equationOfTimeStore.equationOfTimeMsFormat = enabled }
    else if (setting === 'inverted') { previous = this.equationOfTimeStore.equationOfTimeInverted; this.equationOfTimeStore.equationOfTimeInverted = enabled }
    else if (setting === 'enableAtStartup') { previous = this.equationOfTimeStore.equationOfTimeStartup; this.equationOfTimeStore.equationOfTimeStartup = enabled }
    this.equationOfTimeStore.equationOfTimeStatus = ''
    this.port.requestInteractive('setEquationOfTime', setting + '|' + (enabled ? '1' : '0'), () => {}, () => {
      if (mutationId !== this.equationOfTimeMutationId) return
      if (previous !== undefined) {
        if (setting === 'enabled') this.equationOfTimeStore.equationOfTimeEnabled = previous
        else if (setting === 'msFormat') this.equationOfTimeStore.equationOfTimeMsFormat = previous
        else if (setting === 'inverted') this.equationOfTimeStore.equationOfTimeInverted = previous
        else if (setting === 'enableAtStartup') this.equationOfTimeStore.equationOfTimeStartup = previous
      }
      this.equationOfTimeStore.equationOfTimeStatus = I18n.t('plugin_action_failed')
    })
  }

  // 古天文线设置写回（读旧值 → 立即应用新值 → 失败按代际回滚）。
  setArchaeoLineSetting(setting: string, value: string): void {
    const mutationId = ++this.archaeoMutationId
    const previous = this.archaeoStore.archaeoLineSettingValue(setting)
    this.applyArchaeoLineSetting(setting, value)
    this.archaeoStore.archaeoStatus = ''
    this.port.requestInteractive('setArchaeoLineSetting', setting + '|' + value, () => {}, () => {
      if (mutationId !== this.archaeoMutationId) return
      this.applyArchaeoLineSetting(setting, previous)
      this.archaeoStore.archaeoStatus = I18n.t('plugin_action_failed')
    })
  }

  // 把 CLI 取值写入 ArchaeoStore 对应字段（只被本控制器 setArchaeoLineSetting 调用）。
  private applyArchaeoLineSetting(setting: string, value: string): void {
    const enabled = value === '1' || value === 'true'
    switch (setting) {
      case 'enabled': this.archaeoStore.archaeoLinesEnabled = enabled; break
      case 'equinox': this.archaeoStore.archaeoEquinox = enabled; break
      case 'solstices': this.archaeoStore.archaeoSolstices = enabled; break
      case 'crossquarters': this.archaeoStore.archaeoCrossquarters = enabled; break
      case 'majorStandstills': this.archaeoStore.archaeoMajorStandstills = enabled; break
      case 'minorStandstills': this.archaeoStore.archaeoMinorStandstills = enabled; break
      case 'polarCircles': this.archaeoStore.archaeoPolarCircles = enabled; break
      case 'zenithPassage': this.archaeoStore.archaeoZenithPassage = enabled; break
      case 'nadirPassage': this.archaeoStore.archaeoNadirPassage = enabled; break
      case 'selectedObject': this.archaeoStore.archaeoSelectedObject = enabled; break
      case 'selectedObjectAzimuth': this.archaeoStore.archaeoSelectedObjectAzimuth = enabled; break
      case 'selectedObjectHourAngle': this.archaeoStore.archaeoSelectedObjectHourAngle = enabled; break
      case 'currentSun': this.archaeoStore.archaeoCurrentSun = enabled; break
      case 'currentMoon': this.archaeoStore.archaeoCurrentMoon = enabled; break
      case 'currentPlanet': this.archaeoStore.archaeoCurrentPlanet = ['none', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn'].indexOf(value); break
      case 'lineWidth': this.archaeoStore.archaeoLineWidth = Math.round(Number(value)); break
    }
  }

  // 三个目镜叠层开关写回（乐观写 store → 桥 → loadOculars）。
  setTelrad(v: boolean): void {
    this.telescopeStore.telradOn = v
    this.port.requestWhenReady('setTelrad', v ? '1' : '0', () => { this.telescopeStore.loadOculars(false) })
  }
  setCrosshairs(v: boolean): void {
    this.telescopeStore.crosshairsOn = v
    this.port.requestWhenReady('setCrosshairs', v ? '1' : '0', () => { this.telescopeStore.loadOculars(false) })
  }
  setCCD(v: boolean): void {
    this.telescopeStore.ccdOn = v
    this.port.requestWhenReady('setCCD', v ? '1' : '0', () => { this.telescopeStore.loadOculars(false) })
  }

  // 切换目镜/望远镜/镜头/相机档位。
  selectOcularInstrument(kind: string, index: number): void {
    this.port.requestWhenReady('selectOcularInstrument', kind.toLowerCase() + '|' + index.toString(), () => {
      this.telescopeStore.loadOculars(false)
    })
  }

  // 目镜布尔设置写回。
  setOcularSetting(name: string, enabled: boolean): void {
    this.port.requestWhenReady('setOcularSetting', name + '|' + (enabled ? '1' : '0'), () => {
      this.telescopeStore.loadOculars(false)
    })
  }

  // 四个滑杆设置（滑动中只写 store，结束/点击时提交桥）。
  changeOcularCcdRotation(value: number, mode: SliderChangeMode): void {
    this.telescopeStore.ocularCcdRotation = value
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.port.requestWhenReady('setOcularSetting', 'ccdRotation|' + value.toFixed(1), () => {
        this.telescopeStore.loadOculars(false)
      })
    }
  }
  changeOcularMaskOpacity(value: number, mode: SliderChangeMode): void {
    this.telescopeStore.ocularMaskOpacity = Math.round(value)
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.port.requestWhenReady('setOcularSetting', 'maskOpacity|' + this.telescopeStore.ocularMaskOpacity.toString(), () => {
        this.telescopeStore.loadOculars(false)
      })
    }
  }
  changeOcularPrismRotation(value: number, mode: SliderChangeMode): void {
    this.telescopeStore.ocularCcdPrismRotation = value
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.port.requestWhenReady('setOcularSetting', 'prismRotation|' + value.toFixed(1), () => { this.telescopeStore.loadOculars(false) })
    }
  }
  changeOcularCropSize(setting: string, value: number, mode: SliderChangeMode): void {
    const size = Math.round(value)
    if (setting === 'ccdCropHSize') this.telescopeStore.ocularCcdCropHSize = size
    else this.telescopeStore.ocularCcdCropVSize = size
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.port.requestWhenReady('setOcularSetting', setting + '|' + size.toString(), () => { this.telescopeStore.loadOculars(false) })
    }
  }

  // 十字线旋转与档位复位。
  rotateOcularReticle(direction: string): void {
    this.port.requestWhenReady('rotateOcularReticle', direction, () => { this.telescopeStore.loadOculars(false) })
  }
  resetOcularInstrument(kind: string): void {
    this.port.requestWhenReady('resetOcularInstrument', kind, () => { this.telescopeStore.loadOculars(false) })
  }
}
