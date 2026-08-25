import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { Logger } from '../util/Logger';

const logger: Logger = new Logger('ClipboardService');

export class ClipboardFilePayload {
  fileName: string = '';
  data: Uint8Array = new Uint8Array(0);

  constructor(fileName: string, data: Uint8Array) {
    this.fileName = fileName;
    this.data = data;
  }
}

export class ClipboardFileSelection {
  fileName: string = '';
  uri: string = '';
  size: number = 0;

  constructor(fileName: string, uri: string, size: number) {
    this.fileName = fileName;
    this.uri = uri;
    this.size = size;
  }
}

export class ClipboardService {
  private systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();

  hasText(): boolean {
    return this.systemPasteboard.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN);
  }

  async readText(): Promise<string> {
    let data: pasteboard.PasteData = await this.systemPasteboard.getData();
    let result: string = '';
    let count: number = data.getRecordCount();
    for (let index: number = 0; index < count; index += 1) {
      let value: string = data.getRecord(index).toPlainText();
      if (value.length > 0) {
        result = value;
        break;
      }
    }
    return result;
  }

  async writeText(text: string): Promise<void> {
    let data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await this.systemPasteboard.setData(data);
  }

  async readImage(): Promise<image.PixelMap | null> {
    let data: pasteboard.PasteData = await this.systemPasteboard.getData();
    return await this.readImageFromPasteData(data);
  }

  async readImageFromPasteData(data: pasteboard.PasteData): Promise<image.PixelMap | null> {
    let count: number = data.getRecordCount();
    for (let index: number = 0; index < count; index += 1) {
      let record: pasteboard.PasteDataRecord = data.getRecord(index);
      let validTypes: string[] = record.getValidTypes([
        pasteboard.MIMETYPE_PIXELMAP,
        pasteboard.MIMETYPE_TEXT_URI
      ]);
      if (validTypes.includes(pasteboard.MIMETYPE_PIXELMAP)) {
        let value: pasteboard.ValueType = await record.getData(pasteboard.MIMETYPE_PIXELMAP);
        return value as image.PixelMap;
      }
      if (validTypes.includes(pasteboard.MIMETYPE_TEXT_URI)) {
        let value: pasteboard.ValueType = await record.getData(pasteboard.MIMETYPE_TEXT_URI);
        let uri: string = value as string;
        try {
          return await this.decodeImageUri(uri);
        } catch (error) {
          logger.error('UniClipboard failed to decode clipboard image URI: ' + uri);
        }
      }
    }
    return null;
  }

  async decodeImageUri(uri: string): Promise<image.PixelMap> {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
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
  }

  async writeImage(pixelMap: image.PixelMap): Promise<void> {
    let data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
    await this.systemPasteboard.setData(data);
  }

  async writeUri(uri: string): Promise<void> {
    let data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_URI, uri);
    await this.systemPasteboard.setData(data);
  }

  async encodePng(pixelMap: image.PixelMap): Promise<Uint8Array> {
    return await this.encodeImage(pixelMap, 'image/png', 100);
  }

  async encodeSpaceImage(pixelMap: image.PixelMap): Promise<Uint8Array> {
    let imageInfo: image.ImageInfo = pixelMap.getImageInfoSync();
    let longestSide: number = Math.max(imageInfo.size.width, imageInfo.size.height);
    let maximumSide: number = 1600;
    if (longestSide > maximumSide) {
      let scaleRatio: number = maximumSide / longestSide;
      await pixelMap.scale(scaleRatio, scaleRatio);
    }
    let data: Uint8Array = await this.encodeImage(pixelMap, 'image/jpeg', 78, true);
    let maximumBytes: number = 1536 * 1024;
    let attempts: number = 0;
    while (data.length > maximumBytes && attempts < 2) {
      await pixelMap.scale(0.75, 0.75);
      data = await this.encodeImage(pixelMap, 'image/jpeg', 72, true);
      attempts += 1;
    }
    if (data.length > maximumBytes) {
      throw new Error('image remains too large for space transfer');
    }
    return data;
  }

  private async encodeImage(pixelMap: image.PixelMap, format: string, quality: number,
    preserveDynamicRange: boolean = false): Promise<Uint8Array> {
    let packer: image.ImagePacker = image.createImagePacker();
    let options: image.PackingOption = {
      format: format,
      quality: quality
    };
    if (preserveDynamicRange) {
      options.desiredDynamicRange = image.PackingDynamicRange.AUTO;
    }
    try {
      let packed: ArrayBuffer = await packer.packToData(pixelMap, options);
      return new Uint8Array(packed);
    } finally {
      await packer.release();
    }
  }

  async decodeImage(data: Uint8Array): Promise<image.PixelMap> {
    let source: image.ImageSource = image.createImageSource(data.buffer);
    try {
      let options: image.DecodingOptions = {
        desiredDynamicRange: image.DecodingDynamicRange.AUTO
      };
      return await source.createPixelMap(options);
    } finally {
      await source.release();
    }
  }

  readFile(uri: string): ClipboardFilePayload {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      let stat: fileIo.Stat = fileIo.statSync(file.fd);
      let buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      return new ClipboardFilePayload(this.fileNameFromUri(uri), new Uint8Array(buffer));
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  inspectFile(uri: string): ClipboardFileSelection {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      let stat: fileIo.Stat = fileIo.statSync(file.fd);
      let fileName: string = file.name.trim();
      if (fileName.length === 0) {
        fileName = this.fileNameFromUri(uri);
      }
      return new ClipboardFileSelection(fileName, uri, stat.size);
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  writeFile(uri: string, data: Uint8Array): void {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, data.buffer);
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  private fileNameFromUri(uri: string): string {
    let queryIndex: number = uri.indexOf('?');
    let path: string = queryIndex >= 0 ? uri.substring(0, queryIndex) : uri;
    let parts: string[] = path.split('/');
    let name: string = parts.length > 0 ? parts[parts.length - 1] : '';
    if (name.length === 0) {
      return 'shared-file';
    }
    try {
      return decodeURIComponent(name);
    } catch (error) {
      return name;
    }
  }
}
