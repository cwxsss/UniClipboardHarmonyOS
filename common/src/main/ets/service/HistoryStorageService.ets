import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ClipboardHistoryItem } from '../model/ClipboardModels';

const STORE_NAME: string = 'clipboard_history';
const HISTORY_KEY: string = 'local_history_v2';
const LEGACY_HISTORY_KEY: string = 'local_history_v1';
const RETENTION_DAYS_KEY: string = 'retention_days';
const MERGE_DUPLICATES_KEY: string = 'merge_duplicates';
const DEFAULT_RETENTION_DAYS: number = 30;
const IMAGE_PREFIX: string = '/clipboard_history_image_';
const FILE_PREFIX: string = '/clipboard_history_file_';
const SERVER_FILE_PREFIX: string = '/clipboard_server_file_';

class PersistedHistoryRecord {
  id: string = '';
  text: string = '';
  direction: string = '';
  time: string = '';
  kind: string = 'Text';
  payloadPath: string = '';
  timestampMs: number = 0;
  starred: boolean = false;
  tags: string[] = [];
  isSnippet: boolean = false;
  sourceDevice: string = '';
  occurrenceCount: number = 1;

  constructor(id: string, text: string, direction: string, time: string, kind: string,
    payloadPath: string, timestampMs: number, starred: boolean, tags: string[], isSnippet: boolean,
    sourceDevice: string, occurrenceCount: number) {
    this.id = id;
    this.text = text;
    this.direction = direction;
    this.time = time;
    this.kind = kind;
    this.payloadPath = payloadPath;
    this.timestampMs = timestampMs;
    this.starred = starred;
    this.tags = tags;
    this.isSnippet = isSnippet;
    this.sourceDevice = sourceDevice;
    this.occurrenceCount = occurrenceCount;
  }
}

class LegacyPersistedHistoryRecord {
  id: string = '';
  text: string = '';
  direction: string = '';
  time: string = '';
  kind: string = 'Text';
  payloadPath: string = '';
  timestampMs: number = 0;
  starred: boolean = false;
}

export class HistoryLibrarySettings {
  retentionDays: number = DEFAULT_RETENTION_DAYS;
  mergeDuplicates: boolean = true;

  constructor(retentionDays: number = DEFAULT_RETENTION_DAYS, mergeDuplicates: boolean = true) {
    this.retentionDays = retentionDays;
    this.mergeDuplicates = mergeDuplicates;
  }
}

export class HistoryStorageService {
  async load(context: common.Context, retentionDays: number = DEFAULT_RETENTION_DAYS): Promise<ClipboardHistoryItem[]> {
    let records: PersistedHistoryRecord[] = this.readRecords(context);
    let items: ClipboardHistoryItem[] = [];
    let recordsChanged: boolean = false;
    let retainedRecords: PersistedHistoryRecord[] = [];
    let activePaths: Set<string> = new Set<string>();
    let cutoffMs: number = retentionDays > 0 ? Date.now() - retentionDays * 24 * 60 * 60 * 1000 : 0;
    for (let index: number = 0; index < records.length; index++) {
      let record: PersistedHistoryRecord = records[index];
      if (cutoffMs > 0 && record.timestampMs < cutoffMs && !record.starred && !record.isSnippet) {
        recordsChanged = true;
        continue;
      }
      let pixelMap: image.PixelMap | null = null;
      let filePath: string = '';
      if (record.kind === 'Image' && record.payloadPath.length > 0) {
        pixelMap = await this.loadImage(record.payloadPath);
      } else if (record.kind === 'File') {
        filePath = this.restoreFile(context, record);
        if (filePath !== record.payloadPath) {
          record.payloadPath = filePath;
          recordsChanged = true;
        }
      }
      items.push(new ClipboardHistoryItem(record.id, record.text, record.direction, record.time,
        record.kind, pixelMap, null, filePath, record.timestampMs, record.starred === true,
        record.tags, record.isSnippet === true, record.sourceDevice, Math.max(1, record.occurrenceCount)));
      retainedRecords.push(record);
      if (record.payloadPath.length > 0 && this.isManagedPath(context, record.payloadPath)) {
        activePaths.add(record.payloadPath);
      }
    }
    if (recordsChanged) {
      this.writeRecords(context, retainedRecords);
      this.removeUnusedPayloads(context, records, activePaths);
    }
    return items;
  }

