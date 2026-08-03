interface PrivacyConsentCallbacks {
  onAcceptPrivacy: () => Promise<void>
}

@Entry
@Component
struct PrivacyConsent {
  @State private expanded: boolean = false
  private callbacks: PrivacyConsentCallbacks | undefined = undefined

  aboutToAppear(): void {
    const storage = this.getUIContext().getSharedLocalStorage()
    if (storage !== undefined) {
      this.callbacks = storage.get<PrivacyConsentCallbacks>('privacyConsentCallbacks')
    }
  }

  build() {
    Column({ space: 18 }) {
      Text('星象仪')
        .fontSize(30)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F4F7FA')
        .width('100%')

      Text('隐私保护说明')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F4F7FA')
        .width('100%')

      Text('星象仪在获得你的同意后，才会读取设备信息并使用位置、陀螺仪和加速度传感器，为你计算本地星空和方向指引。应用不提供账号服务，也不会将这些信息上传到服务器。')
        .fontSize(16)
        .fontColor('#C7D0DA')
        .lineHeight(25)
        .width('100%')

      if (this.expanded) {
        Text('位置权限仅在你主动使用“使用设备位置”时申请；陀螺仪和加速度传感器仅在你开启方向查看时使用。你可以在系统设置中随时关闭这些权限。')
          .fontSize(15)
          .fontColor('#A9B4BF')
          .lineHeight(23)
          .width('100%')
      }

      Text(this.expanded ? '收起详细说明' : '查看详细说明')
        .fontSize(15)
        .fontColor('#78B7FF')
        .onClick(() => {
          this.expanded = !this.expanded
        })
        .width('100%')

      Blank()

      Button('同意并进入')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(50)
        .backgroundColor('#2379D4')
        .borderRadius(8)
        .onClick(() => {
          if (this.callbacks !== undefined) {
            this.callbacks.onAcceptPrivacy()
          }
        })

      Text('不同意则无法进入星图。')
        .fontSize(13)
        .fontColor('#82909E')
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 56, right: 28, bottom: 36, left: 28 })
    .backgroundColor('#10151C')
  }
}
