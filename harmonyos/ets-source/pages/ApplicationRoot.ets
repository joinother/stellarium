import { PrivacyBootstrap } from './PrivacyBootstrap'
import { WindowNativeNode } from './MainWindowNativeNode'
import { StartupSky } from './StartupSky'
import { I18n } from './I18n'
import { STARTUP_REVEAL_MS, startupLoadingLabel } from './StartupStarGeometry'
import hilog from '@ohos.hilog'

@Entry
@Component
struct ApplicationRoot {
  @Watch('onLanguageChanged') @StorageLink('i18nLang') private language: string = ''
  @StorageLink('stellariumStartupForeground') private foreground: boolean = true
  @StorageLink('stellariumPrivacyNativeStartupAllowed') private nativeAllowed: boolean = false
  @StorageLink('stellariumQtContentReady') private qtContentReady: boolean = false
  @Watch('onSkyReady') @StorageLink('stellariumStartupSkyReady') private skyReady: boolean = false
  @Watch('onSkyReady') @StorageLink('stellariumStartupArtComplete') private artComplete: boolean = false
  @State private loadingVisible: boolean = true
  @State private loadingOpacity: number = 1
  @State private loadingLabel: string = ''

  aboutToAppear(): void {
    AppStorage.setOrCreate('i18nLang', I18n.systemLanguage())
    this.onLanguageChanged()
  }

  private onLanguageChanged(): void {
    this.loadingLabel = startupLoadingLabel(I18n.t('msg_loading'))
  }

  private onSkyReady(): void {
    if (!this.skyReady || !this.artComplete || this.loadingOpacity === 0) return
    this.getUIContext().animateTo({ duration: STARTUP_REVEAL_MS, curve: Curve.EaseInOut,
      onFinish: () => {
        this.loadingVisible = false
        hilog.info(0, 'StellariumStartup', '[startup] sky-revealed')
      } }, () => { this.loadingOpacity = 0 })
  }

  build() {
    Stack() {
      if (this.nativeAllowed && this.qtContentReady) {
        WindowNativeNode()
      }
      if (this.loadingVisible) {
        Stack() {
          StartupSky().hitTestBehavior(HitTestMode.Block)
          if (this.nativeAllowed) {
            Row({ space: 8 }) {
              Text(this.loadingLabel)
                .fontSize(12).fontColor('#9CAEC5').maxLines(2)
                .letterSpacing(1).textAlign(TextAlign.Center)
                .constraintSize({ maxWidth: '70%' })
              LoadingProgress().width(14).height(14).color('#9CAEC5')
                .enableLoading(this.foreground)
            }.width('85%').justifyContent(FlexAlign.Center)
              .translate({ y: 88 }).hitTestBehavior(HitTestMode.None)
          }
        }.width('100%').height('100%').opacity(this.loadingOpacity)
      }
      if (!this.nativeAllowed || !this.qtContentReady) {
        PrivacyBootstrap()
      }
    }.width('100%').height('100%').backgroundColor('#05070F')
  }
}
