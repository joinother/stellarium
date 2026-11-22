// AR 实景观星与预研域状态 store：
// 持有实景相机融合状态、混合比例、镜头 FOV、硬件能力探测摘要，以及离线四模式预研字段。
// 消费方以 @ObjectLink 订阅；字段随用户操作与桥回包更新，宿主与组件的刷新语义不变。
@Observed
export class ARStore {
  arCameraActive: boolean = false
  arCameraStarting: boolean = false
  arSkyBlend: number = 0.55
  arCameraFovDeg: number = 60
  arHardwareSummary: string = ''
  arEngineSlamSupported: boolean = false
  arEngineDepthSupported: boolean = false
  arEngineMeshSupported: boolean = false
  arCameraSupported: boolean = true
  arPreviewMode: string = 'portal'
  arRevealProgress: number = 0.62
  arPreviewStatus: string = ''
}
