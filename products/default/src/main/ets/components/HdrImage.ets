import { ImageModifier } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { uiEffect } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { hdsEffect } from '@kit.UIDesignKit';

const HDR_BRIGHTNESS_RATIO: number = 2.0;

class HdrImageModifier extends ImageModifier {
  private isHdr: boolean = false;
  private pressedHdrFilter: uiEffect.Filter | null = null;
  private pressedPointLightEffect: VisualEffect | null = null;

  constructor(isHdr: boolean) {
    super();
    this.isHdr = isHdr;
    if (deviceInfo.sdkApiVersion >= 20 && canIUse('SystemCapability.UIDesign.HDSComponent.Core')) {
      try {
        let pressedPointLight: hdsEffect.PointLightEffect = {
          sourceType: hdsEffect.PointLightSourceType.BRIGHT,
          illuminatedType: hdsEffect.PointLightIlluminatedType.CONTENT
        };
        this.pressedPointLightEffect = new hdsEffect.HdsEffectBuilder()
          .pointLight(pressedPointLight)
          .buildEffect();
      } catch (error) {
        this.pressedPointLightEffect = null;
      }
    }
    if (this.isHdr && deviceInfo.sdkApiVersion >= 24 && canIUse('SystemCapability.Graphics.Drawing')) {
      try {
        let pressedFilter: uiEffect.Filter = uiEffect.createFilter();
        pressedFilter.hdrBrightnessRatio(HDR_BRIGHTNESS_RATIO);
        this.pressedHdrFilter = pressedFilter;
      } catch (error) {
        this.pressedHdrFilter = null;
      }
    }
  }

  applyPressedAttribute(instance: ImageAttribute): void {
    if (this.pressedPointLightEffect !== null) {
      instance.visualEffect(this.pressedPointLightEffect);
    } else if (deviceInfo.sdkApiVersion >= 12) {
      instance.lightUpEffect(1.0);
    }
    if (!this.isHdr) {
      return;
    }
    if (this.pressedHdrFilter !== null) {
      instance.foregroundFilter(this.pressedHdrFilter);
    } else if (deviceInfo.sdkApiVersion >= 12) {
      instance.dynamicRangeMode(DynamicRangeMode.HIGH);
    }
  }
}

export class HdrImage {
  private static hdrTouchModifier: ImageModifier = new HdrImageModifier(true);
  private static sdrTouchModifier: ImageModifier = new HdrImageModifier(false);

  public static touchContent(pixelMap: image.PixelMap | null): ImageModifier {
    if (pixelMap !== null) {
      try {
        let imageInfo: image.ImageInfo = pixelMap.getImageInfoSync();
        if (imageInfo.isHdr) {
          return HdrImage.hdrTouchModifier;
        }
      } catch (error) {
      }
    }
    return HdrImage.sdrTouchModifier;
  }
}
