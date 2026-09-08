export const STARTUP_GATHER_MS: number = 1250
export const STARTUP_STAGGER_MS: number = 120
export const STARTUP_HOLD_MS: number = 220
export const STARTUP_REVEAL_AT_MS: number = STARTUP_GATHER_MS + STARTUP_STAGGER_MS + STARTUP_HOLD_MS
export const STARTUP_REVEAL_MS: number = 1100

export function startupLoadingLabel(text: string): string {
  return text.replace(/[.…⋯]+\s*$/, '').trim()
}

export interface StartupPoint {
  x: number
  y: number
}

export interface StartupStarAppearance {
  radius: number
  brightness: number
  color: string
  phase: number
  period: number
}

export function startupAppearance(index: number): StartupStarAppearance {
  const prominence = Math.pow(startupSeed(index, 5), 4)
  const temperature = startupSeed(index, 6)
  return {
    radius: 0.28 + prominence * 1.5,
    brightness: 0.16 + prominence * 0.78,
    color: temperature < 0.16 ? '#F4D6AF' : temperature < 0.4 ? '#A5CDF4' : '#E9EEFA',
    phase: startupSeed(index, 7) * Math.PI * 2,
    period: 2400 + startupSeed(index, 8) * 9000
  }
}

export function startupEase(value: number): number {
  const bounded = Math.max(0, Math.min(1, value))
  return bounded * bounded * bounded * (bounded * (bounded * 6 - 15) + 10)
}

export function startupSeed(index: number, channel: number): number {
  let mixed = Math.imul(index + 1, 374761393) ^ Math.imul(channel + 1, 668265263)
  mixed = Math.imul(mixed ^ (mixed >>> 13), 1274126177)
  return ((mixed ^ (mixed >>> 16)) >>> 0) / 4294967296
}

export function startupDrift(index: number, width: number, height: number, elapsed: number): StartupPoint {
  const phase = startupSeed(index, 2) * Math.PI * 2
  const time = elapsed * 1.4 / (8000 + startupSeed(index, 3) * 16000)
  return {
    x: width * (startupSeed(index, 0) + Math.sin(time + phase) * 0.025 +
      Math.sin(time * 0.731 + phase * 1.7) * 0.012),
    y: height * (startupSeed(index, 1) + Math.sin(time * 0.613 + phase * 2.3) * 0.023 +
      Math.sin(time * 1.113 + phase * 0.9) * 0.011)
  }
}

export function startupParticle(index: number, target: StartupPoint, width: number,
  height: number, elapsed: number, assemblyElapsed: number = elapsed): StartupPoint {
  const source = startupDepthPoint(index, width, height, elapsed)
  const blend = startupEase((assemblyElapsed - startupSeed(index, 11) * STARTUP_STAGGER_MS) / STARTUP_GATHER_MS)
  if (blend === 1) return { x: target.x, y: target.y }
  const horizontal = target.x - source.x
  const vertical = target.y - source.y
  const bend = (startupSeed(index, 12) - 0.5) * 0.7 * blend * (1 - blend)
  return { x: source.x + horizontal * blend - vertical * bend,
    y: source.y + vertical * blend + horizontal * bend }
}

export function startupReveal(assemblyElapsed: number): number {
  return startupEase((assemblyElapsed - STARTUP_REVEAL_AT_MS) / STARTUP_REVEAL_MS)
}

export function startupDepthPoint(index: number, width: number, height: number,
  elapsed: number, reveal: number = 0): StartupPoint {
  const point = startupDrift(index, width, height, elapsed)
  const depth = 0.2 + startupSeed(index, 13) * 0.8
  const scale = 1 + depth * (0.08 * startupEase(elapsed / 5000) + 0.16 * startupEase(reveal))
  return { x: width / 2 + (point.x - width / 2) * scale,
    y: height / 2 + (point.y - height / 2) * scale }
}

export function startupReleasePoint(index: number, point: StartupPoint, width: number,
  height: number, reveal: number): StartupPoint {
  const progress = Math.max(0, Math.min(1, reveal))
  const depth = 0.3 + startupSeed(index, 13) * 0.7
  return {
    x: point.x + ((point.x - width / 2) * 0.18 + (startupSeed(index, 14) - 0.5) * width * 0.1) * depth * progress,
    y: point.y + ((point.y - height / 2) * 0.18 + (startupSeed(index, 15) - 0.5) * height * 0.12) * depth * progress
  }
}
