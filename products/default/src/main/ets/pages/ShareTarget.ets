import { common, UIExtensionContentSession } from '@kit.AbilityKit';
import { mediaquery, window } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import {
  hdsMaterial,
  HdsNavigation,
  HdsNavigationTitleMode,
  IconStyleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { Logger, NativeSpaceDevice } from 'common';
import { ClipboardFeatureController } from 'clipboard_feature';
import {
  SHARE_KIND_FILE,
  SHARE_KIND_IMAGE,
  SHARE_STATE_FAILED,
  SHARE_STATE_INVALID,
  SHARE_STATE_LOAD_FAILED,
  SHARE_STATE_LOADING,
  SHARE_STATE_NOT_JOINED,
  ShareTargetController
} from '../viewmodel/ShareTargetController';

import { Api26Material } from '../components/Api26Material';
const logger: Logger = new Logger('ShareTargetPage');

@Entry
@Component
struct ShareTarget {
  @State controller: ShareTargetController = new ShareTargetController();
  @State wideLayout: boolean = false;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  private storage: LocalStorage | undefined = this.getUIContext().getSharedLocalStorage();
  private session: UIExtensionContentSession | undefined =
    this.storage?.get<UIExtensionContentSession>('shareSession');
  private hostWindow: window.Window | undefined = this.storage?.get<window.Window>('shareHostWindow');
  private wideScreenListener: mediaquery.MediaQueryListener | null = null;
  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.configureLayout();
    let featureController: ClipboardFeatureController = ClipboardFeatureController.getInstance();
    featureController.prepareSharedHistory(this.getUIContext());
    featureController.restoreAppearanceVisualSettings();
    this.materialLevel = featureController.appearanceMaterialLevel;
    this.initialize();
  }

  aboutToDisappear(): void {
    if (this.wideScreenListener !== null) {
      this.wideScreenListener.off('change');
      this.wideScreenListener = null;
    }
  }

  private configureLayout(): void {
    let listener: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery()
      .matchMediaSync('(720vp<=width)');
    this.wideScreenListener = listener;
    this.wideLayout = listener.matches;
    listener.on('change', (result: mediaquery.MediaQueryResult): void => {
      this.wideLayout = result.matches;
    });
  }

  private initialize(): void {
    let data: systemShare.SharedData | undefined = this.storage?.get<systemShare.SharedData>('shareData');
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (data === undefined || context === undefined) {
      this.controller.state = SHARE_STATE_INVALID;
      return;
    }
    this.controller.initialize(data, context);
  }

  private async closeWithResult(resultCode: number): Promise<void> {
    if (this.session !== undefined) {
      try {
        await this.session.terminateSelfWithResult({ resultCode: resultCode });
      } catch (error) {
        logger.error('UniClipboard failed to close the share detail page.');
      }
      return;
    }
    if (this.hostWindow === undefined) {
      return;
    }
    try {
      await this.hostWindow.setUIContent('pages/Index');
    } catch (error) {
      logger.error('UniClipboard failed to restore the main page after sharing.');
    }
  }

  private async sendTo(deviceId: string): Promise<void> {
    let sent: boolean = await this.controller.sendTo(deviceId);
    if (sent) {
      await this.closeWithResult(systemShare.ShareAbilityResultCode.CLOSE);
    }
  }

  private async chooseHeaderImage(deviceId: string): Promise<void> {
    let hostContext: common.Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    try {
      let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      await this.controller.setHeaderImage(deviceId, result.photoUris[0], hostContext);
    } catch (error) {
      logger.error('UniClipboard failed to choose a device header image.');
    }
  }

  private contentIcon(): Resource {
    if (this.controller.kind === SHARE_KIND_IMAGE) {
      return $r('sys.symbol.ohos_photo');
    }
    if (this.controller.kind === SHARE_KIND_FILE) {
      return $r('sys.symbol.folder');
    }
    return $r('sys.symbol.link');
  }

  private contentLabel(): ResourceStr {
    if (this.controller.kind === SHARE_KIND_IMAGE) {
      return $r('app.string.share_target_content_image');
    }
    if (this.controller.kind === SHARE_KIND_FILE) {
      return $r('app.string.share_target_content_file');
    }
    return $r('app.string.share_target_content_text');
  }

  private deviceIcon(device: NativeSpaceDevice): Resource {
    if (device.deviceType === 'phone') {
      return $r('sys.symbol.phone');
    }
    if (device.deviceType === '2in1') {
      return $r('sys.symbol.desktop');
    }
    return $r('sys.symbol.device_2');
  }

  private hasOnlineDevice(): boolean {
    for (let index: number = 0; index < this.controller.devices.length; index += 1) {
      if (this.controller.devices[index].online) {
        return true;
      }
    }
    return false;
  }

  @Builder
  private ContentCard() {
    Column({ space: 18 }) {
      Row({ space: 14 }) {
        Column() {
          SymbolGlyph(this.contentIcon())
            .fontSize(30)
            .fontColor([$r('app.color.accent')])
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .borderRadius($r('sys.float.corner_radius_level6'))
        .backgroundColor($r('app.color.accent_soft'))
        .attributeModifier(Api26Material.accentSurface())
        Column({ space: 4 }) {
          Text(this.contentLabel())
            .fontSize($r('sys.float.Body_S'))
            .fontColor($r('sys.color.font_secondary'))
          Text(this.controller.summary.length > 0 ? this.controller.summary : this.contentLabel())
            .fontSize($r('sys.float.Title_M'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .ellipsisMode(EllipsisMode.END)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      Text(this.contentLabel())
        .fontSize($r('sys.float.Body_L'))
        .lineHeight(24)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(this.wideLayout ? 5 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding($r('sys.float.padding_level8'))
    .borderRadius($r('sys.float.corner_radius_level8'))
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .attributeModifier(Api26Material.panel())
    .clip(true)
  }

  @Builder
  private SendAllButton() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        if (this.controller.sending && this.controller.selectedDeviceId.length === 0) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(Api26Material.accentTextColor())
        } else {
          SymbolGlyph($r('sys.symbol.nearby_devices'))
            .fontSize(23)
            .fontColor([Api26Material.accentTextColor()])
        }
        Text($r('app.string.share_target_all_devices'))
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Medium)
          .fontColor(Api26Material.accentTextColor())
          .maxLines(1)
      }
    }
    .height(52)
    .width('100%')
    .backgroundColor($r('app.color.accent'))
    .borderRadius($r('sys.float.corner_radius_level8'))
    .enabled(!this.controller.sending && this.hasOnlineDevice())
    .attributeModifier(Api26Material.accent())
    .onClick((): void => {
      this.sendTo('');
    })
  }

  @Builder
  private SendFailure() {
    if (this.controller.state === SHARE_STATE_FAILED) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(18)
          .fontColor([$r('app.color.danger')])
        Text($r('app.string.share_target_send_failed'))
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('app.color.danger'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }
  }

  @Builder
  private DeviceCard(device: NativeSpaceDevice) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (this.controller.headerImagePath(device.deviceId).length > 0) {
          Image(this.controller.headerImagePath(device.deviceId))
            .width('100%')
            .height(this.wideLayout ? $r('app.float.device_card_header_height') :
              $r('app.float.device_card_header_height_compact'))
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            SymbolGlyph(this.deviceIcon(device))
              .fontSize(64)
              .fontColor([device.online ? $r('app.color.on_accent') : $r('sys.color.icon_tertiary')])
          }
          .width('100%')
          .height(this.wideLayout ? $r('app.float.device_card_header_height') :
            $r('app.float.device_card_header_height_compact'))
          .justifyContent(FlexAlign.Center)
          .backgroundColor(device.online ? $r('app.color.accent') : $r('sys.color.comp_background_tertiary'))
          .attributeModifier(Api26Material.accentSurface())
        }
        Column() {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(device.online ? $r('app.string.share_target_online') : $r('app.string.share_target_offline'))
                .fontSize($r('sys.float.Body_S'))
                .fontColor(device.online ? $r('app.color.on_accent') : $r('sys.color.font_tertiary'))
                .fontWeight(FontWeight.Medium)
              Text(device.deviceName)
                .fontSize($r('sys.float.Title_M'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.on_accent'))
                .maxLines(1)
                .ellipsisMode(EllipsisMode.END)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button({ type: ButtonType.Circle }) {
              if (this.controller.sending && this.controller.selectedDeviceId === device.deviceId) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color($r('app.color.accent'))
              } else {
                SymbolGlyph($r('sys.symbol.arrow_right'))
                  .fontSize(24)
                  .fontColor([device.online ? $r('app.color.accent') : $r('sys.color.icon_tertiary')])
              }
            }
            .width(52)
            .height(52)
            .backgroundColor($r('app.color.on_accent'))
            .enabled(device.online && !this.controller.sending)
            .attributeModifier(Api26Material.accent())
            .onClick((): void => {
              this.sendTo(device.deviceId);
            })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 18, top: 18, bottom: 18 })
        .backgroundColor($r('app.color.card_image_overlay'))
      }
      .width('100%')
      .height(this.wideLayout ? $r('app.float.device_card_header_height') :
        $r('app.float.device_card_header_height_compact'))
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.ohos_photo'))
          .fontSize(18)
          .fontColor([$r('app.color.on_accent')])
      }
      .width(44)
      .height(44)
      .margin({ top: 16, right: 16 })
      .backgroundColor($r('app.color.card_image_overlay'))
      .accessibilityText($r('app.string.share_target_customize_header'))
      .attributeModifier(Api26Material.accent())
      .onClick((): void => {
        this.chooseHeaderImage(device.deviceId);
      })
    }
    .width('100%')
    .height(this.wideLayout ? $r('app.float.device_card_header_height') :
      $r('app.float.device_card_header_height_compact'))
    .borderRadius($r('sys.float.corner_radius_level8'))
    .clip(true)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .opacity(device.online ? 1 : 0.52)
    .enabled(!this.controller.sending)
    .attributeModifier(Api26Material.interactive())
    .onClick((): void => {
      if (device.online) {
        this.sendTo(device.deviceId);
      }
    })
  }

  @Builder
  private EmptyDevices() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.device_2'))
        .fontSize(40)
        .fontColor([$r('sys.color.icon_tertiary')])
      Text($r('app.string.share_target_no_devices'))
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }

  @Builder
  private WideReadyState() {
    Column() {
      Blank().height(56)
      Row({ space: 24 }) {
        Column({ space: 16 }) {
          this.ContentCard()
          this.SendFailure()
          this.SendAllButton()
        }
        .width(380)

        Column({ space: 14 }) {
          Text($r('app.string.share_target_choose_device'))
            .fontSize($r('sys.float.Title_S'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          if (this.controller.devices.length === 0) {
            this.EmptyDevices()
          } else {
            Grid(this.contentScroller) {
              ForEach(this.controller.devices, (device: NativeSpaceDevice) => {
                GridItem() {
                  this.DeviceCard(device)
                }
              }, (device: NativeSpaceDevice): string => device.deviceId)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(20)
            .rowsGap(20)
            .layoutWeight(1)
            .width('100%')
            .height(0)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .height(0)
      .alignItems(VerticalAlign.Top)
      .constraintSize({ maxWidth: 1120 })
      .padding({ left: 24, right: 24, top: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private CompactReadyState() {
    Column() {
      Blank().height(56)
      Scroll(this.contentScroller) {
        Column({ space: 16 }) {
          this.ContentCard()
          this.SendFailure()
          this.SendAllButton()
          Text($r('app.string.share_target_choose_device'))
            .fontSize($r('sys.float.Title_S'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          if (this.controller.devices.length === 0) {
            Column() {
              this.EmptyDevices()
            }
            .height(180)
          } else {
            ForEach(this.controller.devices, (device: NativeSpaceDevice) => {
              this.DeviceCard(device)
            }, (device: NativeSpaceDevice): string => device.deviceId)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 28 })
      }
      .width('100%')
      .layoutWeight(1)
      .height(0)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .constraintSize({ maxWidth: 680 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private LoadingState() {
    Column({ space: 16 }) {
      Blank().height(56)
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.accent'))
      Text($r('app.string.share_target_loading'))
        .fontSize($r('sys.float.Body_L'))
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private RetryState() {
    Column({ space: 16 }) {
      Blank().height(56)
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([$r('app.color.danger')])
      Text($r('app.string.share_target_load_failed'))
        .fontSize($r('sys.float.Body_L'))
        .lineHeight(24)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.share_target_retry'), { type: ButtonType.Normal })
        .height(44)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor($r('app.color.accent'))
        .borderRadius($r('sys.float.corner_radius_level8'))
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.initialize();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private ErrorState(message: ResourceStr) {
    Column({ space: 16 }) {
      Blank().height(56)
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([$r('app.color.danger')])
      Text(message)
        .fontSize($r('sys.float.Body_L'))
        .lineHeight(24)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.share_target_back'), { type: ButtonType.Normal })
        .height(44)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius($r('sys.float.corner_radius_level8'))
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.closeWithResult(systemShare.ShareAbilityResultCode.BACK);
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private PageContent() {
    if (this.controller.state === SHARE_STATE_LOADING) {
      this.LoadingState()
    } else if (this.controller.state === SHARE_STATE_NOT_JOINED) {
      this.ErrorState($r('app.string.share_target_not_joined'))
    } else if (this.controller.state === SHARE_STATE_INVALID) {
      this.ErrorState($r('app.string.share_target_unsupported'))
    } else if (this.controller.state === SHARE_STATE_LOAD_FAILED) {
      this.RetryState()
    } else if (this.wideLayout) {
      this.WideReadyState()
    } else {
      this.CompactReadyState()
    }
  }

  build() {
    HdsNavigation() {
      this.PageContent()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.share_target_title'),
          subTitle: this.controller.state === SHARE_STATE_LOADING ?
            $r('app.string.share_target_loading') : this.contentLabel()
        },
        menu: {
          value: [{
            content: {
              label: 'modal_cancel',
              isEnabled: !this.controller.sending,
              type: IconStyleMode.SMALL,
              action: (): void => {
                this.closeWithResult(systemShare.ShareAbilityResultCode.BACK);
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: $r('app.color.accent')
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: $r('app.color.accent')
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.materialLevel
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .bindToScrollable([this.contentScroller])
    .backgroundColor($r('sys.color.background_secondary'))
    .attributeModifier(Api26Material.panel())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
