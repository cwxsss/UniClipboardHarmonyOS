import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { EngineHostError, EngineHostErrorCategory } from './EngineHostError';

const MAX_FILE_CHUNK_BYTES: number = 4 * 1024 * 1024;

export interface EngineFileMetadata {
  displayName: string;
  sizeBytes: string;
  mimeType?: string;
}

class EngineFileHandleEntry {
  uri: string;
  file: fileIo.File;
  writable: boolean;
  mimeType: string;

  constructor(uri: string, file: fileIo.File, writable: boolean, mimeType: string) {
    this.uri = uri;
    this.file = file;
    this.writable = writable;
    this.mimeType = mimeType;
  }
}

export class EngineFileHandleRegistry {
  private entries: Map<string, EngineFileHandleEntry> = new Map<string, EngineFileHandleEntry>();

  registerInput(uri: string, mimeType: string = ''): string {
    return this.register(uri, false, mimeType);
  }

  registerOutput(uri: string, mimeType: string = ''): string {
    return this.register(uri, true, mimeType);
  }

  remove(handle: string): void {
    let entry: EngineFileHandleEntry | undefined = this.entries.get(handle);
    if (entry === undefined) {
      return;
    }
    this.entries.delete(handle);
    this.closeEntry(entry);
  }

  clear(): void {
    let cleanupFailed: boolean = false;
    this.entries.forEach((entry: EngineFileHandleEntry): void => {
      try {
        this.closeEntry(entry);
      } catch (error) {
        cleanupFailed = true;
      }
    });
    this.entries.clear();
    if (cleanupFailed) {
      throw new EngineHostError(EngineHostErrorCategory.IO, 'file_cleanup');
    }
  }

  fileMetadata(handle: string): EngineFileMetadata {
    let entry: EngineFileHandleEntry = this.requireEntry(handle);
    try {
      let stat: fileIo.Stat = fileIo.statSync(entry.file.fd);
      let displayName: string = entry.file.name.trim();
      if (displayName.length === 0) {
        displayName = 'shared-file';
      }
      let metadata: EngineFileMetadata = {
        displayName: displayName,
        sizeBytes: stat.size.toString()
      };
      if (entry.mimeType.length > 0) {
        metadata.mimeType = entry.mimeType;
      }
      return metadata;
    } catch (error) {
      throw new EngineHostError(EngineHostErrorCategory.IO, 'file_metadata');
    }
  }

  fileReadChunk(handle: string, offset: string, maxBytes: number): Uint8Array {
    let entry: EngineFileHandleEntry = this.requireEntry(handle);
    let parsedOffset: number = this.parseOffset(offset);
    if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0 || maxBytes > MAX_FILE_CHUNK_BYTES) {
      throw new EngineHostError(EngineHostErrorCategory.INVALID_HANDLE, 'file_read_length');
    }
    try {
      let buffer: ArrayBuffer = new ArrayBuffer(maxBytes);
      let count: number = fileIo.readSync(entry.file.fd, buffer, {
        offset: parsedOffset,
        length: maxBytes
      });
      return new Uint8Array(buffer).slice(0, count);
    } catch (error) {
      throw new EngineHostError(EngineHostErrorCategory.IO, 'file_read');
    }
  }

  fileWriteChunk(handle: string, offset: string, bytes: Uint8Array): void {
    let entry: EngineFileHandleEntry = this.requireEntry(handle);
    if (!entry.writable) {
      throw new EngineHostError(EngineHostErrorCategory.PERMISSION_DENIED, 'file_write');
    }
    let parsedOffset: number = this.parseOffset(offset);
    let copy: Uint8Array = new Uint8Array(bytes);
    try {
      fileIo.writeSync(entry.file.fd, copy.buffer, {
        offset: parsedOffset,
        length: copy.byteLength
      });
    } catch (error) {
      throw new EngineHostError(EngineHostErrorCategory.IO, 'file_write');
    } finally {
      copy.fill(0);
    }
  }

  fileFinishWrite(handle: string): void {
    let entry: EngineFileHandleEntry = this.requireEntry(handle);
    if (!entry.writable) {
      throw new EngineHostError(EngineHostErrorCategory.PERMISSION_DENIED, 'file_finish_write');
    }
    try {
      fileIo.fsyncSync(entry.file.fd);
    } catch (error) {
      throw new EngineHostError(EngineHostErrorCategory.IO, 'file_finish_write');
    }
  }

  private register(uri: string, writable: boolean, mimeType: string): string {
    let mode: number = writable ? fileIo.OpenMode.READ_WRITE : fileIo.OpenMode.READ_ONLY;
    try {
      let file: fileIo.File = fileIo.openSync(uri, mode);
      let handle: string = util.generateRandomUUID();
      this.entries.set(handle, new EngineFileHandleEntry(uri, file, writable, mimeType));
      return handle;
    } catch (error) {
      throw new EngineHostError(EngineHostErrorCategory.IO, 'file_register');
    }
  }

  private requireEntry(handle: string): EngineFileHandleEntry {
    let entry: EngineFileHandleEntry | undefined = this.entries.get(handle);
    if (entry === undefined) {
      throw new EngineHostError(EngineHostErrorCategory.INVALID_HANDLE, 'file_handle');
    }
    return entry;
  }

  private parseOffset(value: string): number {
    let parsed: number = Number(value);
    if (!Number.isSafeInteger(parsed) || parsed < 0) {
      throw new EngineHostError(EngineHostErrorCategory.INVALID_HANDLE, 'file_offset');
    }
    return parsed;
  }

  private closeEntry(entry: EngineFileHandleEntry): void {
    try {
      fileIo.closeSync(entry.file);
    } catch (error) {
      throw new EngineHostError(EngineHostErrorCategory.IO, 'file_close');
    }
  }
}
