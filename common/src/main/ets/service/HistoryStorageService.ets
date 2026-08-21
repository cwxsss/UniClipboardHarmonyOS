import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
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
    this.purgePlaintextHistory(context);
    return [];
  }

  async save(context: common.Context, items: ClipboardHistoryItem[]): Promise<void> {
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
    return sourceUri;
  }

  storeServerFile(context: common.Context, id: string, fileName: string, data: Uint8Array): string {
    return '';
  }

  findServerFile(context: common.Context, id: string, fileName: string): string {
    return '';
  }

  purgePlaintextHistory(context: common.Context): void {
    let store: preferences.Preferences = this.getStore(context);
    store.deleteSync(HISTORY_KEY);
    store.deleteSync(LEGACY_HISTORY_KEY);
    store.flushSync();
    this.removeFilesWithPrefixes(context.filesDir,
      [IMAGE_PREFIX.substring(1), FILE_PREFIX.substring(1), SERVER_FILE_PREFIX.substring(1)]);
    this.removeDirectoryContents(context.filesDir + '/engine-received');
    this.removeFilesWithPrefixes(context.cacheDir, ['uniclipboard_latest_file_']);
  }

  discardManagedFile(context: common.Context, path: string): void {
    if (this.isManagedPath(context, path)) {
      this.removeFileIfPresent(path);
    }
  }

  removePayload(context: common.Context, item: ClipboardHistoryItem): void {
    this.removeFileIfPresent(context.filesDir + IMAGE_PREFIX + item.id + '.png');
    this.removeFilesWithPrefixes(context.filesDir, [FILE_PREFIX.substring(1) + item.id]);
    if (item.filePath.length > 0 && this.isManagedPath(context, item.filePath)) {
      this.removeFileIfPresent(item.filePath);
    }
  }

  private getStore(context: common.Context): preferences.Preferences {
    let options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  private removeFilesWithPrefixes(directory: string, prefixes: string[]): void {
    try {
      let names: string[] = fileIo.listFileSync(directory);
      for (let index: number = 0; index < names.length; index++) {
        let name: string = names[index];
        for (let prefixIndex: number = 0; prefixIndex < prefixes.length; prefixIndex++) {
          if (name.startsWith(prefixes[prefixIndex])) {
            this.removeFileIfPresent(directory + '/' + name);
            break;
          }
        }
      }
    } catch (error) {
    }
  }

  private removeDirectoryContents(directory: string): void {
    try {
      let names: string[] = fileIo.listFileSync(directory);
      for (let index: number = 0; index < names.length; index++) {
        this.removeFileIfPresent(directory + '/' + names[index]);
      }
      fileIo.rmdirSync(directory);
    } catch (error) {
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
}
