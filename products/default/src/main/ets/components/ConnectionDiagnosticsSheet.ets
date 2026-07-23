import {
  hdsMaterial,
  HdsNavigation,
  HdsNavigationTitleMode,
  IconStyleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { ClipboardFeatureController } from 'clipboard_feature';

@Component
export struct ConnectionDiagnosticsSheet {
  @Link visible: boolean;
  @State controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();
  private scroller: Scroller = new Scroller();

  @Builder
  private transportValue() {
    if (this.controller.connectionDiagnosticDirectCount > 0 &&
      this.controller.connectionDiagnosticRelayCount > 0) {
      Text($r('app.string.connection_diagnostics_transport_mixed'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticDirectCount > 0) {
      Text($r('app.string.connection_diagnostics_transport_direct'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.success'))
    } else if (this.controller.connectionDiagnosticRelayCount > 0) {
      Text($r('app.string.connection_diagnostics_transport_relay'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.controller.accentColor())
    } else if (this.controller.connectionDiagnosticUnknownCount > 0) {
      Text($r('app.string.connection_diagnostics_transport_unknown'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
    } else {
      Text($r('app.string.connection_diagnostics_transport_offline'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.danger'))
    }
  }

  @Builder
  private networkValue() {
    if (this.controller.connectionDiagnosticNetworkType === 'wifi') {
      Text($r('app.string.connection_diagnostics_network_wifi'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticNetworkType === 'cellular') {
      Text($r('app.string.connection_diagnostics_network_cellular'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticNetworkType === 'ethernet') {
      Text($r('app.string.connection_diagnostics_network_ethernet'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticNetworkType === 'vpn') {
      Text($r('app.string.connection_diagnostics_network_vpn'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticNetworkType === 'bluetooth') {
      Text($r('app.string.connection_diagnostics_network_bluetooth'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticNetworkType === 'other') {
      Text($r('app.string.connection_diagnostics_network_other'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else {
      Text($r('app.string.connection_diagnostics_network_unavailable'))
        .fontSize(14)
        .fontColor($r('app.color.danger'))
    }
  }

  @Builder
  private lastFailureValue() {
    if (this.controller.connectionDiagnosticLastFailure === 'network_unavailable') {
      Text($r('app.string.connection_diagnostics_failure_network'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'permission_unavailable') {
      Text($r('app.string.connection_diagnostics_failure_permission'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'node_unavailable') {
      Text($r('app.string.connection_diagnostics_failure_node'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'space_not_joined') {
      Text($r('app.string.connection_diagnostics_failure_space'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'no_peer') {
      Text($r('app.string.connection_diagnostics_failure_no_peer'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'peer_offline') {
      Text($r('app.string.connection_diagnostics_failure_peer_offline'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'relay_probe_failed') {
      Text($r('app.string.connection_diagnostics_failure_relay'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'space_probe_failed') {
      Text($r('app.string.connection_diagnostics_failure_probe'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else if (this.controller.connectionDiagnosticLastFailure === 'not_configured') {
      Text($r('app.string.connection_diagnostics_failure_not_configured'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    } else {
      Text($r('app.string.connection_diagnostics_failure_none'))
        .fontSize(14)
        .fontColor($r('app.color.success'))
    }
  }

  @Builder
  private permissionRow(label: Resource, granted: boolean) {
    Row({ space: 10 }) {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(granted ? $r('app.color.success') : $r('app.color.danger'))
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(granted ? $r('app.string.connection_diagnostics_permission_granted') :
        $r('app.string.connection_diagnostics_permission_denied'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(granted ? $r('app.color.success') : $r('app.color.danger'))
    }
    .width('100%')
    .height(42)
  }

  @Builder
  private pathCount(value: number, label: Resource, color: ResourceColor) {
    Column({ space: 3 }) {
      Text(value.toString())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 18 }) {
          Blank()
            .width('100%')
            .height(55)
        Column({ space: 7 }) {
          Row({ space: 12 }) {
            Column() {
              SymbolGlyph($r('sys.symbol.connection'))
                .fontSize(26)
                .fontColor([this.controller.accentColor()])
            }
            .width(48)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .borderRadius(15)
            .backgroundColor(this.controller.accentSoftColor())
            Column({ space: 4 }) {
              Text($r('app.string.connection_diagnostics_title'))
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.connection_diagnostics_subtitle'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          if (this.controller.connectionDiagnosticBusy) {
            Text($r('app.string.connection_diagnostics_refreshing'))
              .fontSize(12)
              .fontColor(this.controller.accentColor())
              .width('100%')
          }
        }
        .width('100%')

        Column({ space: 0 }) {
          Row() {
            Text($r('app.string.connection_diagnostics_transport_label'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            this.transportValue()
          }
          .width('100%')
          .height(44)
          Row() {
            Text($r('app.string.connection_diagnostics_latency_label'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            if (this.controller.connectionDiagnosticLatencyMs >= 0) {
              Row({ space: 4 }) {
                Text(this.controller.connectionDiagnosticLatencyMs.toString())
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.connection_diagnostics_latency_unit'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
              }
            } else {
              Text($r('app.string.connection_diagnostics_latency_unavailable'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .width('100%')
          .height(44)
          .border({ width: { top: 1 }, color: $r('app.color.divider') })
          Row() {
            Text($r('app.string.connection_diagnostics_network_label'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            this.networkValue()
          }
          .width('100%')
          .height(44)
          .border({ width: { top: 1 }, color: $r('app.color.divider') })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))

        Row() {
          this.pathCount(this.controller.connectionDiagnosticDirectCount,
            $r('app.string.connection_diagnostics_path_direct'), $r('app.color.success'))
          this.pathCount(this.controller.connectionDiagnosticRelayCount,
            $r('app.string.connection_diagnostics_path_relay'), this.controller.accentColor())
          this.pathCount(this.controller.connectionDiagnosticOfflineCount,
            $r('app.string.connection_diagnostics_path_offline'), $r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })

        Column({ space: 0 }) {
          Text($r('app.string.connection_diagnostics_failure_label'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Row() {
            this.lastFailureValue()
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .padding(16)
        .borderRadius($r('app.float.corner_radius_level10'))
        .border({ width: 1, color: $r('app.color.divider') })

        Column({ space: 0 }) {
          Text($r('app.string.connection_diagnostics_permissions_title'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 4 })
          this.permissionRow($r('app.string.connection_diagnostics_permission_internet'),
            this.controller.connectionDiagnosticInternetGranted)
          this.permissionRow($r('app.string.connection_diagnostics_permission_background'),
            this.controller.connectionDiagnosticBackgroundGranted)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))

        Text($r('app.string.connection_diagnostics_redaction_note'))
          .fontSize(11)
          .lineHeight(17)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Row({ space: 12 }) {
          Button($r('app.string.connection_diagnostics_refresh_action'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(46)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(!this.controller.connectionDiagnosticBusy)
            .onClick((): void => {
              this.controller.refreshConnectionDiagnostics();
            })
          Button(this.controller.connectionDiagnosticExportState === 1 ?
            $r('app.string.connection_diagnostics_exporting') :
            $r('app.string.connection_diagnostics_export_action'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(46)
            .fontSize(14)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.controller.accentColor())
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(this.controller.connectionDiagnosticExportState !== 1)
            .onClick((): void => {
              this.controller.exportRedactedConnectionDiagnostics();
            })
        }
        .width('100%')
        if (this.controller.connectionDiagnosticExportState === 2) {
          Text($r('app.string.connection_diagnostics_export_ready'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        } else if (this.controller.connectionDiagnosticExportState === 3) {
          Text($r('app.string.connection_diagnostics_export_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 30 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.connection_diagnostics_title')
        },
        menu: {
          value: [{
            content: {
              label: 'modal_cancel',
              isEnabled: true,
              type: IconStyleMode.SMALL,
              action: (): void => {
                this.visible = false;
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
          materialLevel: this.controller.aboutMaterialLevel
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }
}
