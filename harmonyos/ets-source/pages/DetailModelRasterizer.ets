import { renderProceduralModel } from './ProceduralDetailModel'
import { DetailModelResources, DetailModelFrame } from './DetailModelRenderTypes'

export function renderDetailModel(resources: DetailModelResources, frame: DetailModelFrame): ArrayBuffer {
    const texture = new Uint8Array(resources.texture ?? new ArrayBuffer(0))
    const textureWidth = resources.textureWidth
    const textureHeight = resources.textureHeight
    const textureStride = resources.textureStride
    const renderSize = frame.renderSize
    const outputBuffer = resources.kind.length > 0
      ? renderProceduralModel(resources.kind, resources.temperature,
        resources.particles, frame.transform, renderSize, frame.scale)
      : new ArrayBuffer(renderSize * renderSize * 4)
    const output = new Uint8Array(outputBuffer)
    const center = (renderSize - 1) / 2
    const ringSpec = resources.ringSpec
    const ringScaleLimit = ringSpec === undefined ? 0.39 : Math.min(0.39, 0.46 / ringSpec.outerRadius)
    const radius = renderSize * ringScaleLimit * frame.scale
    const transform = frame.transform
    const lighting = frame.lighting
    const isSun = lighting?.emissive === true
    const lightX = lighting?.sunDirectionBody[0] ?? 0
    const lightY = lighting?.sunDirectionBody[1] ?? 0
    const lightZ = lighting?.sunDirectionBody[2] ?? 0
    if (resources.kind.length === 0) {
    const firstRow = Math.max(0, Math.floor(center - radius) - 1)
    const lastRow = Math.min(renderSize - 1, Math.ceil(center + radius) + 1)
    for (let y = firstRow; y <= lastRow; y++) {
      const sphereY = (center - y) / radius
      if (Math.abs(sphereY) > 1) continue
      const extent = Math.sqrt(1 - sphereY * sphereY) * radius
      const firstColumn = Math.max(0, Math.floor(center - extent) - 1)
      const lastColumn = Math.min(renderSize - 1, Math.ceil(center + extent) + 1)
      for (let x = firstColumn; x <= lastColumn; x++) {
        const sphereX = (x - center) / radius
        const radiusSquared = sphereX * sphereX + sphereY * sphereY
        const outputIndex = (y * renderSize + x) * 4
        if (radiusSquared > 1) {
          continue
        }
        const sphereZ = Math.sqrt(1 - radiusSquared)
        const objectX = transform[0] * sphereX + transform[1] * sphereY + transform[2] * sphereZ
        const objectY = Math.max(-1, Math.min(1,
          transform[3] * sphereX + transform[4] * sphereY + transform[5] * sphereZ))
        const objectZ = transform[6] * sphereX + transform[7] * sphereY + transform[8] * sphereZ
        let textureU = Math.atan2(objectX, objectZ) / (2 * Math.PI) + 0.5
        textureU -= Math.floor(textureU)
        const textureV = Math.max(0, Math.min(1, 0.5 - Math.asin(objectY) / Math.PI))
        const textureX = textureU * textureWidth
        const textureY = textureV * (textureHeight - 1)
        const x0 = Math.floor(textureX) % textureWidth
        const y0 = Math.floor(textureY)
        const x1 = (x0 + 1) % textureWidth
        const y1 = Math.min(textureHeight - 1, y0 + 1)
        const fractionX = textureX - Math.floor(textureX)
        const fractionY = textureY - y0
        const topLeft = y0 * textureStride + x0 * 4
        const topRight = y0 * textureStride + x1 * 4
        const bottomLeft = y1 * textureStride + x0 * 4
        const bottomRight = y1 * textureStride + x1 * 4
        const topWeight = 1 - fractionY
        const leftWeight = 1 - fractionX
        const red = (texture[topLeft] * leftWeight + texture[topRight] * fractionX) * topWeight +
          (texture[bottomLeft] * leftWeight + texture[bottomRight] * fractionX) * fractionY
        const green = (texture[topLeft + 1] * leftWeight + texture[topRight + 1] * fractionX) * topWeight +
          (texture[bottomLeft + 1] * leftWeight + texture[bottomRight + 1] * fractionX) * fractionY
        const blue = (texture[topLeft + 2] * leftWeight + texture[topRight + 2] * fractionX) * topWeight +
          (texture[bottomLeft + 2] * leftWeight + texture[bottomRight + 2] * fractionX) * fractionY
        const lightDot = objectX * lightX + objectY * lightY + objectZ * lightZ
        let brightness = 1
        if (isSun || lighting === undefined) {
          brightness = 0.86 + sphereZ * 0.14
        } else {
          const transition = Math.max(0, Math.min(1, (lightDot + 0.08) / 0.16))
          const smoothLight = transition * transition * (3 - 2 * transition)
          brightness = (0.17 + 0.83 * smoothLight) * (0.80 + sphereZ * 0.20)
        }
        output[outputIndex] = Math.round(Math.max(0, Math.min(255, red * brightness)))
        output[outputIndex + 1] = Math.round(Math.max(0, Math.min(255, green * brightness)))
        output[outputIndex + 2] = Math.round(Math.max(0, Math.min(255, blue * brightness)))
        output[outputIndex + 3] = Math.round(255 * Math.max(0, Math.min(1,
          (1 - Math.sqrt(radiusSquared)) * radius)))
      }
    }
    renderDetailModelRings(resources, output, renderSize, center, radius, transform)
    }
    return outputBuffer
}

