import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit'
import { Want } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { computeOverflowArea, defaultAstronomyCard, extractInverseTextColor } from './AstronomyCardData'
import {
  readFormConfig,
  removeFormMetadata,
  resolveCardDataForForm,
  writeFormKind,
  writeFormTextColor
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
    const data = resolveCardDataForForm(this.context, formId, Date.now())
    if (inverseColor.length > 0) {
      data['textColor'] = inverseColor
    }
    const bindingData = formBindingData.createFormBindingData(data)
    formProvider.updateForm(formId, bindingData).catch((error: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'update card failed: code=%{public}d msg=%{public}s', error.code, error.message)
    })
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
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'onFormEvent parse failed: %{public}s', String(error))
    }
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
        useDefaultAnimation: true
      })
      hilog.info(DOMAIN, TAG, 'requestOverflow started: formId=%{public}s dim=%{public}s', formId, spec.dimensionClass)
    } catch (error) {
      const err = error as BusinessError
      // Error 801 means the device does not support scene-animation overflow; fail silently and keep static card intact.
      hilog.info(DOMAIN, TAG, 'requestOverflow fallback: code=%{public}d msg=%{public}s', err?.code ?? -1, err?.message ?? String(error))
    }
  }

  onRemoveForm(formId: string): void {
    removeFormMetadata(this.context, formId)
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY
  }
}
