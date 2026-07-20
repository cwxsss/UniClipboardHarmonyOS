import { fileIo } from '@kit.CoreFileKit';
import {
  drainMobileSyncInboundEvents,
  getMobileSyncServerStatus,
  listMobileSyncDevices,
  NativeMobileSyncCredential,
  NativeMobileSyncDevice,
  NativeMobileSyncInboundEvent,
  NativeMobileSyncStatus,
  publishMobileSyncFileFromFd,
  publishMobileSyncImage,
  publishMobileSyncText,
  registerMobileSyncDevice,
  revokeMobileSyncDevice,
  setMobileSyncServerEnabled
} from 'uniclipboard_native';

export class MobileSyncServerService {
  async status(): Promise<NativeMobileSyncStatus> {
    return await getMobileSyncServerStatus();
  }

  async setEnabled(enabled: boolean, port: number): Promise<NativeMobileSyncStatus> {
    return await setMobileSyncServerEnabled(enabled, port);
  }

  async registerDevice(label: string, username: string, password: string,
    port: number): Promise<NativeMobileSyncCredential> {
    return await registerMobileSyncDevice(label, username, password, port);
  }

  async listDevices(): Promise<NativeMobileSyncDevice[]> {
    return await listMobileSyncDevices();
  }

  async revokeDevice(deviceId: string): Promise<void> {
    await revokeMobileSyncDevice(deviceId);
  }

  publishText(text: string): string {
    return publishMobileSyncText(text);
  }

  publishImage(data: Uint8Array): string {
    return publishMobileSyncImage(data, 'image/png');
  }

  publishFile(uri: string, fileSize: number, fileName: string): string {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      return publishMobileSyncFileFromFd(file.fd, fileSize, fileName,
        this.mimeTypeForFile(fileName));
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  drainInboundEvents(): NativeMobileSyncInboundEvent[] {
    return drainMobileSyncInboundEvents();
  }

  private mimeTypeForFile(fileName: string): string {
    let normalized: string = fileName.toLowerCase();
    if (normalized.endsWith('.png')) {
      return 'image/png';
    }
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.gif')) {
      return 'image/gif';
    }
    if (normalized.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (normalized.endsWith('.txt')) {
      return 'text/plain';
    }
    return 'application/octet-stream';
  }
}
