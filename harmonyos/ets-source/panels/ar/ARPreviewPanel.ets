import { Theme } from '@kit.ArkUI'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { ARStore } from '../../state/ARStore'
import { GyroStore } from '../../state/GyroStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// AR 实景观星与预研面板（`activePanel === 'ar'`）。
//
// 一期能力：后置相机预览经 OH_NativeImage 接入 OpenGL ES 单通 GPU 融合，叠加星图 + 陀螺仪指向、
// 星空/实景混合滑杆、镜头视场角匹配与手动罗盘偏置微调；下方保留离线四模式遮罩预研。
interface ArPreviewModeOption {
  id: string
  label: string
}

@Component
export struct ARPreviewPanel {
  @ObjectLink arStore: ARStore
  @ObjectLink gyroStore: GyroStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private labExpanded: boolean = false
  onToggleCamera: () => void = () => {}
  onSetSkyBlend: (value: number) => void = () => {}
  onSetCameraFov: (fovDeg: number) => void = () => {}
  onNudgeCompass: (deltaDeg: number) => void = () => {}
  onResetCompass: () => void = () => {}
  onClosePanelForFullAr: () => void = () => {}
  onSetMode: (mode: string) => void = () => {}
  onSetRevealProgress: (value: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private blendLabel(): string {
    const pct = Math.round(this.arStore.arSkyBlend * 100)
    if (pct <= 15) return '偏实景 ' + String(pct) + '%'
    if (pct >= 88) return '偏星空 ' + String(pct) + '%'
    return '融合 ' + String(pct) + '%'
  }

  private compassOffsetText(): string {
    const v = this.gyroStore.gyroOffsetAz
    if (Math.abs(v) < 0.05) return '0.0°'
    return (v > 0 ? '+' : '') + v.toFixed(1) + '°'
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 顶部标题与隐私说明
        Row({ space: 4 }) {
          Text('AR 实景观星').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.c.text)
          InfoTipButton({
            title: 'AR 实景观星说明',
            tip: '通过后置相机与 OpenGL 单通融合实时叠加星图、星座与天体标签，并自动开启陀螺仪寻星。相机画面仅在本地 GPU 实时合成，不拍照、不落盘、不上传；关闭 AR 或退后台即刻释放相机。'
          })
        }.width('100%').alignItems(VerticalAlign.Center)

        // 主控卡片：开启/关闭实景 AR + 硬件能力探测结果
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Button(this.arStore.arCameraStarting
              ? '正在启动相机…'
              : (this.arStore.arCameraActive ? '关闭 AR 实景' : '开启 AR 实景观星'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.arStore.arCameraActive ? this.c.text : this.c.onAccent)
              .backgroundColor(this.arStore.arCameraActive ? this.c.errorBg : this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL)
              .height(40)
              .layoutWeight(1)
              .enabled(!this.arStore.arCameraStarting && this.arStore.arCameraSupported)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onToggleCamera() })

