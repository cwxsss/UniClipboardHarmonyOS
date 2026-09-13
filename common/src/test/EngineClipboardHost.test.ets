import { describe, expect, it } from '@ohos/hypium';
import {
  BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS,
  BACKGROUND_CLIPBOARD_POLL_RELAXED_INTERVAL_MS,
  BACKGROUND_CLIPBOARD_POLL_SLOW_INTERVAL_MS,
  nextClipboardPollingDelayMs,
  shouldNotifyClipboardChange,
  shouldStartClipboardPolling
} from '../main/ets/engine/EngineClipboardHost';

export default function engineClipboardHostTest(): void {
  describe('EngineClipboardHost', (): void => {
    it('uses an adaptive low-power background fallback', 0, async (): Promise<void> => {
      expect(BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS).assertEqual(1000);
      expect(BACKGROUND_CLIPBOARD_POLL_RELAXED_INTERVAL_MS).assertEqual(2000);
      expect(BACKGROUND_CLIPBOARD_POLL_SLOW_INTERVAL_MS).assertEqual(5000);
      expect(nextClipboardPollingDelayMs(0, false)).assertEqual(1000);
      expect(nextClipboardPollingDelayMs(1, false)).assertEqual(1000);
      expect(nextClipboardPollingDelayMs(2, false)).assertEqual(2000);
      expect(nextClipboardPollingDelayMs(4, false)).assertEqual(5000);
      expect(nextClipboardPollingDelayMs(120, true)).assertEqual(1000);
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