function renderDetailModelRings(
    resources: DetailModelResources,
    output: Uint8Array,
    renderSize: number,
    center: number,
    planetRadius: number,
    transform: number[],
  ): void {
    const ringSpec = resources.ringSpec
    const ringBuffer = resources.ringTexture
    if (ringSpec === undefined || ringBuffer === undefined ||
      resources.ringWidth <= 0 || resources.ringHeight <= 0) {
      return
    }
    const ringTexture = new Uint8Array(ringBuffer)
    const ringWidth = resources.ringWidth
    const outerRadius = planetRadius * ringSpec.outerRadius
    const innerRadius = planetRadius * ringSpec.innerRadius
    const outerRadiusSquared = outerRadius * outerRadius
    const innerRadiusSquared = innerRadius * innerRadius
    for (let y = 0; y < renderSize; y++) {
      const screenY = (center - y)
      for (let x = 0; x < renderSize; x++) {
        const screenX = (x - center)
        const outputIndex = (y * renderSize + x) * 4
        const normalizedX = screenX / planetRadius
        const normalizedY = screenY / planetRadius
        const sphereRadiusSquared = normalizedX * normalizedX + normalizedY * normalizedY
        const ringA = transform[3] * normalizedX + transform[4] * normalizedY
        const ringB = transform[5]
        if (Math.abs(ringB) < 0.0001) {
          continue
        }
        const screenZ = -ringA / ringB
        const objectX = transform[0] * normalizedX + transform[1] * normalizedY + transform[2] * screenZ
        const objectY = transform[3] * normalizedX + transform[4] * normalizedY + transform[5] * screenZ
        const objectZ = transform[6] * normalizedX + transform[7] * normalizedY + transform[8] * screenZ
        const ringRadiusSquared = (objectX * objectX + objectY * objectY + objectZ * objectZ) * planetRadius * planetRadius
        if (ringRadiusSquared < innerRadiusSquared || ringRadiusSquared > outerRadiusSquared) {
          continue
        }
        const ringRadius = Math.sqrt(ringRadiusSquared)
        const radialPosition = Math.max(0, Math.min(1,
          (ringRadius - innerRadius) / Math.max(1, outerRadius - innerRadius)))
        const textureX = radialPosition * (ringWidth - 1)
        const profileRadius = ringSpec.outerRadius > 3 ? 4 : 2
        const profileStart = Math.max(0, Math.floor(textureX - profileRadius))
        const profileEnd = Math.min(ringWidth - 1, Math.ceil(textureX + profileRadius))
        let bestAlpha = 0
        let red = 0
        let green = 0
        let blue = 0
        for (let profileX = profileStart; profileX <= profileEnd; profileX++) {
          for (let profileY = 0; profileY < resources.ringHeight; profileY++) {
            const profileIndex = (profileY * ringWidth + profileX) * 4
            const alpha = ringTexture[profileIndex + 3]
            if (alpha > bestAlpha) {
              bestAlpha = alpha
              red = ringTexture[profileIndex]
              green = ringTexture[profileIndex + 1]
              blue = ringTexture[profileIndex + 2]
            }
          }
        }
        const ringAlpha = Math.max((bestAlpha / 255) * ringSpec.opacity,
          ringSpec.outerRadius > 3 ? 0.16 : 0.10)
        if (ringAlpha <= 0.01) {
          continue
        }
        const planetFrontZ = sphereRadiusSquared <= 1
          ? Math.sqrt(Math.max(0, 1 - sphereRadiusSquared))
          : -Infinity
        if (sphereRadiusSquared <= 1 && screenZ <= planetFrontZ) {
          continue
        }
        const existingAlpha = output[outputIndex + 3] / 255
        const sourceAlpha = Math.max(0, Math.min(1, ringAlpha))
        const combinedAlpha = sourceAlpha + existingAlpha * (1 - sourceAlpha)
        if (combinedAlpha <= 0) {
          continue
        }
        output[outputIndex] = Math.round((red * sourceAlpha + output[outputIndex] * existingAlpha * (1 - sourceAlpha)) / combinedAlpha)
        output[outputIndex + 1] = Math.round((green * sourceAlpha + output[outputIndex + 1] * existingAlpha * (1 - sourceAlpha)) / combinedAlpha)
        output[outputIndex + 2] = Math.round((blue * sourceAlpha + output[outputIndex + 2] * existingAlpha * (1 - sourceAlpha)) / combinedAlpha)
        output[outputIndex + 3] = Math.round(combinedAlpha * 255)
      }
    }
  }
