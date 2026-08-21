import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { EngineHostError, EngineHostErrorCategory } from './EngineHostError';

const ASSET_NOT_FOUND: number = 24000002;
const ASSET_ALREADY_EXISTS: number = 24000003;
const ALIAS_PREFIX: string = 'app.uniclipboard.engine.v1-1.';

export class EngineSecureAssetStore {
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');

  get(key: string): Uint8Array | null {
    try {
      let results: asset.AssetMap[] = asset.querySync(this.query(key, true));
      if (results.length === 0) {
        return null;
      }
      let value: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (value instanceof Uint8Array) {
        return new Uint8Array(value);
      }
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    } catch (error) {
      if (this.errorCode(error as Object) === ASSET_NOT_FOUND) {
        return null;
      }
      if (error instanceof EngineHostError) {
        throw error;
      }
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    }
  }

  set(key: string, value: Uint8Array): void {
    let secret: Uint8Array = new Uint8Array(value);
    try {
      try {
        let update: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        update.set(asset.Tag.SECRET, secret);
        asset.updateSync(this.query(key, false), update);
      } catch (error) {
        if (this.errorCode(error as Object) !== ASSET_NOT_FOUND) {
          throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
        }
        this.addOrUpdate(key, secret);
      }
    } finally {
      secret.fill(0);
    }
  }

  delete(key: string): void {
    try {
      asset.removeSync(this.query(key, false));
    } catch (error) {
      if (this.errorCode(error as Object) !== ASSET_NOT_FOUND) {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_delete');
      }
    }
  }

  verifyAccess(): void {
    let key: string = 'probe-' + util.generateRandomUUID();
    let expected: Uint8Array = new Uint8Array([0x55, 0x43, 0x01]);
    try {
      this.set(key, expected);
      let actual: Uint8Array | null = this.get(key);
      if (actual === null || actual.length !== expected.length) {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_verify');
      }
      for (let index: number = 0; index < expected.length; index += 1) {
        if (actual[index] !== expected[index]) {
          throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_verify');
        }
      }
      actual.fill(0);
    } finally {
      expected.fill(0);
      this.delete(key);
    }
  }

  private addOrUpdate(key: string, secret: Uint8Array): void {
    try {
      let attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      attributes.set(asset.Tag.ALIAS, this.alias(key));
      attributes.set(asset.Tag.SECRET, secret);
      attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      asset.addSync(attributes);
    } catch (error) {
      if (this.errorCode(error as Object) !== ASSET_ALREADY_EXISTS) {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
      }
      try {
        let update: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        update.set(asset.Tag.SECRET, secret);
        asset.updateSync(this.query(key, false), update);
      } catch (updateError) {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
      }
    }
  }

  private query(key: string, includeSecret: boolean): asset.AssetMap {
    let query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.alias(key));
    if (includeSecret) {
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      query.set(asset.Tag.RETURN_LIMIT, 1);
    }
    return query;
  }

  private alias(key: string): Uint8Array {
    return this.encoder.encodeInto(ALIAS_PREFIX + key);
  }

  private errorCode(error: Object): number {
    return (error as BusinessError).code;
  }
}
