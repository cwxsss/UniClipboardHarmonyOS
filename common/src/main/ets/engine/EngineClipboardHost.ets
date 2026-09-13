import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { EngineHostError, EngineHostErrorCategory } from './EngineHostError';
import { Logger } from '../util/Logger';

const PERMISSION_DENIED_CODE: number = 201;
const TEXT_FORMAT: string = 'text/plain';
export const BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS: number = 1000;
export const BACKGROUND_CLIPBOARD_POLL_RELAXED_INTERVAL_MS: number = 2000;
export const BACKGROUND_CLIPBOARD_POLL_SLOW_INTERVAL_MS: number = 5000;
const POLL_IDLE_RELAXED_ROUNDS: number = 2;
const POLL_IDLE_SLOW_ROUNDS: number = 4;
const logger: Logger = new Logger('ClipboardHost');

export function shouldStartClipboardPolling(pollingEnabled: boolean, listening: boolean,
  pollingTimerId: number): boolean {
  return pollingEnabled && listening && pollingTimerId < 0;
}

export function shouldNotifyClipboardChange(hasClipboardBaseline: boolean,
  lastClipboardText: string, currentText: string): boolean {
  return hasClipboardBaseline && currentText !== lastClipboardText;
}

export function nextClipboardPollingDelayMs(idleRounds: number, clipboardChanged: boolean): number {
  if (clipboardChanged || idleRounds < POLL_IDLE_RELAXED_ROUNDS) {
    return BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS;
  }
  if (idleRounds < POLL_IDLE_SLOW_ROUNDS) {
    return BACKGROUND_CLIPBOARD_POLL_RELAXED_INTERVAL_MS;
  }
  return BACKGROUND_CLIPBOARD_POLL_SLOW_INTERVAL_MS;
}

export interface EngineClipboardRepresentation {
  kind: string;
  format: string;
  mimeType?: string;
  bytes?: Uint8Array;
  handle?: string;
  displayName?: string;
  sizeBytes?: string;
}

export interface EngineClipboardSnapshot {
  observedAtMs: number;
  representations: EngineClipboardRepresentation[];
}

export interface EngineClipboardObserver {
  onClipboardChanged(snapshot: EngineClipboardSnapshot): void;
}

export class EngineClipboardHost {
  private systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
  private observer: EngineClipboardObserver | null = null;
  private listening: boolean = false;
  private pollingEnabled: boolean = false;
  private pollingTimerId: number = -1;
  private pollIdleRounds: number = 0;
  private hasClipboardBaseline: boolean = false;
  private lastClipboardText: string = '';
  private lastPollFailureLogAtMs: number = 0;
  private updateCallback = (): void => {
    let changed: boolean = this.notifyClipboardChange();
    if (changed) {
      this.pollIdleRounds = 0;
    }
  };

  verifyAccess(): void {
    try {
      this.systemPasteboard.getDataSync();
    } catch (error) {
      throw this.accessError(error as Object, 'clipboard_verify');
    }
  }

  read(): EngineClipboardSnapshot {
    try {
      let data: pasteboard.PasteData = this.systemPasteboard.getDataSync();
      let text: string = this.extractText(data);
      return this.snapshotFromText(text);
    } catch (error) {
      throw this.accessError(error as Object, 'clipboard_read');
    }
  }

