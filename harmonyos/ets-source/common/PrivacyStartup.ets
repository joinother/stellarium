let consentAcceptedListener: (() => void) | undefined = undefined;
let startupCanvasReadyListener: (() => void) | undefined = undefined;

export function setStartupCanvasReadyListener(listener: (() => void) | undefined): void {
  startupCanvasReadyListener = listener;
}

export function notifyStartupCanvasReady(): void {
  if (startupCanvasReadyListener !== undefined) startupCanvasReadyListener();
}

export function setConsentAcceptedListener(listener: (() => void) | undefined): void {
  consentAcceptedListener = listener;
}

export function notifyConsentAccepted(): void {
  if (consentAcceptedListener !== undefined) consentAcceptedListener();
}
