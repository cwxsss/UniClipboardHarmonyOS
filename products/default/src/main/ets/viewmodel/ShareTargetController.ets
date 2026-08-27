import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import {
  ClipboardService,
  engineRuntimeService,
  EngineRuntimeDevice,
  EngineSendReport,
  Logger
} from 'common';
import { ClipboardFeatureController } from 'clipboard_feature';

const logger: Logger = new Logger('ShareTarget');

export const SHARE_KIND_TEXT: number = 1;
export const SHARE_KIND_IMAGE: number = 2;
export const SHARE_KIND_FILE: number = 3;

export const SHARE_STATE_LOADING: number = 0;
export const SHARE_STATE_READY: number = 1;
export const SHARE_STATE_NOT_JOINED: number = 2;
export const SHARE_STATE_INVALID: number = 3;
export const SHARE_STATE_FAILED: number = 4;
export const SHARE_STATE_LOAD_FAILED: number = 5;

const SHARE_INITIALIZATION_TIMEOUT_MS: number = 15000;
const DEVICE_HEADER_STORE_NAME: string = 'device_card_header_preferences';
const DEVICE_HEADER_KEY: string = 'device_header_records';

class DeviceHeaderRecord {
  deviceId: string = '';
  path: string = '';

  constructor(deviceId: string, path: string) {
    this.deviceId = deviceId;
    this.path = path;
  }
}

@Observed
export class ShareTargetController {
  public state: number = SHARE_STATE_LOADING;
  public kind: number = 0;
  public summary: string = '';
  public sending: boolean = false;
  public devices: EngineRuntimeDevice[] = [];
  public headerImages: DeviceHeaderRecord[] = [];
  public selectedDeviceId: string = '';

  private record: systemShare.SharedRecord | null = null;
  private clipboardService: ClipboardService = new ClipboardService();
  private historyController: ClipboardFeatureController = ClipboardFeatureController.getInstance();
  private initializationId: number = 0;
  private initializationTimerId: number = -1;
  private initializationStage: string = '';

  public async initialize(data: systemShare.SharedData, context: common.Context): Promise<void> {
    this.initializationId += 1;
    let initializationId: number = this.initializationId;
    this.cancelInitializationTimer();
    this.state = SHARE_STATE_LOADING;
    this.record = null;
    this.devices = [];
    this.headerImages = this.loadHeaderImages(context);
    this.kind = 0;
    this.summary = '';
    this.initializationStage = 'shared content';
    this.scheduleInitializationTimeout(initializationId);
    try {
      let records: systemShare.SharedRecord[] = data.getRecords();
      if (records.length !== 1) {
        this.state = SHARE_STATE_INVALID;
        return;
      }
      let record: systemShare.SharedRecord = records[0];
      if (!this.parseRecord(record)) {
        this.state = SHARE_STATE_INVALID;
        return;
      }
      this.record = record;
      this.initializationStage = 'official engine session';
      await engineRuntimeService.start();
      let recovery = await engineRuntimeService.recoverSession(true);
      if (!this.isInitializationActive(initializationId)) {
        return;
      }
      if (!recovery.resumed) {
        this.state = SHARE_STATE_NOT_JOINED;
        return;
      }
      this.initializationStage = 'device list';
      logger.info('UniClipboard share target is reading official Engine devices.');
      let allDevices: EngineRuntimeDevice[] = await engineRuntimeService.queryDevices();
      if (!this.isInitializationActive(initializationId)) {
        return;
      }
      let targets: EngineRuntimeDevice[] = [];
      for (let index: number = 0; index < allDevices.length; index += 1) {
        let device: EngineRuntimeDevice = allDevices[index];
        if (!device.isLocal) {
          targets.push(device);
        }
      }
      this.devices = targets;
      this.state = SHARE_STATE_READY;
    } catch (error) {
      if (this.isInitializationActive(initializationId)) {
        logger.error('UniClipboard share target initialization failed at ' + this.initializationStage + '.');
        this.state = SHARE_STATE_LOAD_FAILED;
      }
    } finally {
      if (initializationId === this.initializationId) {
        this.cancelInitializationTimer();
      }
    }
  }

