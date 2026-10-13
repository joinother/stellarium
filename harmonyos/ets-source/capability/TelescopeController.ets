// LX200 望远镜编辑器 / 控制命令行为控制器：负责档位编辑、协议与端点配置、
// 连接测试、Goto/Sync/Abort 与指向读取，以及 live-position 实时位置轮询链
//（自持 setTimeout 链，宿主生命周期收口）与望远镜控制状态回读 loadTelescopeControlStatus。
//
// 不 import NAPI/UI：桥经 CommandPort；状态整体写回 TelescopeStore
//（面板经 @ObjectLink 消费）。各方法均不调 flashHint / refreshState；仅 live-position
// 的「是否应刷新」谓词经 TelescopeHostHooks 由宿主回注（控制器不触碰 UI 生命周期）。
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import {
  TelescopeControlResponse, TelescopeProfilesResponse, TelescopeProfile, TELESCOPE_SIMULATOR_MODEL
} from '../pages/MainWindowModels'
import { telescopeUpdateTime, telescopeErrorText } from '../common/derive/actions'
import { CommandPort } from '../bridge/CommandPort'
import { TelescopeStore } from '../state/TelescopeStore'

// 宿主 → TelescopeController 的只读谓词注入：控制器不触碰 UI 生命周期。
// 「是否应刷新实时位置」需读 applicationInForeground / panelVisible / activePanel 等
// 生命周期与 UI 状态字段，这些字段留在宿主；控制器只在 schedule / sync 时经 hooks 调用。
export interface TelescopeHostHooks {
  shouldRefreshTelescopePosition(): boolean
}

export class TelescopeController {
  private port: CommandPort
  private telescopeStore: TelescopeStore
  private hooks: TelescopeHostHooks | null = null

  // —— live-position 定时器簇（私有，不入被观察语义） ——
  // 仅本控制器的 schedule / refresh / sync / stop 读写；reqId 用于作废在途回包。
  private lx200LivePositionTimer: number = 0
  private lx200LivePositionRequestPending: boolean = false
  private lx200LivePositionRequestId: number = 0

  constructor(port: CommandPort, telescopeStore: TelescopeStore, hooks: TelescopeHostHooks) {
    this.port = port
    this.telescopeStore = telescopeStore
    this.hooks = hooks
  }

  private ensurePort(): CommandPort | null {
    return this.port
  }

  // 模拟器直接给本地状态；其余协议向桥查询端点。
  validateTelescopeEditorStatus(): void {
    if (this.telescopeStore.lx200Protocol === 'simulated') {
      this.telescopeStore.lx200Transport = I18n.t('m_telescope_transport_simulated')
      this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_offline')
      this.telescopeStore.lx200ConnectionState = 'available'
      return
    }
    this.port.requestInteractive('getTelescopeControl', this.telescopeStore.lx200Host.trim() + '|' + this.telescopeStore.lx200Port.trim(), (result: TelescopeControlResponse) => {
      this.applyTelescopeEndpointStatus(result)
    })
  }

  // 选择档位并回读配置。
  selectTelescopeProfile(slot: number): void {
    if (slot === this.telescopeStore.lx200SelectedSlot && !this.telescopeStore.lx200EditingNew) return
    this.port.requestInteractive('selectTelescopeProfile', slot.toString(), (result: TelescopeProfilesResponse) => {
      if (result.ok === true) {
        this.applyTelescopeProfiles(result)
        this.validateTelescopeEditorStatus()
      } else {
        this.telescopeStore.lx200Status = result.error ?? I18n.t('m_telescope_load_failed')
      }
    })
  }

