export function proceduralModelKind(type: string): string {
  const value = type.toLowerCase()
  if (value.includes('quasar') || value.includes('类星体')) return 'quasar'
  if (value.includes('pulsar') || value.includes('脉冲星')) return 'pulsar'
  if (value.includes('globular') || value.includes('球状星团')) return 'globular-cluster'
  if (value.includes('cluster') || value.includes('星团')) return 'open-cluster'
  if (value.includes('exoplanet') || value.includes('planet') || value.includes('nova') ||
    value.includes('satellite') || value.includes('nebula') || value.includes('galaxy')) return ''
  if (/\bstar\b/.test(value) || value.includes('恒星') || value.includes('变星') || value.includes('双星')) return 'star'
  return ''
}

export function proceduralStarColor(temperature: number): number[] {
  if (!Number.isFinite(temperature) || temperature <= 0) return [238, 242, 248]
  if (temperature >= 11000) return [168, 200, 255]
  if (temperature >= 7500) return [214, 229, 255]
  if (temperature >= 6000) return [255, 245, 216]
  if (temperature >= 4500) return [255, 211, 163]
  return [255, 170, 134]
}

export function proceduralParticles(kind: string, identity: string): number[][] {
  let seed = 2166136261
  for (let index = 0; index < identity.length; index++) seed = Math.imul(seed ^ identity.charCodeAt(index), 16777619) >>> 0
  const random = (): number => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
    return seed / 4294967296
  }
  const particles: number[][] = []
  if (kind === 'globular-cluster' || kind === 'open-cluster') {
    const count = kind === 'globular-cluster' ? 1100 : 170
    for (let index = 0; index < count; index++) {
      const longitude = random() * Math.PI * 2
      const latitude = random() * 2 - 1
      const radial = Math.pow(random(), kind === 'globular-cluster' ? 1.6 : 0.45)
      const equatorial = Math.sqrt(1 - latitude * latitude) * radial
      const warm = random() > 0.45
      particles.push([Math.cos(longitude) * equatorial, latitude * radial, Math.sin(longitude) * equatorial,
        0.010 + random() * 0.012, warm ? 255 : 179, warm ? 224 : 211, warm ? 173 : 255, 0.9])
    }
  } else if (kind === 'pulsar') {
    for (let direction = -1; direction <= 1; direction += 2) {
      for (let index = 0; index < 300; index++) {
        const distance = 0.12 + random() * 0.94
        const angle = random() * Math.PI * 2
        const spread = distance * 0.14 * random()
        particles.push([direction * distance * 0.35 + Math.cos(angle) * spread,
          direction * distance * 0.94, Math.sin(angle) * spread,
          0.014 + distance * 0.018, 145, 207, 255, 0.28 * (1 - distance * 0.5)])
      }
    }
  }
  return particles
}

function blendParticle(output: Uint8Array, size: number, centerX: number, centerY: number,
  radius: number, color: number[], opacity: number): void {
  const extent = Math.max(1, radius * 2)
  for (let row = Math.max(0, Math.floor(centerY - extent)); row <= Math.min(size - 1, Math.ceil(centerY + extent)); row++) {
    for (let column = Math.max(0, Math.floor(centerX - extent)); column <= Math.min(size - 1, Math.ceil(centerX + extent)); column++) {
      const squared = ((column - centerX) ** 2 + (row - centerY) ** 2) / Math.max(0.2, radius * radius)
      if (squared > 4) continue
      const alpha = opacity * Math.exp(-squared * 1.8)
      const offset = (row * size + column) * 4
      const oldAlpha = output[offset + 3] / 255
      const combined = alpha + oldAlpha * (1 - alpha)
      if (combined <= 0) continue
      for (let channel = 0; channel < 3; channel++) {
        output[offset + channel] = Math.round((color[channel] * alpha + output[offset + channel] * oldAlpha * (1 - alpha)) / combined)
      }
      output[offset + 3] = Math.round(combined * 255)
    }
  }
}