  public headerImagePath(deviceId: string): string {
    for (let index: number = 0; index < this.headerImages.length; index += 1) {
      let record: DeviceHeaderRecord = this.headerImages[index];
      if (record.deviceId === deviceId) {
        return record.path;
      }
    }
    return '';
  }

  public async setHeaderImage(deviceId: string, sourceUri: string, context: common.Context): Promise<boolean> {
    if (deviceId.length === 0 || sourceUri.length === 0) {
      return false;
    }
    let previousPath: string = this.headerImagePath(deviceId);
    let targetPath: string = context.filesDir + '/device-card-header-' + this.safeFilePart(deviceId) + '-' +
      Date.now().toString() + '.image';
    let source: fileIo.File | null = null;
    try {
      source = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      fileIo.copyFileSync(source.fd, targetPath);
      let updated: DeviceHeaderRecord[] = [];
      let replaced: boolean = false;
      for (let index: number = 0; index < this.headerImages.length; index += 1) {
        let record: DeviceHeaderRecord = this.headerImages[index];
        if (record.deviceId === deviceId) {
          updated.push(new DeviceHeaderRecord(deviceId, targetPath));
          replaced = true;
        } else {
          updated.push(record);
        }
      }
      if (!replaced) {
        updated.push(new DeviceHeaderRecord(deviceId, targetPath));
      }
      this.headerImages = updated;
      this.saveHeaderImages(context, updated);
      if (previousPath.length > 0 && previousPath !== targetPath && previousPath.startsWith(context.filesDir)) {
        try {
          fileIo.unlinkSync(previousPath);
        } catch (removeError) {
          logger.error('UniClipboard failed to remove the previous device header image.');
        }
      }
      return true;
    } catch (error) {
      try {
        fileIo.unlinkSync(targetPath);
      } catch (removeError) {
        logger.error('UniClipboard failed to remove an incomplete device header image.');
      }
      logger.error('UniClipboard failed to save the device header image.');
      return false;
    } finally {
      if (source !== null) {
        fileIo.closeSync(source.fd);
      }
    }
  }

