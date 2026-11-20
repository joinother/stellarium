import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit'
import { Want } from '@kit.AbilityKit'
import { reminderAgentManager } from '@kit.BackgroundTasksKit'
import { notificationManager } from '@kit.NotificationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  clampTimeOffsetHours,
  computeOverflowArea,
  defaultAstronomyCard,
  extractInverseTextColor,
  nextCyclePlanet,
  planetZhName
} from './AstronomyCardData'
import {
  WidgetRemindedEntry,
  readFormConfig,
  readFormTimeOffset,
  readRemindedEntries,
  removeFormMetadata,
  resolveCardDataForForm,
  writeFormConfig,
  writeFormKind,
  writeFormTextColor,
  writeFormTimeOffset,
  writeRemindedEntries
} from './FormStoreHelper'

const DOMAIN: number = 0xD003
const TAG: string = 'SkyInstrumentForm'

export default class SkyInstrumentFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters as Record<string, Object> | undefined
    const formId = params !== undefined && params[formInfo.FormParam.IDENTITY_KEY] !== undefined
      ? String(params[formInfo.FormParam.IDENTITY_KEY]) : ''
    const formName = params !== undefined && params[formInfo.FormParam.NAME_KEY] !== undefined
      ? String(params[formInfo.FormParam.NAME_KEY]) : 'sky_window_card'
    const editFormId = params !== undefined && params['ohos.extra.param.key.edit_form_id'] !== undefined
      ? String(params['ohos.extra.param.key.edit_form_id']) : ''
    const inverseColor = extractInverseTextColor(params?.[formInfo.FormParam.HOST_BG_INVERSE_COLOR_KEY])

    if (formId.length > 0 && formName.length > 0) {
      writeFormKind(this.context, formId, formName)
    }
    if (formId.length > 0 && inverseColor.length > 0) {
      writeFormTextColor(this.context, formId, inverseColor)
    }

    // If this is a preview card created by FormEditExtensionAbility, mirror the target card's config!
    const sourceFormId = editFormId.length > 0 ? editFormId : formId
    const data = sourceFormId.length > 0
      ? resolveCardDataForForm(this.context, sourceFormId, Date.now())
      : defaultAstronomyCard()
    if (inverseColor.length > 0) {
      data['textColor'] = inverseColor
    }
    return formBindingData.createFormBindingData(data)
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    const inverseColor = extractInverseTextColor(wantParams?.[formInfo.FormParam.HOST_BG_INVERSE_COLOR_KEY])
    if (formId.length > 0 && inverseColor.length > 0) {
      writeFormTextColor(this.context, formId, inverseColor)
    }
    // Scheduled refresh returns card to live current time if user had scrubbed earlier
    if (wantParams === undefined || wantParams['keepTimeOffset'] !== true) {
      writeFormTimeOffset(this.context, formId, 0)
    }
    const data = resolveCardDataForForm(this.context, formId, Date.now())
    if (inverseColor.length > 0) {
      data['textColor'] = inverseColor
    }
    this.pushFormUpdate(formId, data)
  }

  onFormEvent(formId: string, message: string): void {
    if (formId.length === 0 || message.length === 0) return
    try {
      const parsed = JSON.parse(message) as Record<string, Object>
      const eventType = typeof parsed['message'] === 'string' ? String(parsed['message']) : ''
      const formName = typeof parsed['formName'] === 'string' ? String(parsed['formName']) : ''
      if (formName.length > 0) {
        writeFormKind(this.context, formId, formName)
      }

      if (eventType === 'requestOverflow') {
        const config = readFormConfig(this.context, formId)
        if (config.overflowMode === 'off') return
        void this.triggerOverflow(formId)
        return
      }

      if (eventType === 'stepTimeOffset') {
        const delta = Number(parsed['deltaHours'] ?? 4)
        const current = readFormTimeOffset(this.context, formId)
        const next = clampTimeOffsetHours(current + (Number.isFinite(delta) ? delta : 4))
        writeFormTimeOffset(this.context, formId, next)
        const data = resolveCardDataForForm(this.context, formId, Date.now())
        this.pushFormUpdate(formId, data)
        hilog.info(DOMAIN, TAG, 'stepTimeOffset formId=%{public}s offset=%{public}dh', formId, next)
        return
      }

      if (eventType === 'resetTimeOffset') {
        writeFormTimeOffset(this.context, formId, 0)
        const data = resolveCardDataForForm(this.context, formId, Date.now())
        this.pushFormUpdate(formId, data)
        return
      }

      if (eventType === 'cyclePlanet') {
        const config = readFormConfig(this.context, formId)
        const currentDisplayed = typeof parsed['currentPlanet'] === 'string' && String(parsed['currentPlanet']).length > 0
          ? String(parsed['currentPlanet']) : (config.planetMode === 'follow' ? 'Earth' : config.planetMode)
        config.planetMode = nextCyclePlanet(currentDisplayed)
        writeFormConfig(this.context, formId, config)
        writeFormTimeOffset(this.context, formId, 0)
        const data = resolveCardDataForForm(this.context, formId, Date.now())
        this.pushFormUpdate(formId, data)
        hilog.info(DOMAIN, TAG, 'cyclePlanet formId=%{public}s -> %{public}s', formId, config.planetMode)
        return
      }

      if (eventType === 'toggleEventReminder') {
        void this.handleToggleEventReminder(formId, parsed)
        return
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'onFormEvent parse failed: %{public}s', String(error))
    }
  }

  private pushFormUpdate(formId: string, data: Record<string, string>): void {
    const bindingData = formBindingData.createFormBindingData(data)
    formProvider.updateForm(formId, bindingData).catch((error: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'update card failed: code=%{public}d msg=%{public}s', error.code, error.message)
    })
  }

  private async handleToggleEventReminder(formId: string, params: Record<string, Object>): Promise<void> {
    const eventId = typeof params['eventId'] === 'string' ? String(params['eventId']).trim() : ''
    const title = typeof params['title'] === 'string' ? String(params['title']).trim() : '天象提醒'
    const target = typeof params['target'] === 'string' ? String(params['target']).trim() : ''
    const observerPlanet = typeof params['observerPlanet'] === 'string' && String(params['observerPlanet']).trim().length > 0
      ? String(params['observerPlanet']).trim() : 'Earth'
    const eventAt = Number(params['at'] ?? 0)
    const jd = Number(params['jd'] ?? 0)
    if (eventId.length === 0) return

    const entries = readRemindedEntries(this.context)
    let existingIndex = -1
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].eventId === eventId) {
        existingIndex = i
        break
      }
    }

    let toast = ''
    if (existingIndex >= 0) {
      const existingId = entries[existingIndex].reminderId
      try {
        await reminderAgentManager.cancelReminder(existingId)
      } catch (_) {
        // Reminder may already have expired or been cleared by system
      }
      const nextEntries: WidgetRemindedEntry[] = []
      for (let i = 0; i < entries.length; i++) {
        if (i !== existingIndex) nextEntries.push(entries[i])
      }
      writeRemindedEntries(this.context, nextEntries)
      toast = '已取消提醒'
      hilog.info(DOMAIN, TAG, 'widget reminder cancelled: eventId=%{public}s id=%{public}d', eventId, existingId)
    } else {
      try {
        const now = Date.now()
        const triggerMs = Number.isFinite(eventAt) && eventAt > now + 35 * 60000
          ? eventAt - 30 * 60000
          : Math.max(now + 90000, Number.isFinite(eventAt) ? eventAt : now + 90000)
        const triggerDate = new Date(triggerMs)
        const isOffEarth = observerPlanet.toLowerCase() !== 'earth'
        const badgeTitle = isOffEarth
          ? ('星象仪 · 【' + planetZhName(observerPlanet) + '】' + title)
          : ('星象仪 · ' + title)
        const req: reminderAgentManager.ReminderRequestCalendar = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
          dateTime: {
            year: triggerDate.getFullYear(),
            month: triggerDate.getMonth() + 1,
            day: triggerDate.getDate(),
            hour: triggerDate.getHours(),
            minute: triggerDate.getMinutes(),
            second: 0
          },
          title: badgeTitle,
          content: isOffEarth
            ? (planetZhName(observerPlanet) + '观测视角 · 轻触打开星图定位该天象')
            : '天象临近 · 轻触打开星象仪查看观测时机',
          slotType: notificationManager.SlotType.CONTENT_INFORMATION,
          wantAgent: {
            pkgName: 'com.joinother.skyinstrument',
            abilityName: 'QAbility'
          },
          actionButton: [
            { title: '知道了', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }
          ]
        }
        const reminderId = await reminderAgentManager.publishReminder(req)
        entries.push({ eventId: eventId, reminderId: reminderId })
        writeRemindedEntries(this.context, entries)
        toast = '已预约提醒'
        hilog.info(DOMAIN, TAG, 'widget reminder published: eventId=%{public}s id=%{public}d jd=%{public}f target=%{public}s',
          eventId, reminderId, jd, target)
      } catch (error) {
        const err = error as BusinessError
        hilog.warn(DOMAIN, TAG, 'widget publishReminder failed: code=%{public}d msg=%{public}s', err?.code ?? -1, err?.message ?? String(error))
        toast = '请先在星象仪开启通知'
      }
    }

    const data = resolveCardDataForForm(this.context, formId, Date.now())
    data['reminderToast'] = toast
    this.pushFormUpdate(formId, data)
  }

  private async triggerOverflow(formId: string): Promise<void> {
    try {
      const rect: formInfo.Rect = await formProvider.getFormRect(formId)
      if (rect.width <= 0 || rect.height <= 0) {
        hilog.warn(DOMAIN, TAG, 'requestOverflow skipped: invalid rect')
        return
      }
      const spec = computeOverflowArea(rect.width, rect.height)
      await formProvider.requestOverflow(formId, {
        area: {
          left: spec.left,
          top: spec.top,
          width: spec.width,
          height: spec.height
        },
        duration: spec.duration,
        // Disable system cross-fade so pixel-matched active/inactive UI transitions with zero double-image ghosting.
        useDefaultAnimation: false
      })
      hilog.info(DOMAIN, TAG, 'requestOverflow started: formId=%{public}s dim=%{public}s rect=%{public}s area=%{public}s',
        formId, spec.dimensionClass, JSON.stringify(rect), JSON.stringify(spec))
    } catch (error) {
      const err = error as BusinessError
      // Error 801 means the device does not support scene-animation overflow; fail silently and keep static card intact.
      hilog.info(DOMAIN, TAG, 'requestOverflow fallback: formId=%{public}s code=%{public}d msg=%{public}s',
        formId, err?.code ?? -1, err?.message ?? String(error))
    }
  }

  onRemoveForm(formId: string): void {
    removeFormMetadata(this.context, formId)
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY
  }
}
