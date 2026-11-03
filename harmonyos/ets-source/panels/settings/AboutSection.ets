import { Theme } from '@kit.ArkUI'
import deviceInfo from '@ohos.deviceInfo'
import { I18n } from '../../pages/I18n'
import { ToolsStore } from '../../state/ToolsStore'
import {
  APPGALLERY_APP_URL,
  DISTRIBUTION_CONTRIBUTORS_URL,
  DISTRIBUTION_LICENSE,
  DISTRIBUTION_SOURCE_URL,
  UPSTREAM_SKY_CULTURES_URL,
  UPSTREAM_STELLARIUM_CONTRIBUTORS_URL,
  UPSTREAM_STELLARIUM_SOURCE_URL,
  UPSTREAM_STELLARIUM_URL,
  UPSTREAM_STELLARIUM_VERSION,
} from '../../common/QtAppConstants'
import { AppFilingInfo } from '../../common/ui/AppFilingInfo'
import { InfoRow } from '../../common/ui/InfoRow'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 「设置 → 关于」标签页：发行版信息 / 运行环境 / APP 备案 / 第三方许可 /
// 上游项目与本发行版 / 致谢与引用 / 诊断路径。
// 版本与路径由 ToolsStore 的 getAboutInfo 回包提供；打开本页时刷新一次。
// 上游与发行版的公开链接集中在 QtAppConstants，避免同一 URL 在多处维护。

interface AboutLicenseEntry {
  name: string
  license: string
  url: string
}

const ABOUT_LICENSES: Array<AboutLicenseEntry> = [
  { name: 'Qt 6.12.0', license: 'LGPL-3.0', url: 'https://www.qt.io/licensing/open-source-lgpl-obligations' },
  { name: 'md4c', license: 'MIT', url: 'https://github.com/mity/md4c' },
  { name: 'NLopt', license: 'LGPL-2.1-or-later', url: 'https://github.com/stevengj/nlopt' },
  { name: 'fast_float', license: 'Apache-2.0 / MIT / BSL-1.0', url: 'https://github.com/fastfloat/fast_float' },
]

@Component
export struct AboutSection {
  @ObjectLink tools: ToolsStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onOpenUrl: (url: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToAppear(): void {
    this.tools.loadAboutInfo()
  }

  private versionText(): string {
    return this.tools.aboutVersion.length > 0 ? this.tools.aboutVersion : I18n.t('c_loading')
  }

  private qtText(): string {
    return this.tools.aboutQt.length > 0 ? this.tools.aboutQt : '—'
  }

  private platformText(): string {
    const name = deviceInfo.osFullName
    return name.length > 0 ? name : 'HarmonyOS NEXT'
  }

  @Builder
  sectionTitle(text: ResourceStr) {
    Text(text).fontSize(12).fontColor(this.c.sub).width('100%')
      .padding({ left: 8 }).margin({ top: 6, bottom: 4 })
  }

  @Builder
  linkRow(label: ResourceStr, value: ResourceStr, url: string) {
    Row() {
      Text(label).fontSize(11).fontColor(this.c.text).layoutWeight(1)
      Text(value).fontSize(10).fontColor(this.c.accent)
        .constraintSize({ minHeight: 32 })
        .onClick(() => { this.onOpenUrl(url) })
    }.width('100%').padding({ left: 10, right: 10 })
  }

  build() {
    Column({ space: 0 }) {
      // 应用身份：中文 Stellarium·星象仪，英文 Stellarium for OHOS。
      Column({ space: 3 }) {
        Text(I18n.t('about_app_name')).fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.c.text).width('100%')
        Text(I18n.t('about_distribution_desc')).fontSize(10).fontColor(this.c.sub).width('100%')
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })

      // 发行版信息
      this.sectionTitle(I18n.t('about_section_info'))
      Column({ space: 0 }) {
        InfoRow({ label: I18n.t('about_distribution_version'), value: this.versionText() })
        InfoRow({ label: I18n.t('about_upstream_version'), value: UPSTREAM_STELLARIUM_VERSION })
        InfoRow({ label: 'Qt', value: this.qtText() })
        InfoRow({ label: I18n.t('s0352'), value: this.platformText() })
        InfoRow({ label: I18n.t('about_maintainer'), value: I18n.t('about_maintainer_name') })
        InfoRow({ label: I18n.t('resource_license'), value: DISTRIBUTION_LICENSE })
      }
      .width('100%').padding({ top: 3, bottom: 3 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })

      // APP 备案与隐私政策
      this.sectionTitle(I18n.t('about_section_filing'))
      AppFilingInfo()
      Row() {
        Column({ space: 1 }) {
          Text(I18n.t('about_project_privacy')).fontSize(11).fontColor(this.c.text).width('100%')
          Text(I18n.t('about_project_privacy_hint')).fontSize(9).fontColor(this.c.sub).width('100%')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(I18n.t('about_license_view')).fontSize(10).fontColor(this.c.accent)
          .constraintSize({ minHeight: 36 }).margin({ left: 8 })
      }
      .width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ top: 2, bottom: 6 })
      .onClick(() => { this.onOpenUrl(APPGALLERY_APP_URL) })

