import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Logger } from '../util/Logger';

const logger: Logger = new Logger('AppearanceStorage');
const STORE_NAME: string = 'appearance_preferences';
const APPEARANCE_MODE_KEY: string = 'appearance_mode';
const APPEARANCE_THEME_KEY: string = 'appearance_theme';
const APPEARANCE_BACKGROUND_IMAGE_KEY: string = 'appearance_background_image';
const APPEARANCE_BACKGROUND_OPACITY_KEY: string = 'appearance_background_opacity';
const APPEARANCE_BACKGROUND_BLUR_KEY: string = 'appearance_background_blur';
const APPEARANCE_MATERIAL_LEVEL_KEY: string = 'appearance_material_level';
const APPEARANCE_COMPONENT_MATERIAL_STYLE_KEY: string = 'appearance_component_material_style';

const DEFAULT_BACKGROUND_OPACITY: number = 0.4;
const DEFAULT_BACKGROUND_BLUR: number = 8;
const DEFAULT_MATERIAL_LEVEL: number = 10;
const DEFAULT_COMPONENT_MATERIAL_STYLE: number = 2;

export const APPEARANCE_MODE_SYSTEM: string = 'system';
export const APPEARANCE_MODE_LIGHT: string = 'light';
export const APPEARANCE_MODE_DARK: string = 'dark';
export const APPEARANCE_THEME_DEFAULT: string = 'harmony_default';

export class AppearanceVisualSettings {
  backgroundImage: string = '';
  backgroundOpacity: number = DEFAULT_BACKGROUND_OPACITY;
  backgroundBlur: number = DEFAULT_BACKGROUND_BLUR;
  materialLevel: number = DEFAULT_MATERIAL_LEVEL;
  componentMaterialStyle: number = DEFAULT_COMPONENT_MATERIAL_STYLE;

  constructor(backgroundImage: string, backgroundOpacity: number, backgroundBlur: number, materialLevel: number,
    componentMaterialStyle: number) {
    this.backgroundImage = backgroundImage;
    this.backgroundOpacity = backgroundOpacity;
    this.backgroundBlur = backgroundBlur;
    this.materialLevel = materialLevel;
    this.componentMaterialStyle = componentMaterialStyle;
  }
}

export class AppearanceStorageService {
  load(context: common.Context): string {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      let mode: string = store.getSync(APPEARANCE_MODE_KEY, APPEARANCE_MODE_SYSTEM) as string;
      if (mode === APPEARANCE_MODE_LIGHT || mode === APPEARANCE_MODE_DARK) {
        return mode;
      }
    } catch (error) {
      logger.error('UniClipboard failed to restore the appearance mode.');
    }
    return APPEARANCE_MODE_SYSTEM;
  }

  save(context: common.Context, mode: string): void {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      store.putSync(APPEARANCE_MODE_KEY, mode);
      store.flushSync();
    } catch (error) {
      logger.error('UniClipboard failed to persist the appearance mode.');
    }
  }

  loadTheme(context: common.Context): string {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      let themeId: string = store.getSync(APPEARANCE_THEME_KEY, APPEARANCE_THEME_DEFAULT) as string;
      if (themeId.length > 0) {
        return themeId;
      }
    } catch (error) {
      logger.error('UniClipboard failed to restore the appearance theme.');
    }
    return APPEARANCE_THEME_DEFAULT;
  }

  saveTheme(context: common.Context, themeId: string): void {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      store.putSync(APPEARANCE_THEME_KEY, themeId);
      store.flushSync();
    } catch (error) {
      logger.error('UniClipboard failed to persist the appearance theme.');
    }
  }

  loadVisualSettings(context: common.Context): AppearanceVisualSettings {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      let backgroundImage: string = store.getSync(APPEARANCE_BACKGROUND_IMAGE_KEY, '') as string;
      let backgroundOpacity: number = store.getSync(
        APPEARANCE_BACKGROUND_OPACITY_KEY, DEFAULT_BACKGROUND_OPACITY) as number;
      let backgroundBlur: number = store.getSync(APPEARANCE_BACKGROUND_BLUR_KEY, DEFAULT_BACKGROUND_BLUR) as number;
      let materialLevel: number = store.getSync(APPEARANCE_MATERIAL_LEVEL_KEY, DEFAULT_MATERIAL_LEVEL) as number;
      let componentMaterialStyle: number = store.getSync(
        APPEARANCE_COMPONENT_MATERIAL_STYLE_KEY, DEFAULT_COMPONENT_MATERIAL_STYLE) as number;
      if (backgroundOpacity < 0.1 || backgroundOpacity > 1) {
        backgroundOpacity = DEFAULT_BACKGROUND_OPACITY;
      }
      if (backgroundBlur < 0 || backgroundBlur > 30) {
        backgroundBlur = DEFAULT_BACKGROUND_BLUR;
      }
      if (materialLevel !== 0 && materialLevel !== 1 && materialLevel !== 2 && materialLevel !== 10) {
        materialLevel = DEFAULT_MATERIAL_LEVEL;
      }
      if (componentMaterialStyle < -1 || componentMaterialStyle > 4) {
        componentMaterialStyle = DEFAULT_COMPONENT_MATERIAL_STYLE;
      }
      return new AppearanceVisualSettings(backgroundImage, backgroundOpacity, backgroundBlur, materialLevel,
        componentMaterialStyle);
    } catch (error) {
      logger.error('UniClipboard failed to restore the visual appearance settings.');
    }
    return new AppearanceVisualSettings('', DEFAULT_BACKGROUND_OPACITY, DEFAULT_BACKGROUND_BLUR,
      DEFAULT_MATERIAL_LEVEL, DEFAULT_COMPONENT_MATERIAL_STYLE);
  }

  saveVisualSettings(context: common.Context, settings: AppearanceVisualSettings): void {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      store.putSync(APPEARANCE_BACKGROUND_IMAGE_KEY, settings.backgroundImage);
      store.putSync(APPEARANCE_BACKGROUND_OPACITY_KEY, settings.backgroundOpacity);
      store.putSync(APPEARANCE_BACKGROUND_BLUR_KEY, settings.backgroundBlur);
      store.putSync(APPEARANCE_MATERIAL_LEVEL_KEY, settings.materialLevel);
      store.putSync(APPEARANCE_COMPONENT_MATERIAL_STYLE_KEY, settings.componentMaterialStyle);
      store.flushSync();
    } catch (error) {
      logger.error('UniClipboard failed to persist the visual appearance settings.');
    }
  }

  getColorMode(mode: string): ConfigurationConstant.ColorMode {
    if (mode === APPEARANCE_MODE_LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    if (mode === APPEARANCE_MODE_DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
}
