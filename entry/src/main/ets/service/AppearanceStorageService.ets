import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'appearance_preferences';
const APPEARANCE_MODE_KEY: string = 'appearance_mode';

export const APPEARANCE_MODE_SYSTEM: string = 'system';
export const APPEARANCE_MODE_LIGHT: string = 'light';
export const APPEARANCE_MODE_DARK: string = 'dark';

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
      console.error('UniClipboard failed to restore the appearance mode.');
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
      console.error('UniClipboard failed to persist the appearance mode.');
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
