export function panelFontSize(base: number, readable: boolean): number {
  return readable ? Math.min(base + 2, Math.round(base * 1.22)) : base
}

export function objectDetailFontSize(base: number, readable: boolean, emphasis: boolean = false): number {
  if (!readable) return base
  const scale = emphasis ? 1.12 : 1.08
  return Math.min(base + (emphasis ? 2 : 1), Math.round(base * scale))
}
