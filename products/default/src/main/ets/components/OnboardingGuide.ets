import { Api26Material } from './Api26Material';

const ONBOARDING_PAGE_COUNT: number = 4;

@Component
export struct OnboardingGuide {
  @Link visible: boolean;
  @State currentIndex: number = 0;
  private swiperController: SwiperController = new SwiperController();
  onCompleted: () => void = (): void => {};

  aboutToAppear(): void {
    this.currentIndex = 0;
  }

  private nextPage(): void {
    if (this.currentIndex >= ONBOARDING_PAGE_COUNT - 1) {
      this.finishGuide();
      return;
    }
    this.swiperController.changeIndex(this.currentIndex + 1, true);
  }

  private finishGuide(): void {
    this.visible = false;
    this.onCompleted();
  }

  @Builder
  private GuideText(title: Resource, description: Resource) {
    Column({ space: 10 }) {
      Text(title)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      Text(description)
        .fontSize(15)
        .lineHeight(23)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(4)
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
  }

  @Builder
  private WelcomeVisual() {
    Stack() {
      Column()
        .width(238)
        .height(238)
        .borderRadius(119)
        .backgroundColor($r('app.color.accent_soft'))
        .attributeModifier(Api26Material.accentSurface())
      Column()
        .width(174)
        .height(174)
        .borderRadius(87)
        .backgroundColor($r('app.color.accent_medium'))
        .attributeModifier(Api26Material.accentSurface())
      Image($r('app.media.uniclipboard_start_icon'))
        .width(112)
        .height(112)
        .borderRadius(28)
        .objectFit(ImageFit.Cover)
        .shadow({ radius: 22, color: '#26000000', offsetY: 10 })
        .draggable(false)
    }
    .width(260)
    .height(260)
  }

  @Builder
  private DeviceCard(icon: Resource, label: Resource) {
    Column({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(42)
        .fontWeight(FontWeight.Medium)
        .fontColor([$r('app.color.accent')])
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width(118)
    .height(132)
    .justifyContent(FlexAlign.Center)
    .borderRadius(24)
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
    .border({ width: 1, color: $r('app.color.divider') })
    .shadow({ radius: 18, color: '#14000000', offsetY: 8 })
  }

  @Builder
  private SyncVisual() {
    Column({ space: 18 }) {
      Row({ space: 10 }) {
        this.DeviceCard($r('sys.symbol.phone'), $r('app.string.onboarding_device_phone'))
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
            .fontSize(34)
            .fontColor([$r('app.color.accent')])
          Text($r('app.string.onboarding_encrypted'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width(74)
        .alignItems(HorizontalAlign.Center)
        this.DeviceCard($r('sys.symbol.desktop'), $r('app.string.onboarding_device_computer'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.checkmark_shield_fill'))
          .fontSize(18)
          .fontColor([$r('app.color.success')])
        Text($r('app.string.onboarding_trusted_devices'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor($r('app.color.surface_muted'))
      .attributeModifier(Api26Material.subtle())
    }
    .width('100%')
  }

  @Builder
  private HistoryItem(icon: Resource, title: Resource, note: Resource) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor([$r('app.color.accent')])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor($r('app.color.accent_soft'))
      .attributeModifier(Api26Material.accentSurface())
      Column({ space: 3 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text(note)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(58)
  }

  @Builder
  private HistoryVisual() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
        Text($r('app.string.onboarding_search_placeholder'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .borderRadius(14)
      .backgroundColor($r('app.color.surface_muted'))
      .attributeModifier(Api26Material.subtle())
      this.HistoryItem($r('sys.symbol.doc_text'), $r('app.string.onboarding_history_text'),
        $r('app.string.onboarding_history_text_note'))
      this.HistoryItem($r('sys.symbol.ohos_photo'), $r('app.string.onboarding_history_image'),
        $r('app.string.onboarding_history_image_note'))
      this.HistoryItem($r('sys.symbol.doc_zipper'), $r('app.string.onboarding_history_file'),
        $r('app.string.onboarding_history_file_note'))
    }
    .width(320)
    .padding(16)
    .borderRadius(24)
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
    .border({ width: 1, color: $r('app.color.divider') })
    .shadow({ radius: 20, color: '#14000000', offsetY: 8 })
  }

  @Builder
  private PrivacyFeature(icon: Resource, label: Resource) {
    Column({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(28)
        .fontWeight(FontWeight.Medium)
        .fontColor([$r('app.color.accent')])
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .layoutWeight(1)
    .height(108)
    .justifyContent(FlexAlign.Center)
    .borderRadius(20)
    .backgroundColor($r('app.color.surface'))
    .attributeModifier(Api26Material.panel())
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private PrivacyVisual() {
    Column({ space: 18 }) {
      Stack() {
        Column()
          .width(132)
          .height(132)
          .borderRadius(42)
          .backgroundColor($r('app.color.accent_soft'))
          .attributeModifier(Api26Material.accentSurface())
        SymbolGlyph($r('sys.symbol.lock_shield_fill'))
          .fontSize(62)
          .fontColor([$r('app.color.accent')])
      }
      .width(148)
      .height(148)

      Row({ space: 10 }) {
        this.PrivacyFeature($r('sys.symbol.clipboard_sharing'), $r('app.string.onboarding_feature_clipboard'))
        this.PrivacyFeature($r('sys.symbol.ohos_photo'), $r('app.string.onboarding_feature_image'))
        this.PrivacyFeature($r('sys.symbol.folder'), $r('app.string.onboarding_feature_file'))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14 })
  }

  @Builder
  private WelcomePage() {
    Column({ space: 18 }) {
      Blank()
      this.WelcomeVisual()
      this.GuideText($r('app.string.onboarding_welcome_title'),
        $r('app.string.onboarding_welcome_description'))
      Blank()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SyncPage() {
    Column({ space: 24 }) {
      Blank()
      this.SyncVisual()
      this.GuideText($r('app.string.onboarding_sync_title'),
        $r('app.string.onboarding_sync_description'))
      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private HistoryPage() {
    Column({ space: 24 }) {
      Blank()
      this.HistoryVisual()
      this.GuideText($r('app.string.onboarding_history_title'),
        $r('app.string.onboarding_history_description'))
      Blank()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PrivacyPage() {
    Column({ space: 20 }) {
      Blank()
      this.PrivacyVisual()
      this.GuideText($r('app.string.onboarding_privacy_title'),
        $r('app.string.onboarding_privacy_description'))
      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PageDot(index: number) {
    Row()
      .width(this.currentIndex === index ? 22 : 8)
      .height(8)
      .borderRadius(4)
      .backgroundColor(this.currentIndex === index ? $r('app.color.accent') : $r('app.color.divider'))
      .attributeModifier(Api26Material.accentSurface())
      .animation({ duration: 220, curve: Curve.EaseOut })
  }

  build() {
    Column() {
      Row() {
        Blank()
        if (this.currentIndex < ONBOARDING_PAGE_COUNT - 1) {
          Button($r('app.string.onboarding_skip'), { type: ButtonType.Normal })
            .height(38)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .attributeModifier(Api26Material.accent())
            .onClick((): void => {
              this.finishGuide();
            })
        } else {
          Blank()
            .width(72)
        }
      }
      .width('100%')
      .height(48)
      .padding({ left: 18, right: 18 })

      Swiper(this.swiperController) {
        this.WelcomePage()
        this.SyncPage()
        this.HistoryPage()
        this.PrivacyPage()
      }
      .layoutWeight(1)
      .width('100%')
      .index(this.currentIndex)
      .indicator(false)
      .loop(false)
      .onChange((index: number): void => {
        this.currentIndex = index;
      })

      Row({ space: 7 }) {
        this.PageDot(0)
        this.PageDot(1)
        this.PageDot(2)
        this.PageDot(3)
      }
      .height(22)
      .justifyContent(FlexAlign.Center)

      Button(this.currentIndex === ONBOARDING_PAGE_COUNT - 1 ?
        $r('app.string.onboarding_start') : $r('app.string.onboarding_next'), { type: ButtonType.Normal })
        .width('62%')
        .constraintSize({ minWidth: 220, maxWidth: 360 })
        .height(50)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Api26Material.accentTextColor())
        .backgroundColor($r('app.color.accent'))
        .borderRadius(16)
        .margin({ top: 10, bottom: 18 })
        .attributeModifier(Api26Material.accent())
        .onClick((): void => {
          this.nextPage();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