  // 寻找空档位并初始化「新建」编辑器草稿。
  beginNewTelescopeProfile(): void {
    this.stopTelescopeLivePosition(false)
    const used = new Set<number>(this.telescopeStore.lx200Profiles.map((profile: TelescopeProfile) => profile.slot))
    let slot = 1
    while (slot <= 9 && used.has(slot)) slot += 1
    if (slot > 9) {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_slots_full')
      return
    }
    this.telescopeStore.lx200SelectedSlot = slot
    this.telescopeStore.lx200Name = I18n.format('m_telescope_simulator_name', [slot.toString()]) as string
    this.telescopeStore.lx200Protocol = 'simulated'
    this.telescopeStore.lx200DeviceModel = TELESCOPE_SIMULATOR_MODEL
    this.telescopeStore.lx200Host = ''
    this.telescopeStore.lx200Port = ''
    this.telescopeStore.lx200Equinox = 'J2000'
    this.telescopeStore.lx200CommandDelayMs = 0
    this.telescopeStore.lx200Circles = '1, 2, 4'
    this.telescopeStore.lx200EditingNew = true
    this.telescopeStore.lx200ConnectionState = 'available'
    this.telescopeStore.lx200Position = ''
    this.telescopeStore.lx200PositionUpdatedAt = ''
    this.telescopeStore.lx200PositionUpdateState = 'idle'
    this.validateTelescopeEditorStatus()
  }

  // 切换协议并重置端点草稿。
  selectTelescopeProtocol(protocol: string): void {
    if (protocol === this.telescopeStore.lx200Protocol) return
    this.stopTelescopeLivePosition(false)
    this.telescopeStore.lx200Protocol = protocol
    this.telescopeStore.lx200Position = ''
    this.telescopeStore.lx200PositionUpdatedAt = ''
    this.telescopeStore.lx200PositionUpdateState = 'idle'
    if (protocol === 'simulated') {
      this.telescopeStore.lx200DeviceModel = TELESCOPE_SIMULATOR_MODEL
      this.telescopeStore.lx200Host = ''
      this.telescopeStore.lx200Port = ''
      this.telescopeStore.lx200ConnectionState = 'available'
      this.telescopeStore.lx200Status = I18n.t('m_telescope_simulator_ready')
    } else {
      this.telescopeStore.lx200DeviceModel = 'Meade LX200 (compatible)'
      this.telescopeStore.lx200Host = '127.0.0.1'
      this.telescopeStore.lx200Port = '4030'
      this.telescopeStore.lx200ConnectionState = 'not_tested'
      this.telescopeStore.lx200Status = I18n.t('m_telescope_not_tested')
    }
    this.validateTelescopeEditorStatus()
  }

  // 校验并保存档位。
  saveTelescopeProfile(): void {
    const port = Number(this.telescopeStore.lx200Port.trim())
    const invalidEndpoint = this.telescopeStore.lx200Protocol === 'lx200_tcp' &&
      (this.telescopeStore.lx200Host.trim().length === 0 || !Number.isInteger(port) || port < 1 || port > 65535)
    if (this.telescopeStore.lx200Name.trim().length === 0 || invalidEndpoint) {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_invalid_profile')
      return
    }
    const profile: TelescopeProfile = {
      slot: this.telescopeStore.lx200SelectedSlot,
      name: this.telescopeStore.lx200Name.trim(),
      protocol: this.telescopeStore.lx200Protocol,
      deviceModel: this.telescopeStore.lx200DeviceModel,
      host: this.telescopeStore.lx200Host.trim(),
      port: this.telescopeStore.lx200Protocol === 'simulated' ? 0 : port,
      equinox: this.telescopeStore.lx200Equinox,
      commandDelayMs: this.telescopeStore.lx200CommandDelayMs,
      circles: this.telescopeStore.telescopeCircleValues()
    }
    this.telescopeStore.lx200Busy = true
    this.port.requestInteractive('saveTelescopeProfile', JSON.stringify(profile), (result: TelescopeProfilesResponse) => {
      this.telescopeStore.lx200Busy = false
      if (result.ok !== true) {
        this.telescopeStore.lx200Status = result.error ?? I18n.t('m_telescope_save_failed')
        return
      }
      this.applyTelescopeProfiles(result)
      this.telescopeStore.lx200Status = I18n.t('m_telescope_saved')
      this.validateTelescopeEditorStatus()
    }, () => { this.telescopeStore.lx200Busy = false })
  }

