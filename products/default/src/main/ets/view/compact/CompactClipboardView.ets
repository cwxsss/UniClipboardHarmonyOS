import { LengthMetrics, mediaquery, SymbolGlyphModifier, window } from '@kit.ArkUI';
import {
  common,
  ConfigurationConstant
} from '@kit.AbilityKit';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { filePreview } from '@kit.PreviewKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import {
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsTabs,
  IconType,
  IconStyleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import {
  ClipboardHistoryItem,
  ServerHistoryItem,
  APPEARANCE_MODE_DARK,
  APPEARANCE_MODE_LIGHT,
  APPEARANCE_MODE_SYSTEM,
  APPEARANCE_THEME_DEFAULT,
  EngineRuntimeDevice,
  NativeMobileSyncDevice
} from 'common';

import {
  APPEARANCE_THEME_OPTIONS,
  AppearanceThemeOption,
  ClipboardFeatureController,
  ImageSmartAction,
  FEEDBACK_EMAIL
} from 'clipboard_feature';
import { ConnectionDiagnosticsSheet } from '../../components/ConnectionDiagnosticsSheet';
import { LinkPreviewCard } from '../../components/LinkPreviewCard';
import { AppearanceVisualSettingsPanel } from '../../components/AppearanceVisualSettingsPanel';
import { OpticalTransferPanel } from '../../components/OpticalTransferPanel';

import { Api26Material } from '../../components/Api26Material';
import { HdrImage } from '../../components/HdrImage';
@Component
export struct CompactClipboardView {
  @State controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();
  @StorageLink('historyRevision') historyRenderRevision: number = 0;
  @StorageLink('desktopDeviceSyncRevision') desktopDeviceSyncRenderRevision: number = 0;
  @StorageLink('desktopDeviceSendEnabled') desktopDeviceSendEnabled: boolean = true;
  @StorageLink('desktopDeviceSyncText') desktopDeviceSyncText: boolean = true;
  @StorageLink('desktopDeviceSyncImage') desktopDeviceSyncImage: boolean = true;
  @StorageLink('desktopDeviceSyncFile') desktopDeviceSyncFile: boolean = true;
  @StorageLink('desktopDeviceSyncLink') desktopDeviceSyncLink: boolean = true;
  @StorageLink('desktopDeviceSyncRichText') desktopDeviceSyncRichText: boolean = true;
  @StorageLink('desktopDeviceReceiveEnabled') desktopDeviceReceiveEnabled: boolean = true;
  @StorageLink('desktopDeviceReceiveText') desktopDeviceReceiveText: boolean = true;
  @StorageLink('desktopDeviceReceiveImage') desktopDeviceReceiveImage: boolean = true;
  @StorageLink('desktopDeviceReceiveFile') desktopDeviceReceiveFile: boolean = true;
  @StorageLink('desktopDeviceReceiveLink') desktopDeviceReceiveLink: boolean = true;
  @StorageLink('desktopDeviceReceiveRichText') desktopDeviceReceiveRichText: boolean = true;
  @State showAboutSheet: boolean = false;
  @State showFeedbackSheet: boolean = false;
  @State showConnectionDiagnosticsSheet: boolean = false;
  @State showHistoryTagSheet: boolean = false;
  @State showOpticalTransferSheet: boolean = false;
  @State historyTagItemId: string = '';
  @State historyTagDraft: string = '';
  @State connectionDetailVisible: boolean = false;
  @State connectionDetailKind: number = 0;
  @StorageLink('appearanceBackgroundImage') appearanceBackgroundImage: string = '';
  @StorageLink('appearanceBackgroundOpacity') appearanceBackgroundOpacity: number = 0.4;
  @StorageLink('appearanceBackgroundBlur') appearanceBackgroundBlur: number = 8;
  @StorageLink('appearanceComponentMaterialStyle') appearanceComponentMaterialStyle: number = 2;
  @Prop avoidAreaRectHeight: number = 0;
  @Prop navigationRectHeight: number = 0;

  private openFeedback(): void {
    if (this.showFeedbackSheet) {
      return;
    }
    this.showFeedbackSheet = true;
  }

  private openAbout(): void {
    if (this.showAboutSheet) {
      return;
    }
    this.showAboutSheet = true;
  }

  private openConnectionDiagnostics(): void {
    if (this.showConnectionDiagnosticsSheet) {
      return;
    }
    this.showConnectionDiagnosticsSheet = true;
    this.controller.refreshConnectionDiagnostics();
  }

  @Builder
  private opticalTransferSheet() {
    OpticalTransferPanel({
      onClose: (): void => {
        this.showOpticalTransferSheet = false;
      }
    })
  }

  private connectionDetailGeometryId(): string {
    return this.connectionDetailKind === 1 ? 'uniclipboard-space-connection-card' :
      'uniclipboard-more-connections-card';
  }

  private openConnectionDetail(kind: number): void {
    if (this.connectionDetailVisible) {
      return;
    }
    this.connectionDetailKind = kind;
    this.getUIContext().animateTo({
      duration: 420,
      curve: Curve.Friction
    }, (): void => {
      this.connectionDetailVisible = true;
    });
  }

  private closeConnectionDetail(): void {
    if (!this.connectionDetailVisible) {
      return;
    }
    this.getUIContext().animateTo({
      duration: 420,
      curve: Curve.Friction
    }, (): void => {
      this.connectionDetailVisible = false;
    });
  }

  private titleBarConnectionIcon(connected: boolean): IconType {
    if (connected) {
      return $r('sys.symbol.connection');
    }
    let modifier: SymbolGlyphModifier =
      new SymbolGlyphModifier($r('sys.symbol.unconnection'));
    modifier.fontColor([$r('app.color.danger')]);
    return modifier;
  }

  private openFeedbackFromAbout(): void {
    this.showAboutSheet = false;
    setTimeout((): void => {
      this.showFeedbackSheet = true;
    }, 220);
  }

  private async submitFeedback(): Promise<void> {
    let shouldClose: boolean = await this.controller.submitFeedback();
    if (shouldClose) {
      this.showFeedbackSheet = false;
    }
  }

  @Builder
  private connectionDiagnosticsSheet() {
    ConnectionDiagnosticsSheet({
      visible: this.showConnectionDiagnosticsSheet
    })
  }

  private openHistoryTagEditor(item: ClipboardHistoryItem): void {
    this.historyTagItemId = item.id;
    this.historyTagDraft = this.controller.historyTagsText(item);
    this.showHistoryTagSheet = true;
  }

