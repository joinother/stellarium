// 底部 Dock 的"实时激活态" store：只放数据，不含 UI / NAPI，也不自持端口 / hooks。
//
// 消费方：Dock 各入口以 @ObjectLink 观察同一 @Observed 实例。
// 为何经 @ObjectLink 注入而非 @Prop：入口用 `ForEach` 渲染，键值生成函数对未变键的数组项
// 不会重新执行 itemGenerator，把 `active` 作为 @Prop 直接传进子项会在复用后冻结；把激活态
// 并入键值又会让子项销毁重建、打断动画。同一 @Observed 实例经 @ObjectLink 注入可让激活态
// 变化时入口只重渲染、不重建（V1 深观察），且键值保持稳定。
@Observed
export class DockStore {
  activePanel: string = ''
  panelVisible: boolean = false
}