  // 删除当前档位（新建草稿则改为回读）。
  deleteTelescopeProfile(): void {
    if (this.telescopeStore.lx200EditingNew) {
      this.loadTelescopeControlStatus()
      return
    }
    this.port.requestInteractive('deleteTelescopeProfile', this.telescopeStore.lx200SelectedSlot.toString(), (result: TelescopeProfilesResponse) => {
      if (result.ok === true) {
        this.applyTelescopeProfiles(result)
        this.telescopeStore.lx200Status = I18n.t('m_telescope_deleted')
        this.validateTelescopeEditorStatus()
      } else {
        this.telescopeStore.lx200Status = result.error ?? I18n.t('m_telescope_delete_failed')
      }
    })
  }

  // 测试连接并安排 live-position 轮询。
  testTelescopeConnection(): void {
    if (this.telescopeStore.lx200EditingNew) {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_save_before_test')
      return
    }
    this.stopTelescopeLivePosition(false)
    this.telescopeStore.lx200Busy = true
    this.telescopeStore.lx200Status = I18n.t('m_telescope_connecting')
    this.port.requestInteractive('testTelescopeConnection', this.lx200Payload(), (result: TelescopeControlResponse) => {
      this.telescopeStore.lx200Busy = false
      this.applyTelescopeEndpointStatus(result)
      this.telescopeStore.lx200ConnectionState = result.ok === true ? 'available' : 'unavailable'
      this.telescopeStore.lx200Status = result.ok === true
        ? (result.simulated === true ? I18n.t('m_telescope_simulator_ready') : I18n.t('m_telescope_available'))
        : telescopeErrorText(result, I18n.t('m_telescope_test_failed'))
      this.scheduleTelescopeLivePosition()
    }, (result: StellariumBridgeResponse) => {
      const response = result as TelescopeControlResponse
      this.telescopeStore.lx200Busy = false
      if (response.state === 'available' || response.state === 'unavailable') this.telescopeStore.lx200ConnectionState = response.state
      this.telescopeStore.lx200Status = telescopeErrorText(response, I18n.t('m_telescope_test_failed'))
      this.scheduleTelescopeLivePosition()
    })
  }

  // Goto/Sync 回包统一处理（私有助手）。
  private applyLx200Result(result: StellariumBridgeResponse): void {
    const response = result as TelescopeControlResponse
    this.telescopeStore.lx200Busy = false
    if (result.ok === true) {
      this.telescopeStore.lx200ConnectionState = 'available'
      const target = result.target && result.target.length > 0 ? result.target : I18n.t('m_telescope_target_default')
      const mode = result.mode === 'sync' ? I18n.t('m_telescope_mode_sync') : I18n.t('m_telescope_mode_goto')
      const coord = result.ra && result.dec ? ' · ' + result.ra + ' / ' + result.dec : ''
      this.telescopeStore.lx200Status = I18n.format('m_telescope_command_sent', [mode as string, target as string, coord])
      if (result.mode === 'goto') this.setTelescopeLivePosition(true)
    } else {
      if (response.state === 'available' || response.state === 'unavailable') this.telescopeStore.lx200ConnectionState = response.state
      this.telescopeStore.lx200Status = telescopeErrorText(response, I18n.t('m_telescope_disconnected'))
    }
    this.scheduleTelescopeLivePosition()
  }

  // 指向/同步/中止当前选中天体。
  lx200GotoSelected(): void {
    if (this.telescopeStore.lx200EditingNew) {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_save_before_control')
      return
    }
    this.stopTelescopeLivePosition(false)
    this.telescopeStore.lx200Busy = true
    this.telescopeStore.lx200Status = I18n.t('m_telescope_sending_goto')
    this.port.requestInteractive('telescopeLx200GotoSelected', this.lx200Payload(),
      (result: StellariumBridgeResponse) => this.applyLx200Result(result),
      (result: StellariumBridgeResponse) => this.applyLx200Result(result))
  }

