import { curves } from '@kit.ArkUI'
import { UI_MOTION_FAST_MS, UI_MOTION_STANDARD_MS } from './UiTokens'

// Unified HarmonyOS physics-based motion curves & transitions (arkts-animation-usage-guide).
// Physical spring curves derive duration from response & dampingFraction, so callers
// should pair them with `{ curve: uiSpring*() }` rather than a conflicting fixed duration.

export function uiSpringSnappy(): ICurve {
  return curves.springMotion(0.38, 0.88)
}

export function uiSpringStandard(): ICurve {
  return curves.springMotion(0.45, 0.88)
}

export function uiSpringGentle(): ICurve {
  return curves.springMotion(0.52, 0.90)
}

export function uiFadeUpTransition(): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY.animation({ duration: UI_MOTION_STANDARD_MS, curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ x: 0, y: 8 }).animation({ curve: uiSpringStandard() })),
    TransitionEffect.OPACITY.animation({ duration: UI_MOTION_FAST_MS, curve: Curve.EaseIn })
  )
}

export function uiSlideTransition(direction: number): TransitionEffect {
  const enterX = direction >= 0 ? 20 : -20
  const exitX = direction >= 0 ? -14 : 14
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY.animation({ duration: UI_MOTION_STANDARD_MS, curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ x: enterX, y: 0 }).animation({ curve: uiSpringStandard() })),
    TransitionEffect.OPACITY.animation({ duration: UI_MOTION_FAST_MS, curve: Curve.EaseIn })
      .combine(TransitionEffect.translate({ x: exitX, y: 0 }).animation({ duration: UI_MOTION_FAST_MS, curve: Curve.EaseIn }))
  )
}
