import { common } from '@kit.AbilityKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import preferences from '@ohos.data.preferences'
import { buildAstronomyCard, normalizeAstronomyCard, buildTimeline48hSnapshot, applyTimeline48hToCard, CardTonightData } from '../form/AstronomyCardData'

export interface CardPublishResult {
  snapshot: Record<string, string>
  updatedForms: number
  failedForms: number
}

export async function readAstronomyCard(context: common.UIAbilityContext): Promise<Record<string, string>> {
  const store = await preferences.getPreferences(context, 'sky_instrument_card')
  const raw = await store.get('almanacSnapshot', '')
  const timelineRaw = await store.get('timeline48hSnapshot', '')
  const now = Date.now()
  const card = normalizeAstronomyCard(typeof raw === 'string' ? raw : '', now)
  return applyTimeline48hToCard(card, typeof timelineRaw === 'string' ? timelineRaw : '', now)
}

export async function publishAstronomyCard(context: common.UIAbilityContext, tonight: CardTonightData): Promise<CardPublishResult> {
  const now = Date.now()
  const snapshot = buildAstronomyCard(tonight, now)
  const timelineRaw = buildTimeline48hSnapshot(tonight, now)
  const store = await preferences.getPreferences(context, 'sky_instrument_card')
  await store.put('almanacSnapshot', JSON.stringify(snapshot))
  if (timelineRaw.length > 0) {
    await store.put('timeline48hSnapshot', timelineRaw)
  }
  await store.flush()
  const result: CardPublishResult = { snapshot: snapshot, updatedForms: 0, failedForms: 0 }
  try {
    const forms = await formProvider.getPublishedRunningFormInfos()
    const reloadKeys: Array<string> = []
    for (const form of forms) {
      if (form.bundleName !== 'com.joinother.skyinstrument') continue
      try {
        await formProvider.updateForm(form.formId, formBindingData.createFormBindingData(snapshot))
        result.updatedForms++
        const reloadKey = form.moduleName + '|' + form.abilityName + '|' + form.formName
        if (!reloadKeys.includes(reloadKey)) reloadKeys.push(reloadKey)
      } catch (_) {
        result.failedForms++
      }
    }
    for (const reloadKey of reloadKeys) {
      const parts = reloadKey.split('|')
      if (parts.length !== 3) continue
      try {
        await formProvider.reloadForms(context, parts[0], parts[1], parts[2])
      } catch (_) {
      }
    }
  } catch (_) {
    result.failedForms++
  }
  return result
}
