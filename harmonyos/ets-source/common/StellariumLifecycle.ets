export type LifecycleListener = (foreground: boolean) => void

let listener: LifecycleListener | undefined = undefined

export function setLifecycleListener(next: LifecycleListener | undefined): void {
  listener = next
}

export function notifyLifecycle(foreground: boolean): void {
  if (listener !== undefined) {
    listener(foreground)
  }
}
