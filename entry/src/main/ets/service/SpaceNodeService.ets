import {
  NativeCreateSpaceResult,
  NativeJoinSpaceResult,
  NativeSpaceDevice,
  NativeSpaceFileEvent,
  NativeSpaceFileSendResult,
  NativeSpaceFileStatusEvent,
  NativeSpaceImageEvent,
  NativeSpaceInvitation,
  NativeSpaceStatus,
  NativeSpaceTextEvent,
  connectSpaceDevice,
  copySpaceFileToFd,
  createSpace,
  drainSpaceFileEvents,
  drainSpaceFileStatusEvents,
  drainSpaceImageEvents,
  drainSpaceTextEvents,
  getSpaceDevices,
  getSpaceStatus,
  issueSpaceInvitation,
  joinSpace,
  sendSpaceFile,
  sendSpaceFileFromFd,
  sendSpaceImage,
  sendSpaceText,
  startSpaceNode
} from 'uniclipboard_native';
import { fileIo } from '@kit.CoreFileKit';

export class SpaceNodeService {
  async start(dataDir: string, cacheDir: string, deviceType: string): Promise<NativeSpaceStatus> {
    return await startSpaceNode(dataDir, cacheDir, deviceType);
  }

  async status(): Promise<NativeSpaceStatus> {
    return await getSpaceStatus();
  }

  async devices(): Promise<NativeSpaceDevice[]> {
    return await getSpaceDevices();
  }

  async connect(deviceId: string): Promise<boolean> {
    return await connectSpaceDevice(deviceId);
  }

  async join(invitationCode: string, passphrase: string, deviceName: string): Promise<NativeJoinSpaceResult> {
    return await joinSpace(invitationCode, passphrase, deviceName);
  }

  async create(passphrase: string, deviceName: string): Promise<NativeCreateSpaceResult> {
    return await createSpace(passphrase, deviceName);
  }

  async issueInvitation(): Promise<NativeSpaceInvitation> {
    return await issueSpaceInvitation();
  }

  async sendText(text: string): Promise<number> {
    return await sendSpaceText(text);
  }

  async sendImage(data: Uint8Array): Promise<number> {
    return await sendSpaceImage(data, 'image/jpeg');
  }

  async sendFile(data: Uint8Array, fileName: string): Promise<number> {
    return await sendSpaceFile(data, fileName);
  }

  async sendFileFromUri(uri: string, fileSize: number, fileName: string): Promise<NativeSpaceFileSendResult> {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      return await sendSpaceFileFromFd(file.fd, fileSize, fileName);
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  async copyFileToUri(sourcePath: string, targetUri: string): Promise<void> {
    let file: fileIo.File = fileIo.openSync(
      targetUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      await copySpaceFileToFd(sourcePath, file.fd);
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  async copyUriToUri(sourceUri: string, targetUri: string): Promise<void> {
    let source: fileIo.File = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
    let target: fileIo.File | null = null;
    try {
      target = fileIo.openSync(targetUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      await copySpaceFileToFd('/proc/self/fd/' + source.fd.toString(), target.fd);
    } finally {
      if (target !== null) {
        fileIo.closeSync(target.fd);
      }
      fileIo.closeSync(source.fd);
    }
  }

  drainTextEvents(): NativeSpaceTextEvent[] {
    return drainSpaceTextEvents();
  }

  drainImageEvents(): NativeSpaceImageEvent[] {
    return drainSpaceImageEvents();
  }

  drainFileEvents(): NativeSpaceFileEvent[] {
    return drainSpaceFileEvents();
  }

  drainFileStatusEvents(): NativeSpaceFileStatusEvent[] {
    return drainSpaceFileStatusEvents();
  }
}
