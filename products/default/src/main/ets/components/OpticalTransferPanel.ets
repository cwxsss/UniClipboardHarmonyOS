import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { customScan, generateBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { util } from '@kit.ArkTS';
import {
  ClipboardFilePayload,
  ClipboardService,
  OPTICAL_FRAME_BYTES,
  OPTICAL_MAX_PAYLOAD_BYTES,
  OpticalFountainDecoder,
  OpticalFountainEncoder,
  OpticalFrame,
  OpticalTransferEnvelope,
  SyncContent,
  packOpticalEnvelope,
  parseOpticalFrame,
  unpackOpticalEnvelope
} from 'common';
import { ClipboardFeatureController } from 'clipboard_feature';
import { Api26Material } from './Api26Material';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const CAMERA_WIDTH: number = 300;
const CAMERA_HEIGHT: number = 400;
const QR_SIZE: number = 760;
const EXPECTED_OVERHEAD: number = 1.18;
const FRAME_INTERVAL_MS: number = 125;

@Component
export struct OpticalTransferPanel {
  @State controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();
  @State mode: number = 0;
  @State senderState: number = 0;
  @State senderLabel: string = '';
  @State senderFrame: number = 0;
  @State senderTotalEstimate: number = 0;
  @State qrPixelMap: image.PixelMap | null = null;
  @State receiverState: number = 0;
  @State receiverFrames: number = 0;
  @State receiverTotalEstimate: number = 0;
  @State receiverProgress: number = 0;
  @State cameraReady: boolean = false;
  @State receivedLabel: string = '';
  onClose: () => void = (): void => {};
  private clipboardService: ClipboardService = new ClipboardService();
  private encoder: OpticalFountainEncoder | null = null;
  private decoder: OpticalFountainDecoder | null = null;
  private senderGeneration: number = 0;
  private senderTimer: number = -1;
  private scanInitialized: boolean = false;
  private scanStarted: boolean = false;
  private xComponentController: XComponentController = new XComponentController();

  aboutToDisappear(): void {
    this.stopSender();
    this.stopReceiver();
  }

  private switchMode(mode: number): void {
    if (this.mode === mode) {
      return;
    }
    this.stopSender();
    this.stopReceiver();
    this.mode = mode;
    if (mode === 1) {
      this.startReceiver();
    }
  }

  private stopSender(): void {
    this.senderGeneration += 1;
    if (this.senderTimer >= 0) {
      clearTimeout(this.senderTimer);
      this.senderTimer = -1;
    }
    this.encoder = null;
  }

  private async releaseQrPixelMap(): Promise<void> {
    let current: image.PixelMap | null = this.qrPixelMap;
    this.qrPixelMap = null;
    if (current !== null) {
      try {
        await current.release();
      } catch (error) {
      }
    }
  }

  private async prepareSender(): Promise<void> {
    this.stopSender();
    await this.releaseQrPixelMap();
    this.senderState = 1;
    this.senderLabel = '';
    this.senderFrame = 0;
    this.senderTotalEstimate = 0;
    try {
      let envelope: OpticalTransferEnvelope | null = await this.currentEnvelope();
      if (envelope === null || envelope.data.length === 0) {
        this.senderState = 3;
        return;
      }
      let payload: Uint8Array = packOpticalEnvelope(envelope.kind, envelope.name, envelope.data);
      if (payload.length > OPTICAL_MAX_PAYLOAD_BYTES) {
        this.senderState = 4;
        return;
      }
      let sessionId: number = Math.max(1, Date.now() & 0xFFFF);
      let encoder: OpticalFountainEncoder = new OpticalFountainEncoder(payload, OPTICAL_FRAME_BYTES, sessionId);
      this.encoder = encoder;
      this.senderLabel = envelope.name.length > 0 ? envelope.name : this.textPreview(envelope.data);
      this.senderTotalEstimate = Math.ceil(encoder.blockCount * EXPECTED_OVERHEAD);
      this.senderState = 2;
      let generation: number = this.senderGeneration;
      await this.generateNextFrame(generation);
    } catch (error) {
      this.senderState = 3;
    }
  }

  private async currentEnvelope(): Promise<OpticalTransferEnvelope | null> {
    if (this.controller.composerFileUri.length > 0 && this.controller.composerFileName.length > 0) {
      let file: ClipboardFilePayload = this.clipboardService.readFile(this.controller.composerFileUri);
      return new OpticalTransferEnvelope('File', this.controller.composerFileName, file.data);
    }
    if (this.controller.composerImage !== null) {
      let imageData: Uint8Array = await this.clipboardService.encodePng(this.controller.composerImage);
      return new OpticalTransferEnvelope('Image', 'image.png', imageData);
    }
    if (this.controller.composerText.trim().length > 0) {
      let textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
      return new OpticalTransferEnvelope('Text', '', textEncoder.encodeInto(this.controller.composerText));
    }
    if (this.controller.latestKind === 'Image' && this.controller.latestImage !== null) {
      let imageData: Uint8Array = await this.clipboardService.encodePng(this.controller.latestImage);
      return new OpticalTransferEnvelope('Image', 'image.png', imageData);
    }
    if (this.controller.latestKind === 'File') {
      if (this.controller.latestFileData !== null) {
        return new OpticalTransferEnvelope('File', this.controller.latestFileName,
          this.controller.latestFileData);
      }
      if (this.controller.latestFilePath.length > 0) {
        let file: ClipboardFilePayload = this.clipboardService.readFile(this.controller.latestFilePath);
        return new OpticalTransferEnvelope('File', this.controller.latestFileName, file.data);
      }
    }
    if (this.controller.latestKind === 'Text' && this.controller.latestText.length > 0) {
      let textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
      return new OpticalTransferEnvelope('Text', '', textEncoder.encodeInto(this.controller.latestText));
    }
    return null;
  }

  private textPreview(data: Uint8Array): string {
    let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
    let text: string = decoder.decodeToString(data);
    return text.length > 40 ? text.substring(0, 40) + '…' : text;
  }

  private async generateNextFrame(generation: number): Promise<void> {
    let encoder: OpticalFountainEncoder | null = this.encoder;
    if (generation !== this.senderGeneration || encoder === null || this.senderState !== 2) {
      return;
    }
    try {
      let frameText: string = encoder.frameText(this.senderFrame);
      let options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        width: QR_SIZE,
        height: QR_SIZE,
        margin: 4,
        level: generateBarcode.ErrorCorrectionLevel.LEVEL_L,
        backgroundColor: 0xFFFFFF,
        pixelMapColor: 0x000000
      };
      let nextPixelMap: image.PixelMap = await generateBarcode.createBarcode(frameText, options);
      if (generation !== this.senderGeneration) {
        await nextPixelMap.release();
        return;
      }
      let previous: image.PixelMap | null = this.qrPixelMap;
      this.qrPixelMap = nextPixelMap;
      this.senderFrame += 1;
      if (previous !== null) {
        await previous.release();
      }
      this.senderTimer = setTimeout((): void => {
        this.generateNextFrame(generation);
      }, FRAME_INTERVAL_MS);
    } catch (error) {
      this.senderState = 3;
    }
  }

  private async requestCameraPermission(): Promise<boolean> {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return false;
    }
    try {
      let manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      let result: PermissionRequestResult = await manager.requestPermissionsFromUser(context, [CAMERA_PERMISSION]);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (error) {
      return false;
    }
  }

  private async startReceiver(): Promise<void> {
    await this.stopReceiver();
    this.receiverState = 1;
    this.receiverFrames = 0;
    this.receiverTotalEstimate = 0;
    this.receiverProgress = 0;
    this.receivedLabel = '';
    this.decoder = null;
    let granted: boolean = await this.requestCameraPermission();
    if (!granted || this.mode !== 1) {
      this.receiverState = 7;
      return;
    }
    try {
      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };
      customScan.init(options);
      this.scanInitialized = true;
      this.receiverState = 2;
      this.cameraReady = true;
    } catch (error) {
      this.receiverState = 6;
    }
  }

  private startScanSurface(): void {
    if (!this.cameraReady || !this.scanInitialized || this.scanStarted) {
      return;
    }
    try {
      let surfaceId: string = this.xComponentController.getXComponentSurfaceId();
      let viewControl: customScan.ViewControl = {
        width: CAMERA_WIDTH,
        height: CAMERA_HEIGHT,
        surfaceId: surfaceId
      };
      customScan.start(viewControl,
        (error: BusinessError, results: Array<scanBarcode.ScanResult>): void => {
          if (error) {
            this.receiverState = 6;
            return;
          }
          for (let index: number = 0; index < results.length; index += 1) {
            this.handleScanValue(results[index].originalValue);
          }
          if (this.receiverState !== 5 && this.scanStarted) {
            try {
              customScan.rescan();
            } catch (scanError) {
              this.receiverState = 6;
            }
          }
        });
      this.scanStarted = true;
    } catch (error) {
      this.receiverState = 6;
    }
  }

  private handleScanValue(value: string): void {
    let frame: OpticalFrame | null = parseOpticalFrame(value);
    if (frame === null || this.receiverState === 5) {
      return;
    }
    let decoder: OpticalFountainDecoder | null = this.decoder;
    if (decoder === null || decoder.sessionId !== frame.sessionId) {
      decoder = new OpticalFountainDecoder(frame);
      this.decoder = decoder;
      this.receiverTotalEstimate = Math.ceil(frame.blockCount * EXPECTED_OVERHEAD);
      this.receiverState = 3;
    }
    if (!decoder.isCompatible(frame)) {
      return;
    }
    decoder.addFrame(frame);
    this.receiverFrames = decoder.framesNew;
    this.receiverProgress = Math.min(0.99, decoder.framesNew /
      Math.max(1, this.receiverTotalEstimate));
    if (decoder.isComplete()) {
      this.finishReceive(decoder);
    }
  }

  private async finishReceive(decoder: OpticalFountainDecoder): Promise<void> {
    this.receiverState = 4;
    let payload: Uint8Array | null = decoder.assemble();
    if (payload === null) {
      this.receiverState = 6;
      return;
    }
    let envelope: OpticalTransferEnvelope | null = unpackOpticalEnvelope(payload);
    if (envelope === null) {
      this.receiverState = 6;
      return;
    }
    try {
      let contentId: string = 'optical-' + Date.now().toString();
      if (envelope.kind === 'Text') {
        let textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
        let text: string = textDecoder.decodeToString(envelope.data);
        await this.controller.applyLatestContent(
          new SyncContent('Text', text, contentId, '', new Uint8Array(0)), true);
        this.receivedLabel = this.textPreview(envelope.data);
      } else {
        let fileName: string = envelope.name.length > 0 ? envelope.name :
          envelope.kind === 'Image' ? 'image.png' : 'shared-file';
        await this.controller.applyLatestContent(
          new SyncContent(envelope.kind, fileName, contentId, fileName, envelope.data), true);
        this.receivedLabel = fileName;
      }
      this.receiverProgress = 1;
      this.receiverState = 5;
      await this.stopReceiverCamera();
    } catch (error) {
      this.receiverState = 6;
    }
  }

  private async stopReceiverCamera(): Promise<void> {
    this.cameraReady = false;
    if (this.scanStarted) {
      try {
        await customScan.stop();
      } catch (error) {
      }
      this.scanStarted = false;
    }
    if (this.scanInitialized) {
      try {
        await customScan.release();
      } catch (error) {
      }
      this.scanInitialized = false;
    }
  }

  private async stopReceiver(): Promise<void> {
    await this.stopReceiverCamera();
    this.decoder = null;
  }

  @Builder
  private modeButton(mode: number, icon: Resource, label: Resource) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([this.mode === mode ? this.controller.accentColor() : $r('app.color.text_secondary')])
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.mode === mode ? this.controller.accentColor() : $r('app.color.text_primary'))
      }
    }
    .layoutWeight(1)
    .height(44)
    .backgroundColor(this.mode === mode ? this.controller.accentSoftColor() : $r('app.color.surface_muted'))
    .borderRadius(14)
    .attributeModifier(Api26Material.accent())
    .onClick((): void => {
      this.switchMode(mode);
    })
  }

  @Builder
  private senderContent() {
    Column({ space: 14 }) {
      Text($r('app.string.optical_send_note'))
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.senderState === 2 && this.qrPixelMap !== null) {
        Image(this.qrPixelMap)
          .width(300)
          .height(300)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Color.White)
          .borderRadius(18)
        Text(this.senderLabel)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Row({ space: 8 }) {
          Text($r('app.string.optical_frames_sent'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.senderFrame.toString())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.controller.accentColor())
          Text('/')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.senderTotalEstimate.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      } else {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(64)
            .fontColor([this.controller.accentColor()])
          if (this.senderState === 1) {
            Text($r('app.string.optical_preparing'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          } else if (this.senderState === 4) {
            Text($r('app.string.optical_too_large'))
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.danger'))
              .textAlign(TextAlign.Center)
          } else if (this.senderState === 3) {
            Text($r('app.string.optical_no_content'))
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.danger'))
              .textAlign(TextAlign.Center)
          } else {
            Text($r('app.string.optical_send_ready'))
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .height(260)
        .justifyContent(FlexAlign.Center)
        .padding(24)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(18)
      }
      Button(this.senderState === 2 ? $r('app.string.optical_restart_send') :
        $r('app.string.optical_start_send'), { type: ButtonType.Normal })
        .width('100%')
        .height(46)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius(14)
        .enabled(this.senderState !== 1)
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.prepareSender();
        })
    }
    .width('100%')
  }

  @Builder
  private receiverContent() {
    Column({ space: 14 }) {
      Text($r('app.string.optical_receive_note'))
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.cameraReady) {
        Stack() {
          XComponent({
            id: 'optical-transfer-camera',
            type: XComponentType.SURFACE,
            controller: this.xComponentController
          })
            .width(CAMERA_WIDTH)
            .height(CAMERA_HEIGHT)
            .onLoad((): void => {
              this.startScanSurface();
            })
          Column()
            .width(220)
            .height(220)
            .border({ width: 3, color: this.controller.accentColor() })
            .borderRadius(22)
        }
        .width(CAMERA_WIDTH)
        .height(CAMERA_HEIGHT)
        .alignContent(Alignment.Center)
        .clip(true)
        .borderRadius(18)
        .backgroundColor(Color.Black)
      } else {
        Column({ space: 12 }) {
          SymbolGlyph(this.receiverState === 5 ? $r('sys.symbol.checkmark_circle_fill') :
            $r('sys.symbol.line_viewfinder'))
            .fontSize(64)
            .fontColor([this.receiverState === 5 ? $r('app.color.success') : this.controller.accentColor()])
          if (this.receiverState === 1) {
            Text($r('app.string.optical_requesting_camera'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          } else if (this.receiverState === 5) {
            Text($r('app.string.optical_receive_complete'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.success'))
            Text(this.receivedLabel)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
          } else if (this.receiverState === 7) {
            Text($r('app.string.optical_camera_denied'))
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.danger'))
              .textAlign(TextAlign.Center)
          } else if (this.receiverState === 6) {
            Text($r('app.string.optical_receive_failed'))
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.danger'))
              .textAlign(TextAlign.Center)
          } else {
            Text($r('app.string.optical_receive_ready'))
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
        .padding(24)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(18)
      }
      if (this.receiverState === 3 || this.receiverState === 4) {
        Progress({ value: this.receiverProgress * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .color(this.controller.accentColor())
        Row({ space: 8 }) {
          Text($r('app.string.optical_frames_received'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.receiverFrames.toString())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.controller.accentColor())
          Text('/')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.receiverTotalEstimate.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      if (!this.cameraReady && this.receiverState !== 1 && this.receiverState !== 5) {
        Button($r('app.string.optical_start_receive'), { type: ButtonType.Normal })
          .width('100%')
          .height(46)
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .borderRadius(14)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.startReceiver();
          })
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.optical_transfer_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.optical_transfer_subtitle'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.surface_muted'))
        .attributeModifier(Api26Material.interactive())
        .onClick((): void => {
          this.onClose();
        })
      }
      .width('100%')
      Row({ space: 10 }) {
        this.modeButton(0, $r('sys.symbol.qrcode'), $r('app.string.optical_send_tab'))
        this.modeButton(1, $r('sys.symbol.line_viewfinder'), $r('app.string.optical_receive_tab'))
      }
      .width('100%')
      Scroll() {
        if (this.mode === 0) {
          this.senderContent()
        } else {
          this.receiverContent()
        }
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 20, bottom: 22 })
    .backgroundColor($r('app.color.page_background'))
  }
}
