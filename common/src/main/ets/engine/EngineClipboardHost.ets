import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { EngineHostError, EngineHostErrorCategory } from './EngineHostError';

const PERMISSION_DENIED_CODE: number = 201;
const TEXT_FORMAT: string = 'text/plain';

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
  onClipboardChanged(): void;
}

export class EngineClipboardHost {
  private systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
  private observer: EngineClipboardObserver | null = null;
  private listening: boolean = false;
  private updateCallback = (): void => {
    let observer: EngineClipboardObserver | null = this.observer;
    if (observer !== null) {
      observer.onClipboardChanged();
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
      let representations: EngineClipboardRepresentation[] = [];
      let text: string = data.getPrimaryText();
      if (text.length > 0) {
        let representation: EngineClipboardRepresentation = {
          kind: 'inline',
          format: TEXT_FORMAT,
          mimeType: TEXT_FORMAT,
          bytes: this.encoder.encodeInto(text)
        };
        representations.push(representation);
      }
      return {
        observedAtMs: Date.now(),
        representations: representations
      };
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
    try {
      this.systemPasteboard.on('update', this.updateCallback);
      this.listening = true;
    } catch (error) {
      this.observer = null;
      throw this.accessError(error as Object, 'clipboard_listen');
    }
  }

  releaseListener(): void {
    if (!this.listening) {
      this.observer = null;
      return;
    }
    try {
      this.systemPasteboard.off('update', this.updateCallback);
    } catch (error) {
      throw this.accessError(error as Object, 'clipboard_release');
    } finally {
      this.listening = false;
      this.observer = null;
    }
  }

  private accessError(error: Object, operation: string): EngineHostError {
    let businessError: BusinessError = error as BusinessError;
    if (businessError.code === PERMISSION_DENIED_CODE) {
      return new EngineHostError(EngineHostErrorCategory.PERMISSION_DENIED, operation);
    }
    return new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, operation);
  }
}
