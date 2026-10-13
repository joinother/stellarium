import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { AboutResponse, LogResponse, ExportConfigResponse, ImportConfigResponse } from '../pages/MainWindowModels'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → ToolsStore 的 UI 提示注入：store 不触碰 UI，角度测量动作回包后经宿主 flashHint 提示。
// 配置整包动作（保存设置 / 恢复默认 / 导出 / 导入）的宿主动作（saveAppSettings 与导出配置的
// 剪贴板落点）经具名 hook 回注。
export interface ToolsHostHooks {
  flashHint(text: ResourceStr): void
  saveAppSettings(): void
  copyConfigExportText(text: string, successHint: ResourceStr): void
}

// 「工具 / 帮助 / 角度测量 / 录制控制」域的状态簇：持有帮助 / 工具面板
// （about*、log*、configExport* / configImport*、screenshotSaving、会话导入导出文本等）、
// 角度测量工具、天空资料图加载状态提示与录制控制条 UI 状态。
// 消费方以 @ObjectLink 观察；自持 CommandPort、请求序号 seq，宿主经 ToolsHostHooks 注入 UI 提示。
//
// 刻意不入 store：recordCount 是录制过程中每个可录制命令都写一次的高频进度读数，保持宿主字段并以
// @Prop 传入 RecordingControlBar；录制引擎其余字段（recordBuffer / recordMsg / recordings / replay* /
// video* / screenVideo* / screenCapture* / scriptControl* 拖拽瞬时量）由桥回调、定时器与触摸每帧写入，
// 留在宿主；skyTextureStatusTimer / DelayTimer / Polls 为定时器标识，非 UI 状态；
// sessionJson / sessionExportSig / sessionHint 与 500ms 后二次比对的会话续传共享，归 SessionToolStore。
//
// 只放数据与纯计算，不 import UI / NAPI（只额外 import 纯类型 AboutResponse 与纯接口
// CommandPort，两者都不触碰 libentry.so / @ohos.*）。
//
// —— 桥注入 ——
// 本 store 的加载器（load*）自持：宿主在 aboutToAppear 调用 attachPort(port, onChanged) 注入
// CommandPort 与发布回调，store 侧用 ensurePort() 守卫；请求序号 seq 由 store 单一持有
// （禁止宿主 / store 双序号），本加载器暂未用到。
// 消费方均为 @ObjectLink，字段赋值即刷新，故宿主注入的 onChanged 为空实现（该域无 publish* 发布点）。
@Observed
export class ToolsStore {
  // —— 帮助 / 工具面板（关于 / 日志 / 配置导入导出） ——
  aboutVersion: string = ''
  aboutQt: string = ''
  aboutUserDir: string = ''
  aboutConfigFile: string = ''
  logText: string = ''
  logVisible: boolean = false
  configExportText: string = ''
  configExportVisible: boolean = false
  configImportText: string = ''
  configImportMsg: string = ''
  screenshotSaving: boolean = false
  sessionExportText: string = ''
  sessionImportText: string = ''
  sessionImportMsg: string = ''

  // —— 角度测量工具（点击两个位置量角） ——
  angleMeasureEnabled: boolean = false
  angleMeasureHasStart: boolean = false
  angleMeasureHasEnd: boolean = false
  angleMeasureText: string = ''
  angleMeasurePending: boolean = false

  // —— 天空资料图加载状态提示（工具状态条，UI 仍在 harmonyShell 内） ——
  skyTextureStatusVisible: boolean = false
  skyTextureStatusText: string = ''
  skyTextureStatusError: boolean = false

  // —— 脚本录制控制条（显示/暂停/展开，属 UI 状态；进度计数不入 store） ——
  recording: boolean = false
  recordingPaused: boolean = false
  recordingUiExpanded: boolean = true

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 请求序号 seq 由本 store 单一持有：loadAngleMeasure 与 toggleAngleMeasure 共用它作废在途回包。
  private seq: number = 0
  private onChanged: (() => void) | null = null
  // 宿主 UI 提示注入（toggleAngleMeasure 回包提示）。
  private hooks: ToolsHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: ToolsHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 帮助面板「关于」：桥查询版本 / Qt 版本 / 用户目录 / 配置文件。
  loadAboutInfo(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    port.requestWhenReady('getAboutInfo', '', (r: StellariumBridgeResponse) => {
      const resp = r as AboutResponse
      this.aboutVersion = resp.version ?? ''
      this.aboutQt = resp.qtVersion ?? ''
      this.aboutUserDir = resp.userDir ?? ''
      this.aboutConfigFile = resp.configFile ?? ''
      this.notifyChanged()
    })
  }

  // 帮助面板「日志」：桥拉取最近日志文本并置为可见。
  loadLog(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    port.requestWhenReady('getLog', '6000', (r: StellariumBridgeResponse) => {
      const resp = r as LogResponse
      this.logText = resp.log ?? ''
      this.logVisible = true
      this.notifyChanged()
    })
  }