  async save(context: common.Context, items: ClipboardHistoryItem[]): Promise<void> {
    let oldRecords: PersistedHistoryRecord[] = this.readRecords(context);
    let records: PersistedHistoryRecord[] = [];
    let activePaths: Set<string> = new Set<string>();
    for (let index: number = 0; index < items.length; index++) {
      let item: ClipboardHistoryItem = items[index];
      let payloadPath: string = '';
      if (item.kind === 'Image' && item.imagePreview !== null) {
        payloadPath = await this.ensureImage(context, item);
      } else if (item.kind === 'File') {
        payloadPath = this.ensureFile(context, item);
      }
      if (payloadPath.length > 0 && this.isManagedPath(context, payloadPath)) {
        activePaths.add(payloadPath);
      }
      records.push(new PersistedHistoryRecord(item.id, item.text, item.direction, item.time,
        item.kind, payloadPath, item.timestampMs, item.starred, item.tags, item.isSnippet,
        item.sourceDevice, item.occurrenceCount));
    }
    this.writeRecords(context, records);
    this.removeUnusedPayloads(context, oldRecords, activePaths);
  }

  loadSettings(context: common.Context): HistoryLibrarySettings {
    let store: preferences.Preferences = this.getStore(context);
    let retentionDays: number = store.getSync(RETENTION_DAYS_KEY, DEFAULT_RETENTION_DAYS) as number;
    let mergeDuplicates: boolean = store.getSync(MERGE_DUPLICATES_KEY, true) as boolean;
    if (retentionDays < 0) {
      retentionDays = DEFAULT_RETENTION_DAYS;
    }
    return new HistoryLibrarySettings(retentionDays, mergeDuplicates);
  }

  saveSettings(context: common.Context, settings: HistoryLibrarySettings): void {
    let store: preferences.Preferences = this.getStore(context);
    store.putSync(RETENTION_DAYS_KEY, settings.retentionDays);
    store.putSync(MERGE_DUPLICATES_KEY, settings.mergeDuplicates);
    store.flushSync();
  }

  stageFile(context: common.Context, sourceUri: string, id: string, fileName: string): string {
    let targetPath: string = this.filePath(context, id, fileName);
    let source: fileIo.File | null = null;
    try {
      source = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      fileIo.copyFileSync(source.fd, targetPath);
      return targetPath;
    } catch (error) {
      this.removeFileIfPresent(targetPath);
      return '';
    } finally {
      if (source !== null) {
        fileIo.closeSync(source.fd);
      }
    }
  }