export function renderProceduralModel(kind: string, temperature: number, particles: number[][],
  transform: number[], size: number, scale: number): ArrayBuffer {
  const buffer = new ArrayBuffer(size * size * 4)
  const output = new Uint8Array(buffer)
  const center = (size - 1) / 2
  const radius = size * 0.39 * scale
  const color = proceduralStarColor(temperature)
  if (kind === 'star' || kind === 'quasar' || kind === 'pulsar') {
    const bodyRadius = kind === 'star' ? 0.90 : kind === 'pulsar' ? 0.14 : 0.11
    const diskVisible = kind === 'quasar' && Math.abs(transform[5]) >= 0.0001
    const extent = radius * (diskVisible ? 1 : bodyRadius)
    const start = Math.max(0, Math.floor(center - extent) - 1)
    const end = Math.min(size - 1, Math.ceil(center + extent) + 1)
    for (let row = start; row <= end; row++) {
      const screenY = (center - row) / radius
      for (let column = start; column <= end; column++) {
        const screenX = (column - center) / radius
        const squared = screenX * screenX + screenY * screenY
        const offset = (row * size + column) * 4
        if (squared < bodyRadius * bodyRadius) {
          const screenZ = Math.sqrt(bodyRadius * bodyRadius - squared) / bodyRadius
          const bodyX = transform[0] * screenX / bodyRadius + transform[1] * screenY / bodyRadius + transform[2] * screenZ
          const bodyY = transform[3] * screenX / bodyRadius + transform[4] * screenY / bodyRadius + transform[5] * screenZ
          const bodyZ = transform[6] * screenX / bodyRadius + transform[7] * screenY / bodyRadius + transform[8] * screenZ
          const grain = 0.94 + 0.035 * Math.sin(bodyX * 85 + Math.sin(bodyZ * 47)) * Math.sin(bodyY * 73)
          const brightness = (0.55 + 0.45 * screenZ) * grain
          for (let channel = 0; channel < 3; channel++) output[offset + channel] = kind === 'quasar' ? 2 : Math.round(color[channel] * brightness)
          output[offset + 3] = Math.round(255 * Math.min(1, (bodyRadius - Math.sqrt(squared)) * radius))
        }
        if (!diskVisible) continue
        const screenZ = -(transform[3] * screenX + transform[4] * screenY) / transform[5]
        const bodyX = transform[0] * screenX + transform[1] * screenY + transform[2] * screenZ
        const bodyZ = transform[6] * screenX + transform[7] * screenY + transform[8] * screenZ
        const radial = Math.sqrt(bodyX * bodyX + bodyZ * bodyZ)
        if (radial < 0.15 || radial > 1 || Math.abs(screenZ) > 1.1) continue
        if (squared < bodyRadius * bodyRadius && screenZ < Math.sqrt(bodyRadius * bodyRadius - squared)) continue
        const heat = Math.pow(1 - radial, 0.65)
        const pattern = 0.86 + 0.14 * Math.sin(radial * 95 + 6 * Math.atan2(bodyZ, bodyX))
        output[offset] = Math.round(255 * pattern)
        output[offset + 1] = Math.round((85 + heat * 170) * pattern)
        output[offset + 2] = Math.round((28 + heat * 175) * pattern)
        output[offset + 3] = Math.round(255 * Math.min(1, (1 - radial) * 8) * (0.45 + heat * 0.55))
      }
    }
  }
  const projected: number[][] = particles.map((point: number[]) => {
    const screenX = transform[0] * point[0] + transform[3] * point[1] + transform[6] * point[2]
    const screenY = transform[1] * point[0] + transform[4] * point[1] + transform[7] * point[2]
    const screenZ = transform[2] * point[0] + transform[5] * point[1] + transform[8] * point[2]
    return [screenX, screenY, screenZ, point[3], point[4], point[5], point[6], point[7]]
  })
  projected.sort((left: number[], right: number[]) => left[2] - right[2])
  for (const point of projected) {
    if (kind === 'pulsar' && point[0] ** 2 + point[1] ** 2 < 0.14 ** 2 && point[2] < 0) continue
    blendParticle(output, size, center + point[0] * radius, center - point[1] * radius,
      Math.max(0.65, point[3] * radius), [point[4], point[5], point[6]], point[7])
  }
  return buffer
}
