import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit'
import { common, Want } from '@kit.AbilityKit'
import preferences from '@ohos.data.preferences'
import hilog from '@ohos.hilog'
import { defaultAstronomyCard, normalizeAstronomyCard, applyTimeline48hToCard } from './AstronomyCardData'

const CARD_STORE = 'sky_instrument_card'
const CARD_SNAPSHOT_KEY = 'almanacSnapshot'
const CARD_TIMELINE_KEY = 'timeline48hSnapshot'
const DOMAIN = 0xD003
const TAG = 'SkyInstrumentForm'

function defaultCardData(): Record<string, string> {
  return defaultAstronomyCard()
}

async function readCardData(context: common.FormExtensionContext): Promise<Record<string, string>> {
  const fallback = defaultCardData()
  try {
    const store = await preferences.getPreferences(context, CARD_STORE)
    const raw = await store.get(CARD_SNAPSHOT_KEY, '')
    if (typeof raw !== 'string' || raw.length === 0) return fallback
    const timelineRaw = await store.get(CARD_TIMELINE_KEY, '')
    const now = Date.now()
    const card = normalizeAstronomyCard(raw, now)
    return applyTimeline48hToCard(card, typeof timelineRaw === 'string' ? timelineRaw : '', now)
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'read card snapshot failed: %{public}s', String(error))
    return fallback
  }
}

export default class SkyInstrumentFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '')
    if (formId.length > 0) {
      void readCardData(this.context).then((data: Record<string, string>) => {
        return formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      }).catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'initial card update failed: %{public}s', error.message)
      })
    }
    return formBindingData.createFormBindingData(defaultCardData())
  }

  onUpdateForm(formId: string): void {
    void readCardData(this.context).then((data: Record<string, string>) => {
      const bindingData = formBindingData.createFormBindingData(data)
      return formProvider.updateForm(formId, bindingData)
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'update card failed: %{public}s', error.message)
    })
  }

  onRemoveForm(_formId: string): void {
    // No external resource or subscription is created by the card.
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY
  }
}
