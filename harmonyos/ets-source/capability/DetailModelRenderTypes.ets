export interface DetailModelLight {
  viewToBody: number[]
  sunDirectionBody: number[]
  emissive: boolean
}

export interface DetailModelRing {
  innerRadius: number
  outerRadius: number
  opacity: number
}

export interface DetailModelResources {
  texture?: ArrayBuffer
  textureWidth: number
  textureHeight: number
  textureStride: number
  ringTexture?: ArrayBuffer
  ringWidth: number
  ringHeight: number
  ringSpec?: DetailModelRing
  kind: string
  temperature: number
  particles: number[][]
}

export interface DetailModelFrame {
  renderSize: number
  scale: number
  transform: number[]
  lighting?: DetailModelLight
}

export interface DetailModelRequest {
  resources?: DetailModelResources
  frame: DetailModelFrame
}

export interface DetailModelResult {
  pixels?: ArrayBuffer
  computeMs: number
  uiPulseCount?: number
  uiMaxDelayMs?: number
  error?: string
}
