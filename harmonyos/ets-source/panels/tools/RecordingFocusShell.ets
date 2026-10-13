// 录制聚焦态的全屏触摸承接层。
//
// 本身无状态：只把天空触摸事件下发给宿主 `handleSkyTouch`（选中 / 平移 / 缩放），
// 与录制控制条一起构成录制中"收起控制条"的聚焦壳。回调注入，不持有 store。
//
// 视觉：撑满父容器、HitTestMode.Default。
@Component
export struct RecordingFocusShell {
  onSkyTouch: (event: TouchEvent) => void = () => {}

  build() {
    Stack() { }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Default)
      .onTouch((event: TouchEvent) => { this.onSkyTouch(event) })
  }
}
