import { pasteboard } from '@kit.BasicServicesKit';
import { hasCurrentPrivacyConsent } from './PrivacyConsent';

export interface ClipboardWriteResult {
  ok: boolean;
  error?: string;
  characters?: number;
}

let writePending: boolean = false;

export async function writeClipboardText(text: string): Promise<ClipboardWriteResult> {
  if (!hasCurrentPrivacyConsent() || AppStorage.get<boolean>('stellariumStartupForeground') !== true) {
    return { ok: false, error: 'privacy consent and foreground are required' };
  }
  if (text.length === 0 || text.length > 2097152) {
    return { ok: false, error: 'text must contain 1..2097152 characters' };
  }
  if (writePending) {
    return { ok: false, error: 'clipboard write is already pending' };
  }
  writePending = true;
  try {
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
    return { ok: true, characters: text.length };
  } catch (_) {
    return { ok: false, error: 'clipboard write failed' };
  } finally {
    writePending = false;
  }
}
