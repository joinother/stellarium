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
  @StorageLink('stellariumPrivacyConsentVerifiedUi') private consentVerifiedUi: boolean = false
  @StorageLink('stellariumQtContentReady') private qtContentReady: boolean = false
  @Watch('onSkyReady') @StorageLink('stellariumStartupSkyReady') private skyReady: boolean = false
  @Watch('onSkyReady') @StorageLink('stellariumStartupArtComplete') private artComplete: boolean = false
  @State private loadingVisible: boolean = true
  @State private loadingOpacity: number = 1
  @State private loadingLabel: string = ''

  aboutToAppear(): void {
    AppStorage.setOrCreate('i18nLang', I18n.systemLanguage())
    this.onLanguageChanged()
    // Dismiss the startup layer when the sky/art gates are already open by the
    // time this page mounts (warm restart, or a UI-only run that releases the
    // gates before the page is constructed): @Watch only fires on later changes,
    // so without this the loading layer would stay on top forever. No-op while
    // the gates are still false, which is the normal cold-start path.
    this.onSkyReady()
  }

  private onLanguageChanged(): void {
    this.loadingLabel = startupLoadingLabel(I18n.t('msg_loading'))
  }

  // 系统返回手势 / 返回键：优先交由应用内处理（关闭详情卡 → 退出极轴镜 → 面板返回或关闭）。
  // 宿主（WindowNativeNode）把"当前是否有可返回的应用内状态"镜像到 AppStorage，这里据此决定是否
  // 消费；无可返回时才交回系统（退出应用）。此前没有 onBackPress，系统返回会直接退到桌面。
  onBackPress(): boolean {
    if (AppStorage.get<boolean>('stellariumBackConsumable') === true) {
      AppStorage.setOrCreate('stellariumRequestBack', Date.now())
      return true
    }
    return false
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
          if (this.nativeAllowed || this.consentVerifiedUi) {
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
