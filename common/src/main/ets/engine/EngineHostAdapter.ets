import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { EngineClipboardHost, EngineClipboardObserver, EngineClipboardSnapshot } from './EngineClipboardHost';
import { EngineFileHandleRegistry, EngineFileMetadata } from './EngineFileHandleRegistry';
import { EngineHostError, EngineHostErrorCategory } from './EngineHostError';
import { EngineSecureAssetStore } from './EngineSecureAssetStore';

const ENGINE_DIRECTORY_NAME: string = 'uniclipboard-engine-v1-1';
const LEGACY_PROFILE_ID: string = '.engine-v1-1';

// Mirrors the public OhHostResult declaration shipped beside the official HAR.
export interface EngineHostResult<T> {
  ok: boolean;
  value?: T;
  errorCategory?: string;
}

// Mirrors the public OhHost declaration. The HAR's Index.d.ets currently does
// not re-export these types, so ArkTS cannot import them without a private patch.
export interface EngineHostCallbacks {
  privateDataDirectory: string;
  cacheDirectory: string;
  temporaryDirectory: string;
  secureStorageGet(key: string): EngineHostResult<Uint8Array | null>;
  secureStorageSet(key: string, value: Uint8Array): EngineHostResult<void>;
  secureStorageDelete(key: string): EngineHostResult<void>;
  fileMetadata(handle: string): EngineHostResult<EngineFileMetadata>;
  fileReadChunk(handle: string, offset: string, maxBytes: number): EngineHostResult<Uint8Array>;
  fileWriteChunk(handle: string, offset: string, bytes: Uint8Array): EngineHostResult<void>;
  fileFinishWrite(handle: string): EngineHostResult<void>;
  clipboardRead(): EngineHostResult<EngineClipboardSnapshot>;
  clipboardWrite(snapshot: EngineClipboardSnapshot): EngineHostResult<void>;
}

class EngineHostDirectories {
  privateDataDirectory: string;
  cacheDirectory: string;
  temporaryDirectory: string;

  constructor(context: common.UIAbilityContext, profileId: string) {
    let scope: string = profileId === LEGACY_PROFILE_ID ? '' : '/' + profileId;
    this.privateDataDirectory = context.filesDir + '/' + ENGINE_DIRECTORY_NAME + scope;
    this.cacheDirectory = context.cacheDir + '/' + ENGINE_DIRECTORY_NAME + scope;
    this.temporaryDirectory = context.tempDir + '/' + ENGINE_DIRECTORY_NAME + scope;
    this.ensureDirectory(this.privateDataDirectory);
    this.ensureDirectory(this.cacheDirectory);
    this.ensureDirectory(this.temporaryDirectory);
  }

  private ensureDirectory(path: string): void {
    try {
      try {
        if (fileIo.statSync(path).isDirectory()) {
          return;
        }
        throw new EngineHostError(EngineHostErrorCategory.IO, 'directory_prepare');
      } catch (error) {
        if (error instanceof EngineHostError) {
          throw error;
        }
      }
      fileIo.mkdirSync(path, true);
      if (!fileIo.statSync(path).isDirectory()) {
        throw new EngineHostError(EngineHostErrorCategory.IO, 'directory_prepare');
      }
    } catch (error) {
      if (error instanceof EngineHostError) {
        throw error;
      }
      throw new EngineHostError(EngineHostErrorCategory.IO, 'directory_prepare');
    }
  }
}

class EngineHostCallbacksImpl implements EngineHostCallbacks {
  privateDataDirectory: string;
  cacheDirectory: string;
  temporaryDirectory: string;
  private storage: EngineSecureAssetStore;
  private files: EngineFileHandleRegistry;
  private clipboard: EngineClipboardHost;

