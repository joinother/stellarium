// AR 预研域状态 store：持有预览模式（overlay / portal / depth / sky-only）、地景抠除进度与状态文案。
// 消费方以 @ObjectLink 订阅；字段随用户操作与桥回包更新，宿主与组件的刷新语义不变。
@Observed
export class ARStore {
  arPreviewMode: string = 'portal'
  arRevealProgress: number = 0.62
  arPreviewStatus: string = ''
}