  storeServerFile(context: common.Context, id: string, fileName: string, data: Uint8Array): string {
    if (data.length === 0) {
      return '';
    }
    let targetPath: string = context.filesDir + SERVER_FILE_PREFIX + id + this.fileExtension(fileName);
    if (this.fileExists(targetPath)) {
      return targetPath;
    }
    try {
      let file: fileIo.File = fileIo.openSync(targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, data.buffer);
      } finally {
        fileIo.closeSync(file.fd);
      }
      return targetPath;
    } catch (error) {
      this.removeFileIfPresent(targetPath);
      return '';
    }
  }

  findServerFile(context: common.Context, id: string, fileName: string): string {
    let path: string = context.filesDir + SERVER_FILE_PREFIX + id + this.fileExtension(fileName);
    return this.fileExists(path) ? path : '';
  }

  discardManagedFile(context: common.Context, path: string): void {
    if (this.isManagedPath(context, path)) {
      this.removeFileIfPresent(path);
    }
  }

  removePayload(context: common.Context, item: ClipboardHistoryItem): void {
    this.removeFileIfPresent(this.imagePath(context, item.id));
    this.removeFileIfPresent(this.filePath(context, item.id, item.text));
    this.removeFileIfPresent(this.filePath(context, item.id, ''));
    if (item.filePath.length > 0 && this.isManagedPath(context, item.filePath)) {
      this.removeFileIfPresent(item.filePath);
    }
  }

  private getStore(context: common.Context): preferences.Preferences {
    let options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  private readRecords(context: common.Context): PersistedHistoryRecord[] {
    let store: preferences.Preferences = this.getStore(context);
    let serialized: string = store.getSync(HISTORY_KEY, '') as string;
    if (serialized.length > 0) {
      try {
        return JSON.parse(serialized) as PersistedHistoryRecord[];
      } catch (error) {
        return [];
      }
    }
    let legacySerialized: string = store.getSync(LEGACY_HISTORY_KEY, '') as string;
    if (legacySerialized.length === 0) {
      return [];
    }
    try {
      let legacyRecords: LegacyPersistedHistoryRecord[] = JSON.parse(legacySerialized) as LegacyPersistedHistoryRecord[];
      let migratedRecords: PersistedHistoryRecord[] = [];
      for (let index: number = 0; index < legacyRecords.length; index++) {
        let record: LegacyPersistedHistoryRecord = legacyRecords[index];
        migratedRecords.push(new PersistedHistoryRecord(record.id, record.text, record.direction, record.time,
          record.kind, record.payloadPath, record.timestampMs, record.starred, [], false, '', 1));
      }
      this.writeRecords(context, migratedRecords);
      return migratedRecords;
    } catch (error) {
      return [];
    }
  }

  private writeRecords(context: common.Context, records: PersistedHistoryRecord[]): void {
    let store: preferences.Preferences = this.getStore(context);
    store.putSync(HISTORY_KEY, JSON.stringify(records));
    store.flushSync();
  }

  private async ensureImage(context: common.Context, item: ClipboardHistoryItem): Promise<string> {
    let path: string = this.imagePath(context, item.id);
    if (this.fileExists(path)) {
      return path;
    }
    let pixelMap: image.PixelMap | null = item.imagePreview;
    if (pixelMap === null) {
      return '';
    }
    let file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    let packer: image.ImagePacker = image.createImagePacker();
    let options: image.PackingOption = {
      format: 'image/png',
      quality: 100
    };
    try {
      await packer.packToFile(pixelMap, file.fd, options);
      return path;
    } catch (error) {
      this.removeFileIfPresent(path);
      return '';
    } finally {
      fileIo.closeSync(file.fd);
      await packer.release();
    }
  }

  private ensureFile(context: common.Context, item: ClipboardHistoryItem): string {
    if (item.filePath.length > 0 && this.isManagedPath(context, item.filePath) &&
      this.fileExists(item.filePath)) {
      return item.filePath;
    }
    let targetPath: string = this.filePath(context, item.id, item.text);
    try {
      if (item.fileData !== null && item.fileData.length > 0) {
        let file: fileIo.File = fileIo.openSync(targetPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, item.fileData.buffer);
        } finally {
          fileIo.closeSync(file.fd);
        }
        return targetPath;
      }
      if (item.filePath.length > 0) {
        let source: fileIo.File = fileIo.openSync(item.filePath, fileIo.OpenMode.READ_ONLY);
        try {
          fileIo.copyFileSync(source.fd, targetPath);
          return targetPath;
        } finally {
          fileIo.closeSync(source.fd);
        }
      }
    } catch (error) {
      this.removeFileIfPresent(targetPath);
    }
    return '';
  }

  private restoreFile(context: common.Context, record: PersistedHistoryRecord): string {
    let sourcePath: string = record.payloadPath;
    if (sourcePath.length === 0) {
      return '';
    }
    if (this.isManagedPath(context, sourcePath)) {
      return this.fileExists(sourcePath) ? sourcePath : '';
    }
    let targetPath: string = this.filePath(context, record.id, record.text);
    let source: fileIo.File | null = null;
    try {
      source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      fileIo.copyFileSync(source.fd, targetPath);
      return targetPath;
    } catch (error) {
      this.removeFileIfPresent(targetPath);
      return '';
    } finally {
      if (source !== null) {
        fileIo.closeSync(source.fd);
      }
    }
  }

  private async loadImage(path: string): Promise<image.PixelMap | null> {
    try {
      let file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        let source: image.ImageSource = image.createImageSource(file.fd);
        try {
          let options: image.DecodingOptions = {
            desiredDynamicRange: image.DecodingDynamicRange.AUTO
          };
          return await source.createPixelMap(options);
        } finally {
          await source.release();
        }
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (error) {
      return null;
    }
  }

  private removeUnusedPayloads(context: common.Context, oldRecords: PersistedHistoryRecord[],
    activePaths: Set<string>): void {
    for (let index: number = 0; index < oldRecords.length; index++) {
      let path: string = oldRecords[index].payloadPath;
      if (path.length > 0 && this.isManagedPath(context, path) && !activePaths.has(path)) {
        this.removeFileIfPresent(path);
      }
    }
  }

  private fileExists(path: string): boolean {
    try {
      let file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      fileIo.closeSync(file.fd);
      return true;
    } catch (error) {
      return false;
    }
  }

  private removeFileIfPresent(path: string): void {
    try {
      fileIo.unlinkSync(path);
    } catch (error) {
    }
  }

  private isManagedPath(context: common.Context, path: string): boolean {
    return path.startsWith(context.filesDir + IMAGE_PREFIX) || path.startsWith(context.filesDir + FILE_PREFIX) ||
      path.startsWith(context.filesDir + SERVER_FILE_PREFIX);
  }

  private imagePath(context: common.Context, id: string): string {
    return context.filesDir + IMAGE_PREFIX + id + '.png';
  }

  private filePath(context: common.Context, id: string, fileName: string): string {
    return context.filesDir + FILE_PREFIX + id + this.fileExtension(fileName);
  }

  private fileExtension(fileName: string): string {
    let dotIndex: number = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= fileName.length - 1) {
      return '';
    }
    let extension: string = fileName.substring(dotIndex).toLowerCase();
    if (extension.length > 11 || extension.indexOf('/') >= 0 || extension.indexOf('\\') >= 0) {
      return '';
    }
    return extension;
  }
}