  constructor(directories: EngineHostDirectories, storage: EngineSecureAssetStore,
    files: EngineFileHandleRegistry, clipboard: EngineClipboardHost) {
    this.privateDataDirectory = directories.privateDataDirectory;
    this.cacheDirectory = directories.cacheDirectory;
    this.temporaryDirectory = directories.temporaryDirectory;
    this.storage = storage;
    this.files = files;
    this.clipboard = clipboard;
  }

  // N-API invokes host functions without a receiver, so these callbacks must
  // retain the adapter instance instead of relying on prototype-method this.
  secureStorageGet = (key: string): EngineHostResult<Uint8Array | null> =>
    this.execute((): Uint8Array | null => this.storage.get(key));

  secureStorageSet = (key: string, value: Uint8Array): EngineHostResult<void> =>
    this.execute((): void => this.storage.set(key, value));

  secureStorageDelete = (key: string): EngineHostResult<void> =>
    this.execute((): void => this.storage.delete(key));

  fileMetadata = (handle: string): EngineHostResult<EngineFileMetadata> =>
    this.execute((): EngineFileMetadata => this.files.fileMetadata(handle));

  fileReadChunk = (handle: string, offset: string, maxBytes: number): EngineHostResult<Uint8Array> =>
    this.execute((): Uint8Array => this.files.fileReadChunk(handle, offset, maxBytes));

  fileWriteChunk = (handle: string, offset: string, bytes: Uint8Array): EngineHostResult<void> =>
    this.execute((): void => this.files.fileWriteChunk(handle, offset, bytes));

  fileFinishWrite = (handle: string): EngineHostResult<void> =>
    this.execute((): void => this.files.fileFinishWrite(handle));

  clipboardRead = (): EngineHostResult<EngineClipboardSnapshot> =>
    this.execute((): EngineClipboardSnapshot => this.clipboard.read());

  clipboardWrite = (snapshot: EngineClipboardSnapshot): EngineHostResult<void> =>
    this.execute((): void => this.clipboard.write(snapshot));

  private execute<T>(operation: () => T): EngineHostResult<T> {
    try {
      return { ok: true, value: operation() };
    } catch (error) {
      if (error instanceof EngineHostError) {
        let hostError: EngineHostError = error as EngineHostError;
        return { ok: false, errorCategory: hostError.category };
      }
      return { ok: false, errorCategory: EngineHostErrorCategory.IO };
    }
  }
}

export class EngineHostAdapter {
  private storage: EngineSecureAssetStore = new EngineSecureAssetStore();
  private files: EngineFileHandleRegistry = new EngineFileHandleRegistry();
  private clipboard: EngineClipboardHost = new EngineClipboardHost();

  prepare(context: common.UIAbilityContext, profileId: string = LEGACY_PROFILE_ID): EngineHostCallbacks {
    let directories: EngineHostDirectories = new EngineHostDirectories(context, profileId);
    this.storage = new EngineSecureAssetStore(profileId);
    this.storage.verifyAccess();
    this.clipboard.verifyAccess();
    return new EngineHostCallbacksImpl(directories, this.storage, this.files, this.clipboard);
  }

  registerInput(uri: string, mimeType: string = ''): string {
    return this.files.registerInput(uri, mimeType);
  }

  registerOutput(uri: string, mimeType: string = ''): string {
    return this.files.registerOutput(uri, mimeType);
  }

  releaseFile(handle: string): void {
    this.files.remove(handle);
  }

  listenClipboard(observer: EngineClipboardObserver): void {
    this.clipboard.listen(observer);
  }

  releaseClipboardListener(): void {
    this.clipboard.releaseListener();
  }

  setClipboardPollingEnabled(enabled: boolean): void {
    this.clipboard.setPollingEnabled(enabled);
  }

  shutdown(): void {
    let clipboardError: EngineHostError | null = null;
    try {
      this.clipboard.releaseListener();
    } catch (error) {
      clipboardError = error instanceof EngineHostError ? error as EngineHostError :
        new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'clipboard_release');
    }
    this.files.clear();
    if (clipboardError !== null) {
      throw clipboardError;
    }
  }
}