            if (this.arStore.arCameraActive) {
              Button('全屏观星')
                .fontSize(12)
                .fontColor(this.c.accent)
                .backgroundColor(this.c.accentSoft)
                .borderRadius(UI_RADIUS_CONTROL)
                .height(40)
                .padding({ left: 12, right: 12 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.onClosePanelForFullAr() })
            }
          }.width('100%')

          if (this.arStore.arHardwareSummary.length > 0) {
            Text(this.arStore.arHardwareSummary)
              .fontSize(11)
              .fontColor(this.c.sub)
              .lineHeight(16)
              .width('100%')
          }
          if (this.arStore.arPreviewStatus.length > 0) {
            Text(this.arStore.arPreviewStatus)
              .fontSize(11)
              .fontColor(this.c.tertiary)
              .lineHeight(16)
              .width('100%')
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CARD)
        .border({ width: 0.5, color: this.c.border })

        // 实景-星空混合 + 镜头视场角匹配 + 罗盘偏置微调
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text('实景 · 星空').fontSize(12).fontColor(this.c.text).width(78)
            Slider({ value: this.arStore.arSkyBlend, min: 0, max: 1, step: 0.02, style: SliderStyle.OutSet })
              .layoutWeight(1)
              .blockColor(this.c.accent)
              .trackColor(this.c.bgStrong)
              .selectedColor(this.c.accent)
              .onChange((v: number) => { this.onSetSkyBlend(v) })
            Text(this.blendLabel()).fontSize(11).fontColor(this.c.sub).width(64).textAlign(TextAlign.End)
          }.width('100%').alignItems(VerticalAlign.Center)

          Row({ space: 8 }) {
            Text('镜头视场角').fontSize(12).fontColor(this.c.text).width(78)
            Slider({ value: this.arStore.arCameraFovDeg, min: 35, max: 85, step: 1, style: SliderStyle.OutSet })
              .layoutWeight(1)
              .blockColor(this.c.accent)
              .trackColor(this.c.bgStrong)
              .selectedColor(this.c.accent)
              .onChange((v: number) => { this.onSetCameraFov(v) })
            Text(Math.round(this.arStore.arCameraFovDeg) + '°').fontSize(11).fontColor(this.c.sub).width(64).textAlign(TextAlign.End)
          }.width('100%').alignItems(VerticalAlign.Center)

          Divider().color(this.c.border).strokeWidth(0.5)

          Row({ space: 6 }) {
            Text('罗盘微调').fontSize(12).fontColor(this.c.text)
            Text('对齐月亮/亮星').fontSize(10.5).fontColor(this.c.tertiary).layoutWeight(1)
            Text(this.compassOffsetText()).fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(this.c.accent)
          }.width('100%').alignItems(VerticalAlign.Center)

          Row({ space: 6 }) {
            Button('-5°')
              .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 2, right: 2 }).layoutWeight(1)
              .onClick(() => { this.onNudgeCompass(-5) })
            Button('-1°')
              .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 2, right: 2 }).layoutWeight(1)
              .onClick(() => { this.onNudgeCompass(-1) })
            Button('归零')
              .fontSize(11).fontColor(this.c.accent).backgroundColor(this.c.accentSoft)
              .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 2, right: 2 }).layoutWeight(1)
              .onClick(() => { this.onResetCompass() })
            Button('+1°')
              .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 2, right: 2 }).layoutWeight(1)
              .onClick(() => { this.onNudgeCompass(1) })
            Button('+5°')
              .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_PILL).height(30).padding({ left: 2, right: 2 }).layoutWeight(1)
              .onClick(() => { this.onNudgeCompass(5) })
          }.width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CARD)
        .border({ width: 0.5, color: this.c.border })

        // 进阶遮罩预研（折叠，保留离线四模式与地景抠除验证契约）
        Column({ space: 10 }) {
          Row() {
            Text('进阶遮罩预研（离线示意）').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.sub).layoutWeight(1)
            Text(this.labExpanded ? '收起' : '展开').fontSize(11).fontColor(this.c.accent)
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
              this.labExpanded = !this.labExpanded
            })
          })

          if (this.labExpanded) {
            Row({ space: 6 }) {
              ForEach([
                { id: 'overlay', label: '星空叠加' },
                { id: 'portal', label: '地景递进' },
                { id: 'depth', label: '深度遮挡' },
                { id: 'sky-only', label: '只保留星空' }
              ] as ArPreviewModeOption[], (item: ArPreviewModeOption) => {
                Text(item.label)
                  .fontSize(11)
                  .fontColor(this.arStore.arPreviewMode === item.id ? this.c.onAccent : this.c.sub)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(32)
                  .padding({ top: 7, bottom: 7 })
                  .backgroundColor(this.arStore.arPreviewMode === item.id ? this.c.accent : this.c.soft)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                  .onClick(() => { this.onSetMode(item.id) })
              }, (item: ArPreviewModeOption) => item.id)
            }.width('100%')

            Stack({ alignContent: Alignment.TopStart }) {
              Column() {
                Text('星空层').fontSize(14).fontColor(this.c.fourth).margin({ top: 22 })
                Text(this.arStore.arPreviewMode === 'depth' ? '等待深度/网格适配' : (this.arStore.arPreviewMode === 'sky-only' ? '地面遮罩已抠除，仅保留星空' : '星体与坐标叠加预览'))
                  .fontSize(11).fontColor(this.c.spinner).margin({ top: 6 })
              }
                .width('100%').height(160).justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Center)
                .backgroundColor(this.c.mediaCard)
              Column() {
                Text('地面 / 墙面层').fontSize(13).fontColor(this.c.detailSub).margin({ top: 24 })
                Text(this.arStore.arPreviewMode === 'portal' ? '拖动进度，观察从地景到星空的递进' : (this.arStore.arPreviewMode === 'sky-only' ? '只保留星空层' : '遮挡层'))
                  .fontSize(10).fontColor(this.c.iconTertiary).margin({ top: 6 })
              }
                .width(((1 - this.arStore.arRevealProgress) * 100).toFixed(2) + '%').height(160)
                .backgroundColor(this.c.overlayScrim)
                .alignItems(HorizontalAlign.Center)
                .clip(true)
              if (this.arStore.arPreviewMode === 'portal') {
                Column() {
                  Text('门户边缘').fontSize(10).fontColor(this.c.iconSecondary)
                }
                  .width(96).height(116).border({ width: 1.5, color: this.c.dockActive })
                  .borderRadius(UI_RADIUS_CARD).margin({ left: 16, top: 22 }).opacity(0.86)
              }
            }
              .width('100%').height(160).clip(true).borderRadius(UI_RADIUS_CARD)
              .border({ width: 0.5, color: this.c.border })

            Row({ space: 8 }) {
              Text('地景抠除').fontSize(12).fontColor(this.c.text).width(62)
              Slider({ value: this.arStore.arRevealProgress, min: 0, max: 1, step: 0.01, style: SliderStyle.OutSet })
                .layoutWeight(1).blockColor(this.c.accent).trackColor(this.c.bgStrong).selectedColor(this.c.accent)
                .onChange((value: number) => { this.onSetRevealProgress(value) })
              Text(Math.round(this.arStore.arRevealProgress * 100) + '%').fontSize(11).fontColor(this.c.sub).width(42).textAlign(TextAlign.End)
            }.width('100%').height(34)
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CARD)
        .border({ width: 0.5, color: this.c.border })
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
