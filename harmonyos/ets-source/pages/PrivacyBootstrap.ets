@Entry
@Component
struct PrivacyBootstrap {
  @StorageLink('stellariumStartupPreparing')
  private startupPreparing: boolean = false

  build() {
    Stack() {
      if (this.startupPreparing) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#D8E7F3')
      }
    }
      .width('100%')
      .height('100%')
      .backgroundColor('#070b12')
  }
}
