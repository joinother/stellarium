import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import {
  CHROME_ZOOM_EDGE_PADDING,
  chromeZoomLayerHeight,
  chromeZoomLayerTop
} from '../../common/ui/ChromeGeometry'

// 面板/Dock 壳层的四个小组件。
//
// 都是无状态外观件：时钟文本、几何参数与拖拽回调由宿主以 @Prop / 回调解入。

// 主界面 Dock 右上常驻时钟（HH:mm）：点按直接打开时间面板。
@Component
export struct DockClockChip {
  @Prop clockText: string
  onOpenTime: () => void = () => {}

  build() {
    Row() {
      Text(this.clockText)
        .fontSize(22)
        .fontColor('rgba(229, 255, 255, 0.85)')
    }
      .height(36)
      .padding({ left: 14, right: 14 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('rgba(10, 14, 26, 0.55)')
      .backdropBlur(20)
      .borderRadius(UI_RADIUS_PILL)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onOpenTime() })
  }
}

// Dock 时钟定位层：右端与 dock 栏对齐；空白区触摸穿透回星图，仅时钟本体拦截点击。
@Component
export struct DockClockLayer {
  @Prop clockText: string
  @Prop layerWidth: number
  @Prop posX: number
  @Prop posY: number
  onOpenTime: () => void = () => {}

  build() {
    Row() {
      Stack() { DockClockChip({ clockText: this.clockText, onOpenTime: this.onOpenTime }) }
        .hitTestBehavior(HitTestMode.Block)
    }
      .width(this.layerWidth)
      .height(44)
      .justifyContent(FlexAlign.End)
      .padding({ right: 4 })
      .position({ x: this.posX, y: this.posY })
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(40)
  }
}

// Dock 上方的视场（FOV）读数胶囊：与常驻时钟同一行（posY = dockTop - 48）。
//
// 造型：双行 —— 上行 10vp 的 "FOV" 细字标签，下行 16vp 的数值。
// 之所以不用单行 "FOV 60.0°"：单行在 22vp 下约 134vp 宽，是时钟（"10:44" ≈ 83vp）的 1.55 倍，
// 左右两端体量不对称。双行后宽度只由最宽的一行决定（数值 ≈ 43~51vp + 24 内边距 ≈ 67~75vp），
// 反而比时钟更窄，且**高度仍保持 36vp**，与时钟同高、读数行不受影响（缩放按钮的贴靠关系不变）。
// 纯信息展示：整层与胶囊都不参与命中测试，点击穿透回星图。
@Component
export struct DockFovChip {
  @Prop fovText: string
  @Prop textColor: string

  build() {
    Column() {
      Text('FOV')
        .fontSize(10)
        .height(12)
        .fontColor('rgba(229, 255, 255, 0.55)')
      Text(this.fovText)
        .fontSize(16)
        .height(20)
        .fontColor(this.textColor.length > 0 ? this.textColor : 'rgba(229, 255, 255, 0.85)')
    }
      .height(36)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(10, 14, 26, 0.55)')
      .backdropBlur(20)
      .borderRadius(UI_RADIUS_PILL)
      .hitTestBehavior(HitTestMode.None)
  }
}

// Dock 视场显示定位层：与常驻时钟同一行，贴在左端（右端留给时钟，左右对称），
// 缩放按钮列的正下方 —— 两者同列，形成"上方按钮、下方读数"的一组。
@Component
export struct DockFovLayer {
  @Prop fovText: string
  @Prop layerWidth: number
  @Prop posX: number
  @Prop posY: number
  @Prop textColor: string

  build() {
    Row() {
      DockFovChip({ fovText: this.fovText, textColor: this.textColor })
    }
      .width(this.layerWidth)
      .height(44)
      .justifyContent(FlexAlign.Start)
      .padding({ left: 4 })
      .position({ x: this.posX, y: this.posY })
      .hitTestBehavior(HitTestMode.None)
      .zIndex(40)
  }
}

// 星图缩放按钮层：非手势缩放（直接走原生 zoomStep，与键盘快捷键同一命令族，factor<1 放大、>1 缩小）。
// 排列由形态决定：手机·半折竖排（44×2 + 8 间距 = 96 高），平板横排（一行 44 高 + 4 间隙）；
// 两种排列都紧贴读数行上沿 —— rowY 即读数行上沿，由宿主按形态给出，本组件自持几何，
// 避免 96/44/4 这些数字散落到两个壳里去重复。
// 空白区触摸穿透回星图，仅按钮本体拦截点击。视觉与 DockClockChip 同族。
@Component
export struct SkyZoomLayer {
  @Prop layerWidth: number
  @Prop posX: number
  @Prop rowY: number
  @Prop horizontal: boolean
  @Prop textColor: string
  onZoomIn: () => void = () => {}
  onZoomOut: () => void = () => {}

  @Builder
  zoomButtonPair() {
    Stack({ alignContent: Alignment.Center }) {
      Text('+')
        .fontSize(24)
        .fontColor(this.textColor.length > 0 ? this.textColor : 'rgba(229, 255, 255, 0.85)')
    }
      .width(44)
      .height(44)
      .backgroundColor('rgba(10, 14, 26, 0.55)')
      .backdropBlur(20)
      .borderRadius(22)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onZoomIn() })
      .id('skyZoomInButton')
    Stack({ alignContent: Alignment.Center }) {
      Text('−')
        .fontSize(24)
        .fontColor(this.textColor.length > 0 ? this.textColor : 'rgba(229, 255, 255, 0.85)')
    }
      .width(44)
      .height(44)
      .backgroundColor('rgba(10, 14, 26, 0.55)')
      .backdropBlur(20)
      .borderRadius(22)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onZoomOut() })
      .id('skyZoomOutButton')
  }

  build() {
    Row() {
      if (this.horizontal) {
        Row({ space: 8 }) {
          this.zoomButtonPair()
        }
          .hitTestBehavior(HitTestMode.Block)
      } else {
        Column({ space: 8 }) {
          this.zoomButtonPair()
        }
          .hitTestBehavior(HitTestMode.Block)
      }
    }
      .width(this.layerWidth)
      .height(chromeZoomLayerHeight(this.horizontal))
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .padding({ left: CHROME_ZOOM_EDGE_PADDING })
      .position({ x: this.posX, y: chromeZoomLayerTop(this.rowY, this.horizontal) })
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(40)
  }
}

// 平板/折叠布局的面板抓手（纯装饰）。
@Component
export struct PadPanelHandle {
  build() {
    Row()
      .width(58)
      .height(5)
      .backgroundColor('rgba(255, 255, 255, 0.58)')
      .borderRadius(3)
      .alignSelf(ItemAlign.Center)
      .margin({ top: 2, bottom: 10 })
      .hitTestBehavior(HitTestMode.None)
  }
}

// 手机紧凑面板的抓手：垂直拖拽由宿主接管（更新/结算面板高度）。
@Component
export struct PanelHandle {
  onDrag: (offsetY: number) => void = () => {}
  onDragFinish: () => void = () => {}

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(58)
        .height(5)
        .backgroundColor('rgba(255, 255, 255, 0.30)')
        .borderRadius(3)
    }
      .width('100%')
      .height(28)
      .alignSelf(ItemAlign.Center)
      .margin({ bottom: 2 })
      .gesture(
        PanGesture()
          .onActionUpdate((event: GestureEvent) => {
            this.onDrag(event.offsetY)
          })
          .onActionEnd(() => {
            this.onDragFinish()
          })
      )
  }
}
