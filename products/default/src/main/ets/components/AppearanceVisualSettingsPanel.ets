import { ClipboardFeatureController } from 'clipboard_feature';
import { Api26Material } from './Api26Material';

@Component
export struct AppearanceVisualSettingsPanel {
  @State controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();
  @StorageLink('appearanceBackgroundImage') appearanceBackgroundImage: string = '';
  @StorageLink('appearanceBackgroundOpacity') appearanceBackgroundOpacity: number = 0.4;
  @StorageLink('appearanceBackgroundBlur') appearanceBackgroundBlur: number = 8;
  @Prop compact: boolean = true;

  @Builder
  private settingDescription(title: Resource, note: Resource) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(note)
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private backgroundPreview() {
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
      Column({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.ohos_photo'))
          .fontSize(30)
          .fontColor([this.controller.accentColor()])
        Text(this.appearanceBackgroundImage.length > 0 ?
          $r('app.string.appearance_background_preview_applied') :
          $r('app.string.appearance_background_preview_empty'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .padding({ left: 22, right: 22, top: 16, bottom: 16 })
      .borderRadius($r('app.float.corner_radius_level8'))
      .backgroundColor($r('app.color.surface'))
      .attributeModifier(Api26Material.panel())
    }
    .width('100%')
    .height(this.compact ? 148 : 210)
    .clip(true)
    .borderRadius($r('app.float.corner_radius_level8'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private backgroundOpacitySlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.appearance_background_opacity'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(Math.round(this.appearanceBackgroundOpacity * 100).toString() + '%')
          .fontSize($r('app.float.font_body_small'))
          .fontColor(this.controller.accentColor())
      }
      .width('100%')
      Slider({
        value: this.appearanceBackgroundOpacity,
        min: 0.1,
        max: 1,
        step: 0.01,
        style: SliderStyle.InSet
      })
        .width('100%')
        .selectedColor(this.controller.accentColor())
        .trackColor($r('app.color.surface_muted'))
        .showTips(true)
        .onChange((nextValue: number, mode: SliderChangeMode): void => {
          this.appearanceBackgroundOpacity = nextValue;
          this.controller.updateAppearanceBackgroundOpacity(nextValue,
            mode !== SliderChangeMode.Begin && mode !== SliderChangeMode.Moving);
        })
    }
    .width('100%')
  }

  @Builder
  private backgroundBlurSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.appearance_background_blur'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(Math.round(this.appearanceBackgroundBlur).toString())
          .fontSize($r('app.float.font_body_small'))
          .fontColor(this.controller.accentColor())
      }
      .width('100%')
      Slider({
        value: this.appearanceBackgroundBlur,
        min: 0,
        max: 30,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .selectedColor(this.controller.accentColor())
        .trackColor($r('app.color.surface_muted'))
        .showTips(true)
        .onChange((nextValue: number, mode: SliderChangeMode): void => {
          this.appearanceBackgroundBlur = nextValue;
          this.controller.updateAppearanceBackgroundBlur(nextValue,
            mode !== SliderChangeMode.Begin && mode !== SliderChangeMode.Moving);
        })
    }
    .width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.ohos_photo'))
          .fontSize(24)
          .fontColor([this.controller.accentColor()])
        this.settingDescription($r('app.string.appearance_background_title'),
          $r('app.string.appearance_background_note'))
      }
      .width('100%')

      this.backgroundPreview()

      Row({ space: 10 }) {
        Button($r('app.string.appearance_background_select'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .fontColor(this.controller.accentColor())
          .backgroundColor(this.controller.accentSoftColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .attributeModifier(Api26Material.accent())
          .onClick((): void => {
            this.controller.selectAppearanceBackgroundImage();
          })
        if (this.appearanceBackgroundImage.length > 0) {
          Button($r('app.string.appearance_background_clear'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .attributeModifier(Api26Material.interactive())
            .onClick((): void => {
              this.appearanceBackgroundImage = '';
              this.appearanceBackgroundOpacity = 0.4;
              this.appearanceBackgroundBlur = 8;
              this.controller.clearAppearanceBackgroundImage();
            })
        }
      }
      .width('100%')

      if (this.appearanceBackgroundImage.length > 0) {
        this.backgroundOpacitySlider()
        this.backgroundBlurSlider()
      }

      Divider()
        .color($r('app.color.divider'))

      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.rectangle_stack'))
          .fontSize(24)
          .fontColor([this.controller.accentColor()])
        this.settingDescription($r('app.string.appearance_material_level_title'),
          $r('app.string.appearance_material_level_note'))
        Select([
          { value: $r('app.string.appearance_material_exquisite') },
          { value: $r('app.string.appearance_material_gentle') },
          { value: $r('app.string.appearance_material_smooth') },
          { value: $r('app.string.appearance_material_adaptive') }
        ])
          .selected(this.controller.appearanceMaterialLevelIndex())
          .value(this.controller.appearanceMaterialLevelIndex() === 0 ?
            $r('app.string.appearance_material_exquisite') :
            (this.controller.appearanceMaterialLevelIndex() === 1 ?
              $r('app.string.appearance_material_gentle') :
              (this.controller.appearanceMaterialLevelIndex() === 2 ?
                $r('app.string.appearance_material_smooth') :
                $r('app.string.appearance_material_adaptive'))))
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(this.controller.accentColor())
          .selectedOptionBgColor(this.controller.accentSoftColor())
          .onSelect((index: number): void => {
            this.controller.selectAppearanceMaterialLevelByIndex(index);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 58 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.divider'))

      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.rectangle_stack'))
          .fontSize(24)
          .fontColor([this.controller.accentSecondaryColor()])
        this.settingDescription($r('app.string.appearance_component_material_title'),
          $r('app.string.appearance_component_material_note'))
        Select([
          { value: $r('app.string.appearance_component_material_off') },
          { value: $r('app.string.appearance_component_material_ultra_thin') },
          { value: $r('app.string.appearance_component_material_thin') },
          { value: $r('app.string.appearance_component_material_regular') },
          { value: $r('app.string.appearance_component_material_thick') },
          { value: $r('app.string.appearance_component_material_ultra_thick') }
        ])
          .selected(this.controller.appearanceComponentMaterialIndex())
          .value(this.controller.appearanceComponentMaterialLabel())
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(this.controller.accentColor())
          .selectedOptionBgColor(this.controller.accentSoftColor())
          .onSelect((index: number): void => {
            this.controller.selectAppearanceComponentMaterialByIndex(index);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 58 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}