  // 角度测量开关状态：拉取 enabled / hasStart / hasEnd / 角度文本；
  // 回包按 seq 作废在途请求（与 toggleAngleMeasure 共用）。
  loadAngleMeasure(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    const requestId = ++this.seq
    port.requestWhenReady('getAngleMeasure', '', (r: StellariumBridgeResponse) => {
      if (requestId !== this.seq) return
      if (r.ok !== true) return
      this.angleMeasureEnabled = r.enabled === true
      this.angleMeasureHasStart = r.hasStart === true
      this.angleMeasureHasEnd = r.hasEnd === true
      this.angleMeasureText = r.angleText ?? ''
    })
  }

  // 切换角度测量：乐观写入后按回包确认或回滚（store 不触碰 UI，提示经 hooks.flashHint）。
  toggleAngleMeasure(targetEnabled?: boolean): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    const enabled = targetEnabled === undefined ? !this.angleMeasureEnabled : targetEnabled
    const previousEnabled = this.angleMeasureEnabled
    const previousHasStart = this.angleMeasureHasStart
    const previousHasEnd = this.angleMeasureHasEnd
    const previousText = this.angleMeasureText
    const requestId = ++this.seq
    this.angleMeasurePending = true
    this.angleMeasureEnabled = enabled
    if (!enabled) {
      this.angleMeasureHasStart = false
      this.angleMeasureHasEnd = false
      this.angleMeasureText = ''
    }
    port.requestInteractive('setActionChecked', 'actionShow_Angle_Measure|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (requestId !== this.seq) return
      this.angleMeasurePending = false
      if (r.ok !== true) {
        this.angleMeasureEnabled = previousEnabled
        this.angleMeasureHasStart = previousHasStart
        this.angleMeasureHasEnd = previousHasEnd
        this.angleMeasureText = previousText
        hooks.flashHint('角度测量插件不可用')
        return
      }
      this.angleMeasureEnabled = r.checked === true
      if (!this.angleMeasureEnabled) {
        this.angleMeasureHasStart = false
        this.angleMeasureHasEnd = false
        this.angleMeasureText = ''
      }
      hooks.flashHint(this.angleMeasureEnabled ? '角度测量已开启，请点击两个位置' : '角度测量已关闭')
    }, () => {
      if (requestId !== this.seq) return
      this.angleMeasurePending = false
      this.angleMeasureEnabled = previousEnabled
      this.angleMeasureHasStart = previousHasStart
      this.angleMeasureHasEnd = previousHasEnd
      this.angleMeasureText = previousText
      hooks.flashHint('角度测量插件不可用')
    })
  }

  // ==== 配置整包（保存设置 / 恢复默认 / 导出 / 导入）====

  // 保存全部核心设置：宿主持久化动作经 hooks.saveAppSettings。
  saveAllCoreSettings(): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    hooks.saveAppSettings()
    port.requestInteractive('saveAllSettings', '', (r: StellariumBridgeResponse) => {
      hooks.flashHint(r.ok === true ? I18n.t('settings_saved') : I18n.t('msg_apply_failed'))
    })
  }

  // 恢复默认设置。
  restoreCoreDefaults(): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    port.requestInteractive('restoreDefaultSettings', '', (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        hooks.flashHint(I18n.t('msg_apply_failed'))
        return
      }
      hooks.flashHint(I18n.t('settings_defaults_restart'))
    })
  }

  // 导出配置：导出文本落本 store，剪贴板经 hooks（适配器留宿主）。
  exportConfig(): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    port.requestWhenReady('exportConfig', '', (r: StellariumBridgeResponse) => {
      const resp = r as ExportConfigResponse
      if (resp.ok !== true) {
        hooks.flashHint(I18n.t('config_export_failed'))
        return
      }
      this.configExportText = resp.content ?? ''
      this.configExportVisible = true
      hooks.copyConfigExportText(this.configExportText, I18n.t('config_export_copied'))
    })
  }

  // 导入配置。
  importConfig(): void {
    const hooks = this.hooks
    const port = this.ensurePort()
    if (hooks === null || port === null) {
      return
    }
    const text = this.configImportText.trim()
    if (text.length === 0) {
      hooks.flashHint(I18n.t('msg_paste_config_first'))
      return
    }
    this.configImportMsg = '正在导入…'
    port.requestWhenReady('importConfig', text, (r: StellariumBridgeResponse) => {
      const resp = r as ImportConfigResponse
      if (resp.ok === true) {
        this.configImportText = ''
        this.configImportMsg = '已导入 ' + (resp.applied ?? 0) + ' 项配置'
        hooks.flashHint(this.configImportMsg)
      } else {
        this.configImportMsg = '导入失败：' + (resp.error ?? '未知错误')
      }
    })
  }
}
