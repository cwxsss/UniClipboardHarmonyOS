import { common, contextConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { notificationManager } from '@kit.NotificationKit';

const NOTIFICATION_DOMAIN: number = 0xD215;
const NOTIFICATION_TAG: string = 'UniClipboardNotification';
const NOTIFICATION_LABEL: string = 'uniclipboard-received';
// Port of UniClipboard desktop Cuelume's "success" recipe to a native WAV asset.
const NOTIFICATION_SOUND: string = 'notification_received.wav';
const NOTIFICATION_BASE_ID: number = 31000;

export class ReceivedNotificationService {
  private static instance: ReceivedNotificationService | null = null;
  private slotReady: boolean = false;
  private permissionPrompted: boolean = false;
  private nextNotificationId: number = NOTIFICATION_BASE_ID;
  private soundUri: string = '';

  private constructor() {
  }

  public static getInstance(): ReceivedNotificationService {
    if (ReceivedNotificationService.instance === null) {
      ReceivedNotificationService.instance = new ReceivedNotificationService();
    }
    return ReceivedNotificationService.instance;
  }

  public async notifyReceived(context: common.UIAbilityContext, kind: string, displayName: string,
    preview: image.PixelMap | null = null, fileSize: number = 0, sourceLabel: string = ''): Promise<void> {
    let ready: boolean = await this.ensureReady(context);
    if (!ready) {
      return;
    }
    let content: notificationManager.NotificationContent = await this.buildContent(
      context, kind, displayName, preview, fileSize, sourceLabel);
    let sound: string = this.prepareSound(context);
    let request: notificationManager.NotificationRequest = {
      id: this.takeNotificationId(),
      label: NOTIFICATION_LABEL,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: content,
      groupName: NOTIFICATION_LABEL,
      sound: sound
    };
    try {
      await notificationManager.publish(request);
    } catch (error) {
      let publishError: BusinessError = error as BusinessError;
      hilog.warn(NOTIFICATION_DOMAIN, NOTIFICATION_TAG,
        'publish received notification failed. code=%{public}d message=%{public}s',
        publishError.code, publishError.message);
    }
  }

  private async buildContent(context: common.UIAbilityContext, kind: string, displayName: string,
    preview: image.PixelMap | null, fileSize: number, sourceLabel: string): Promise<notificationManager.NotificationContent> {
    let title: string = await this.resourceString(context, 'notification_received_title', 'UniClipboard 收到新内容');
    if (sourceLabel.length > 0) {
      title += ' · ' + sourceLabel;
    }
    let text: string = await this.notificationText(context, kind, displayName);
    let additionalText: string = await this.resourceString(context, 'notification_received_open',
      '打开 UniClipboard 查看并使用');
    if (preview !== null && (kind === 'Image' || this.isImageFile(displayName))) {
      let thumbnail: image.PixelMap = await this.createThumbnail(preview);
      return {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_PICTURE,
        picture: {
          title: title,
          text: text,
          additionalText: additionalText,
          briefText: this.previewText(text),
          expandedTitle: title,
          picture: thumbnail
        }
      };
    }
    if (kind === 'File' && this.isDocumentFile(displayName)) {
      let longText: string = this.fileDescription(displayName, fileSize);
      return {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_LONG_TEXT,
        longText: {
          title: title,
          text: text,
          additionalText: additionalText,
          briefText: this.previewText(text),
          expandedTitle: title,
          longText: longText
        }
      };
    }
    if (kind === 'Text') {
      return {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
        multiLine: {
          title: title,
          text: text,
          additionalText: additionalText,
          briefText: this.previewText(text),
          longTitle: title,
          lines: this.textLines(displayName)
        }
      };
    }
    if (kind === 'File') {
      return {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
        multiLine: {
          title: title,
          text: text,
          additionalText: additionalText,
          briefText: this.previewText(text),
          longTitle: title,
          lines: [this.fileCategory(displayName), this.previewText(displayName), this.formatFileSize(fileSize)]
        }
      };
    }
    return {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: title,
        text: text,
        additionalText: additionalText
      }
    };
  }

  private async createThumbnail(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    try {
      let imageInfo: image.ImageInfo = pixelMap.getImageInfoSync();
      let width: number = imageInfo.size.width;
      let height: number = imageInfo.size.height;
      let longestEdge: number = Math.max(width, height);
      if (longestEdge <= 320) {
        return pixelMap;
      }
      let scale: number = 320 / longestEdge;
      let region: image.Region = {
        x: 0,
        y: 0,
        size: {
          width: width,
          height: height
        }
      };
      return await pixelMap.createCroppedAndScaledPixelMap(region, scale, scale,
        image.AntiAliasingLevel.MEDIUM);
    } catch (error) {
      hilog.warn(NOTIFICATION_DOMAIN, NOTIFICATION_TAG,
        'create notification thumbnail failed, using original image.');
      return pixelMap;
    }
  }

  private prepareSound(context: common.UIAbilityContext): string {
    if (this.soundUri.length > 0) {
      return this.soundUri;
    }
    try {
      let applicationContext: common.ApplicationContext = context.getApplicationContext();
      applicationContext.area = contextConstant.AreaMode.EL1;
      let soundDirectory: string = applicationContext.filesDir;
      let soundPath: string = soundDirectory + '/' + NOTIFICATION_SOUND;
      if (!fileIo.accessSync(soundPath)) {
        if (!fileIo.accessSync(soundDirectory)) {
          fileIo.mkdirSync(soundDirectory, true);
        }
        let rawFileData: Uint8Array = context.resourceManager.getRawFileContentSync(NOTIFICATION_SOUND);
        let soundFile: fileIo.File = fileIo.openSync(soundPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(soundFile.fd, rawFileData.buffer);
        } finally {
          fileIo.closeSync(soundFile.fd);
        }
      }
      this.soundUri = 'uri::' + fileUri.getUriFromPath(soundPath);
      hilog.info(NOTIFICATION_DOMAIN, NOTIFICATION_TAG,
        'prepared notification sound at %{public}s', this.soundUri);
      return this.soundUri;
    } catch (error) {
      hilog.warn(NOTIFICATION_DOMAIN, NOTIFICATION_TAG,
        'prepare notification sound failed, falling back to system sound.');
      return NOTIFICATION_SOUND;
    }
  }

  private async ensureReady(context: common.UIAbilityContext): Promise<boolean> {
    if (!this.slotReady) {
      try {
        await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
        this.slotReady = true;
      } catch (error) {
        let slotError: BusinessError = error as BusinessError;
        hilog.warn(NOTIFICATION_DOMAIN, NOTIFICATION_TAG,
          'add notification slot failed. code=%{public}d message=%{public}s',
          slotError.code, slotError.message);
        return false;
      }
    }
    if (!this.permissionPrompted) {
      this.permissionPrompted = true;
      try {
        let enabled: boolean = await notificationManager.isNotificationEnabled();
        if (!enabled) {
          await notificationManager.requestEnableNotification(context);
        }
      } catch (error) {
        let permissionError: BusinessError = error as BusinessError;
        hilog.warn(NOTIFICATION_DOMAIN, NOTIFICATION_TAG,
          'request notification permission failed. code=%{public}d message=%{public}s',
          permissionError.code, permissionError.message);
      }
    }
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (error) {
      return false;
    }
  }

  private async notificationText(context: common.UIAbilityContext, kind: string, displayName: string): Promise<string> {
    if (kind === 'Image') {
      let prefix: string = await this.resourceString(context, 'notification_received_image', '图片已接收');
      return prefix + (displayName.length > 0 ? '：' + displayName : '');
    }
    if (kind === 'File') {
      let prefix: string = await this.resourceString(context, 'notification_received_file', '文件已接收');
      return prefix + (displayName.length > 0 ? '：' + displayName : '');
    }
    if (displayName.length > 0) {
      let prefix: string = await this.resourceString(context, 'notification_received_text', '文本已接收');
      return prefix + '：' + this.previewText(displayName);
    }
    return await this.resourceString(context, 'notification_received_text', '文本已接收');
  }

  private async resourceString(context: common.UIAbilityContext, name: string, fallback: string): Promise<string> {
    try {
      return await context.resourceManager.getStringByName(name);
    } catch (error) {
      return fallback;
    }
  }

  private previewText(value: string): string {
    let normalized: string = value.replace(/\s+/g, ' ').trim();
    if (normalized.length > 80) {
      return normalized.substring(0, 80) + '…';
    }
    return normalized;
  }

  private textLines(value: string): Array<string> {
    let normalized: string = this.previewText(value);
    if (normalized.length === 0) {
      return ['文本内容', '（空文本）', '来自 UniClipboard'];
    }
    let lines: Array<string> = [];
    let first: string = normalized.substring(0, 42);
    lines.push(first);
    if (normalized.length > 42) {
      lines.push(normalized.substring(42, 84));
    }
    if (normalized.length > 84) {
      lines.push(normalized.substring(84, 126));
    } else {
      lines.push('来自 UniClipboard');
    }
    return lines;
  }

  private fileExtension(name: string): string {
    let dot: number = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  private fileCategory(name: string): string {
    let extension: string = this.fileExtension(name);
    if (extension === 'pdf') {
      return 'PDF 文档';
    }
    if (extension === 'doc' || extension === 'docx' || extension === 'txt' || extension === 'md' ||
      extension === 'rtf') {
      return '文字文档';
    }
    if (extension === 'xls' || extension === 'xlsx' || extension === 'csv') {
      return '表格文件';
    }
    if (extension === 'ppt' || extension === 'pptx') {
      return '演示文稿';
    }
    if (extension === 'jpg' || extension === 'jpeg' || extension === 'png' || extension === 'gif' ||
      extension === 'webp' || extension === 'bmp') {
      return '图片文件';
    }
    if (extension === 'mp4' || extension === 'mov' || extension === 'mkv' || extension === 'avi') {
      return '视频文件';
    }
    if (extension === 'mp3' || extension === 'wav' || extension === 'm4a' || extension === 'flac') {
      return '音频文件';
    }
    if (extension === 'zip' || extension === 'rar' || extension === '7z' || extension === 'tar' ||
      extension === 'gz') {
      return '压缩包';
    }
    return '文件';
  }

  private isDocumentFile(name: string): boolean {
    let extension: string = this.fileExtension(name);
    return extension === 'pdf' || extension === 'doc' || extension === 'docx' || extension === 'txt' ||
      extension === 'md' || extension === 'rtf' || extension === 'xls' || extension === 'xlsx' ||
      extension === 'csv' || extension === 'ppt' || extension === 'pptx';
  }

  private isImageFile(name: string): boolean {
    let extension: string = this.fileExtension(name);
    return extension === 'jpg' || extension === 'jpeg' || extension === 'png' || extension === 'gif' ||
      extension === 'webp' || extension === 'bmp';
  }

  private formatFileSize(size: number): string {
    if (size <= 0) {
      return '文件已接收';
    }
    if (size < 1024) {
      return size.toFixed(0) + ' B';
    }
    if (size < 1024 * 1024) {
      return (size / 1024).toFixed(1) + ' KB';
    }
    return (size / (1024 * 1024)).toFixed(1) + ' MB';
  }

  private fileDescription(name: string, size: number): string {
    return this.fileCategory(name) + '：' + this.previewText(name) + '（' + this.formatFileSize(size) + '）';
  }

  private takeNotificationId(): number {
    let id: number = this.nextNotificationId;
    this.nextNotificationId += 1;
    if (this.nextNotificationId > NOTIFICATION_BASE_ID + 500) {
      this.nextNotificationId = NOTIFICATION_BASE_ID;
    }
    return id;
  }
}