  @Builder
  private historyTagEditorSheet() {
    Column({ space: 14 }) {
      Text($r('app.string.history_tag_edit_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text($r('app.string.history_tag_edit_note'))
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: $r('app.string.history_tag_placeholder'), text: this.historyTagDraft })
        .height(48)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.historyTagDraft = value;
        })
      Row({ space: 10 }) {
        Button($r('app.string.cancel_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(44)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.showHistoryTagSheet = false;
          })
        Button($r('app.string.history_tag_save_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(44)
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.setHistoryTags(this.historyTagItemId, this.historyTagDraft);
            this.showHistoryTagSheet = false;
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
  }

  @Builder
  private spaceJoinCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.connection'))
          .fontSize(24)
          .fontColor([this.controller.accentColor()])
        Column({ space: 3 }) {
          Text(!this.controller.spaceJoined && this.controller.spaceActionMode === 0 ? $r('app.string.space_create_title') :
            $r('app.string.space_join_title'))
            .fontSize($r('app.float.font_subtitle_large'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.controller.spaceJoined ?
            (this.controller.spacePeerConnected ? $r('app.string.space_peer_online') :
              $r('app.string.space_peer_waiting')) :
            (this.controller.spaceActionMode === 0 ? $r('app.string.space_create_note') :
              $r('app.string.space_join_note')))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      if (this.controller.spaceNodeState === 1) {
        Text($r('app.string.space_node_starting'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else if (this.controller.spaceNodeState === 3) {
        Text($r('app.string.space_node_failed'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.danger'))
          .width('100%')
        Button($r('app.string.space_node_retry'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.initializeSpaceNode();
          })
      } else if (this.controller.spaceJoined) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.controller.spacePeerConnected ? $r('app.color.success') :
                $r('app.color.text_secondary'))
            Text(this.controller.spaceDeviceName.length > 0 ? this.controller.spaceDeviceName : $r('app.string.space_joined_device'))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          Text(this.controller.spacePeerConnected ? $r('app.string.space_peer_online') :
            $r('app.string.space_peer_waiting'))
            .fontSize(12)
            .fontColor(this.controller.spacePeerConnected ? $r('app.color.success') :
              $r('app.color.text_secondary'))
            .width('100%')
          if (this.controller.spaceCreatedId.length > 0) {
            Text($r('app.string.desktop_space_id'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Text(this.controller.spaceCreatedId)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))
        .attributeModifier(Api26Material.subtle())
        if (this.controller.spaceJoinState === 1 && !this.controller.spaceSwitchOpen) {
          Text($r('app.string.space_switch_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        }
        Button(this.controller.mobileInvitationOpen ? $r('app.string.space_mobile_invite_collapse') :
          $r('app.string.space_mobile_invite_open'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor(this.controller.mobileInvitationOpen ? $r('app.color.text_primary') :
            $r('app.color.on_accent'))
          .backgroundColor(this.controller.mobileInvitationOpen ? $r('app.color.surface_muted') :
            this.controller.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.controller.spaceInvitationBusy)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.mobileInvitationOpen = !this.controller.mobileInvitationOpen;
          })
        if (this.controller.mobileInvitationOpen) {
          Text($r('app.string.space_mobile_invite_note'))
            .fontSize($r('app.float.font_body_small'))
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          this.spaceInvitationCard()
        }
        Button(this.controller.spaceSwitchOpen ? $r('app.string.space_switch_cancel') :
          $r('app.string.space_switch_open'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.controller.spaceJoinBusy)
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.getUIContext().animateTo({
              duration: 380,
              curve: Curve.EaseOut
            }, (): void => {
              this.controller.spaceSwitchOpen = !this.controller.spaceSwitchOpen;
              this.controller.spaceInvitationCode = '';
              this.controller.spacePassphrase = '';
              this.controller.spaceJoinState = 0;
              this.controller.spaceInvitationScanState = 0;
            });
          })
        if (this.controller.spaceSwitchOpen) {
          Column({ space: 10 }) {
            Row({ space: 4 }) {
              this.spaceModeButton(0, $r('app.string.space_create_new_mode'))
              this.spaceModeButton(1, $r('app.string.space_join_other_mode'))
            }
            .width('100%')
            .padding(3)
            .borderRadius($r('app.float.corner_radius_level10'))
            .backgroundColor($r('app.color.surface_muted'))
            .attributeModifier(Api26Material.subtle())
            if (this.controller.spaceActionMode === 0) {
              this.desktopCreateSpaceForm()
            } else {
              this.desktopJoinSpaceForm()
            }
          }
          .transition({ type: TransitionType.Insert, opacity: 0, translate: { y: 24 } })
          .transition({ type: TransitionType.Delete, opacity: 0, translate: { y: -16 } })
        }
      } else if (this.controller.spaceNodeState === 2) {
        Row({ space: 4 }) {
          this.spaceModeButton(0, $r('app.string.space_create_mode'))
          this.spaceModeButton(1, $r('app.string.space_join_mode'))
        }
        .width('100%')
        .padding(3)
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))
        .attributeModifier(Api26Material.subtle())
        if (this.controller.spaceActionMode === 0) {
          Text($r('app.string.space_create_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({
            placeholder: $r('app.string.space_create_device_placeholder'),
            text: this.controller.spaceCreateDeviceName
          })
            .height(50)
            .fontSize($r('app.float.font_body_large'))
            .fontColor(this.controller.spaceCreateDeviceNameRecommended ? $r('app.color.text_secondary') :
              $r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .onFocus((): void => {
              this.controller.spaceCreateDeviceNameRecommended = false;
            })
            .attributeModifier(Api26Material.input())
            .onChange((value: string): void => {
              this.controller.spaceCreateDeviceName = value;
              this.controller.spaceCreateDeviceNameRecommended = false;
              this.controller.spaceCreateState = 0;
            })
          TextInput({
            placeholder: $r('app.string.space_passphrase_placeholder'),
            text: this.controller.spaceCreatePassphrase
          })
            .type(InputType.Password)
            .height(50)
            .fontSize($r('app.float.font_body_large'))
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .attributeModifier(Api26Material.input())
            .onChange((value: string): void => {
              this.controller.spaceCreatePassphrase = value;
              this.controller.spaceCreateState = 0;
            })
          TextInput({
            placeholder: $r('app.string.space_create_confirm_placeholder'),
            text: this.controller.spaceCreatePassphraseConfirm
          })
            .type(InputType.Password)
            .height(50)
            .fontSize($r('app.float.font_body_large'))
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .attributeModifier(Api26Material.input())
            .onChange((value: string): void => {
              this.controller.spaceCreatePassphraseConfirm = value;
              this.controller.spaceCreateState = 0;
            })
          Text($r('app.string.space_create_requirement'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          if (this.controller.spaceCreateState === 2) {
            Text($r('app.string.space_create_failed'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }
          Button(this.controller.spaceCreateBusy ? $r('app.string.space_creating_action') :
            $r('app.string.space_create_action'), { type: ButtonType.Normal })
            .height(50)
            .width('100%')
            .fontSize($r('app.float.font_body_large'))
            .fontColor(Api26Material.accentTextColor())
            .backgroundColor(this.controller.accentColor())
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(this.controller.canCreateSpace())
            .attributeModifier(Api26Material.accent())
            .onClick((): void => {
              this.controller.createCurrentSpace();
            })
        } else {
          Button($r('app.string.space_scan_invitation'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.scanSpaceInvitation();
          })
        if (this.controller.spaceInvitationScanState === 1) {
          Text($r('app.string.space_scan_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        } else if (this.controller.spaceInvitationScanState === 2) {
          Text($r('app.string.space_scan_invalid'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        Text($r('app.string.space_manual_link_note'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({
          placeholder: $r('app.string.space_create_device_placeholder'),
          text: this.controller.spaceJoinDeviceName
        })
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.spaceJoinDeviceName = value;
            this.controller.spaceJoinState = 0;
          })
        TextInput({
          placeholder: $r('app.string.space_code_placeholder'),
          text: this.controller.spaceInvitationCode
        })
          .height(50)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.spaceInvitationCode = value.toUpperCase();
            this.controller.spaceJoinState = 0;
          })
        TextInput({
          placeholder: $r('app.string.space_passphrase_placeholder'),
          text: this.controller.spacePassphrase
        })
          .type(InputType.Password)
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.spacePassphrase = value;
            this.controller.spaceJoinState = 0;
          })
        if (this.controller.spaceJoinState === 1) {
          Text($r('app.string.space_join_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        } else if (this.controller.spaceJoinState === 2) {
          Text($r('app.string.space_join_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
          Button(this.controller.spaceJoinBusy ? $r('app.string.space_joining_action') :
            $r('app.string.space_join_action'), { type: ButtonType.Normal })
            .height(50)
            .width('100%')
            .fontSize($r('app.float.font_body_large'))
            .fontColor(Api26Material.accentTextColor())
            .backgroundColor(this.controller.accentColor())
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(this.controller.canJoinSpace())
            .attributeModifier(Api26Material.accent())
            .onClick((): void => {
              this.controller.joinCurrentSpace();
            })
        }
      }
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }


  @Builder
  private historyServerSendToMenu(item: ServerHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_all_action')
      }).onClick((): void => {
          this.controller.sendServerHistoryItemToTarget(item, 'all');
      })
      ForEach(this.controller.spaceDevices, (device: EngineRuntimeDevice) => {
        MenuItem({
          content: device.deviceName
        }).enabled(device.online).onClick((): void => {
            this.controller.sendServerHistoryItemToTarget(item, device.deviceName);
        })
      }, (device: EngineRuntimeDevice): string => 'space-' + device.deviceId)
      ForEach(this.controller.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
        MenuItem({
          content: device.label
        }).enabled(device.online).onClick((): void => {
            this.controller.sendServerHistoryItemToTarget(item, device.label);
        })
      }, (device: NativeMobileSyncDevice): string => 'mobile-' + device.deviceId)
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }


  @Builder
  private historyLocalSendToMenu(item: ClipboardHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_all_action')
      }).onClick((): void => {
          this.controller.sendLocalHistoryItemToTarget(item, 'all');
      })
      ForEach(this.controller.spaceDevices, (device: EngineRuntimeDevice) => {
        MenuItem({
          content: device.deviceName
        }).enabled(device.online).onClick((): void => {
            this.controller.sendLocalHistoryItemToTarget(item, device.deviceName);
        })
      }, (device: EngineRuntimeDevice): string => 'space-' + device.deviceId)
      ForEach(this.controller.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
        MenuItem({
          content: device.label
        }).enabled(device.online).onClick((): void => {
            this.controller.sendLocalHistoryItemToTarget(item, device.label);
        })
      }, (device: NativeMobileSyncDevice): string => 'mobile-' + device.deviceId)
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }


  @Builder
  private historyServerContextMenu(item: ServerHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.clipboard_sharing')),
        content: $r('app.string.copy_action')
      }).onClick((): void => {
          this.controller.copyServerHistoryItem(item);
      })
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.star')),
        content: item.starred ? $r('app.string.history_unstar_action') : $r('app.string.history_star_action')
      }).onClick((): void => {
          this.controller.toggleHistoryStarred(item);
      })
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_action'),
        symbolEndIcon: this.controller.historyMenuSymbol($r('sys.symbol.chevron_forward')),
        builder: (): void => this.historyServerSendToMenu(item)
      })
      MenuItem({
        symbolStartIcon: this.controller.historyDeleteMenuSymbol(),
        content: $r('app.string.history_delete_action')
      }).onClick((): void => {
          this.controller.confirmDeleteHistory(item);
      })
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }


  @Builder
  private historyLocalContextMenu(item: ClipboardHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.clipboard_sharing')),
        content: $r('app.string.copy_action')
      }).onClick((): void => {
          this.controller.copyLocalHistoryItem(item);
      })
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.star')),
        content: item.starred ? $r('app.string.history_unstar_action') : $r('app.string.history_star_action')
      }).onClick((): void => {
          this.controller.toggleLocalHistoryStarred(item);
      })
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.bookmark')),
        content: item.isSnippet ? $r('app.string.history_remove_snippet_action') :
          $r('app.string.history_add_snippet_action')
      }).onClick((): void => {
          this.controller.toggleHistorySnippet(item);
      })
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.label')),
        content: $r('app.string.history_tag_edit_action')
      }).onClick((): void => {
          this.openHistoryTagEditor(item);
      })
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.checkmark_circle')),
        content: $r('app.string.history_select_action')
      }).onClick((): void => {
          if (!this.controller.historySelectionMode) {
            this.controller.toggleHistorySelectionMode();
          }
          this.controller.toggleHistorySelection(item.id);
      })
      MenuItem({
        symbolStartIcon: this.controller.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_action'),
        symbolEndIcon: this.controller.historyMenuSymbol($r('sys.symbol.chevron_forward')),
        builder: (): void => this.historyLocalSendToMenu(item)
      })
      MenuItem({
        symbolStartIcon: this.controller.historyDeleteMenuSymbol(),
        content: $r('app.string.history_delete_action')
      }).onClick((): void => {
          this.controller.confirmDeleteLocalHistory(item);
      })
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }


  @Builder
  private imageIntelligencePanel() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text($r('app.string.image_intelligence_title'))
          .fontSize($r('app.float.font_subtitle_large'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button(this.controller.currentImageRecognitionState() === 1 ?
          $r('app.string.image_intelligence_running') : $r('app.string.image_intelligence_action'),
        { type: ButtonType.Normal })
          .height(36)
          .fontSize(13)
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.controller.currentImageRecognitionState() !== 1)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.recognizeCurrentImage();
          })
      }
      .width('100%')
      if (this.controller.currentImageRecognitionState() === 2) {
        if (this.controller.currentImageRecognizedText().length > 0) {
          Row({ space: 8 }) {
            Text($r('app.string.image_intelligence_text_title'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            Button($r('app.string.copy_action'), { type: ButtonType.Normal })
              .height(32)
              .fontSize(12)
              .fontColor(this.controller.accentColor())
              .backgroundColor($r('app.color.surface'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .attributeModifier(Api26Material.accent())
              .onClick((): void => {
                this.controller.copyImageRecognizedText();
              })
          }
          .width('100%')
          Text(this.controller.currentImageRecognizedText())
            .fontSize($r('app.float.font_body_medium'))
            .lineHeight(21)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding(12)
            .borderRadius($r('app.float.corner_radius_level4'))
            .backgroundColor($r('app.color.surface'))
            .attributeModifier(Api26Material.panel())
        }
        if (this.controller.currentImageSmartActions().length > 0) {
          Text($r('app.string.image_intelligence_actions_title'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          ForEach(this.controller.currentImageSmartActions(), (action: ImageSmartAction) => {
            Row({ space: 8 }) {
              Text(action.kind === 'link' ? $r('app.string.image_intelligence_link') :
                (action.kind === 'phone' ? $r('app.string.image_intelligence_phone') :
                  $r('app.string.image_intelligence_qr')))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.controller.accentColor())
              Text(action.value)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Button($r('app.string.copy_action'), { type: ButtonType.Normal })
                .height(32)
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.surface'))
                .borderRadius($r('app.float.corner_radius_level10'))
                .attributeModifier(Api26Material.interactive())
                .onClick((): void => {
                  this.controller.copyImageSmartAction(action);
                })
              if (this.controller.imageSmartActionCanOpen(action)) {
                Button(action.kind === 'phone' ? $r('app.string.image_intelligence_dial') :
                  $r('app.string.image_intelligence_open'), { type: ButtonType.Normal })
                  .height(32)
                  .fontSize(12)
                  .fontColor(Api26Material.accentTextColor())
                  .backgroundColor(this.controller.accentColor())
                  .borderRadius($r('app.float.corner_radius_level10'))
                  .attributeModifier(Api26Material.accent())
                  .onClick((): void => {
                    this.controller.openImageSmartAction(action);
                  })
              }
            }
            .width('100%')
            .padding(10)
            .borderRadius($r('app.float.corner_radius_level4'))
            .backgroundColor($r('app.color.surface_muted'))
            .attributeModifier(Api26Material.subtle())
          }, (action: ImageSmartAction): string => action.kind + ':' + action.value)
        }
      } else if (this.controller.currentImageRecognitionState() === 3) {
        Text($r('app.string.image_intelligence_empty'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else if (this.controller.currentImageRecognitionState() === 4) {
        Text($r('app.string.image_intelligence_failed'))
          .fontSize(13)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface_muted'))
    .attributeModifier(Api26Material.subtle())
  }


  @Builder
  private mobileLatestContent() {
    if (this.controller.desktopHasGestureShareContent() && !this.controller.desktopGestureShareHintDismissed) {
      this.desktopGestureShareHint()
    }
    if (this.controller.latestKind === 'Image' && this.controller.latestImage !== null) {
      if (this.controller.latestImageRevision % 2 === 0) {
        Image(this.controller.latestImage)
          .id('latest-image-even')
          .width('100%')
          .aspectRatio(this.controller.latestImageAspectRatio())
          .constraintSize({ maxHeight: 380 })
          .objectFit(ImageFit.Contain)
          .attributeModifier(HdrImage.touchContent(this.controller.latestImage))
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor($r('app.color.surface_muted'))
          .attributeModifier(Api26Material.subtle())
      } else {
        Image(this.controller.latestImage)
          .id('latest-image-odd')
          .width('100%')
          .aspectRatio(this.controller.latestImageAspectRatio())
          .constraintSize({ maxHeight: 380 })
          .objectFit(ImageFit.Contain)
          .attributeModifier(HdrImage.touchContent(this.controller.latestImage))
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor($r('app.color.surface_muted'))
          .attributeModifier(Api26Material.subtle())
      }
      Text(this.controller.latestText)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      this.imageIntelligencePanel()
    } else if (this.controller.latestKind === 'File' && this.controller.desktopShowsFile()) {
      if (this.controller.desktopFileIsVideo() && this.controller.desktopFilePreviewUri().length > 0) {
        Video({ src: this.controller.desktopFilePreviewUri() })
          .id('mobile-latest-video-' + this.controller.desktopFilePreviewKey())
          .width('100%')
          .aspectRatio(this.controller.desktopVideoAspectRatio)
          .constraintSize({ maxHeight: 380 })
          .controls(true)
          .autoPlay(true)
          .objectFit(ImageFit.Contain)
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor(Color.Black)
          .onPrepared((_preparedInfo: PreparedInfo): void => {
            this.controller.loadDesktopVideoAspectRatio();
          })
          .onError((): void => {
            this.controller.desktopFilePreviewState = 2;
          })
      } else if (this.controller.desktopFileIsAudio()) {
        this.desktopAudioPreview()
      } else {
        Column({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(50)
            .fontColor([this.controller.accentColor()])
          Text(this.controller.desktopFileIsDocument() ? $r('app.string.file_preview_document') :
            $r('app.string.file_preview_generic'))
            .fontSize($r('app.float.font_subtitle_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.file_preview_system_note'))
            .fontSize($r('app.float.font_body_medium'))
            .lineHeight(20)
            .textAlign(TextAlign.Center)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(3)
        }
        .width('100%')
        .height(210)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 22, right: 22 })
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface_muted'))
        .attributeModifier(Api26Material.subtle())
      }
      Text(this.controller.desktopFileName())
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 10 }) {
        Button(this.controller.desktopFilePreviewState === 1 ? $r('app.string.file_preview_opening') :
          $r('app.string.file_preview_action'), { type: ButtonType.Normal })
          .height(40)
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.controller.desktopFilePreviewUri().length > 0 && this.controller.desktopFilePreviewState !== 1)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.openDesktopFilePreview();
          })
        if (this.controller.desktopFilePreviewState === 2) {
          Text($r('app.string.file_preview_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .maxLines(2)
        }
      }
      .width('100%')
    } else if (this.controller.currentTextLooksLikeLink()) {
      LinkPreviewCard()
    } else {
      Text(this.controller.latestText.length > 0 ? this.controller.latestText : $r('app.string.latest_empty'))
        .fontSize(16)
        .fontColor(this.controller.latestText.length > 0 ? $r('app.color.text_primary') :
          $r('app.color.text_secondary'))
        .lineHeight(24)
        .maxLines(7)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding(16)
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface_muted'))
        .attributeModifier(Api26Material.subtle())
    }
  }


  @Builder
  private syncPage() {
    Scroll(this.controller.syncScroller) {
      Column({ space: 12 }) {
        Column({ space: 16 }) {
          Row({ space: 8 }) {
            Text($r('app.string.latest_title'))
              .fontSize($r('app.float.font_title_small'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(this.controller.history.length.toString())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.controller.accentColor())
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius($r('app.float.corner_radius_level2'))
              .backgroundColor(this.controller.accentSoftColor())
              .attributeModifier(Api26Material.accentSurface())
            Blank()
          }
          this.mobileLatestContent()
          Row({ space: 10 }) {
            Button(!this.controller.hasConfig() && this.controller.spaceJoined ? $r('app.string.space_refresh_sync_action') :
              $r('app.string.pull_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor(Api26Material.accentTextColor())
              .backgroundColor(this.controller.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.busy)
              .attributeModifier(Api26Material.accent())
              .onClick(() => {
                this.controller.pullLatest();
              })
            Button(this.controller.latestKind === 'File' ? $r('app.string.save_file_action') :
              $r('app.string.copy_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(this.controller.latestCopyable())
              .attributeModifier(Api26Material.interactive())
              .onClick(() => {
                this.controller.copyLatest();
              })
          }
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.qrcode'))
                .fontSize(20)
                .fontColor([this.controller.accentColor()])
              Text($r('app.string.optical_transfer_action'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.controller.accentColor())
            }
          }
            .width('100%')
            .height(42)
            .backgroundColor(this.controller.accentSoftColor())
            .borderRadius($r('app.float.corner_radius_level10'))
            .attributeModifier(Api26Material.accent())
            .onClick((): void => {
              this.showOpticalTransferSheet = true;
            })
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .attributeModifier(Api26Material.panel())
        .scale({ x: this.controller.latestContentPulse, y: this.controller.latestContentPulse })

        Column({ space: 12 }) {
          Text($r('app.string.composer_title'))
            .fontSize($r('app.float.font_title_small'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          TextArea({ placeholder: $r('app.string.composer_placeholder'), text: this.controller.composerText })
            .height(124)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level8'))
            .padding(14)
            .attributeModifier(Api26Material.input())
            .onChange((value: string) => {
              this.controller.composerText = value;
            })
          Row({ space: 10 }) {
            PasteButton({
              icon: PasteIconStyle.LINES,
              text: PasteDescription.PASTE,
              buttonType: ButtonType.Normal
            })
              .width('48%')
              .height(46)
              .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .iconColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.paste_button_background'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
                if (result === PasteButtonOnClickResult.SUCCESS) {
                  this.controller.readLocalClipboard();
                } else {
                  this.controller.statusCode = 3;
                }
              })
            Button($r('app.string.send_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor(Api26Material.accentTextColor())
              .backgroundColor(this.controller.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.busy && this.controller.composerText.trim().length > 0)
              .attributeModifier(Api26Material.accent())
              .onClick(() => {
                this.controller.sendText();
              })
          }
          Divider()
            .color($r('app.color.divider'))
            .margin({ top: 6, bottom: 2 })
          Text($r('app.string.image_composer_title'))
            .fontSize($r('app.float.font_title_small'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          if (this.controller.composerImage !== null) {
            if (this.controller.composerImageRevision % 2 === 0) {
              Image(this.controller.composerImage)
                .id('composer-image-even')
                .width('100%')
                .height(220)
                .objectFit(ImageFit.Contain)
                .attributeModifier(HdrImage.touchContent(this.controller.composerImage))
                .borderRadius($r('app.float.corner_radius_level4'))
                .backgroundColor($r('app.color.surface_muted'))
                .attributeModifier(Api26Material.subtle())
            } else {
              Image(this.controller.composerImage)
                .id('composer-image-odd')
                .width('100%')
                .height(220)
                .objectFit(ImageFit.Contain)
                .attributeModifier(HdrImage.touchContent(this.controller.composerImage))
                .borderRadius($r('app.float.corner_radius_level4'))
                .backgroundColor($r('app.color.surface_muted'))
                .attributeModifier(Api26Material.subtle())
            }
          } else {
            Text($r('app.string.image_empty'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(22)
              .width('100%')
              .padding(14)
              .borderRadius($r('app.float.corner_radius_level8'))
              .backgroundColor($r('app.color.surface_muted'))
              .attributeModifier(Api26Material.subtle())
          }
          Row({ space: 10 }) {
            PasteButton({
              icon: PasteIconStyle.LINES,
              text: PasteDescription.PASTE,
              buttonType: ButtonType.Normal
            })
              .width('48%')
              .height(46)
              .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .iconColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.paste_button_background'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.busy && this.controller.imageReadState !== 1)
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
                if (result === PasteButtonOnClickResult.SUCCESS) {
                  pasteboard.getSystemPasteboard().getData((error: BusinessError, data: pasteboard.PasteData): void => {
                    if (error) {
                      this.controller.imageReadState = 4;
                      this.controller.statusCode = 3;
                      return;
                    }
                    this.controller.readLocalImageFromPasteData(data);
                  });
                } else {
                  this.controller.imageReadState = 4;
                  this.controller.statusCode = 3;
                }
              })
            Button(this.controller.imageSendState === 1 ? $r('app.string.image_sending') :
              $r('app.string.send_image_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor(Api26Material.accentTextColor())
              .backgroundColor(this.controller.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.busy && this.controller.composerImage !== null)
              .attributeModifier(Api26Material.accent())
              .onClick(() => {
                this.controller.sendImage();
              })
          }
          if (this.controller.imageSendState === 1) {
            Text($r('app.string.image_sending'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.controller.imageSendState === 2) {
            Text($r('app.string.image_send_success'))
              .fontSize(12)
              .fontColor($r('app.color.success'))
              .width('100%')
          } else if (this.controller.imageSendState === 3) {
            Text($r('app.string.image_send_failed'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          } else if (this.controller.imageReadState === 2) {
            Text($r('app.string.image_read_success'))
              .fontSize(12)
              .fontColor($r('app.color.success'))
              .width('100%')
          } else if (this.controller.imageReadState === 3) {
            Text($r('app.string.image_read_empty'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.controller.imageReadState === 4) {
            Text($r('app.string.clipboard_permission_denied'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          } else if (this.controller.imageReadState === 5) {
            Text($r('app.string.image_read_failed'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }
          Divider()
            .color($r('app.color.divider'))
            .margin({ top: 6, bottom: 2 })
          this.compactFileComposer()
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .attributeModifier(Api26Material.panel())

        Column({ space: 10 }) {
          Row() {
            Text($r('app.string.server_history_title'))
              .fontSize($r('app.float.font_title_small'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Button($r('app.string.server_history_refresh'), { type: ButtonType.Normal })
              .height(34)
              .fontSize($r('app.float.font_body_medium'))
              .fontColor(this.controller.accentColor())
              .backgroundColor(this.controller.accentSoftColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.historyLoading)
              .attributeModifier(Api26Material.accent())
              .onClick(() => {
                this.controller.loadServerHistory(true);
              })
          }
          .width('100%')
          TextInput({ placeholder: $r('app.string.server_history_search_placeholder'),
            text: this.controller.historySearchText })
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .attributeModifier(Api26Material.input())
            .onChange((value: string) => {
              this.controller.historySearchText = value;
            })
          Row({ space: 8 }) {
            Button($r('app.string.server_history_search_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(38)
              .fontSize($r('app.float.font_body_medium'))
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.historyLoading)
              .attributeModifier(Api26Material.interactive())
              .onClick(() => {
                this.controller.loadServerHistory(true);
              })
            Button(this.controller.historyStarredOnly ? $r('app.string.server_history_all_action') :
              $r('app.string.server_history_starred_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(38)
              .fontSize($r('app.float.font_body_medium'))
              .fontColor(this.controller.historyStarredOnly ? this.controller.accentColor() : $r('app.color.text_primary'))
              .backgroundColor(this.controller.historyStarredOnly ? this.controller.accentSoftColor() :
                $r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.historyLoading)
              .attributeModifier(Api26Material.accent())
              .onClick(() => {
                this.controller.historyStarredOnly = !this.controller.historyStarredOnly;
                this.controller.loadServerHistory(true);
              })
          }
          .width('100%')
          if (this.controller.serverHistory.length === 0) {
            Text($r('app.string.server_history_empty'))
              .fontSize(14)
              .lineHeight(21)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.controller.serverHistory, (item: ServerHistoryItem) => {
              Column({ space: 5 }) {
                Text(item.text)
                  .fontSize($r('app.float.font_body_large'))
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Row({ space: 8 }) {
                  Text(item.time)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  if (item.pinned) {
                    Text($r('app.string.server_history_pinned'))
                      .fontSize(12)
                      .fontColor(this.controller.accentColor())
                  }
                  if (item.starred) {
                    Text('★')
                      .fontSize(12)
                      .fontColor(this.controller.accentColor())
                  }
                }
                Row({ space: 8 }) {
                  Button(item.starred ? $r('app.string.history_unstar_action') :
                    $r('app.string.history_star_action'), { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(12)
                    .fontColor(item.starred ? this.controller.accentColor() : $r('app.color.text_primary'))
                    .backgroundColor($r('app.color.surface_muted'))
                    .borderRadius($r('app.float.corner_radius_level4'))
                    .enabled(!this.controller.historyMutationBusy)
                    .attributeModifier(Api26Material.accent())
                    .onClick(() => {
                      this.controller.toggleHistoryStarred(item);
                    })
                  Button(item.pinned ? $r('app.string.history_unpin_action') :
                    $r('app.string.history_pin_action'), { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(12)
                    .fontColor(item.pinned ? this.controller.accentColor() : $r('app.color.text_primary'))
                    .backgroundColor($r('app.color.surface_muted'))
                    .borderRadius($r('app.float.corner_radius_level4'))
                    .enabled(!this.controller.historyMutationBusy)
                    .attributeModifier(Api26Material.accent())
                    .onClick(() => {
                      this.controller.toggleHistoryPinned(item);
                    })
                  Button($r('app.string.history_delete_action'), { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(12)
                    .fontColor($r('app.color.danger'))
                    .backgroundColor($r('app.color.surface_muted'))
                    .borderRadius($r('app.float.corner_radius_level4'))
                    .enabled(!this.controller.historyMutationBusy)
                    .attributeModifier(Api26Material.interactive())
                    .onClick(() => {
                      this.controller.confirmDeleteHistory(item);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius($r('app.float.corner_radius_level8'))
              .backgroundColor($r('app.color.surface_muted'))
              .border({ width: 1, color: $r('app.color.divider') })
              .clickEffect({ level: ClickEffectLevel.MIDDLE })
              .bindContextMenu(this.historyServerContextMenu(item), ResponseType.LongPress)
              .attributeModifier(Api26Material.interactive())
            }, (item: ServerHistoryItem) => item.id)
            Button(this.controller.historyEnd ? $r('app.string.server_history_end') :
              $r('app.string.server_history_load_more'), { type: ButtonType.Normal })
              .height(42)
              .width('100%')
              .fontSize($r('app.float.font_body_medium'))
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.controller.historyLoading && !this.controller.historyEnd)
              .attributeModifier(Api26Material.interactive())
              .onClick(() => {
                this.controller.loadServerHistory(false);
              })
          }
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .attributeModifier(Api26Material.panel())

        Column({ space: 10 }) {
          Row() {
            Text($r('app.string.history_title'))
              .fontSize($r('app.float.font_title_small'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Button(this.controller.historySelectionMode ? $r('app.string.cancel_action') :
              $r('app.string.history_select_action'), { type: ButtonType.Normal })
              .height(34)
              .fontSize(12)
              .fontColor(this.controller.accentColor())
              .backgroundColor(this.controller.accentSoftColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .attributeModifier(Api26Material.accent())
              .onClick((): void => {
                this.controller.toggleHistorySelectionMode();
              })
          }
          .width('100%')
          Row({ space: 8 }) {
            Button($r('app.string.desktop_all'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(34)
              .fontSize(12)
              .fontColor(!this.controller.historySnippetOnly ? this.controller.accentColor() :
                $r('app.color.text_primary'))
              .backgroundColor(!this.controller.historySnippetOnly ? this.controller.accentSoftColor() :
                $r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .attributeModifier(Api26Material.accent())
              .onClick((): void => {
                this.controller.clearHistoryLibraryFilters();
              })
            Button($r('app.string.history_snippets_title'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(34)
              .fontSize(12)
              .fontColor(this.controller.historySnippetOnly ? this.controller.accentColor() :
                $r('app.color.text_primary'))
              .backgroundColor(this.controller.historySnippetOnly ? this.controller.accentSoftColor() :
                $r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .attributeModifier(Api26Material.accent())
              .onClick((): void => {
                this.controller.historySnippetOnly = true;
              })
          }
          .width('100%')
          if (this.controller.historyDeviceOptions().length > 0) {
            Text($r('app.string.history_devices_title'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            ForEach(this.controller.historyDeviceOptions(), (deviceName: string) => {
              Button(deviceName, { type: ButtonType.Normal })
                .height(34)
                .width('100%')
                .fontSize(12)
                .fontColor(this.controller.historyDeviceFilter === deviceName ? this.controller.accentColor() :
                  $r('app.color.text_primary'))
                .backgroundColor(this.controller.historyDeviceFilter === deviceName ?
                  this.controller.accentSoftColor() : $r('app.color.surface_muted'))
                .borderRadius($r('app.float.corner_radius_level10'))
                .attributeModifier(Api26Material.accent())
                .onClick((): void => {
                  this.controller.applyHistoryDeviceFilter(deviceName);
                })
            }, (deviceName: string): string => deviceName)
          }
          if (this.controller.historyTagOptions().length > 0) {
            Text($r('app.string.history_custom_tags_title'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            ForEach(this.controller.historyTagOptions(), (tag: string) => {
              Button(tag, { type: ButtonType.Normal })
                .height(34)
                .width('100%')
                .fontSize(12)
                .fontColor(this.controller.desktopCustomTagFilter === tag ? this.controller.accentColor() :
                  $r('app.color.text_primary'))
                .backgroundColor(this.controller.desktopCustomTagFilter === tag ?
                  this.controller.accentSoftColor() : $r('app.color.surface_muted'))
                .borderRadius($r('app.float.corner_radius_level10'))
                .attributeModifier(Api26Material.accent())
                .onClick((): void => {
                  this.controller.applyHistoryTagFilter(tag);
                })
            }, (tag: string): string => tag)
          }
          if (this.controller.historySelectionMode) {
            Row({ space: 8 }) {
              Button($r('app.string.history_select_all_action'), { type: ButtonType.Normal })
                .layoutWeight(1)
                .height(34)
                .fontSize(11)
                .fontColor(this.controller.accentColor())
                .backgroundColor(this.controller.accentSoftColor())
                .borderRadius($r('app.float.corner_radius_level10'))
                .attributeModifier(Api26Material.accent())
                .onClick((): void => {
                  this.controller.selectAllFilteredHistory();
                })
              Button($r('app.string.history_batch_star_action'), { type: ButtonType.Normal })
                .layoutWeight(1)
                .height(34)
                .fontSize(11)
                .fontColor(this.controller.accentColor())
                .backgroundColor(this.controller.accentSoftColor())
                .enabled(this.controller.historySelectedIds.length > 0)
                .borderRadius($r('app.float.corner_radius_level10'))
                .attributeModifier(Api26Material.accent())
                .onClick((): void => {
                  this.controller.batchToggleSelectedStarred();
                })
              Button($r('app.string.history_delete_action'), { type: ButtonType.Normal })
                .layoutWeight(1)
                .height(34)
                .fontSize(11)
                .fontColor($r('app.color.danger'))
                .backgroundColor(this.controller.accentSoftColor())
                .enabled(this.controller.historySelectedIds.length > 0)
                .borderRadius($r('app.float.corner_radius_level10'))
                .attributeModifier(Api26Material.interactive())
                .onClick((): void => {
                  this.controller.batchDeleteSelectedHistory();
                })
            }
            .width('100%')
          }
          if (this.historyRenderRevision >= 0 && this.controller.compactFilteredHistory().length === 0) {
            Text($r('app.string.history_empty'))
              .fontSize(14)
              .lineHeight(21)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.controller.compactFilteredHistory(), (item: ClipboardHistoryItem) => {
              Row({ space: 12 }) {
                Column() {
                  SymbolGlyph(this.controller.historySelectionMode ?
                    (this.controller.historyItemSelected(item.id) ? $r('sys.symbol.checkmark_circle_fill') :
                      $r('sys.symbol.circle')) :
                    (item.direction === 'sent' ? $r('sys.symbol.arrowshape_up_to_line_fill') :
                      $r('sys.symbol.arrowshape_down_to_line_fill')))
                    .fontSize(22)
                    .fontWeight(FontWeight.Medium)
                    .fontColor([item.direction === 'sent' ? this.controller.accentColor() :
                      $r('app.color.success')])
                }
                .width(36)
                .height(36)
                .justifyContent(FlexAlign.Center)
                .borderRadius($r('app.float.corner_radius_level10'))
                .backgroundColor($r('app.color.surface_muted'))
                .attributeModifier(Api26Material.subtle())
                Column({ space: 4 }) {
                  Text(item.text)
                    .fontSize($r('app.float.font_body_large'))
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row({ space: 8 }) {
                    Row({ space: 6 }) {
                      if (item.isSnippet) {
                        SymbolGlyph($r('sys.symbol.bookmark_fill'))
                          .fontSize(12)
                          .fontColor([this.controller.accentColor()])
                      }
                      if (item.tags.length > 0) {
                        Text(this.controller.historyTagsText(item))
                          .fontSize(11)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .fontColor($r('app.color.text_secondary'))
                          .layoutWeight(1)
                      }
                      if (item.sourceDevice.length > 0) {
                        Text(item.sourceDevice)
                          .fontSize(11)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .fontColor($r('app.color.text_secondary'))
                          .layoutWeight(1)
                      }
                    }
                    .layoutWeight(1)
                    .clip(true)
                    Row({ space: 8 }) {
                      Text(item.direction === 'sent' ? $r('app.string.direction_sent') :
                        (item.direction === 'received' ? $r('app.string.direction_received') :
                          $r('app.string.direction_history')))
                        .fontSize(12)
                        .fontColor(item.direction === 'sent' ? this.controller.accentColor() :
                          (item.direction === 'received' ? $r('app.color.success') :
                            $r('app.color.text_secondary')))
                      Text(item.time)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                      if (item.occurrenceCount > 1) {
                        Text('×' + item.occurrenceCount.toString())
                          .fontSize(11)
                          .fontColor($r('app.color.text_secondary'))
                      }
                    }
                  }
                  .width('100%')
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius($r('app.float.corner_radius_level8'))
              .backgroundColor($r('app.color.surface_muted'))
              .border({ width: 1, color: $r('app.color.divider') })
              .clickEffect({ level: ClickEffectLevel.MIDDLE })
              .bindContextMenu(this.historyLocalContextMenu(item), ResponseType.LongPress)
              .attributeModifier(Api26Material.interactive())
              .onClick((): void => {
                if (this.controller.historySelectionMode) {
                  this.controller.toggleHistorySelection(item.id);
                } else {
                  this.controller.copyLocalHistoryItem(item);
                }
              })
            }, (item: ClipboardHistoryItem) => item.id)
          }
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .attributeModifier(Api26Material.panel())
        .scale({ x: this.controller.historyPulse, y: this.controller.historyPulse })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 56 + this.avoidAreaRectHeight,
        bottom: 116 + this.navigationRectHeight
      })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }


  @Builder
  private compactAppearanceOption(mode: string, icon: Resource, label: Resource) {
    Column({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.controller.appearanceMode === mode ? this.controller.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize($r('app.float.font_body_medium'))
        .fontWeight(this.controller.appearanceMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.controller.appearanceMode === mode ? this.controller.accentColor() :
          $r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .height(82)
    .justifyContent(FlexAlign.Center)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.controller.appearanceMode === mode ? this.controller.accentSoftColor() :
      $r('app.color.surface_muted'))
    .border({
      width: this.controller.appearanceMode === mode ? 2 : 1,
      color: this.controller.appearanceMode === mode ? this.controller.accentColor() : $r('app.color.divider')
    })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .attributeModifier(Api26Material.navigation(this.controller.appearanceMode === mode))
    .onClick((): void => {
      this.controller.selectAppearanceMode(mode);
    })
  }


  @Builder
  private compactAppearanceThemeOption(option: AppearanceThemeOption) {
    Row({ space: 10 }) {
      Row({ space: 4 }) {
        Blank()
          .width(22)
          .height(14)
          .borderRadius(7)
          .backgroundColor(option.primaryColor)
        Blank()
          .width(22)
          .height(14)
          .borderRadius(7)
          .backgroundColor(option.secondaryColor)
      }
      Text(this.controller.appearanceThemeLabel(option.id))
        .fontSize(13)
        .fontWeight(this.controller.appearanceThemeId === option.id ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.controller.appearanceThemeId === option.id ? this.controller.accentColor() :
          $r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(56)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.controller.appearanceThemeId === option.id ? this.controller.accentSoftColor() :
      $r('app.color.surface_muted'))
    .border({
      width: this.controller.appearanceThemeId === option.id ? 2 : 1,
      color: this.controller.appearanceThemeId === option.id ? this.controller.accentColor() : $r('app.color.divider')
    })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .attributeModifier(Api26Material.navigation(this.controller.appearanceThemeId === option.id))
    .onClick((): void => {
      this.controller.selectAppearanceTheme(option.id);
    })
  }


  @Builder
  private compactAppearanceCard() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.paintpalette'))
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.controller.accentColor()])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius($r('app.float.corner_radius_level4'))
        .backgroundColor(this.controller.accentSoftColor())
        .attributeModifier(Api26Material.accentSurface())
        Column({ space: 4 }) {
          Text($r('app.string.appearance_title'))
            .fontSize($r('app.float.font_subtitle_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.appearance_note'))
            .width('100%')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Row({ space: 8 }) {
        this.compactAppearanceOption(APPEARANCE_MODE_SYSTEM, $r('sys.symbol.circle_fill_half'),
          $r('app.string.appearance_follow_system'))
        this.compactAppearanceOption(APPEARANCE_MODE_LIGHT, $r('sys.symbol.sun_max'),
          $r('app.string.appearance_light'))
        this.compactAppearanceOption(APPEARANCE_MODE_DARK, $r('sys.symbol.moon'),
          $r('app.string.appearance_dark'))
      }
      .width('100%')
      Text($r('app.string.appearance_theme_title'))
        .fontSize($r('app.float.font_body_medium'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[0])
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[1])
        }
        .width('100%')
        Row({ space: 10 }) {
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[2])
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[3])
        }
        .width('100%')
        Row({ space: 10 }) {
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[4])
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[5])
        }
        .width('100%')
      }
      .width('100%')
      Divider()
        .color($r('app.color.divider'))
      AppearanceVisualSettingsPanel({ compact: true })
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }


  @Builder
  private compactDiagnosticsCard() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.connection'))
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.controller.accentColor()])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius($r('app.float.corner_radius_level4'))
        .backgroundColor(this.controller.accentSoftColor())
        .attributeModifier(Api26Material.accentSurface())
        Column({ space: 4 }) {
          Text($r('app.string.connection_diagnostics_title'))
            .fontSize($r('app.float.font_subtitle_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.connection_diagnostics_subtitle'))
            .width('100%')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Button($r('app.string.connection_diagnostics_open_action'), { type: ButtonType.Normal })
        .height(44)
        .width('100%')
        .fontSize($r('app.float.font_body_medium'))
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.openConnectionDiagnostics();
        })
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }


  @Builder
  private backgroundSyncSwitchRow() {
    Row({ space: 16 }) {
      Column({ space: 4 }) {
        Text($r('app.string.background_sync_title'))
          .fontSize($r('app.float.font_body_large'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.background_sync_note'))
          .fontSize($r('app.float.font_body_small'))
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.controller.backgroundSyncEnabled })
        .selectedColor(this.controller.accentColor())
        .onChange((enabled: boolean): void => {
          this.controller.setBackgroundSyncEnabled(enabled).catch((): void => {
          });
        })
    }
    .width('100%')
    .height(78)
  }


  @Builder
  private mobileSyncManagementCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.mobile_sync_server_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.controller.mobileSyncRunning ? $r('app.string.mobile_sync_server_running') :
            $r('app.string.mobile_sync_server_stopped'))
            .fontSize(12)
            .fontColor(this.controller.mobileSyncRunning ? $r('app.color.success') :
              $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.controller.mobileSyncEnabled })
          .selectedColor(this.controller.accentColor())
          .enabled(!this.controller.mobileSyncBusy)
          .onChange((enabled: boolean): void => {
            this.controller.toggleMobileSyncServer(enabled);
          })
      }
      .width('100%')
      Text($r('app.string.mobile_sync_server_note'))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 10 }) {
        Text($r('app.string.mobile_sync_port'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.controller.mobileSyncPort, placeholder: '42720' })
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level8'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.mobileSyncPort = value;
          })
        Button($r('app.string.operation_success'), { type: ButtonType.Normal })
          .height(42)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level8'))
          .enabled(!this.controller.mobileSyncBusy)
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.toggleMobileSyncServer(this.controller.mobileSyncEnabled);
          })
      }
      .width('100%')
      if (this.controller.mobileSyncUrls.length > 0) {
        Text($r('app.string.mobile_sync_addresses'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        ForEach(this.controller.mobileSyncUrls, (url: string) => {
          Text(url)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .padding(10)
            .borderRadius($r('app.float.corner_radius_level4'))
            .backgroundColor($r('app.color.surface_muted'))
            .attributeModifier(Api26Material.subtle())
        }, (url: string): string => url)
      } else {
        Text($r('app.string.mobile_sync_no_address'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      Row() {
        Text($r('app.string.mobile_sync_registered_devices'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button($r('app.string.mobile_sync_add_device'), { type: ButtonType.Normal })
          .height(36)
          .fontSize(12)
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .borderRadius($r('app.float.corner_radius_level8'))
          .enabled(this.controller.mobileSyncRunning && !this.controller.mobileSyncBusy)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.mobileSyncAddOpen = !this.controller.mobileSyncAddOpen;
            this.controller.mobileSyncCredential = null;
            this.controller.mobileSyncDeviceName = '';
            this.controller.mobileSyncCustomUsername = '';
            this.controller.mobileSyncCustomPassword = '';
            this.controller.mobileSyncAdvancedOpen = false;
            this.controller.mobileSyncState = 0;
          })
      }
      .width('100%')
      if (this.controller.mobileSyncDevices.length === 0) {
        Text($r('app.string.mobile_sync_no_devices'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else {
        ForEach(this.controller.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
          Row({ space: 10 }) {
            Stack({ alignContent: Alignment.BottomEnd }) {
              Column() {
                SymbolGlyph($r('sys.symbol.phone'))
                  .fontSize(22)
                  .fontColor([this.controller.accentColor()])
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .borderRadius($r('app.float.corner_radius_level4'))
              .backgroundColor(this.controller.accentSoftColor())
              .attributeModifier(Api26Material.accentSurface())
              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor(device.online ? $r('app.color.success') :
                  $r('app.color.text_secondary'))
                .border({ width: 2, color: $r('app.color.surface_muted') })
            }
            .width(40)
            .height(40)
            Column({ space: 3 }) {
              Text(device.label)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(device.online ? $r('app.string.device_status_online') :
                (device.lastSeenAtMs > 0 ? $r('app.string.device_status_offline') :
                  $r('app.string.mobile_sync_never_seen')))
                .fontSize(11)
                .fontColor(device.online ? $r('app.color.success') :
                  $r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            Button($r('app.string.mobile_sync_revoke'), { type: ButtonType.Normal })
              .height(32)
              .fontSize(11)
              .fontColor($r('app.color.danger'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level4'))
              .enabled(!this.controller.desktopDeviceMutationBusy)
              .attributeModifier(Api26Material.interactive())
              .onClick((): void => {
                this.controller.revokeMobileSyncDevice(device);
              })
          }
          .width('100%')
          .padding(8)
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor($r('app.color.surface_muted'))
          .attributeModifier(Api26Material.subtle())
        }, (device: NativeMobileSyncDevice): string => device.deviceId)
      }
      if (this.controller.mobileSyncAddOpen && this.controller.mobileSyncCredential === null) {
        Column({ space: 9 }) {
          Text($r('app.string.mobile_sync_add_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text($r('app.string.mobile_sync_add_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text($r('app.string.mobile_sync_device_name'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ placeholder: $r('app.string.mobile_sync_device_placeholder'),
            text: this.controller.mobileSyncDeviceName })
            .height(44)
            .fontSize(14)
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level8'))
            .attributeModifier(Api26Material.input())
            .onChange((value: string): void => {
              this.controller.mobileSyncDeviceName = value;
            })
          Text($r('app.string.mobile_sync_advanced'))
            .fontSize(12)
            .fontColor(this.controller.accentColor())
            .width('100%')
            .onClick((): void => {
              this.controller.mobileSyncAdvancedOpen = !this.controller.mobileSyncAdvancedOpen;
            })
          if (this.controller.mobileSyncAdvancedOpen) {
            TextInput({ placeholder: $r('app.string.mobile_sync_custom_username'),
              text: this.controller.mobileSyncCustomUsername })
              .height(44)
              .fontSize(14)
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level8'))
              .attributeModifier(Api26Material.input())
              .onChange((value: string): void => {
                this.controller.mobileSyncCustomUsername = value;
              })
            TextInput({ placeholder: $r('app.string.mobile_sync_custom_password'),
              text: this.controller.mobileSyncCustomPassword })
              .type(InputType.Password)
              .height(44)
              .fontSize(14)
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level8'))
              .attributeModifier(Api26Material.input())
              .onChange((value: string): void => {
                this.controller.mobileSyncCustomPassword = value;
              })
          }
          Button(this.controller.mobileSyncBusy ? $r('app.string.mobile_sync_creating') :
            $r('app.string.mobile_sync_create'), { type: ButtonType.Normal })
            .width('100%')
            .height(44)
            .fontColor(Api26Material.accentTextColor())
            .backgroundColor(this.controller.accentColor())
            .borderRadius($r('app.float.corner_radius_level8'))
            .enabled(this.controller.mobileSyncDeviceName.trim().length > 0 && !this.controller.mobileSyncBusy)
            .attributeModifier(Api26Material.accent())
            .onClick((): void => {
              this.controller.createMobileSyncDevice();
            })
        }
        .width('100%')
        .padding(12)
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface_muted'))
        .attributeModifier(Api26Material.subtle())
      }
      if (this.controller.mobileSyncCredential !== null) {
        Column({ space: 10 }) {
          Text($r('app.string.mobile_sync_scan_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Row() {
            QRCode(this.controller.mobileSyncCredential.connectUri)
              .width(190)
              .height(190)
              .color($r('app.color.qr_foreground'))
              .backgroundColor($r('app.color.qr_background'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          Text($r('app.string.mobile_sync_scan_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text($r('app.string.mobile_sync_username'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text(this.controller.mobileSyncCredential.username)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
          Text($r('app.string.mobile_sync_password'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text(this.controller.mobileSyncPasswordVisible ? this.controller.mobileSyncCredential.password : '••••••••••••')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .onClick((): void => {
              this.controller.mobileSyncPasswordVisible = !this.controller.mobileSyncPasswordVisible;
            })
          Text($r('app.string.mobile_sync_one_time_secret'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .borderRadius($r('app.float.corner_radius_level8'))
        .border({ width: 1, color: $r('app.color.danger') })
      }
      if (this.controller.mobileSyncState === 3) {
        Text($r('app.string.mobile_sync_server_failed'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }


  @Builder
  private compactSpaceConnectionHeroCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(206)
          .height(206)
          .borderRadius(103)
          .backgroundColor(this.controller.accentSoftColor())
        Row()
          .width(156)
          .height(156)
          .borderRadius(78)
          .border({ width: 2, color: this.controller.accentMediumColor() })
        Row() {
          SymbolGlyph($r('sys.symbol.lock_shield_fill'))
            .fontSize(54)
            .fontColor([this.controller.accentColor(), this.controller.accentSecondaryColor()])
        }
        .width(112)
        .height(112)
        .justifyContent(FlexAlign.Center)
        .borderRadius(56)
        .backgroundColor($r('app.color.surface'))
      }
      .width('100%')
      .height(188)
      .translate({ y: 4 })
      Column({ space: 5 }) {
        Blank()
        Text($r('app.string.device_space_connection_eyebrow'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.controller.accentColor())
          .width('100%')
        Text($r('app.string.device_space_connection_title'))
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .width('100%')
        Row({ space: 12 }) {
          Text(this.controller.spaceJoined ?
            (this.controller.spacePeerConnected ? $r('app.string.space_peer_online') :
              $r('app.string.space_peer_waiting')) :
            $r('app.string.device_space_connection_not_joined'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .layoutWeight(1)
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_right'))
              .fontSize(23)
              .fontColor([this.controller.accentColor()])
          }
          .width(52)
          .height(52)
          .justifyContent(FlexAlign.Center)
          .borderRadius(26)
          .backgroundColor(this.controller.accentSoftColor())
          .attributeModifier(Api26Material.accentSurface())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding(24)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(304)
    .borderRadius($r('app.float.corner_radius_level8'))
    .clip(true)
    .renderGroup(true)
    .backgroundColor(Api26Material.cardBackgroundColor())
    .border({ width: 1, color: this.controller.accentMediumColor() })
    .geometryTransition('uniclipboard-space-connection-card', { follow: true })
    .transition(TransitionEffect.opacity(0.99).animation({ duration: 420, curve: Curve.Friction }))
    .id('compact-space-connection-card')
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .attributeModifier(Api26Material.interactive())
    .onClick((): void => {
      this.openConnectionDetail(1);
    })
  }


  @Builder
  private compactMoreConnectionsHeroCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(206)
          .height(206)
          .borderRadius(103)
          .backgroundColor(this.controller.accentSoftColor())
        Row()
          .width(156)
          .height(156)
          .borderRadius(78)
          .border({ width: 2, color: this.controller.accentMediumColor() })
        Row() {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(54)
            .fontColor([this.controller.accentSecondaryColor(), this.controller.accentColor()])
        }
        .width(112)
        .height(112)
        .justifyContent(FlexAlign.Center)
        .borderRadius(56)
        .backgroundColor($r('app.color.surface'))
      }
      .width('100%')
      .height(188)
      .translate({ y: 4 })
      Column({ space: 5 }) {
        Blank()
        Text($r('app.string.device_more_connections_eyebrow'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.controller.accentSecondaryColor())
          .width('100%')
        Text($r('app.string.device_more_connections_title'))
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .width('100%')
        Row({ space: 12 }) {
          Text($r('app.string.device_more_connections_note'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .layoutWeight(1)
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_right'))
              .fontSize(23)
              .fontColor([this.controller.accentColor()])
          }
          .width(52)
          .height(52)
          .justifyContent(FlexAlign.Center)
          .borderRadius(26)
          .backgroundColor(this.controller.accentSoftColor())
          .attributeModifier(Api26Material.accentSurface())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding(24)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(304)
    .borderRadius($r('app.float.corner_radius_level8'))
    .clip(true)
    .renderGroup(true)
    .backgroundColor(Api26Material.cardBackgroundColor())
    .border({ width: 1, color: this.controller.accentMediumColor() })
    .geometryTransition('uniclipboard-more-connections-card', { follow: true })
    .transition(TransitionEffect.opacity(0.99).animation({ duration: 420, curve: Curve.Friction }))
    .id('compact-more-connections-card')
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .attributeModifier(Api26Material.interactive())
    .onClick((): void => {
      this.openConnectionDetail(2);
    })
  }


  @Builder
  private compactConnectionDetailPage() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
      if (this.appearanceBackgroundImage.length > 0) {
        Image(this.appearanceBackgroundImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.appearanceBackgroundOpacity)
          .blur(this.appearanceBackgroundBlur)
      }
      Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(23)
            .fontColor([this.controller.accentColor()])
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .borderRadius(24)
        .backgroundColor(Api26Material.cardBackgroundColor())
        .border({ width: 1, color: this.controller.accentMediumColor() })
        .clickEffect({ level: ClickEffectLevel.MIDDLE })
        .attributeModifier(Api26Material.interactive())
        .onClick((): void => {
          this.closeConnectionDetail();
        })
      }
      .width(48)
      .height(48)
      .position({ x: 18, y: 14 + this.avoidAreaRectHeight })
      .zIndex(10)
      Column({ space: 10 }) {
        Row() {
          SymbolGlyph(this.connectionDetailKind === 1 ? $r('sys.symbol.lock_shield_fill') :
            $r('sys.symbol.ellipsis_circle'))
            .fontSize(46)
            .fontColor([this.controller.accentColor(), this.controller.accentSecondaryColor()])
        }
        .width(94)
        .height(94)
        .justifyContent(FlexAlign.Center)
        .borderRadius(47)
        .backgroundColor(this.controller.accentSoftColor())
        .attributeModifier(Api26Material.accentSurface())
        Text(this.connectionDetailKind === 1 ? $r('app.string.device_space_connection_title') :
          $r('app.string.device_more_connections_title'))
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.connectionDetailKind === 1 ?
          (this.controller.spaceJoined ?
            (this.controller.spacePeerConnected ? $r('app.string.space_peer_online') :
              $r('app.string.space_peer_waiting')) :
            $r('app.string.device_space_connection_not_joined')) :
          $r('app.string.device_more_connections_note'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
      }
      .width('100%')
      .height(204)
      .justifyContent(FlexAlign.Center)
      .margin({ left: 16, right: 16, top: 14 + this.avoidAreaRectHeight })
      Scroll() {
        Column({ space: 12 }) {
          if (this.connectionDetailKind === 1) {
            this.spaceJoinCard()
          } else {
            this.mobileSpaceRelayCard()
            this.mobileSyncManagementCard()
          }
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 20,
          bottom: 32 + this.navigationRectHeight
        })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .borderRadius({ topLeft: 28, topRight: 28 })
      .backgroundColor(this.controller.pageBackgroundColor())
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .geometryTransition(this.connectionDetailGeometryId())
    .transition(TransitionEffect.opacity(0.99).animation({ duration: 420, curve: Curve.Friction }))
    .id('compact-connection-detail-cover')
  }


  @Builder
  private mobileSpaceConnectionGuide() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Text($r('app.string.mobile_space_connection_title'))
          .fontSize($r('app.float.font_subtitle_large'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.mobile_space_connection_recommended'))
          .fontSize($r('app.float.font_caption_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.controller.accentColor())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius($r('app.float.corner_radius_level10'))
          .backgroundColor(this.controller.accentSoftColor())
          .attributeModifier(Api26Material.accentSurface())
      }
      .width('100%')
      Text($r('app.string.mobile_space_connection_note'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 7 }) {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(16)
          .fontColor([this.controller.accentColor()])
        Text($r('app.string.mobile_connection_difference_note'))
          .fontSize($r('app.float.font_body_small'))
          .lineHeight(18)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .borderRadius($r('app.float.corner_radius_level4'))
      .backgroundColor(this.controller.accentSoftColor())
      .attributeModifier(Api26Material.accentSurface())
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }


  @Builder
  private mobileSpaceRelayCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text($r('app.string.space_relay_settings_title'))
            .fontSize($r('app.float.font_body_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.space_relay_allow_note'))
            .fontSize($r('app.float.font_body_small'))
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.controller.spaceRelayFallbackEnabled })
          .selectedColor(this.controller.accentColor())
          .enabled(!this.controller.spaceRelaySettingsBusy)
          .onChange((enabled: boolean): void => {
            this.controller.spaceRelayFallbackEnabled = enabled;
            this.controller.spaceRelaySettingsChanged();
          })
      }
      .width('100%')
      Text($r('app.string.space_relay_settings_note'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text($r('app.string.space_relay_urls_label'))
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextArea({
        placeholder: $r('app.string.space_relay_urls_placeholder'),
        text: this.controller.spaceRelayUrlsText
      })
        .height(96)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .padding(12)
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.spaceRelayUrlsText = value;
          this.controller.spaceRelaySettingsChanged();
        })
      Button(this.controller.spaceRelaySettingsBusy ? $r('app.string.space_relay_saving_action') :
        (this.controller.spaceRelaySettingsState === 2 ? $r('app.string.space_relay_retry_action') :
          $r('app.string.space_relay_save_action')), { type: ButtonType.Normal })
        .height(46)
        .width('100%')
        .fontSize($r('app.float.font_body_large'))
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(!this.controller.spaceRelaySettingsBusy)
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.controller.saveSpaceNetworkSettings();
        })
      if (this.controller.spaceRelaySettingsState === 1) {
        Text($r('app.string.space_relay_saved'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.success'))
          .width('100%')
      } else if (this.controller.spaceRelaySettingsState === 2) {
        Text($r('app.string.space_relay_save_failed'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }


  @Builder
  private mobileLegacyConnectionCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(22)
          .fontColor([$r('app.color.text_secondary')])
        Column({ space: 3 }) {
          Text($r('app.string.legacy_connection_title'))
            .fontSize($r('app.float.font_body_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text($r('app.string.legacy_connection_note'))
            .fontSize($r('app.float.font_body_small'))
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      Button(this.controller.legacyConnectionExpanded ? $r('app.string.legacy_connection_collapse') :
        $r('app.string.legacy_connection_expand'), { type: ButtonType.Normal })
        .height(44)
        .width('100%')
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.interactive())
        .onClick((): void => {
          this.getUIContext().animateTo({
            duration: 380,
            curve: Curve.EaseOut
          }, (): void => {
            this.controller.legacyConnectionExpanded = !this.controller.legacyConnectionExpanded;
          });
        })
      if (this.controller.legacyConnectionExpanded) {
        Column({ space: 10 }) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ top: 2, bottom: 2 })
        Text($r('app.string.legacy_connect_code_title'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        TextArea({ placeholder: $r('app.string.connect_uri_placeholder'), text: this.controller.connectUri })
          .height(96)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level8'))
          .padding(12)
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.connectUri = value;
            this.controller.connectUriState = 0;
          })
        if (this.controller.connectUriState === 1) {
          Text($r('app.string.connect_uri_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        } else if (this.controller.connectUriState === 2) {
          Text($r('app.string.connect_uri_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        } else if (this.controller.connectUriState === 3) {
          Text($r('app.string.connect_uri_scan_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        Button($r('app.string.connect_uri_scan_action'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.scanConnectUri();
          })
        Button($r('app.string.connect_uri_action'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.controller.connectUri.trim().length > 0)
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.importConnectUri();
          })
        Divider()
          .color($r('app.color.divider'))
          .margin({ top: 6, bottom: 2 })
        Text($r('app.string.legacy_service_form_title'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text($r('app.string.legacy_server_url_label'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({ placeholder: $r('app.string.server_url_placeholder'), text: this.controller.serverUrl })
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.serverUrl = value;
            this.controller.connectionChanged();
          })
        Text($r('app.string.username_label'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 6 })
        TextInput({ placeholder: $r('app.string.username_placeholder'), text: this.controller.username })
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.username = value;
            this.controller.connectionChanged();
          })
        Text($r('app.string.password_label'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 6 })
        TextInput({ placeholder: $r('app.string.password_placeholder'), text: this.controller.password })
          .type(InputType.Password)
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.password = value;
            this.controller.connectionChanged();
          })
        Button($r('app.string.test_connection_action'), { type: ButtonType.Normal })
          .height(50)
          .width('100%')
          .fontSize($r('app.float.font_body_large'))
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .margin({ top: 12 })
          .enabled(this.controller.hasConfig() && !this.controller.busy)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.testConnection();
          })
        Button(this.controller.realtimeActive ? $r('app.string.realtime_stop_action') :
          $r('app.string.realtime_start_action'), { type: ButtonType.Normal })
          .height(50)
          .width('100%')
          .fontSize($r('app.float.font_body_large'))
          .fontColor(this.controller.realtimeActive ? $r('app.color.danger') : $r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.controller.hasConfig())
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.toggleRealtime();
          })
        Text(this.controller.realtimeActive ? $r('app.string.realtime_active_note') :
          $r('app.string.realtime_inactive_note'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.controller.realtimeActive ? $r('app.color.success') : $r('app.color.text_secondary'))
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .renderGroup(true)
        .transition({ type: TransitionType.Insert, opacity: 0, translate: { y: 24 } })
        .transition({ type: TransitionType.Delete, opacity: 0, translate: { y: -16 } })
      }
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }


  @Builder
  private compactDevicePage() {
    Scroll(this.controller.devicesScroller) {
      Column({ space: 12 }) {
        this.compactSpaceConnectionHeroCard()

        this.compactMoreConnectionsHeroCard()

        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text($r('app.string.desktop_paired_devices'))
                .fontSize($r('app.float.font_subtitle_large'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(this.controller.spaceJoined ? $r('app.string.desktop_roster_note') :
                $r('app.string.desktop_no_device'))
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.controller.spaceDevices.length.toString())
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .borderRadius($r('app.float.corner_radius_level10'))
              .backgroundColor($r('app.color.surface_muted'))
              .attributeModifier(Api26Material.subtle())
          }
          .width('100%')
          if (this.controller.spaceJoined) {
            Row({ space: 10 }) {
              Button($r('app.string.desktop_refresh_devices'), { type: ButtonType.Normal })
                .layoutWeight(1)
                .height(42)
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius($r('app.float.corner_radius_level10'))
                .enabled(!this.controller.spaceDeviceRefreshBusy && !this.controller.spaceConnectBusy &&
                  !this.controller.desktopDeviceMutationBusy)
                .attributeModifier(Api26Material.interactive())
                .onClick((): void => {
                  this.controller.refreshSpaceDevices();
                })
              Button(this.controller.spaceConnectBusy ? $r('app.string.desktop_connecting_all_devices') :
                $r('app.string.desktop_connect_all_devices'), { type: ButtonType.Normal })
                .layoutWeight(1)
                .height(42)
                .fontSize($r('app.float.font_body_small'))
                .fontColor(Api26Material.accentTextColor())
                .backgroundColor(this.controller.accentColor())
                .borderRadius($r('app.float.corner_radius_level10'))
                .enabled(!this.controller.spaceConnectBusy && !this.controller.desktopDeviceMutationBusy)
                .attributeModifier(Api26Material.accent())
                .onClick((): void => {
                  this.controller.connectAllSpaceDevices();
                })
            }
            .width('100%')
            if (this.controller.spaceConnectState === 2) {
              Text($r('app.string.desktop_connect_devices_success'))
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.success'))
                .width('100%')
            } else if (this.controller.spaceConnectState === 3) {
              Text($r('app.string.desktop_connect_devices_failed'))
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.danger'))
                .width('100%')
            }
            ForEach(this.controller.spaceDevices, (device: EngineRuntimeDevice) => {
              this.desktopPairedDeviceRow(device)
            }, (device: EngineRuntimeDevice): string => device.deviceId + ':' + device.online.toString() + ':' +
              device.state)
            if (this.controller.desktopSelectedSpaceDeviceId.length > 0 &&
              !this.controller.desktopSelectedSpaceDeviceIsLocal) {
              this.compactSelectedDeviceSyncCard()
            }
          }
          Text($r('app.string.device_management_hint'))
            .fontSize($r('app.float.font_body_small'))
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .attributeModifier(Api26Material.panel())

      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 56 + this.avoidAreaRectHeight,
        bottom: 116 + this.navigationRectHeight
      })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height('100%')
    .bindContentCover(this.connectionDetailVisible, this.compactConnectionDetailPage(), {
      modalTransition: ModalTransition.NONE,
      onWillDismiss: (_action: DismissContentCoverAction): void => {
        this.closeConnectionDetail();
      },
      onDisappear: (): void => {
        this.connectionDetailVisible = false;
      }
    })
  }


  @Builder
  private compactHistoryLibrarySettings() {
    Column({ space: 12 }) {
      Text($r('app.string.history_library_settings_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text($r('app.string.history_retention_note'))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        this.compactHistoryRetentionButton(7, $r('app.string.history_retention_7_days'))
        this.compactHistoryRetentionButton(30, $r('app.string.history_retention_30_days'))
      }
      .width('100%')
      Row({ space: 8 }) {
        this.compactHistoryRetentionButton(90, $r('app.string.history_retention_90_days'))
        this.compactHistoryRetentionButton(0, $r('app.string.history_retention_forever'))
      }
      .width('100%')
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text($r('app.string.history_merge_duplicates_title'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.history_merge_duplicates_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.controller.historyMergeDuplicates })
          .selectedColor(this.controller.accentColor())
          .onChange((enabled: boolean): void => {
            this.controller.setHistoryMergeDuplicates(enabled);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }


  @Builder
  private compactHistoryRetentionButton(days: number, label: Resource) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(38)
      .fontSize(12)
      .fontColor(this.controller.historyRetentionDays === days ? this.controller.accentColor() :
        $r('app.color.text_primary'))
      .backgroundColor(this.controller.historyRetentionDays === days ? this.controller.accentSoftColor() :
        $r('app.color.surface_muted'))
      .borderRadius($r('app.float.corner_radius_level10'))
      .attributeModifier(Api26Material.accent())
      .onClick((): void => {
        this.controller.setHistoryRetentionDays(days);
      })
  }


  @Builder
  private settingsPage() {
    Scroll(this.controller.settingsScroller) {
      Column({ space: 12 }) {
        this.compactAppearanceCard()
        this.compactDiagnosticsCard()

        Column() {
          this.backgroundSyncSwitchRow()
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .attributeModifier(Api26Material.panel())

        this.compactHistoryLibrarySettings()
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 56 + this.avoidAreaRectHeight,
        bottom: 116 + this.navigationRectHeight
      })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }


  @Builder
  private compactTabBar(index: number, icon: Resource, label: Resource) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontWeight(this.controller.selectedTab === index ? FontWeight.Bold : FontWeight.Regular)
        .fontColor([this.controller.selectedTab === index ? this.controller.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize(10)
        .fontWeight(this.controller.selectedTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.controller.selectedTab === index ? this.controller.accentColor() :
          $r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }


  @Builder
  private compactAboutCapability(icon: Resource, label: Resource) {
    Column({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.controller.accentColor()])
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(72)
    .justifyContent(FlexAlign.Center)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.controller.accentSoftColor())
    .attributeModifier(Api26Material.accentSurface())
  }


  @Builder
  private feedbackSheetContent() {
    Column({ space: 0 }) {
      Text($r('app.string.feedback_description'))
        .fontSize($r('app.float.font_body_large'))
        .lineHeight(24)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text($r('app.string.feedback_content_label'))
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 24, bottom: 10 })
      TextArea({
        placeholder: $r('app.string.feedback_content_placeholder'),
        text: this.controller.feedbackText
      })
        .width('100%')
        .height(160)
        .fontSize($r('app.float.font_body_large'))
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .border({ width: 1, color: $r('app.color.divider') })
        .padding(16)
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.feedbackText = value;
        })
      Text($r('app.string.feedback_email_label'))
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 22, bottom: 10 })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.envelope'))
          .fontSize(20)
          .fontColor([this.controller.accentColor()])
        Text(FEEDBACK_EMAIL)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
      }
      .width('100%')
      .height(54)
      .padding({ left: 16, right: 16 })
      .borderRadius($r('app.float.corner_radius_level8'))
      .backgroundColor(this.controller.accentSoftColor())
      .attributeModifier(Api26Material.accent())
      Button($r('app.string.feedback_write_clipboard_action'), { type: ButtonType.Normal })
        .width('100%')
        .height(50)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .margin({ top: 24 })
        .enabled(this.controller.feedbackText.trim().length > 0)
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.submitFeedback();
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 18, bottom: 26 })
  }


  @Builder
  private feedbackSheet() {
    HdsNavigation() {
      Scroll() {
        Column() {
          Blank()
            .width('100%')
            .height(55)
          this.feedbackSheetContent()
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.feedback_dialog_title')
        },
        menu: {
          value: [{
            content: {
              label: 'modal_cancel',
              isEnabled: true,
              type: IconStyleMode.SMALL,
              action: (): void => {
                this.showFeedbackSheet = false;
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
              iconColor: this.controller.accentColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.controller.accentColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.controller.appearanceMaterialLevel
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.controller.pageBackgroundColor())
  }


  @Builder
  private aboutSheetContent() {
    Column({ space: 0 }) {
      Image($r('app.media.uniclipboard_start_icon'))
        .width(82)
        .height(82)
        .borderRadius($r('app.float.corner_radius_level4'))
        .objectFit(ImageFit.Cover)
      Text($r('app.string.app_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
      Text($r('app.string.desktop_version'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.controller.accentColor())
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor(this.controller.accentSoftColor())
        .attributeModifier(Api26Material.accentSurface())
        .margin({ top: 8 })
      Row({ space: 5 }) {
        Text($r('app.string.about_engine_version_label'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(this.controller.engineVersion)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .margin({ top: 8 })
      Text($r('app.string.about_tagline'))
        .fontSize($r('app.float.font_subtitle_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 18 })
      Text($r('app.string.about_description'))
        .fontSize(14)
        .lineHeight(21)
        .textAlign(TextAlign.Center)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
      Row({ space: 10 }) {
        this.compactAboutCapability($r('sys.symbol.rectangle_stack'),
          $r('app.string.about_feature_sync'))
        this.compactAboutCapability($r('sys.symbol.connection'),
          $r('app.string.about_feature_space'))
        this.compactAboutCapability($r('sys.symbol.desktop'),
          $r('app.string.about_feature_native'))
      }
      .width('100%')
      .margin({ top: 22 })
      Text($r('app.string.about_footer'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 18 })
      Button($r('app.string.about_feedback_action'), { type: ButtonType.Normal })
        .width('100%')
        .height(48)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .margin({ top: 22 })
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.openFeedbackFromAbout();
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 24 })
  }


  @Builder
  private aboutSheet() {
    HdsNavigation() {
      Scroll(this.controller.aboutScroller) {
        Column() {
          Blank()
            .width('100%')
            .height(55)
          this.aboutSheetContent()
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.about_title')
        },
        menu: {
          value: [{
            content: {
              label: 'modal_cancel',
              isEnabled: true,
              type: IconStyleMode.SMALL,
              action: (): void => {
                this.showAboutSheet = false;
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.controller.appearanceMaterialLevel
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.controller.aboutScroller])
    .backgroundColor(this.controller.pageBackgroundColor())
  }


  @Builder
  private compactSyncNavigation() {
    HdsNavigation() {
      this.syncPage()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.nav_sync'),
          subTitle: $r('app.string.app_subtitle')
        },
        menu: {
          value: [{
            content: {
              icon: this.titleBarConnectionIcon(this.controller.isConnectionAvailable()),
              label: this.controller.isConnectionAvailable() ?
                $r('app.string.status_online') : $r('app.string.status_offline'),
              action: (): void => {
                this.openConnectionDiagnostics();
              }
            }
          }, {
            content: {
              icon: $r('sys.symbol.info_circle'),
              label: $r('app.string.about_title'),
              action: (): void => {
                this.openAbout();
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
              iconColor: this.controller.accentColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.controller.accentColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.controller.appearanceMaterialLevel
        }
      }
    })
    .bindToScrollable([this.controller.syncScroller])
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.controller.pageBackgroundColor())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }


  @Builder
  private compactDevicesNavigation() {
    HdsNavigation() {
      this.compactDevicePage()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.desktop_devices'),
          subTitle: $r('app.string.app_subtitle')
        },
        menu: {
          value: [{
            content: {
              icon: this.titleBarConnectionIcon(this.controller.isConnectionAvailable()),
              label: this.controller.isConnectionAvailable() ?
                $r('app.string.status_online') : $r('app.string.status_offline'),
              action: (): void => {
                this.openConnectionDiagnostics();
              }
            }
          }, {
            content: {
              icon: $r('sys.symbol.info_circle'),
              label: $r('app.string.about_title'),
              action: (): void => {
                this.openAbout();
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
              iconColor: this.controller.accentColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.controller.accentColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.controller.appearanceMaterialLevel
        }
      }
    })
    .bindToScrollable([this.controller.devicesScroller])
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.controller.pageBackgroundColor())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }


  @Builder
  private compactSettingsNavigation() {
    HdsNavigation() {
      this.settingsPage()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.nav_settings')
        },
        menu: {
          value: [{
            content: {
              icon: this.titleBarConnectionIcon(this.controller.isConnectionAvailable()),
              label: this.controller.isConnectionAvailable() ?
                $r('app.string.status_online') : $r('app.string.status_offline'),
              action: (): void => {
                this.openConnectionDiagnostics();
              }
            }
          }, {
            content: {
              icon: $r('sys.symbol.info_circle'),
              label: $r('app.string.about_title'),
              action: (): void => {
                this.openAbout();
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
              iconColor: this.controller.accentColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.controller.accentColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.controller.appearanceMaterialLevel
        }
      }
    })
    .bindToScrollable([this.controller.settingsScroller])
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.controller.pageBackgroundColor())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }


  @Builder
  private compactNavigation() {
    HdsTabs({ index: this.controller.selectedTab }) {
      TabContent() {
        this.compactSyncNavigation()
      }
        .tabBar(this.compactTabBar(0, $r('sys.symbol.clipboard_sharing'),
          $r('app.string.nav_sync')))

      TabContent() {
        this.compactDevicesNavigation()
      }
        .tabBar(this.compactTabBar(1, $r('sys.symbol.desktop'),
          $r('app.string.desktop_devices')))

      TabContent() {
        this.compactSettingsNavigation()
      }
        .tabBar(this.compactTabBar(2, $r('sys.symbol.gearshape'),
          $r('app.string.nav_settings')))
    }
    .barPosition(BarPosition.End)
    .vertical(false)
    .scrollable(false)
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: { smallWidth: 260, mediumWidth: 360, largeWidth: 440 },
      barBottomMargin: 28,
      gradientMask: { maskColor: $r('app.color.navigation_mask'), maskHeight: 92 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: this.controller.appearanceMaterialLevel
      }
    })
    .onChange((index: number): void => {
      this.controller.selectPage(index);
    })
    .width('100%')
    .height('100%')
    .backgroundColor(this.controller.pageBackgroundColor())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }


  @Builder
  private compactFileComposer() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(26)
          .fontColor([$r('app.color.text_secondary')])
          .width(46)
        Column({ space: 3 }) {
          Text($r('app.string.file_composer_title'))
            .fontSize($r('app.float.font_body_medium'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          if (this.controller.fileTransferState === 1) {
            Text($r('app.string.file_selecting'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.controller.fileTransferState === 2) {
            Text(this.controller.composerFileName)
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.success'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (this.controller.fileTransferState === 3) {
            Text($r('app.string.file_sending'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.controller.fileTransferState === 4) {
            Text($r('app.string.file_send_failed'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.danger'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (this.controller.fileTransferState === 5) {
            Text($r('app.string.file_too_large'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.danger'))
              .width('100%')
          } else if (this.controller.fileTransferState === 6) {
            Text($r('app.string.file_send_success'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.success'))
              .width('100%')
          } else if (this.controller.fileTransferState === 7) {
            Text($r('app.string.file_send_pending'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else {
            Text($r('app.string.file_empty'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Row({ space: 10 }) {
        Button(this.controller.fileTransferState === 1 ? $r('app.string.file_selecting') :
          $r('app.string.select_file_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(46)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.controller.busy && this.controller.fileTransferState !== 1)
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.selectFile();
          })
        Button(this.controller.fileTransferState === 3 ? $r('app.string.file_sending') :
          $r('app.string.send_file_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(46)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.controller.busy && this.controller.composerFileUri.length > 0 && this.controller.spaceJoined)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.sendFile();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }


  @Builder
  private desktopAudioPreview() {
    Column({ space: 16 }) {
      if (this.controller.desktopAudioCover !== null) {
        Image(this.controller.desktopAudioCover)
          .id('desktop-audio-cover-' + this.controller.desktopAudioCoverRevision.toString())
          .width(200)
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.corner_radius_level8'))
      } else {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(58)
          .fontColor([this.controller.accentColor()])
      }
      Text(this.controller.desktopAudioDisplayTitle())
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      if (this.controller.desktopAudioDisplayArtist().length > 0) {
        Text(this.controller.desktopAudioDisplayArtist())
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      Slider({
        value: this.controller.desktopAudioPosition,
        min: 0,
        max: this.controller.desktopAudioDuration > 0 ? this.controller.desktopAudioDuration : 1,
        step: 100,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor(this.controller.accentColor())
        .enabled(this.controller.desktopAudioDuration > 0 && this.controller.desktopAudioState !== 5)
        .onChange((value: number, mode: SliderChangeMode): void => {
          this.controller.desktopAudioPosition = value;
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.controller.desktopAudioSeeking = true;
          } else {
            this.controller.desktopAudioSeeking = false;
            this.controller.seekDesktopAudio(value);
          }
        })
      Row() {
        Text(this.controller.formatAudioTime(this.controller.desktopAudioPosition))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.controller.formatAudioTime(this.controller.desktopAudioDuration))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Button(this.controller.desktopAudioState === 3 ? $r('app.string.audio_pause_action') :
        $r('app.string.audio_play_action'), { type: ButtonType.Normal })
        .height(42)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.controller.desktopAudioState !== 1 && this.controller.desktopAudioState !== 5 &&
          this.controller.desktopFileSourcePath().length > 0)
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.controller.toggleDesktopAudioPlayback();
        })
      if (this.controller.desktopAudioState === 1) {
        Text($r('app.string.audio_preparing'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      } else if (this.controller.desktopAudioState === 5) {
        Text($r('app.string.audio_play_failed'))
          .fontSize(12)
          .fontColor($r('app.color.danger'))
      }
      Divider()
        .color($r('app.color.divider'))
      Text($r('app.string.audio_lyrics_title'))
        .width('100%')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.controller.desktopAudioLyrics.length > 0) {
        Column({ space: 10 }) {
          Text(this.controller.desktopLyricTextAtOffset(-1))
            .fontSize($r('app.float.font_body_medium'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          Text(this.controller.desktopLyricTextAtOffset(0))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.controller.accentColor())
            .textAlign(TextAlign.Center)
          Text(this.controller.desktopLyricTextAtOffset(1))
            .fontSize($r('app.float.font_body_medium'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(104)
        .justifyContent(FlexAlign.Center)
      } else if (this.controller.desktopAudioPlainLyrics.length > 0) {
        Scroll() {
          Text(this.controller.desktopAudioPlainLyrics)
            .width('100%')
            .fontSize($r('app.float.font_body_medium'))
            .lineHeight(22)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(140)
        .scrollBar(BarState.Auto)
      } else if (this.controller.desktopAudioMetadataState === 1) {
        Text($r('app.string.audio_metadata_loading'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
      } else {
        Text($r('app.string.audio_lyrics_unavailable'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .id('desktop-audio-player-' + this.controller.desktopFilePreviewKey())
    .width('100%')
    .padding(24)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface_muted'))
    .attributeModifier(Api26Material.subtle())
    .onAppear((): void => {
      this.controller.prepareDesktopAudio();
    })
  }


  private desktopGestureShareMessage(): Resource {
    if (this.controller.desktopGestureShareState === 2) {
      return $r('app.string.gesture_share_sending');
    }
    if (this.controller.desktopGestureShareState === 3) {
      return $r('app.string.gesture_share_success');
    }
    if (this.controller.desktopGestureShareState === 4) {
      return $r('app.string.gesture_share_failed');
    }
    if (this.controller.desktopGestureShareState === 5) {
      return $r('app.string.gesture_share_unsupported');
    }
    if (this.controller.desktopGestureShareState !== 1) {
      return $r('app.string.gesture_share_preparing');
    }
    let contentKind: number = this.controller.desktopGestureShareContentKind();
    if (contentKind === 2 || contentKind === 4) {
      return $r('app.string.gesture_share_ready_image');
    }
    if (contentKind === 5) {
      return $r('app.string.gesture_share_ready_video');
    }
    if (contentKind === 6) {
      return $r('app.string.gesture_share_ready_audio');
    }
    if (contentKind === 7) {
      return $r('app.string.gesture_share_ready_pdf');
    }
    if (contentKind === 8) {
      return $r('app.string.gesture_share_ready_archive');
    }
    if (contentKind === 9) {
      return $r('app.string.gesture_share_ready_word');
    }
    if (contentKind === 10) {
      return $r('app.string.gesture_share_ready_excel');
    }
    if (contentKind === 11) {
      return $r('app.string.gesture_share_ready_ppt');
    }
    if (contentKind === 12) {
      return $r('app.string.gesture_share_ready_document');
    }
    if (contentKind === 1) {
      return $r('app.string.gesture_share_ready');
    }
    return $r('app.string.gesture_share_ready_text');
  }


  @Builder
  private desktopGestureShareHint() {
    Row({ space: 8 }) {
      if (this.controller.desktopGestureShareContentKind() === 2 || this.controller.desktopGestureShareContentKind() === 4) {
        SymbolGlyph($r('sys.symbol.ohos_photo'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 5) {
        SymbolGlyph($r('sys.symbol.video'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 6) {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 8) {
        SymbolGlyph($r('sys.symbol.doc_zipper'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 7) {
        SymbolGlyph($r('sys.symbol.pdf_doc'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 9) {
        SymbolGlyph($r('sys.symbol.word_book'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 10) {
        SymbolGlyph($r('sys.symbol.grid'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 11) {
        SymbolGlyph($r('sys.symbol.play_round_rectangle'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else if (this.controller.desktopGestureShareContentKind() === 1 || this.controller.desktopGestureShareContentKind() === 12) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      } else {
        SymbolGlyph($r('sys.symbol.text_alignleft'))
          .fontSize(26)
          .fontColor([this.controller.desktopGestureShareState === 4 || this.controller.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.controller.accentColor()])
      }
      Column({ space: 3 }) {
        Text($r('app.string.gesture_share_title'))
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.desktopGestureShareMessage())
          .width('100%')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([$r('app.color.text_secondary')])
        .width(32)
        .height(32)
        .padding(7)
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))
        .attributeModifier(Api26Material.interactive())
        .onClick((): void => {
          this.controller.desktopGestureShareHintDismissed = true;
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.controller.accentSoftColor())
    .attributeModifier(Api26Material.accentSurface())
  }


  @Builder
  private spaceModeButton(mode: number, label: Resource) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(38)
      .fontSize($r('app.float.font_body_medium'))
      .fontColor(this.controller.spaceActionMode === mode ? $r('app.color.text_primary') :
        $r('app.color.text_secondary'))
      .backgroundColor(this.controller.spaceActionMode === mode ? this.controller.accentSoftColor() : Color.Transparent)
      .borderRadius($r('app.float.corner_radius_level10'))
      .attributeModifier(Api26Material.navigation(this.controller.spaceActionMode === mode))
      .onClick((): void => {
        this.controller.spaceActionMode = mode;
        this.controller.spaceCreateState = 0;
        this.controller.spaceJoinState = 0;
      })
  }


  @Builder
  private desktopCreateSpaceForm() {
    Column({ space: 10 }) {
      Text(this.controller.spaceJoined ? $r('app.string.space_create_new_title') :
        $r('app.string.space_create_title'))
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(this.controller.spaceJoined ? $r('app.string.space_create_new_note') :
        $r('app.string.space_create_note'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: $r('app.string.space_create_device_placeholder'),
        text: this.controller.spaceCreateDeviceName })
        .height(44)
        .fontColor(this.controller.spaceCreateDeviceNameRecommended ? $r('app.color.text_secondary') :
          $r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onFocus((): void => {
          this.controller.spaceCreateDeviceNameRecommended = false;
        })
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.spaceCreateDeviceName = value;
          this.controller.spaceCreateDeviceNameRecommended = false;
          this.controller.spaceCreateState = 0;
        })
      TextInput({ placeholder: $r('app.string.space_passphrase_placeholder'),
        text: this.controller.spaceCreatePassphrase })
        .type(InputType.Password)
        .height(44)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.spaceCreatePassphrase = value;
          this.controller.spaceCreateState = 0;
        })
      TextInput({ placeholder: $r('app.string.space_create_confirm_placeholder'),
        text: this.controller.spaceCreatePassphraseConfirm })
        .type(InputType.Password)
        .height(44)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.spaceCreatePassphraseConfirm = value;
          this.controller.spaceCreateState = 0;
        })
      Text($r('app.string.space_create_requirement'))
        .fontSize(10)
        .lineHeight(15)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.controller.spaceCreateState === 2) {
        Text($r('app.string.space_create_failed'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Button(this.controller.spaceCreateBusy ? $r('app.string.space_creating_action') :
        (this.controller.spaceJoined ? $r('app.string.space_create_new_action') :
          $r('app.string.space_create_action')), { type: ButtonType.Normal })
        .width('100%')
        .height(44)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.controller.canCreateSpace())
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.controller.createCurrentSpace();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }


  @Builder
  private desktopJoinSpaceForm() {
    Column({ space: 10 }) {
      Text(this.controller.spaceJoined ? $r('app.string.space_switch_note') : $r('app.string.space_join_note'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button($r('app.string.space_scan_invitation'), { type: ButtonType.Normal })
        .height(42)
        .width('100%')
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.interactive())
        .onClick((): void => {
          this.controller.scanSpaceInvitation();
        })
      if (!this.controller.spaceJoined) {
        TextInput({ placeholder: $r('app.string.space_create_device_placeholder'),
          text: this.controller.spaceJoinDeviceName })
          .height(46)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.input())
          .onChange((value: string): void => {
            this.controller.spaceJoinDeviceName = value;
            this.controller.spaceJoinState = 0;
          })
      }
      TextInput({ placeholder: $r('app.string.space_code_placeholder'),
        text: this.controller.spaceInvitationCode })
        .height(46)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.spaceInvitationCode = value.toUpperCase();
          this.controller.spaceJoinState = 0;
        })
      TextInput({ placeholder: $r('app.string.space_passphrase_placeholder'),
        text: this.controller.spacePassphrase })
        .type(InputType.Password)
        .height(46)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.spacePassphrase = value;
          this.controller.spaceJoinState = 0;
        })
      if (this.controller.spaceJoinState === 2) {
        Text(this.controller.spaceJoined ? $r('app.string.space_switch_failed') :
          $r('app.string.space_join_failed'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Button(this.controller.spaceJoinBusy ?
        (this.controller.spaceJoined ? $r('app.string.space_switching_action') :
          $r('app.string.space_joining_action')) :
        (this.controller.spaceJoined ? $r('app.string.space_switch_action') :
          $r('app.string.space_join_action')), { type: ButtonType.Normal })
        .width('100%')
        .height(44)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor(this.controller.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.controller.canJoinSpace())
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.controller.joinCurrentSpace();
        })
    }
    .width('100%')
  }


  @Builder
  private spaceInvitationCard() {
    Column({ space: 9 }) {
      Text($r('app.string.space_invitation_title'))
        .fontSize($r('app.float.font_body_medium'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text($r('app.string.space_qr_note'))
        .fontSize(10)
        .lineHeight(15)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: $r('app.string.space_invitation_passphrase_placeholder'),
        text: this.controller.spaceCreatePassphrase })
        .type(InputType.Password)
        .height(40)
        .fontSize(12)
        .backgroundColor($r('app.color.surface'))
        .borderRadius($r('app.float.corner_radius_level4'))
        .attributeModifier(Api26Material.input())
        .onChange((value: string): void => {
          this.controller.spaceCreatePassphrase = value;
          this.controller.spaceCreateState = 0;
          this.controller.spaceIssuedInvitationCode = '';
          this.controller.spaceInvitationExpiresAtMs = 0;
        })
      if (this.controller.buildSpaceInvitationUri().length > 0) {
        Row() {
          QRCode(this.controller.buildSpaceInvitationUri())
            .width(176)
            .height(176)
            .color($r('app.color.qr_foreground'))
            .backgroundColor($r('app.color.qr_background'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 5, bottom: 5 })
        Text($r('app.string.space_invitation_code_label'))
          .fontSize($r('app.float.font_body_small'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.controller.spaceIssuedInvitationCode)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.controller.accentColor())
          .letterSpacing(2)
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')
        Text($r('app.string.space_passphrase_label'))
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text(this.controller.spaceCreatePassphrase)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_primary'))
          .copyOption(CopyOptions.LocalDevice)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.controller.spaceInvitationExpiresAtMs > 0) {
          Row({ space: 5 }) {
            Text($r('app.string.space_invitation_expires'))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
            Text(this.controller.invitationExpiryText())
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }
        Text($r('app.string.space_share_invitation_note'))
          .fontSize($r('app.float.font_caption_medium'))
          .lineHeight(15)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Button($r('app.string.space_share_invitation_action'), { type: ButtonType.Normal })
          .width('100%')
          .height(42)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor(Api26Material.accentTextColor())
          .backgroundColor(this.controller.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.shareCurrentSpaceInvitation();
          })
      }
      Text(this.controller.spaceCreateState === 3 ? $r('app.string.space_invitation_failed') :
        $r('app.string.space_invitation_note'))
        .fontSize(10)
        .lineHeight(15)
        .fontColor(this.controller.spaceCreateState === 3 ? $r('app.color.danger') :
          $r('app.color.text_secondary'))
        .width('100%')
      Button(this.controller.spaceInvitationBusy ? $r('app.string.space_issuing_invitation') :
        $r('app.string.space_issue_invitation'), { type: ButtonType.Normal })
        .width('100%')
        .height(40)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.controller.canIssueSpaceInvitation())
        .attributeModifier(Api26Material.interactive())
        .onClick((): void => {
          this.controller.issueCurrentSpaceInvitation();
        })
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor($r('app.color.surface_muted'))
    .attributeModifier(Api26Material.subtle())
  }


  @Builder
  private desktopDeviceTypeGlyph(deviceType: string) {
    if (deviceType === 'phone') {
      SymbolGlyph($r('sys.symbol.phone'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'tablet') {
      SymbolGlyph($r('sys.symbol.pad'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'tv') {
      SymbolGlyph($r('sys.symbol.TV_tv'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'wearable') {
      SymbolGlyph($r('sys.symbol.watch'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'car') {
      SymbolGlyph($r('sys.symbol.car'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else {
      SymbolGlyph($r('sys.symbol.desktop'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    }
  }


  @Builder
  private desktopDeviceTypeLabel(deviceType: string) {
    if (deviceType === 'phone') {
      Text($r('app.string.device_type_phone'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'tablet') {
      Text($r('app.string.device_type_tablet'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === '2in1') {
      Text($r('app.string.device_type_2in1'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'tv') {
      Text($r('app.string.device_type_tv'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'wearable') {
      Text($r('app.string.device_type_wearable'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'car') {
      Text($r('app.string.device_type_car'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else {
      Text($r('app.string.device_type_unknown'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    }
  }


  @Builder
  private desktopPairedDeviceContextMenu(device: EngineRuntimeDevice) {
    Menu() {
      if (device.isLocal) {
        MenuItem({
          content: $r('app.string.desktop_this_device')
        }).enabled(false)
      } else {
        MenuItem({
          symbolStartIcon: this.controller.historyDeleteMenuSymbol(),
          content: $r('app.string.space_revoke_device_confirm')
        })
          .enabled(!this.controller.desktopDeviceMutationBusy)
          .onClick((): void => {
            setTimeout((): void => {
              this.controller.revokeSpaceDevice(device);
            }, 120);
          })
      }
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }


  @Builder
  private desktopMobileDeviceContextMenu(device: NativeMobileSyncDevice) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.controller.historyDeleteMenuSymbol(),
        content: $r('app.string.mobile_sync_revoke_confirm')
      })
      .enabled(!this.controller.desktopDeviceMutationBusy)
      .onClick((): void => {
        setTimeout((): void => {
          this.controller.revokeMobileSyncDevice(device);
        }, 120);
      })
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }


  @Builder
  private compactDeviceContentTypeSwitch(title: Resource, contentType: string) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.desktopDeviceSyncChecked(contentType) })
        .id('desktop-device-sync-' + contentType + '-' + this.desktopDeviceSyncRenderRevision.toString())
        .selectedColor(this.controller.accentColor())
        .enabled(this.controller.desktopDeviceSyncState === 2 && !this.controller.desktopDeviceSyncSaving)
        .onChange((enabled: boolean): void => {
          this.controller.updateDesktopDeviceSyncPreference(contentType, enabled);
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 14, right: 12 })
    .borderRadius($r('app.float.corner_radius_level8'))
    .border({ width: 1, color: $r('app.color.divider') })
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
  }

  private desktopDeviceSyncChecked(contentType: string): boolean {
    if (contentType === 'receive_text') {
      return this.desktopDeviceReceiveText;
    }
    if (contentType === 'receive_image') {
      return this.desktopDeviceReceiveImage;
    }
    if (contentType === 'receive_file') {
      return this.desktopDeviceReceiveFile;
    }
    if (contentType === 'receive_link') {
      return this.desktopDeviceReceiveLink;
    }
    if (contentType === 'receive_rich_text') {
      return this.desktopDeviceReceiveRichText;
    }
    if (contentType === 'text') {
      return this.desktopDeviceSyncText;
    }
    if (contentType === 'image') {
      return this.desktopDeviceSyncImage;
    }
    if (contentType === 'file') {
      return this.desktopDeviceSyncFile;
    }
    if (contentType === 'link') {
      return this.desktopDeviceSyncLink;
    }
    return this.desktopDeviceSyncRichText;
  }


  @Builder
  private compactSelectedDeviceSyncCard() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column() {
          this.desktopDeviceTypeGlyph(this.controller.desktopSelectedSpaceDeviceType)
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor(this.controller.accentSoftColor())
        .attributeModifier(Api26Material.accentSurface())
        Column({ space: 3 }) {
          Text(this.controller.desktopSelectedSpaceDeviceName)
            .fontSize($r('app.float.font_body_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.controller.desktopSelectedSpaceDeviceOnline ? $r('app.string.device_status_online') :
            (this.controller.desktopSelectedSpaceDeviceState === 'unknown' ?
              $r('app.string.device_status_unknown') : $r('app.string.device_status_offline')))
            .fontSize($r('app.float.font_body_small'))
            .fontColor(this.controller.desktopSelectedSpaceDeviceOnline ? $r('app.color.success') :
              $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button($r('app.string.desktop_device_sync_restore'), { type: ButtonType.Normal })
          .height(34)
          .fontSize(11)
          .fontColor(this.controller.accentColor())
          .backgroundColor(Color.Transparent)
          .enabled(this.controller.desktopDeviceSyncState === 2 && !this.controller.desktopDeviceSyncSaving)
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.resetDesktopDeviceSyncPreferences();
          })
      }
      .width('100%')
      Text(this.controller.desktopSelectedSpaceDeviceId)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text($r('app.string.desktop_device_send_enabled'))
            .fontSize($r('app.float.font_body_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.desktop_device_send_enabled_note'))
            .fontSize(11)
            .lineHeight(17)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.desktopDeviceSendEnabled })
          .id('desktop-device-sync-send-' + this.desktopDeviceSyncRenderRevision.toString())
          .selectedColor(this.controller.accentColor())
          .enabled(this.controller.desktopDeviceSyncState === 2 && !this.controller.desktopDeviceSyncSaving)
          .onChange((enabled: boolean): void => {
            this.controller.updateDesktopDeviceSyncPreference('send', enabled);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      Row({ space: 12 }) {
        Text($r('app.string.desktop_device_receive_enabled'))
          .fontSize($r('app.float.font_body_large'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.desktopDeviceReceiveEnabled })
          .id('desktop-device-sync-receive-' + this.desktopDeviceSyncRenderRevision.toString())
          .selectedColor(this.controller.accentColor())
          .enabled(this.controller.desktopDeviceSyncState === 2 && !this.controller.desktopDeviceSyncSaving)
          .onChange((enabled: boolean): void => {
            this.controller.updateDesktopDeviceSyncPreference('receive', enabled);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      if (this.controller.desktopDeviceSyncState === 1) {
        Text($r('app.string.desktop_device_sync_loading'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else if (this.controller.desktopDeviceSyncState === 3) {
        Text($r('app.string.desktop_device_sync_failed'))
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .onClick((): void => {
            this.controller.loadDesktopDeviceSyncPreferences(
              this.controller.desktopSelectedSpaceDeviceId);
          })
      }
      Text($r('app.string.desktop_device_send_types'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_text'), 'text')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_image'), 'image')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_file'), 'file')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_link'), 'link')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_rich_text'), 'rich_text')
      Text($r('app.string.desktop_device_receive_types'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 6 })
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_text'), 'receive_text')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_image'), 'receive_image')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_file'), 'receive_file')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_link'), 'receive_link')
      this.compactDeviceContentTypeSwitch($r('app.string.desktop_device_sync_rich_text'),
        'receive_rich_text')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface_muted'))
    .attributeModifier(Api26Material.subtle())
  }


  @Builder
  private desktopPairedDeviceRow(device: EngineRuntimeDevice) {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          this.desktopDeviceTypeGlyph(device.deviceType)
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(13)
        .backgroundColor(this.controller.accentSoftColor())
        .attributeModifier(Api26Material.accentSurface())
        Row()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
          .border({ width: 2, color: $r('app.color.surface_muted') })
      }
      .width(44)
      .height(44)
      Column({ space: 4 }) {
        Text(device.deviceName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          this.desktopDeviceTypeLabel(device.deviceType)
          Text(device.isLocal ? $r('app.string.desktop_this_device') :
            (device.online ? $r('app.string.device_status_online') :
              (device.state === 'unknown' ? $r('app.string.device_status_unknown') :
                $r('app.string.device_status_offline'))))
            .fontSize($r('app.float.font_body_small'))
            .fontColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      if (!device.isLocal) {
        Button(this.controller.spaceConnectingDeviceId === device.deviceId ?
          $r('app.string.desktop_connecting_device') :
          (device.online ? $r('app.string.desktop_device_connected') :
            $r('app.string.desktop_connect_device')), { type: ButtonType.Normal })
          .height(32)
          .fontSize($r('app.float.font_body_small'))
          .fontColor(device.online ? $r('app.color.success') : $r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius($r('app.float.corner_radius_level4'))
          .enabled(!device.online && !this.controller.spaceConnectBusy && !this.controller.desktopDeviceMutationBusy)
          .attributeModifier(Api26Material.interactive())
          .onClick((): void => {
            this.controller.connectSpaceDevice(device);
          })
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 10, right: 12 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor(device.deviceId === this.controller.desktopSelectedSpaceDeviceId ?
      this.controller.accentSoftColor() : $r('app.color.surface_muted'))
    .border({
      width: device.deviceId === this.controller.desktopSelectedSpaceDeviceId ? 1 : 0,
      color: device.deviceId === this.controller.desktopSelectedSpaceDeviceId ?
        this.controller.accentColor() : Color.Transparent
    })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .attributeModifier(Api26Material.interactive())
    .onClick((): void => {
      this.controller.selectDesktopSpaceDevice(device);
    })
    .bindContextMenu(this.desktopPairedDeviceContextMenu(device), ResponseType.LongPress)
  }


  @Builder
  private desktopMobileDeviceRow(device: NativeMobileSyncDevice) {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          SymbolGlyph($r('sys.symbol.phone'))
            .fontSize(24)
            .fontColor([this.controller.accentColor()])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(13)
        .backgroundColor(this.controller.accentSoftColor())
        .attributeModifier(Api26Material.accentSurface())
        Row()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
          .border({ width: 2, color: $r('app.color.surface_muted') })
      }
      .width(44)
      .height(44)
      Column({ space: 4 }) {
        Text(device.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          Text(device.username)
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(device.online ? $r('app.string.device_status_online') :
            (device.lastSeenAtMs > 0 ? $r('app.string.device_status_offline') :
              $r('app.string.device_status_unknown')))
            .fontSize($r('app.float.font_body_small'))
            .fontColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding({ left: 10, right: 12 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor($r('app.color.surface_muted'))
    .attributeModifier(Api26Material.subtle())
    .bindContextMenu(this.desktopMobileDeviceContextMenu(device), ResponseType.LongPress)
  }


  @Builder
  private componentMaterialNavigation() {
    if (this.appearanceComponentMaterialStyle < 0) {
      this.compactNavigation()
    } else if (this.appearanceComponentMaterialStyle === 0) {
      this.compactNavigation()
    } else if (this.appearanceComponentMaterialStyle === 1) {
      this.compactNavigation()
    } else if (this.appearanceComponentMaterialStyle === 2) {
      this.compactNavigation()
    } else if (this.appearanceComponentMaterialStyle === 3) {
      this.compactNavigation()
    } else {
      this.compactNavigation()
    }
  }

  build() {
    Stack() {
      Column()
        .width(1)
        .height(1)
        .opacity(0)
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showOpticalTransferSheet, this.opticalTransferSheet(), {
          detents: [SheetSize.LARGE],
          preferType: SheetType.BOTTOM,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.page_background')
        })
      Stack() {
        Stack() {
          Stack() {
            this.componentMaterialNavigation()
          }
          .width('100%')
          .height('100%')
          .bindSheet($$this.showFeedbackSheet, this.feedbackSheet(), {
            detents: [SheetSize.MEDIUM],
            preferType: SheetType.CENTER,
            dragBar: false,
            showClose: false,
            backgroundColor: $r('app.color.page_background'),
            blurStyle: BlurStyle.Regular,
            onWillDisappear: (): void => {
              this.showFeedbackSheet = false;
            }
          })
        }
        .width('100%')
        .height('100%')
        .bindSheet($$this.showAboutSheet, this.aboutSheet(), {
          detents: [SheetSize.MEDIUM],
          preferType: SheetType.CENTER,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.page_background'),
          blurStyle: BlurStyle.Regular,
          onWillDisappear: (): void => {
            this.showAboutSheet = false;
          }
        })
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showHistoryTagSheet, this.historyTagEditorSheet(), {
        detents: [SheetSize.MEDIUM],
        preferType: SheetType.CENTER,
        dragBar: false,
        backgroundColor: $r('app.color.page_background'),
        onWillDisappear: (): void => {
          this.showHistoryTagSheet = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.controller.pageBackgroundColor())
    .bindSheet($$this.showConnectionDiagnosticsSheet, this.connectionDiagnosticsSheet(), {
      detents: [SheetSize.MEDIUM],
      preferType: SheetType.CENTER,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.page_background'),
      blurStyle: BlurStyle.Regular,
      onWillDisappear: (): void => {
        this.showConnectionDiagnosticsSheet = false;
      }
    })
  }
}
