import {
  NativeCreateSpaceResult,
  NativeJoinSpaceResult,
  NativeSpaceDevice,
  NativeSpaceFileEvent,
  NativeSpaceFileSendResult,
  NativeSpaceFileStatusEvent,
  NativeSpaceImageEvent,
  NativeSpaceInvitation,
  NativeSpaceMemberSyncPreferences,
  NativeSpaceNetworkSettings,
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
  getSpaceMemberSyncPreferences,
  getSpaceNetworkSettings,
  getSpaceStatus,
  issueSpaceInvitation,
  joinSpace,
  probeSpaceRelayUrl,
  replaceSpace,
  resetSpaceMemberSyncPreferences,
  sendSpaceFile,
  sendSpaceFileFromFd,
  sendSpaceFileFromFdToDevice,
  sendSpaceImage,
  sendSpaceImageToDevice,
  sendSpaceText,
  sendSpaceTextToDevice,
  startSpaceNode,
  stopSpaceNode,
  switchSpace,
  updateSpaceNetworkSettings,
  updateSpaceMemberSendPreferences,
  wakeSpaceConnections,
  revokeSpaceMember
} from 'uniclipboard_native';
import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../util/Logger';

const logger: Logger = new Logger('SpaceNode');

export class SpaceNodeService {
  private async reconnectTarget(deviceId: string): Promise<void> {
    wakeSpaceConnections();
    let online: boolean = await connectSpaceDevice(deviceId);
    if (!online) {
      throw new Error('target space device is offline');
    }
  }

  private async reconnectKnownPeers(): Promise<number> {
    wakeSpaceConnections();
    let devices: NativeSpaceDevice[] = await getSpaceDevices();
    let onlinePeerCount: number = 0;
    for (let index: number = 0; index < devices.length; index++) {
      let device: NativeSpaceDevice = devices[index];
      if (device.isLocal) {
        continue;
      }
      try {
        let online: boolean = await connectSpaceDevice(device.deviceId);
        if (online) {
          onlinePeerCount += 1;
        }
      } catch (error) {
        logger.warn('UniClipboard failed to reconnect space device: ' + device.deviceId);
      }
    }
    logger.info('UniClipboard reconnected space peer count: ' + onlinePeerCount.toString());
    return onlinePeerCount;
  }

  async start(dataDir: string, cacheDir: string, deviceType: string): Promise<NativeSpaceStatus> {
    return await startSpaceNode(dataDir, cacheDir, deviceType);
  }

  async status(): Promise<NativeSpaceStatus> {
    return await getSpaceStatus();
  }

  async networkSettings(): Promise<NativeSpaceNetworkSettings> {
    return await getSpaceNetworkSettings();
  }

  async updateNetworkSettings(allowRelayFallback: boolean,
    customRelayUrls: string[]): Promise<NativeSpaceNetworkSettings> {
    return await updateSpaceNetworkSettings(allowRelayFallback, customRelayUrls);
  }

  async probeRelayUrl(url: string): Promise<number> {
    return await probeSpaceRelayUrl(url);
  }

  async stop(): Promise<void> {
    await stopSpaceNode();
  }

  async devices(): Promise<NativeSpaceDevice[]> {
    return await getSpaceDevices();
  }

  async memberSyncPreferences(deviceId: string): Promise<NativeSpaceMemberSyncPreferences> {
    return await getSpaceMemberSyncPreferences(deviceId);
  }

  async updateMemberSendPreferences(deviceId: string, sendEnabled: boolean, text: boolean,
    imageEnabled: boolean, file: boolean, link: boolean,
    richText: boolean): Promise<NativeSpaceMemberSyncPreferences> {
    return await updateSpaceMemberSendPreferences(
      deviceId, sendEnabled, text, imageEnabled, file, link, richText);
  }

  async resetMemberSyncPreferences(deviceId: string): Promise<NativeSpaceMemberSyncPreferences> {
    return await resetSpaceMemberSyncPreferences(deviceId);
  }

  async connect(deviceId: string): Promise<boolean> {
    return await connectSpaceDevice(deviceId);
  }

  wakeConnections(): void {
    wakeSpaceConnections();
  }

  async join(invitationCode: string, passphrase: string, deviceName: string): Promise<NativeJoinSpaceResult> {
    return await joinSpace(invitationCode, passphrase, deviceName);
  }

  async switchTo(invitationCode: string, passphrase: string): Promise<NativeJoinSpaceResult> {
    return await switchSpace(invitationCode, passphrase);
  }

  async create(passphrase: string, deviceName: string): Promise<NativeCreateSpaceResult> {
    return await createSpace(passphrase, deviceName);
  }

  async replace(passphrase: string, deviceName: string): Promise<NativeCreateSpaceResult> {
    return await replaceSpace(passphrase, deviceName);
  }

  async issueInvitation(): Promise<NativeSpaceInvitation> {
    return await issueSpaceInvitation();
  }

  async revoke(deviceId: string): Promise<void> {
    await revokeSpaceMember(deviceId);
  }

  async sendText(text: string): Promise<number> {
    await this.reconnectKnownPeers();
    return await sendSpaceText(text);
  }

  async sendTextToDevice(text: string, deviceId: string): Promise<number> {
    await this.reconnectTarget(deviceId);
    return await sendSpaceTextToDevice(text, deviceId);
  }

  async sendImage(data: Uint8Array): Promise<number> {
    await this.reconnectKnownPeers();
    return await sendSpaceImage(data, 'image/jpeg');
  }

  async sendImageToDevice(data: Uint8Array, deviceId: string): Promise<number> {
    await this.reconnectTarget(deviceId);
    return await sendSpaceImageToDevice(data, 'image/jpeg', deviceId);
  }

  async sendFile(data: Uint8Array, fileName: string): Promise<number> {
    await this.reconnectKnownPeers();
    return await sendSpaceFile(data, fileName);
  }

  async sendFileFromUri(uri: string, fileSize: number, fileName: string): Promise<NativeSpaceFileSendResult> {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      await this.reconnectKnownPeers();
      return await sendSpaceFileFromFd(file.fd, fileSize, fileName);
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  async sendFileFromUriToDevice(uri: string, fileSize: number, fileName: string,
    deviceId: string): Promise<NativeSpaceFileSendResult> {
    let file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      await this.reconnectTarget(deviceId);
      return await sendSpaceFileFromFdToDevice(file.fd, fileSize, fileName, deviceId);
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