  lx200SyncSelected(): void {
    if (this.telescopeStore.lx200EditingNew) {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_save_before_control')
      return
    }
    this.stopTelescopeLivePosition(false)
    this.telescopeStore.lx200Busy = true
    this.telescopeStore.lx200Status = I18n.t('m_telescope_sending_sync')
    this.port.requestInteractive('telescopeLx200SyncSelected', this.lx200Payload(),
      (result: StellariumBridgeResponse) => this.applyLx200Result(result),
      (result: StellariumBridgeResponse) => this.applyLx200Result(result))
  }

  lx200Abort(): void {
    if (this.telescopeStore.lx200EditingNew) {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_save_before_control')
      return
    }
    this.stopTelescopeLivePosition(false)
    this.telescopeStore.lx200Busy = true
    this.port.requestInteractive('telescopeLx200Abort', this.lx200Payload(), (result: StellariumBridgeResponse) => {
      const response = result as TelescopeControlResponse
      this.telescopeStore.lx200Busy = false
      if (response.state === 'available' || response.state === 'unavailable') this.telescopeStore.lx200ConnectionState = response.state
      this.telescopeStore.lx200Status = result.ok === true ? I18n.t('m_telescope_stop_sent') :
        telescopeErrorText(response, I18n.t('m_telescope_stop_failed'))
      this.scheduleTelescopeLivePosition()
    }, (result: StellariumBridgeResponse) => {
      const response = result as TelescopeControlResponse
      this.telescopeStore.lx200Busy = false
      if (response.state === 'available' || response.state === 'unavailable') this.telescopeStore.lx200ConnectionState = response.state
      this.telescopeStore.lx200Status = telescopeErrorText(response, I18n.t('m_telescope_stop_failed'))
      this.scheduleTelescopeLivePosition()
    })
  }

  // 读取望远镜指向（center=true 时居中屏幕）。
  readTelescopePosition(center: boolean = false): void {
    if (this.telescopeStore.lx200EditingNew) {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_save_before_control')
      return
    }
    this.stopTelescopeLivePosition(false)
    this.telescopeStore.lx200Busy = true
    this.telescopeStore.lx200Status = center ? I18n.t('m_telescope_centering') : I18n.t('m_telescope_reading_position')
    const command = center ? 'centerScreenOnTelescope' : 'getTelescopePosition'
    this.port.requestInteractive(command, this.lx200Payload(), (result: TelescopeControlResponse) => {
      this.telescopeStore.lx200Busy = false
      if (result.ok === true) {
        this.telescopeStore.lx200ConnectionState = 'available'
        this.telescopeStore.lx200Position = (result.ra ?? '--:--:--') + ' / ' + (result.dec ?? '--°--:--')
        this.telescopeStore.lx200PositionUpdatedAt = telescopeUpdateTime()
        this.telescopeStore.lx200PositionUpdateState = 'fresh'
        this.telescopeStore.lx200Status = center ? I18n.t('m_telescope_centered') : I18n.t('m_telescope_position_updated')
      } else {
        if (result.state === 'available' || result.state === 'unavailable') this.telescopeStore.lx200ConnectionState = result.state
        this.telescopeStore.lx200Status = telescopeErrorText(result, I18n.t('m_telescope_position_failed'))
      }
      this.scheduleTelescopeLivePosition()
    }, (result: StellariumBridgeResponse) => {
      const response = result as TelescopeControlResponse
      this.telescopeStore.lx200Busy = false
      if (response.state === 'available' || response.state === 'unavailable') this.telescopeStore.lx200ConnectionState = response.state
      this.telescopeStore.lx200PositionUpdateState = 'error'
      this.telescopeStore.lx200Status = telescopeErrorText(response, I18n.t('m_telescope_position_failed'))
      this.scheduleTelescopeLivePosition()
    })
  }

