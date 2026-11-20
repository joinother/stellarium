export function panelFontSize(base: number, readable: boolean): number {
  return readable ? Math.min(base + 2, Math.round(base * 1.22)) : base
}

export function objectDetailFontSize(base: number, readable: boolean, emphasis: boolean = false): number {
  if (!readable) return base
  const scale = emphasis ? 1.12 : 1.08
  return Math.min(base + (emphasis ? 2 : 1), Math.round(base * scale))
}

export function clampUiScale(scale: number): number {
  if (!Number.isFinite(scale) || scale <= 0) return 1.0
  return Math.max(0.9, Math.min(1.45, scale))
}

export function uiFontSize(base: number, readable: boolean, scale: number = 1.0): number {
  const stepped = panelFontSize(base, readable)
  const effective = clampUiScale(scale)
  return Math.max(10, Math.min(Math.round(stepped * 1.45), Math.round(stepped * effective)))
}

export function uiControlHeight(base: number, readable: boolean, scale: number = 1.0): number {
  const readableBase = readable ? Math.round(base * 1.1) : base
  const effective = clampUiScale(scale)
  return Math.round(readableBase * (1 + (effective - 1) * 0.65))
}

export function uiChipPaddingV(base: number, scale: number = 1.0): number {
  const effective = clampUiScale(scale)
  return Math.max(base, Math.round(base * (1 + (effective - 1) * 0.5)))
}