  write(snapshot: EngineClipboardSnapshot): void {
    for (let index: number = 0; index < snapshot.representations.length; index += 1) {
      let representation: EngineClipboardRepresentation = snapshot.representations[index];
      if (representation.kind === 'inline' && representation.format === TEXT_FORMAT &&
        representation.bytes !== undefined) {
        try {
          let text: string = this.decoder.decodeToString(representation.bytes);
          let data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
          this.systemPasteboard.setDataSync(data);
          this.lastClipboardText = text;
          this.hasClipboardBaseline = true;
          this.pollIdleRounds = 0;
          return;
        } catch (error) {
          throw this.accessError(error as Object, 'clipboard_write');
        }
      }
    }
    throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'clipboard_format');
  }

  listen(observer: EngineClipboardObserver): void {
    this.releaseListener();
    this.observer = observer;
    this.pollIdleRounds = 0;
    this.primeClipboardBaseline();
    try {
      this.systemPasteboard.on('update', this.updateCallback);
      this.listening = true;
      this.startPollingIfNeeded();
    } catch (error) {
      this.observer = null;
      throw this.accessError(error as Object, 'clipboard_listen');
    }
  }

  setPollingEnabled(enabled: boolean): void {
    this.pollingEnabled = enabled;
    logger.info('Clipboard polling enabled=' + (enabled ? '1' : '0') +
      ' listening=' + (this.listening ? '1' : '0'));
    if (enabled) {
      this.pollIdleRounds = 0;
      this.startPollingIfNeeded();
    } else {
      this.stopPolling();
    }
  }

  releaseListener(): void {
    this.stopPolling();
    if (!this.listening) {
      this.observer = null;
      this.hasClipboardBaseline = false;
      this.pollIdleRounds = 0;
      return;
    }
    try {
      this.systemPasteboard.off('update', this.updateCallback);
    } catch (error) {
      throw this.accessError(error as Object, 'clipboard_release');
    } finally {
      this.listening = false;
      this.observer = null;
      this.hasClipboardBaseline = false;
      this.pollIdleRounds = 0;
    }
  }

  private primeClipboardBaseline(): void {
    try {
      let data: pasteboard.PasteData = this.systemPasteboard.getDataSync();
      this.lastClipboardText = this.extractText(data);
      this.hasClipboardBaseline = true;
    } catch (error) {
      this.hasClipboardBaseline = false;
    }
  }

  private notifyClipboardChange(): boolean {
    if (!this.listening || this.observer === null) {
      return false;
    }
    try {
      let data: pasteboard.PasteData = this.systemPasteboard.getDataSync();
      let currentText: string = this.extractText(data);
      if (!this.hasClipboardBaseline) {
        this.lastClipboardText = currentText;
        this.hasClipboardBaseline = true;
        return false;
      }
      if (!shouldNotifyClipboardChange(this.hasClipboardBaseline, this.lastClipboardText, currentText)) {
        return false;
      }
      this.lastClipboardText = currentText;
      logger.info('Clipboard observed text change length=' + currentText.length.toString());
      let observer: EngineClipboardObserver | null = this.observer;
      if (observer !== null) {
        observer.onClipboardChanged(this.snapshotFromText(currentText));
      }
      return true;
    } catch (error) {
      // Permission and transient pasteboard failures are retried by the next poll.
      let nowMs: number = Date.now();
      if (nowMs - this.lastPollFailureLogAtMs >= 5000) {
        this.lastPollFailureLogAtMs = nowMs;
        logger.warn('Clipboard polling read failed.');
      }
      return false;
    }
  }

  private extractText(data: pasteboard.PasteData): string {
    let recordCount: number = data.getRecordCount();
    for (let index: number = 0; index < recordCount; index += 1) {
      let text: string = data.getRecord(index).toPlainText();
      if (text.length > 0) {
        return text;
      }
    }
    return data.getPrimaryText();
  }

  private snapshotFromText(text: string): EngineClipboardSnapshot {
    let representations: EngineClipboardRepresentation[] = [];
    if (text.length > 0) {
      representations.push({
        kind: 'inline',
        format: TEXT_FORMAT,
        mimeType: TEXT_FORMAT,
        bytes: this.encoder.encodeInto(text)
      });
    }
    return {
      observedAtMs: Date.now(),
      representations: representations
    };
  }

  private startPollingIfNeeded(): void {
    if (!shouldStartClipboardPolling(this.pollingEnabled, this.listening, this.pollingTimerId)) {
      return;
    }
    this.scheduleNextPoll();
    logger.info('Clipboard polling started with adaptive backoff.');
  }

  private stopPolling(): void {
    if (this.pollingTimerId < 0) {
      return;
    }
    clearTimeout(this.pollingTimerId);
    this.pollingTimerId = -1;
  }

  private scheduleNextPoll(): void {
    if (!shouldStartClipboardPolling(this.pollingEnabled, this.listening, this.pollingTimerId)) {
      return;
    }
    let delayMs: number = nextClipboardPollingDelayMs(this.pollIdleRounds, false);
    this.pollingTimerId = setTimeout((): void => {
      this.pollingTimerId = -1;
      let changed: boolean = this.notifyClipboardChange();
      if (changed) {
        this.pollIdleRounds = 0;
      } else {
        this.pollIdleRounds += 1;
      }
      this.scheduleNextPoll();
    }, delayMs);
  }

  private accessError(error: Object, operation: string): EngineHostError {
    let businessError: BusinessError = error as BusinessError;
    if (businessError.code === PERMISSION_DENIED_CODE) {
      return new EngineHostError(EngineHostErrorCategory.PERMISSION_DENIED, operation);
    }
    return new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, operation);
  }
}
