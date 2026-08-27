import { image } from '@kit.ImageKit';

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
