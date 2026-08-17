import { ClipboardFeatureController } from 'clipboard_feature';

import { Api26Material } from './Api26Material';
@Component
export struct LinkPreviewCard {
  @State controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();
  @State glowOffsetX: number = -48;
  @State keywordOpacity: number = 0;
  @State keywordOffsetY: number = 8;
  @State arrowScale: number = 0.94;
  private animationTimerId: number = -1;

  aboutToAppear(): void {
    this.animationTimerId = setTimeout((): void => {
      this.getUIContext().animateTo({
        duration: 3600,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, (): void => {
        this.glowOffsetX = 48;
        this.arrowScale = 1.06;
      });
      this.getUIContext().animateTo({
        duration: 420,
        curve: Curve.EaseOut
      }, (): void => {
        this.keywordOpacity = 1;
        this.keywordOffsetY = 0;
      });
    }, 80);
  }

  aboutToDisappear(): void {
    if (this.animationTimerId >= 0) {
      clearTimeout(this.animationTimerId);
      this.animationTimerId = -1;
    }
  }

  private fallbackKeywords(): string[] {
    if (this.controller.linkPreview !== null && this.controller.linkPreview.keywords.length > 0) {
      return this.controller.linkPreview.keywords;
    }
    let keywords: string[] = [];
    keywords.push(this.controller.currentLinkUrl());
    return keywords;
  }

  @Builder
  private fallbackArtwork() {
    Stack() {
      Row()
        .width(170)
        .height(170)
        .borderRadius(85)
        .backgroundColor($r('app.color.on_accent'))
        .opacity(0.14)
        .translate({ x: this.glowOffsetX, y: -46 })
      Row()
        .width(92)
        .height(92)
        .borderRadius(46)
        .backgroundColor($r('app.color.on_accent'))
        .opacity(0.1)
        .translate({ x: -this.glowOffsetX * 0.55, y: 48 })
      Column({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(30)
          .fontColor([$r('app.color.on_accent')])
          .opacity(0.92)
        Row({ space: 7 }) {
          ForEach(this.fallbackKeywords(), (keyword: string) => {
            Text(keyword)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_accent'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 86 })
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius($r('app.float.corner_radius_level10'))
              .backgroundColor($r('app.color.link_preview_keyword_background'))
              .attributeModifier(Api26Material.subtle())
          }, (keyword: string): string => keyword)
        }
      }
      .opacity(this.keywordOpacity)
      .translate({ y: this.keywordOffsetY })
    }
    .width('100%')
    .height(154)
    .renderGroup(true)
  }

  build() {
    Column() {
      Stack() {
        if (this.controller.linkPreview !== null && this.controller.linkPreview.imageUrl.length > 0 &&
          this.controller.linkPreviewState === 2) {
          Image(this.controller.linkPreview.imageUrl)
            .width('100%')
            .height(154)
            .objectFit(ImageFit.Cover)
            .onError((): void => {
              this.controller.markLinkPreviewImageFailed();
            })
        } else {
          Stack() {
            this.fallbackArtwork()
          }
            .width('100%')
            .height(154)
            .linearGradient({
              colors: [[this.controller.accentColor(), 0], [this.controller.accentSecondaryColor(), 1]]
            })
        }
        if (this.controller.linkPreviewState === 1) {
          Text($r('app.string.link_preview_loading'))
            .fontSize(12)
            .fontColor($r('app.color.on_accent'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius($r('app.float.corner_radius_level10'))
            .backgroundColor($r('app.color.card_image_overlay'))
        }
      }
      .width('100%')
      .height(154)
      .borderRadius($r('app.float.corner_radius_level8'))
      .clip(true)
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.controller.linkPreview !== null && this.controller.linkPreview.title.length > 0 ?
            this.controller.linkPreview.title : this.controller.currentLinkUrl())
            .fontSize($r('app.float.font_body_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.controller.linkPreview !== null && this.controller.linkPreview.siteName.length > 0 ?
            this.controller.linkPreview.siteName : this.controller.currentLinkUrl())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.controller.linkPreview !== null && this.controller.linkPreview.description.length > 0) {
            Text(this.controller.linkPreview.description)
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_forward'))
          .fontSize(20)
          .fontColor([this.controller.accentColor()])
          .scale({ x: this.arrowScale, y: this.arrowScale })
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 12, bottom: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface_muted'))
    .attributeModifier(Api26Material.interactive())
    .hoverEffect(HoverEffect.Scale)
    .onClick((): void => {
      this.controller.openCurrentLink();
    })
  }
}
