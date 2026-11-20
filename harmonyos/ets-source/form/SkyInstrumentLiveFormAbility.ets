import { formInfo, LiveFormExtensionAbility, LiveFormInfo } from '@kit.FormKit'
import { UIExtensionContentSession } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { readFormKind, resolveCardDataForForm } from './FormStoreHelper'

const DOMAIN: number = 0xD003
const TAG: string = 'SkyLiveFormAbility'

export default class SkyInstrumentLiveFormAbility extends LiveFormExtensionAbility {
  onLiveFormCreate(liveFormInfo: LiveFormInfo, session: UIExtensionContentSession): void {
    const storage: LocalStorage = new LocalStorage()
    const formId: string = liveFormInfo.formId
    const borderRadius: number = liveFormInfo.borderRadius
    const formRect: formInfo.Rect = liveFormInfo.rect
    const formKind: string = readFormKind(this.context, formId)
    const snapshot: Record<string, string> = resolveCardDataForForm(this.context, formId, Date.now())

    storage.setOrCreate('context', this.context)
    storage.setOrCreate('formId', formId)
    storage.setOrCreate('borderRadius', borderRadius)
    storage.setOrCreate('formRect', formRect)
    storage.setOrCreate('formKind', formKind)
    storage.setOrCreate('snapshotJson', JSON.stringify(snapshot))

    hilog.info(DOMAIN, TAG, 'onLiveFormCreate formId=%{public}s kind=%{public}s rect=%{public}s',
      formId, formKind, JSON.stringify(formRect))

    try {
      session.loadContent('form/SkyLiveFormPage', storage)
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadContent SkyLiveFormPage failed: %{public}s', String(error))
    }
  }

  onLiveFormDestroy(liveFormInfo: LiveFormInfo): void {
    hilog.info(DOMAIN, TAG, 'onLiveFormDestroy formId=%{public}s', liveFormInfo.formId)
  }
}
