import { common } from '@kit.AbilityKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import {
  buildAstronomyCard,
  buildTimeline48hSnapshot,
  CardTonightData,
  defaultCardConfig
} from '../form/AstronomyCardData'
import {
  resolveCardDataForConfig,
  resolveCardDataForForm,
  writePlanetSnapshot
} from '../form/FormStoreHelper'

export interface CardPublishResult {
  snapshot: Record<string, string>
  updatedForms: number
  failedForms: number
}

export async function readAstronomyCard(context: common.UIAbilityContext): Promise<Record<string, string>> {
  return resolveCardDataForConfig(context, defaultCardConfig(), Date.now())
}

export async function publishAstronomyCard(context: common.UIAbilityContext, tonight: CardTonightData): Promise<CardPublishResult> {
  const now = Date.now()
  const snapshot = buildAstronomyCard(tonight, now)
  const timelineRaw = buildTimeline48hSnapshot(tonight, now)
  writePlanetSnapshot(context, snapshot, timelineRaw)
  const result: CardPublishResult = { snapshot: snapshot, updatedForms: 0, failedForms: 0 }
  try {
    const forms = await formProvider.getPublishedRunningFormInfos()
    for (let i = 0; i < forms.length; i++) {
      const form = forms[i]
      if (form.bundleName !== 'com.joinother.skyinstrument') continue
      try {
        // Resolve per-formId data so pinned Mars/Moon/Titan cards keep their own world
        // while 'follow' cards immediately switch to the app's current world.
        const formData = resolveCardDataForForm(context, form.formId, now)
        await formProvider.updateForm(form.formId, formBindingData.createFormBindingData(formData))
        result.updatedForms++
      } catch (_) {
        result.failedForms++
      }
    }
  } catch (_) {
    result.failedForms++
  }
  return result
}
