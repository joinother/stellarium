interface PrivacyConsentCallbacks {
  onAcceptPrivacy: () => Promise<void>
  onDeclinePrivacy: () => Promise<void>
}

@CustomDialog
struct PrivacyConsentDialog {
  controller: CustomDialogController
  onAccept: () => void = (): void => {}
  onDecline: () => void = (): void => {}

  build() {
    Column({ space: 0 }) {
      Image($r('app.media.app_icon'))
        .width(40)
        .height(40)
        .borderRadius(10)
        .margin({ bottom: 8 })

      Text('星象仪')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#18202B')
        .margin({ bottom: 8 })

      Text('隐私保护提示')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#18202B')
        .margin({ bottom: 14 })

      Text('为提供本地星图与方向指引，星象仪会在你同意后使用设备位置和方向传感器等必要信息。')
        .fontSize(15)
        .fontColor('#4E5969')
        .lineHeight(22)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ bottom: 10 })

      Text('相关权限仅在使用对应功能时申请，信息仅在本机处理，不会上传至服务器。点击“同意”即表示你已阅读并同意《隐私声明》。')
        .fontSize(13)
        .fontColor('#7B8798')
        .lineHeight(19)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ bottom: 20 })

      Row({ space: 10 }) {
        Button('暂不使用')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0A59C7')
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: '#C8D1DE' })
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick((): void => {
            this.onDecline()
          })

        Button('同意')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor('#0A59C7')
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .onClick((): void => {
            this.onAccept()
          })
      }
      .width('100%')
    }
    .width('84%')
    .constraintSize({ maxWidth: 360 })
    .padding({ top: 24, right: 20, bottom: 20, left: 20 })
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
  }
}

@Entry
@Component
struct PrivacyConsent {
  private callbacks: PrivacyConsentCallbacks | undefined = undefined
  private dialogShown: boolean = false
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: PrivacyConsentDialog({
      onAccept: (): void => {
        this.acceptPrivacy()
      },
      onDecline: (): void => {
        this.declinePrivacy()
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true,
    maskColor: 'rgba(0, 0, 0, 0.62)'
  })

  aboutToAppear(): void {
    const storage = this.getUIContext().getSharedLocalStorage()
    if (storage !== undefined) {
      this.callbacks = storage.get<PrivacyConsentCallbacks>('privacyConsentCallbacks')
    }
    if (!this.dialogShown) {
      this.dialogShown = true
      this.dialogController.open()
    }
  }

  private async acceptPrivacy(): Promise<void> {
    this.dialogController.close()
    if (this.callbacks !== undefined) {
      await this.callbacks.onAcceptPrivacy()
    }
  }

  private async declinePrivacy(): Promise<void> {
    this.dialogController.close()
    if (this.callbacks !== undefined) {
      await this.callbacks.onDeclinePrivacy()
    }
  }

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#10151C')
  }
}
