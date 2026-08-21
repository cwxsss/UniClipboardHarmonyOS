import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { EngineHostError, EngineHostErrorCategory } from './EngineHostError';
import { EngineFileHandleRegistry, EngineFileMetadata } from './EngineFileHandleRegistry';
import { ClipboardService } from '../service/ClipboardService';
import { Logger } from '../util/Logger';

const PERMISSION_DENIED_CODE: number = 201;
const TEXT_FORMAT: string = 'text/plain';
const IMAGE_FORMAT: string = 'image/png';
const FILE_FORMAT: string = 'application/octet-stream';
const BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS: number = 1000;
const logger: Logger = new Logger('ClipboardHost');

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
  private files: EngineFileHandleRegistry;
  private clipboardService: ClipboardService;
  private observer: EngineClipboardObserver | null = null;
  private listening: boolean = false;
  private pollingEnabled: boolean = false;
  private pollingTimerId: number = -1;
  private hasClipboardBaseline: boolean = false;
  private lastClipboardTimestamp: number = 0;
  private suppressNextChange: boolean = false;
  private refreshPending: boolean = false;
  private refreshTask: Promise<void> | null = null;
  private listenerGeneration: number = 0;
  private lastPollFailureLogAtMs: number = 0;
  private updateCallback = (): void => {
    this.scheduleClipboardRefresh();
  };

  constructor(files: EngineFileHandleRegistry, clipboardService: ClipboardService = new ClipboardService()) {
    this.files = files;
    this.clipboardService = clipboardService;
  }

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
      return this.snapshotFromText(text, this.clipboardTimestamp(data));
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
          // setDataSync may fire the update callback before it returns. Prime
          // the baseline first so a remote write is never captured as local.
          this.suppressNextChange = true;
          this.systemPasteboard.setDataSync(data);
          return;
        } catch (error) {
          this.suppressNextChange = false;
          throw this.accessError(error as Object, 'clipboard_write');
        }
      }
    }
    throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'clipboard_format');
  }

  listen(observer: EngineClipboardObserver): void {
    this.releaseListener();
    this.observer = observer;
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
      this.refreshPending = false;
      this.suppressNextChange = false;
      this.listenerGeneration += 1;
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
      this.refreshPending = false;
      this.suppressNextChange = false;
      this.listenerGeneration += 1;
    }
  }

  private primeClipboardBaseline(): void {
    try {
      let data: pasteboard.PasteData = this.systemPasteboard.getDataSync();
      this.lastClipboardTimestamp = this.clipboardTimestamp(data);
      this.hasClipboardBaseline = true;
    } catch (error) {
      this.hasClipboardBaseline = false;
    }
  }

  private scheduleClipboardRefresh(): void {
    if (!this.listening || this.observer === null) {
      return;
    }
    this.refreshPending = true;
    if (this.refreshTask !== null) {
      return;
    }
    let generation: number = this.listenerGeneration;
    let task: Promise<void> = this.drainClipboardRefreshes(generation);
    this.refreshTask = task;
    task.then((): void => {
      if (this.refreshTask === task) {
        this.refreshTask = null;
        if (this.refreshPending && this.listening) {
          this.scheduleClipboardRefresh();
        }
      }
    }).catch((): void => {
      if (this.refreshTask === task) {
        this.refreshTask = null;
        if (this.refreshPending && this.listening) {
          this.scheduleClipboardRefresh();
        }
      }
    });
  }

  private async drainClipboardRefreshes(generation: number): Promise<void> {
    while (this.refreshPending && this.listening && generation === this.listenerGeneration) {
      this.refreshPending = false;
      await this.refreshClipboardSnapshot(generation);
    }
  }

  private async refreshClipboardSnapshot(generation: number): Promise<void> {
    let snapshot: EngineClipboardSnapshot | null = null;
    try {
      snapshot = await this.readRichSnapshot();
      if (!this.hasClipboardBaseline) {
        this.lastClipboardTimestamp = snapshot.observedAtMs;
        this.hasClipboardBaseline = true;
        this.releaseSnapshotFiles(snapshot);
        return;
      }
      if (snapshot.observedAtMs === this.lastClipboardTimestamp) {
        this.releaseSnapshotFiles(snapshot);
        return;
      }
      this.lastClipboardTimestamp = snapshot.observedAtMs;
      if (this.suppressNextChange) {
        this.suppressNextChange = false;
        this.releaseSnapshotFiles(snapshot);
        return;
      }
      let observer: EngineClipboardObserver | null = this.observer;
      if (observer === null || !this.listening || generation !== this.listenerGeneration) {
        this.releaseSnapshotFiles(snapshot);
        return;
      }
      logger.info('Clipboard change captured representations=' + snapshot.representations.length.toString());
      observer.onClipboardChanged(snapshot);
    } catch (error) {
      if (snapshot !== null) {
        this.releaseSnapshotFiles(snapshot);
      }
      let nowMs: number = Date.now();
      if (nowMs - this.lastPollFailureLogAtMs >= 5000) {
        this.lastPollFailureLogAtMs = nowMs;
        logger.warn('Clipboard snapshot refresh failed.');
      }
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

  private snapshotFromText(text: string, observedAtMs: number): EngineClipboardSnapshot {
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
      observedAtMs: observedAtMs,
      representations: representations
    };
  }

  private async readRichSnapshot(): Promise<EngineClipboardSnapshot> {
    let data: pasteboard.PasteData = await this.systemPasteboard.getData();
    let observedAtMs: number = this.clipboardTimestamp(data);
    let pixelMap: image.PixelMap | null = await this.clipboardService.readImageFromPasteData(data);
    if (pixelMap !== null) {
      try {
        let bytes: Uint8Array = await this.clipboardService.encodePng(pixelMap);
        return {
          observedAtMs: observedAtMs,
          representations: [{
            kind: 'inline',
            format: IMAGE_FORMAT,
            mimeType: IMAGE_FORMAT,
            bytes: bytes
          }]
        };
      } finally {
        await pixelMap.release();
      }
    }

    let fileRepresentations: EngineClipboardRepresentation[] = [];
    try {
      let count: number = data.getRecordCount();
      for (let index: number = 0; index < count; index += 1) {
        let record: pasteboard.PasteDataRecord = data.getRecord(index);
        let uri: string = record.uri;
        if (uri.trim().length === 0) {
          continue;
        }
        let handle: string = this.files.registerInput(uri);
        let metadata: EngineFileMetadata;
        try {
          metadata = this.files.fileMetadata(handle);
        } catch (error) {
          this.files.remove(handle);
          throw new EngineHostError(EngineHostErrorCategory.IO, 'clipboard_file_metadata');
        }
        fileRepresentations.push({
          kind: 'file',
          format: FILE_FORMAT,
          handle: handle,
          displayName: metadata.displayName,
          sizeBytes: metadata.sizeBytes
        });
      }
      if (fileRepresentations.length > 0) {
        return { observedAtMs: observedAtMs, representations: fileRepresentations };
      }
    } catch (error) {
      this.releaseRepresentations(fileRepresentations);
      if (error instanceof EngineHostError) {
        throw error as EngineHostError;
      }
      throw new EngineHostError(EngineHostErrorCategory.IO, 'clipboard_file_snapshot');
    }

    return this.snapshotFromText(this.extractText(data), observedAtMs);
  }

  private clipboardTimestamp(data: pasteboard.PasteData): number {
    let timestamp: number = data.getProperty().timestamp;
    return Number.isSafeInteger(timestamp) && timestamp > 0 ? timestamp : Date.now();
  }

  private releaseSnapshotFiles(snapshot: EngineClipboardSnapshot): void {
    this.releaseRepresentations(snapshot.representations);
  }

  private releaseRepresentations(representations: EngineClipboardRepresentation[]): void {
    for (let index: number = 0; index < representations.length; index += 1) {
      let handle: string | undefined = representations[index].handle;
      if (representations[index].kind === 'file' && handle !== undefined) {
        this.files.remove(handle);
      }
    }
  }

  private startPollingIfNeeded(): void {
    if (!this.pollingEnabled || !this.listening || this.pollingTimerId >= 0) {
      return;
    }
    this.pollingTimerId = setInterval((): void => {
      this.scheduleClipboardRefresh();
    }, BACKGROUND_CLIPBOARD_POLL_INTERVAL_MS);
    logger.info('Clipboard polling started.');
  }

  private stopPolling(): void {
    if (this.pollingTimerId < 0) {
      return;
    }
    clearInterval(this.pollingTimerId);
    this.pollingTimerId = -1;
  }

  private accessError(error: Object, operation: string): EngineHostError {
    let businessError: BusinessError = error as BusinessError;
    if (businessError.code === PERMISSION_DENIED_CODE) {
      return new EngineHostError(EngineHostErrorCategory.PERMISSION_DENIED, operation);
    }
    return new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, operation);
  }
}
