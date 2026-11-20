import { FormEditExtensionAbility } from '@kit.FormKit'
import { UIExtensionContentSession, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0xD003
const TAG: string = 'SkyFormEditAbility'

export default class SkyInstrumentFormEditAbility extends FormEditExtensionAbility {
  onCreate(): void {
    hilog.info(DOMAIN, TAG, 'onCreate')
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy')
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    const storage: LocalStorage = new LocalStorage()
    const params = want.parameters as Record<string, Object> | undefined
    const formId: string = params !== undefined && params['cardId'] !== undefined
      ? String(params['cardId']) : ''
    const previewFormId: string = params !== undefined && params['previewCardId'] !== undefined
      ? String(params['previewCardId']) : ''

    storage.setOrCreate('formId', formId)
    storage.setOrCreate('previewFormId', previewFormId)
    storage.setOrCreate('context', this.context)

    hilog.info(DOMAIN, TAG, 'onSessionCreate formId=%{public}s previewFormId=%{public}s', formId, previewFormId)
    try {
      session.loadContent('form/SkyFormEditPage', storage)
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', String(error))
    }
  }

  onSessionDestroy(_session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, 'onSessionDestroy')
  }
}
