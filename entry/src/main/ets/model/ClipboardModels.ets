import { image } from '@kit.ImageKit';

export interface ServerConfig {
  baseUrl: string;
  username: string;
  password: string;
}

export class ClipboardHistoryItem {
  id: string = '';
  text: string = '';
  direction: string = '';
  time: string = '';
  kind: string = 'Text';
  imagePreview: image.PixelMap | null = null;
  fileData: Uint8Array | null = null;
  filePath: string = '';
  timestampMs: number = 0;
  starred: boolean = false;

  constructor(id: string, text: string, direction: string, time: string, kind: string = 'Text',
    imagePreview: image.PixelMap | null = null, fileData: Uint8Array | null = null, filePath: string = '',
    timestampMs: number = 0, starred: boolean = false) {
    this.id = id;
    this.text = text;
    this.direction = direction;
    this.time = time;
    this.kind = kind;
    this.imagePreview = imagePreview;
    this.fileData = fileData;
    this.filePath = filePath;
    this.timestampMs = timestampMs;
    this.starred = starred;
  }
}

export class SyncResult {
  text: string = '';
  contentId: string = '';

  constructor(text: string, contentId: string) {
    this.text = text;
    this.contentId = contentId;
  }
}

export class SyncContent {
  kind: string = '';
  text: string = '';
  contentId: string = '';
  dataName: string = '';
  data: Uint8Array = new Uint8Array(0);

  constructor(kind: string, text: string, contentId: string, dataName: string, data: Uint8Array) {
    this.kind = kind;
    this.text = text;
    this.contentId = contentId;
    this.dataName = dataName;
    this.data = data;
  }
}

export class ServerHistoryItem {
  id: string = '';
  text: string = '';
  kind: string = '';
  time: string = '';
  starred: boolean = false;
  pinned: boolean = false;
  version: number = 0;
  timestampMs: number = 0;

  constructor(id: string, text: string, kind: string, time: string, starred: boolean, pinned: boolean,
    version: number, timestampMs: number) {
    this.id = id;
    this.text = text;
    this.kind = kind;
    this.time = time;
    this.starred = starred;
    this.pinned = pinned;
    this.version = version;
    this.timestampMs = timestampMs;
  }
}

export class SyncEvent {
  eventType: string = '';
  detail: string = '';

  constructor(eventType: string, detail: string) {
    this.eventType = eventType;
    this.detail = detail;
  }
}
