import { image } from '@kit.ImageKit';

export interface ServerConfig {
  baseUrl: string;
  username: string;
  password: string;
}

export class LinkPreview {
  url: string = '';
  title: string = '';
  description: string = '';
  siteName: string = '';
  imageUrl: string = '';
  keywords: string[] = [];

  constructor(url: string, title: string, description: string, siteName: string, imageUrl: string,
    keywords: string[] = []) {
    this.url = url;
    this.title = title;
    this.description = description;
    this.siteName = siteName;
    this.imageUrl = imageUrl;
    this.keywords = keywords;
  }
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
  tags: string[] = [];
  isSnippet: boolean = false;
  sourceDevice: string = '';
  occurrenceCount: number = 1;

  constructor(id: string, text: string, direction: string, time: string, kind: string = 'Text',
    imagePreview: image.PixelMap | null = null, fileData: Uint8Array | null = null, filePath: string = '',
    timestampMs: number = 0, starred: boolean = false, tags: string[] = [], isSnippet: boolean = false,
    sourceDevice: string = '', occurrenceCount: number = 1) {
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
    this.tags = tags;
    this.isSnippet = isSnippet;
    this.sourceDevice = sourceDevice;
    this.occurrenceCount = occurrenceCount;
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
  hasData: boolean = false;
  version: number = 0;
  timestampMs: number = 0;

  constructor(id: string, text: string, kind: string, time: string, starred: boolean, pinned: boolean,
    hasData: boolean, version: number, timestampMs: number) {
    this.id = id;
    this.text = text;
    this.kind = kind;
    this.time = time;
    this.starred = starred;
    this.pinned = pinned;
    this.hasData = hasData;
    this.version = version;
    this.timestampMs = timestampMs;
  }
}