  // ===== LX200 实时位置（live-position）定时器簇 =====
  // 宿主只保留生命周期谓词 shouldRefreshTelescopePosition 并经 hooks 注入；
  // 面板开合 / 前后台切换经本控制器的 set / sync / stop / schedule 收口。

  // 读宿主生命周期字段的部分经 hooks 注入。
  private shouldRefreshLivePosition(): boolean {
    return this.hooks !== null && this.hooks.shouldRefreshTelescopePosition()
  }

  stopTelescopeLivePosition(markStale: boolean = true): void {
    if (this.lx200LivePositionTimer !== 0) {
      clearTimeout(this.lx200LivePositionTimer)
      this.lx200LivePositionTimer = 0
    }
    this.lx200LivePositionRequestPending = false
    this.lx200LivePositionRequestId++
    if (markStale && this.telescopeStore.lx200Position.length > 0) {
      this.telescopeStore.lx200PositionUpdateState = 'stale'
    }
  }

  scheduleTelescopeLivePosition(delayMs: number = 1000): void {
    if (!this.shouldRefreshLivePosition() || this.lx200LivePositionTimer !== 0) return
    this.lx200LivePositionTimer = setTimeout(() => {
      this.lx200LivePositionTimer = 0
      this.refreshTelescopeLivePosition()
    }, delayMs) as number
  }

  refreshTelescopeLivePosition(): void {
    const port = this.ensurePort()
    if (port === null) return
    if (!this.shouldRefreshLivePosition() || this.lx200LivePositionRequestPending) return
    this.lx200LivePositionRequestPending = true
    this.telescopeStore.lx200PositionUpdateState = 'updating'
    const requestId = ++this.lx200LivePositionRequestId
    port.requestInteractive('getTelescopePosition', this.lx200Payload(), (result: TelescopeControlResponse) => {
      if (requestId !== this.lx200LivePositionRequestId) return
      this.lx200LivePositionRequestPending = false
      if (result.ok === true) {
        this.telescopeStore.lx200ConnectionState = 'available'
        this.telescopeStore.lx200Position = (result.ra ?? '--:--:--') + ' / ' + (result.dec ?? '--°--:--')
        this.telescopeStore.lx200PositionUpdatedAt = telescopeUpdateTime()
        this.telescopeStore.lx200PositionUpdateState = 'fresh'
        this.scheduleTelescopeLivePosition(1000)
        return
      }
      if (result.state === 'available' || result.state === 'unavailable') this.telescopeStore.lx200ConnectionState = result.state
      this.telescopeStore.lx200PositionUpdateState = 'error'
      this.telescopeStore.lx200Status = telescopeErrorText(result, I18n.t('m_telescope_position_failed'))
      this.scheduleTelescopeLivePosition(1800)
    }, (result: StellariumBridgeResponse) => {
      if (requestId !== this.lx200LivePositionRequestId) return
      this.lx200LivePositionRequestPending = false
      this.telescopeStore.lx200PositionUpdateState = 'error'
      this.telescopeStore.lx200Status = result.error ?? I18n.t('m_telescope_position_failed')
      this.scheduleTelescopeLivePosition(1800)
    })
  }

  syncTelescopeLivePosition(): void {
    if (!this.shouldRefreshLivePosition()) {
      this.stopTelescopeLivePosition()
      return
    }
    if (this.lx200LivePositionRequestPending || this.lx200LivePositionTimer !== 0) return
    this.refreshTelescopeLivePosition()
  }

  setTelescopeLivePosition(enabled: boolean): void {
    this.telescopeStore.lx200LivePositionEnabled = enabled
    if (enabled) {
      this.telescopeStore.lx200PositionUpdateState = 'updating'
      this.syncTelescopeLivePosition()
    } else {
      this.stopTelescopeLivePosition()
    }
  }

  lx200Payload(): string {
    return JSON.stringify({
      slot: this.telescopeStore.lx200SelectedSlot,
      targetSource: this.telescopeStore.lx200TargetSource
    })
  }

