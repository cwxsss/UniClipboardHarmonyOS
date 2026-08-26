import { describe, expect, it } from '@ohos/hypium';
import {
  BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS,
  shouldNotifyClipboardChange,
  shouldStartClipboardPolling
} from '../main/ets/engine/EngineClipboardHost';

export default function engineClipboardHostTest(): void {
  describe('EngineClipboardHost', (): void => {
    it('keeps the background fallback at or below 200ms', 0, async (): Promise<void> => {
      expect(BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS <= 200).assertTrue();
    });

    it('does not create a duplicate polling timer', 0, async (): Promise<void> => {
      expect(shouldStartClipboardPolling(true, true, -1)).assertTrue();
      expect(shouldStartClipboardPolling(true, true, 1)).assertFalse();
      expect(shouldStartClipboardPolling(false, true, -1)).assertFalse();
      expect(shouldStartClipboardPolling(true, false, -1)).assertFalse();
    });

    it('does not notify twice for the same clipboard text', 0, async (): Promise<void> => {
      expect(shouldNotifyClipboardChange(true, 'same', 'same')).assertFalse();
      expect(shouldNotifyClipboardChange(true, 'old', 'new')).assertTrue();
      expect(shouldNotifyClipboardChange(false, '', 'new')).assertFalse();
    });
  });
}
