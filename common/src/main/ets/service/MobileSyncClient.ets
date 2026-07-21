import {
  deleteHistory,
  drainSseEvents,
  getHistoryPayload,
  getLatestContent,
  getLatestText,
  LatestText,
  NativeClipboardContent,
  NativeHistoryItem,
  NativeServerConfig,
  NativeSseEvent,
  probeServer,
  putFileFromFd,
  putImage,
  putText,
  queryClipboardHistory,
  setHistoryPinned,
  setHistoryStarred,
  startSse,
  stopSse
} from 'uniclipboard_native';
import { fileIo } from '@kit.CoreFileKit';
import {
  ServerConfig,
  ServerHistoryItem,
  SyncContent,
  SyncEvent,
  SyncResult
} from '../model/ClipboardModels';

export class MobileSyncClient {
  private config: ServerConfig;

  constructor(config: ServerConfig) {
    this.config = config;
  }

  async probe(): Promise<void> {
    await probeServer(this.nativeConfig());
  }

  async getLatest(): Promise<SyncResult> {
    let latest: LatestText = await getLatestText(this.nativeConfig());
    return new SyncResult(latest.text, latest.contentId);
  }

  async getLatestContent(): Promise<SyncContent> {
    let latest: NativeClipboardContent = await getLatestContent(this.nativeConfig());
    return new SyncContent(latest.kind, latest.text, latest.contentId, latest.dataName, latest.data);
  }

  async putText(text: string): Promise<string> {
    let contentId: string | null = await putText(this.nativeConfig(), text);
    return contentId === null ? '' : contentId;
  }

  async putImage(data: Uint8Array): Promise<string> {
    let contentId: string | null = await putImage(this.nativeConfig(), data);
    return contentId === null ? '' : contentId;
  }

  async putFileFromUri(uri: string, fileSize: number, fileName: string): Promise<string> {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      let contentId: string | null = await putFileFromFd(
        this.nativeConfig(), file.fd, fileSize, fileName);
      return contentId === null ? '' : contentId;
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  async queryHistory(page: number, searchText: string, starredOnly: boolean): Promise<ServerHistoryItem[]> {
    let nativeItems: NativeHistoryItem[] = await queryClipboardHistory(
      this.nativeConfig(), page, searchText.trim(), starredOnly);
    let items: ServerHistoryItem[] = [];
    for (let index: number = 0; index < nativeItems.length; index++) {
      let nativeItem: NativeHistoryItem = nativeItems[index];
      items.push(new ServerHistoryItem(
        nativeItem.id,
        nativeItem.text,
        nativeItem.kind,
        this.formatTimestamp(nativeItem.timestampMs),
        nativeItem.starred,
        nativeItem.pinned,
        nativeItem.hasData,
        nativeItem.version,
        nativeItem.timestampMs));
    }
    return items;
  }

  startRealtime(): void {
    startSse(this.nativeConfig());
  }

  stopRealtime(): void {
    stopSse();
  }

  drainRealtimeEvents(): SyncEvent[] {
    let nativeEvents: NativeSseEvent[] = drainSseEvents();
    let events: SyncEvent[] = [];
    for (let index: number = 0; index < nativeEvents.length; index++) {
      let nativeEvent: NativeSseEvent = nativeEvents[index];
      events.push(new SyncEvent(nativeEvent.eventType, nativeEvent.detail));
    }
    return events;
  }

  async setHistoryStarred(item: ServerHistoryItem, starred: boolean): Promise<ServerHistoryItem> {
    let nativeItem: NativeHistoryItem = await setHistoryStarred(
      this.nativeConfig(), item.kind, item.id, starred, item.version);
    return this.serverHistoryItem(nativeItem);
  }

  async setHistoryPinned(item: ServerHistoryItem, pinned: boolean): Promise<ServerHistoryItem> {
    let nativeItem: NativeHistoryItem = await setHistoryPinned(
      this.nativeConfig(), item.kind, item.id, pinned, item.version);
    return this.serverHistoryItem(nativeItem);
  }

  async deleteHistory(item: ServerHistoryItem): Promise<void> {
    await deleteHistory(this.nativeConfig(), item.kind, item.id, item.version);
  }

  async getHistoryPayload(item: ServerHistoryItem): Promise<Uint8Array> {
    return await getHistoryPayload(this.nativeConfig(), item.kind, item.id);
  }

  private serverHistoryItem(nativeItem: NativeHistoryItem): ServerHistoryItem {
    return new ServerHistoryItem(
      nativeItem.id,
      nativeItem.text,
      nativeItem.kind,
      this.formatTimestamp(nativeItem.timestampMs),
      nativeItem.starred,
      nativeItem.pinned,
      nativeItem.hasData,
      nativeItem.version,
      nativeItem.timestampMs);
  }

  private formatTimestamp(timestampMs: number): string {
    if (timestampMs <= 0) {
      return '';
    }
    let date: Date = new Date(timestampMs);
    let month: string = (date.getMonth() + 1).toString().padStart(2, '0');
    let day: string = date.getDate().toString().padStart(2, '0');
    let hours: string = date.getHours().toString().padStart(2, '0');
    let minutes: string = date.getMinutes().toString().padStart(2, '0');
    return month + '-' + day + ' ' + hours + ':' + minutes;
  }

  private nativeConfig(): NativeServerConfig {
    let config: NativeServerConfig = {
      baseUrl: this.config.baseUrl.trim(),
      username: this.config.username,
      password: this.config.password
    };
    return config;
  }
}
