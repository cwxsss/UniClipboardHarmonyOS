import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { ServerConfig } from '../model/ClipboardModels';

const STORE_NAME: string = 'connection_config';
const SERVER_URL_KEY: string = 'server_url';
const USERNAME_ALIAS: string = 'uniclipboard_username';
const PASSWORD_ALIAS: string = 'uniclipboard_password';

export class ConfigStorageService {
  load(context: common.Context): ServerConfig {
    let storeOptions: preferences.Options = { name: STORE_NAME };
    let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
    let config: ServerConfig = {
      baseUrl: store.getSync(SERVER_URL_KEY, '') as string,
      username: this.readAsset(USERNAME_ALIAS),
      password: this.readAsset(PASSWORD_ALIAS)
    };
    return config;
  }

  save(context: common.Context, config: ServerConfig): void {
    let storeOptions: preferences.Options = { name: STORE_NAME };
    let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
    store.putSync(SERVER_URL_KEY, config.baseUrl.trim());
    store.flushSync();
    this.writeAsset(USERNAME_ALIAS, config.username);
    this.writeAsset(PASSWORD_ALIAS, config.password);
  }

  private encode(value: string): Uint8Array {
    let encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(value);
  }

  private readAsset(alias: string): string {
    let query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      let results: asset.AssetMap[] = asset.querySync(query);
      if (results.length === 0) {
        return '';
      }
      let secret: Uint8Array = results[0].get(asset.Tag.SECRET) as Uint8Array;
      let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(secret);
    } catch (error) {
      return '';
    }
  }

  private writeAsset(alias: string, value: string): void {
    let query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(alias));
    try {
      asset.removeSync(query);
    } catch (error) {
    }
    let attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.encode(alias));
    attributes.set(asset.Tag.SECRET, this.encode(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    asset.addSync(attributes);
  }
}