  applyTelescopeProfile(profile: TelescopeProfile): void {
    this.stopTelescopeLivePosition(false)
    this.telescopeStore.lx200SelectedSlot = profile.slot
    this.telescopeStore.lx200Name = profile.name
    this.telescopeStore.lx200Protocol = profile.protocol
    this.telescopeStore.lx200DeviceModel = profile.deviceModel
    this.telescopeStore.lx200Host = profile.host
    this.telescopeStore.lx200Port = profile.port.toString()
    this.telescopeStore.lx200Equinox = profile.equinox
    this.telescopeStore.lx200CommandDelayMs = profile.commandDelayMs
    this.telescopeStore.lx200Circles = profile.circles.join(', ')
    this.telescopeStore.lx200ConnectionState = profile.protocol === 'simulated' ? 'available' : (profile.state ?? 'not_tested')
    this.telescopeStore.lx200Position = ''
    this.telescopeStore.lx200PositionUpdatedAt = ''
    this.telescopeStore.lx200PositionUpdateState = 'idle'
    if (profile.protocol === 'simulated') {
      this.telescopeStore.lx200Transport = I18n.t('m_telescope_transport_simulated')
      this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_offline')
      this.telescopeStore.lx200Status = I18n.t('m_telescope_simulator_ready')
    } else if (this.telescopeStore.lx200ConnectionState === 'unavailable') {
      this.telescopeStore.lx200Status = profile.lastError ?? I18n.t('m_telescope_unavailable')
    } else if (this.telescopeStore.lx200ConnectionState === 'available') {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_available')
    } else {
      this.telescopeStore.lx200Status = I18n.t('m_telescope_not_tested')
    }
    this.telescopeStore.lx200EditingNew = false
    this.scheduleTelescopeLivePosition(500)
  }

  applyTelescopeProfiles(result: TelescopeProfilesResponse): void {
    const profiles = result.profiles ?? []
    this.telescopeStore.lx200Profiles = profiles
    const selectedSlot = result.selectedSlot ?? (profiles.length > 0 ? profiles[0].slot : 1)
    this.telescopeStore.lx200SelectedSlot = selectedSlot
    const selected = profiles.find((profile: TelescopeProfile) => profile.slot === selectedSlot)
    if (selected !== undefined) {
      this.applyTelescopeProfile(selected)
    }
  }

  applyTelescopeEndpointStatus(result: TelescopeControlResponse): void {
    if (result.ok !== true) {
      this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_invalid')
      this.telescopeStore.lx200Transport = I18n.t('m_telescope_transport_tcp')
      return
    }
    if (result.simulated === true || result.scope === 'offline_simulator') {
      this.telescopeStore.lx200Transport = I18n.t('m_telescope_transport_simulated')
      this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_offline')
      this.telescopeStore.lx200ConnectionState = 'available'
      return
    }
    this.telescopeStore.lx200Transport = I18n.t('m_telescope_transport_tcp')
    const scope = result.scope as string
    if (scope === 'local_device') this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_local')
    else if (scope === 'local_or_lan') this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_lan')
    else if (scope === 'public_or_unclassified' || scope === 'hostname_or_unclassified') this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_blocked')
    else this.telescopeStore.lx200Scope = I18n.t('m_telescope_scope_unknown')
    this.telescopeStore.lx200ConnectionState = result.state ?? this.telescopeStore.lx200ConnectionState
  }

  loadTelescopeControlStatus(): void {
    const port = this.ensurePort()
    if (port === null) return
    port.requestInteractive('getTelescopeProfiles', '', (result: TelescopeProfilesResponse) => {
      if (result.ok !== true) {
        this.telescopeStore.lx200Status = result.error ?? I18n.t('m_telescope_load_failed')
        return
      }
      this.applyTelescopeProfiles(result)
      port.requestInteractive('getTelescopeControl', this.lx200Payload(), (endpoint: TelescopeControlResponse) => {
        this.applyTelescopeEndpointStatus(endpoint)
        this.scheduleTelescopeLivePosition(500)
      })
    })
  }
}