  private loadHeaderImages(context: common.Context): DeviceHeaderRecord[] {
    try {
      let options: preferences.Options = { name: DEVICE_HEADER_STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      let serialized: string = store.getSync(DEVICE_HEADER_KEY, '') as string;
      if (serialized.length === 0) {
        return [];
      }
      let records: DeviceHeaderRecord[] = JSON.parse(serialized) as DeviceHeaderRecord[];
      let valid: DeviceHeaderRecord[] = [];
      for (let index: number = 0; index < records.length; index += 1) {
        let record: DeviceHeaderRecord = records[index];
        if (record.deviceId.length > 0 && record.path.length > 0) {
          valid.push(new DeviceHeaderRecord(record.deviceId, record.path));
        }
      }
      return valid;
    } catch (error) {
      return [];
    }
  }

  private saveHeaderImages(context: common.Context, records: DeviceHeaderRecord[]): void {
    try {
      let options: preferences.Options = { name: DEVICE_HEADER_STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      store.putSync(DEVICE_HEADER_KEY, JSON.stringify(records));
      store.flushSync();
    } catch (error) {
      logger.error('UniClipboard failed to persist device header images.');
    }
  }

  private safeFilePart(value: string): string {
    let result: string = value.replace(/[^a-zA-Z0-9_-]/g, '_');
    return result.length > 0 ? result : 'device';
  }

  private isInitializationActive(initializationId: number): boolean {
    return initializationId === this.initializationId && this.state === SHARE_STATE_LOADING;
  }

  private scheduleInitializationTimeout(initializationId: number): void {
    this.initializationTimerId = setTimeout((): void => {
      if (!this.isInitializationActive(initializationId)) {
        return;
      }
      logger.error('UniClipboard share target initialization timed out at ' + this.initializationStage + '.');
      this.state = SHARE_STATE_LOAD_FAILED;
      this.initializationTimerId = -1;
    }, SHARE_INITIALIZATION_TIMEOUT_MS);
  }

  private cancelInitializationTimer(): void {
    if (this.initializationTimerId < 0) {
      return;
    }
    clearTimeout(this.initializationTimerId);
    this.initializationTimerId = -1;
  }

  public async sendTo(deviceId: string): Promise<boolean> {
    let record: systemShare.SharedRecord | null = this.record;
    if (record === null || (this.state !== SHARE_STATE_READY && this.state !== SHARE_STATE_FAILED) || this.sending) {
      return false;
    }
    if ((this.kind === SHARE_KIND_IMAGE || this.kind === SHARE_KIND_FILE) && deviceId.trim().length === 0) {
      this.state = SHARE_STATE_FAILED;
      return false;
    }
    this.state = SHARE_STATE_READY;
    this.sending = true;
    this.selectedDeviceId = deviceId;
    try {
      let acceptedCount: number = 0;
      let historyText: string = '';
      let historyKind: string = 'Text';
      let historyImage: image.PixelMap | null = null;
      let historyFilePath: string = '';
      let targets: string[] = [];
      if (deviceId.length > 0) {
        targets.push(deviceId);
      }
      if (this.kind === SHARE_KIND_TEXT) {
        let content: string = record.content === undefined ? '' : record.content;
        let report: EngineSendReport = await engineRuntimeService.sendText(content, targets);
        acceptedCount = report.totalAccepted + report.totalPending;
        historyText = content;
      } else if (this.kind === SHARE_KIND_IMAGE) {
        let imageUri: string = record.uri === undefined ? '' : record.uri;
        let pixelMap: image.PixelMap = await this.clipboardService.decodeImageUri(imageUri);
        let imageData: Uint8Array = await this.clipboardService.encodePng(pixelMap);
        let report: EngineSendReport = await engineRuntimeService.sendImage(imageData, 'image/png', targets);
        acceptedCount = report.totalAccepted + report.totalPending;
        historyText = this.summary.length > 0 ? this.summary : 'image.jpg';
        historyKind = 'Image';
        historyImage = pixelMap;
      } else if (this.kind === SHARE_KIND_FILE) {
        let fileUri: string = record.uri === undefined ? '' : record.uri;
        if (fileUri.length === 0) {
          this.state = SHARE_STATE_FAILED;
          return false;
        }
        let report: EngineSendReport = await engineRuntimeService.sendFileFromUri(fileUri, '', targets);
        acceptedCount = report.totalAccepted + report.totalPending;
        historyText = this.summary.length > 0 ? this.summary : 'shared-file';
        historyKind = 'File';
        historyFilePath = fileUri;
      }
      if (acceptedCount <= 0) {
        this.state = SHARE_STATE_FAILED;
        return false;
      }
      this.historyController.addHistory(historyText, 'sent', historyKind, historyImage, null,
        historyFilePath);
      return true;
    } catch (error) {
      this.state = SHARE_STATE_FAILED;
      return false;
    } finally {
      this.sending = false;
    }
  }

  private parseRecord(record: systemShare.SharedRecord): boolean {
    let content: string = record.content === undefined ? '' : record.content;
    if (content.trim().length > 0) {
      this.kind = SHARE_KIND_TEXT;
      this.summary = this.ellipsize(content.trim());
      return true;
    }
    let uri: string = record.uri === undefined ? '' : record.uri;
    if (uri.length === 0) {
      return false;
    }
    if (this.belongsTo(record.utd, uniformTypeDescriptor.UniformDataType.IMAGE)) {
      this.kind = SHARE_KIND_IMAGE;
      this.summary = record.title === undefined ? '' : record.title;
      return true;
    }
    this.kind = SHARE_KIND_FILE;
    if (record.title !== undefined && record.title.trim().length > 0) {
      this.summary = record.title.trim();
    } else {
      try {
        this.summary = this.clipboardService.inspectFile(uri).fileName;
      } catch (error) {
        this.summary = '';
      }
    }
    return true;
  }

  private belongsTo(utd: string, parentUtd: string): boolean {
    if (utd === parentUtd) {
      return true;
    }
    try {
      let descriptor: uniformTypeDescriptor.TypeDescriptor = uniformTypeDescriptor.getTypeDescriptor(utd);
      return descriptor.belongsTo(parentUtd);
    } catch (error) {
      return false;
    }
  }

  private ellipsize(value: string): string {
    if (value.length <= 120) {
      return value;
    }
    return value.substring(0, 120) + '…';
  }
}