      // 第三方开源组件
      this.sectionTitle(I18n.t('about_section_licenses'))
      Text(I18n.t('about_license_note')).fontSize(9).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10 }).margin({ bottom: 5 })
      ForEach(ABOUT_LICENSES, (entry: AboutLicenseEntry) => {
        Row() {
          Column({ space: 1 }) {
            Text(entry.name).fontSize(12).fontColor(this.c.text).width('100%')
            Text(entry.license).fontSize(10).fontColor(this.c.sub).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text(I18n.t('about_license_view')).fontSize(10).fontColor(this.c.accent)
            .constraintSize({ minHeight: 36 })
            .margin({ left: 8 })
            .onClick(() => { this.onOpenUrl(entry.url) })
        }
        .width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
      }, (entry: AboutLicenseEntry) => entry.name)

      // 上游项目与本发行版
      this.sectionTitle(I18n.t('about_section_project'))
      Column({ space: 0 }) {
        Text(I18n.t('about_upstream_project')).fontSize(11).fontWeight(FontWeight.Medium)
          .fontColor(this.c.text).width('100%').padding({ left: 10, right: 10, top: 6, bottom: 2 })
        this.linkRow(I18n.t('about_project_website'), 'stellarium.org', UPSTREAM_STELLARIUM_URL)
        this.linkRow(I18n.t('about_project_source'), 'GitHub', UPSTREAM_STELLARIUM_SOURCE_URL)
        this.linkRow(I18n.t('about_upstream_contributors'), 'GitHub', UPSTREAM_STELLARIUM_CONTRIBUTORS_URL)
        InfoRow({ label: I18n.t('resource_license'), value: DISTRIBUTION_LICENSE })
        Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 4, bottom: 4 })
        Text(I18n.t('about_this_distribution')).fontSize(11).fontWeight(FontWeight.Medium)
          .fontColor(this.c.text).width('100%').padding({ left: 10, right: 10, top: 2, bottom: 2 })
        InfoRow({ label: I18n.t('about_maintainer'), value: I18n.t('about_maintainer_name') })
        this.linkRow(I18n.t('about_distribution_source'), 'GitHub', DISTRIBUTION_SOURCE_URL)
        InfoRow({ label: I18n.t('about_upstream_version'), value: UPSTREAM_STELLARIUM_VERSION })
        InfoRow({ label: I18n.t('resource_license'), value: DISTRIBUTION_LICENSE })
        Text(I18n.t('about_distribution_note')).fontSize(9).fontColor(this.c.sub).width('100%')
          .padding({ left: 10, right: 10, top: 4, bottom: 6 })
      }
      .width('100%').padding({ top: 4, bottom: 4 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })

      // 致谢与引用
      this.sectionTitle(I18n.t('about_credits'))
      Column({ space: 0 }) {
        this.linkRow(I18n.t('about_credits_upstream'), 'GitHub', UPSTREAM_STELLARIUM_CONTRIBUTORS_URL)
        this.linkRow(I18n.t('about_credits_data'), 'GitHub', UPSTREAM_SKY_CULTURES_URL)
        this.linkRow(I18n.t('about_credits_distribution'), 'GitHub', DISTRIBUTION_CONTRIBUTORS_URL)
        Text(I18n.t('about_project_citation')).fontSize(10).fontColor(this.c.sub).width('100%')
          .padding({ left: 10, right: 10, top: 5 })
        Text(I18n.t('about_project_citation_text')).fontSize(9).fontColor(this.c.sub).width('100%')
          .padding({ left: 10, right: 10, top: 2 })
        Text('doi.org/10.1558/jsa.17822').fontSize(9).fontColor(this.c.accent)
          .width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 6 })
          .onClick(() => { this.onOpenUrl('https://doi.org/10.1558/jsa.17822') })
      }
      .width('100%').padding({ top: 4, bottom: 4 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })

      // 诊断信息
      this.sectionTitle(I18n.t('about_section_diagnostics'))
      Text(I18n.t('about_diagnostics_note')).fontSize(9).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10 }).margin({ bottom: 4 })
      if (this.tools.aboutUserDir.length > 0) {
        Text(I18n.t('c_user_dir') + ': ' + this.tools.aboutUserDir).fontSize(9).fontColor(this.c.sub)
          .width('100%').padding({ left: 10, right: 10 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.tools.aboutConfigFile.length > 0) {
        Text(I18n.t('c_config_file') + ': ' + this.tools.aboutConfigFile).fontSize(9).fontColor(this.c.sub)
          .width('100%').padding({ left: 10, right: 10 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.tools.aboutLogFile.length > 0) {
        Text(I18n.t('about_log_file') + ': ' + this.tools.aboutLogFile).fontSize(9).fontColor(this.c.sub)
          .width('100%').padding({ left: 10, right: 10 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // 版权与许可声明
      Text('Copyright (C) 2000–2026 Stellarium Developers').fontSize(9).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10 }).margin({ top: 8 })
      Text(I18n.t('about_gpl_notice')).fontSize(9).fontColor(this.c.sub).width('100%')
        .padding({ left: 10, right: 10, bottom: 8 }).margin({ top: 2 }).maxLines(3)
    }
    .width('100%')
  }
}
