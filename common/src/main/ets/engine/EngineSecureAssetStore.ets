import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { EngineHostError, EngineHostErrorCategory } from './EngineHostError';

const ASSET_NOT_FOUND: number = 24000002;
const ASSET_ALREADY_EXISTS: number = 24000003;
const ALIAS_PREFIX: string = 'app.uniclipboard.engine.v1-1.';
const LEGACY_PROFILE_ID: string = '.engine-v1-1';
const MAX_ASSET_SECRET_BYTES: number = 1024;
const MAX_ALIAS_BYTES: number = 256;
const MAX_CHUNK_COUNT: number = 1_000_000;
const INDEX_SUFFIX: string = '.uc-index-v1';
const CHUNK_ALIAS_PREFIX: string = 'chunk.';
const INDEX_MAGIC: number[] = [0x55, 0x43, 0x41, 0x31];
const INDEX_VERSION: number = 1;
const UUID_BYTES: number = 36;

interface AssetChunkIndex {
  generation: string;
  count: number;
  length: number;
}

export class EngineSecureAssetStore {
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private profileId: string;

  constructor(profileId: string = LEGACY_PROFILE_ID) {
    this.profileId = profileId;
  }

  get(key: string): Uint8Array | null {
    try {
      let index: Uint8Array | null = this.readAsset(this.indexQuery(key, true));
      if (index !== null) {
        return this.readChunkedValue(key, index);
      }
      let results: asset.AssetMap[] = asset.querySync(this.query(key, true));
      if (results.length === 0) {
        return null;
      }
      let value: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (value instanceof Uint8Array) {
        return new Uint8Array(value);
      }
      console.error('[secure-asset] invalid stage=1');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    } catch (error) {
      if (this.errorCode(error as Object) === ASSET_NOT_FOUND) {
        return null;
      }
      if (error instanceof EngineHostError) {
        throw error;
      }
      console.error('[secure-asset] invalid stage=2');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    }
  }

  set(key: string, input: Uint8Array): void {
    // N-API Buffer may arrive as ArrayBuffer; normalize before reading length.
    let value: Uint8Array = new Uint8Array(new Uint8Array(input));
    let generation: string = util.generateRandomUUID();
    let written: number = 0;
    let published: boolean = false;
    let previousIndex: Uint8Array | null = this.readAsset(this.indexQuery(key, true));
    let previousMetadata: AssetChunkIndex | null = previousIndex === null ? null : this.decodeIndex(previousIndex);
    let index: Uint8Array = this.encodeIndex(generation, Math.max(1, Math.ceil(value.length / MAX_ASSET_SECRET_BYTES)), value.length);
    try {
      for (let offset: number = 0; offset < value.length || (value.length === 0 && offset === 0); offset += MAX_ASSET_SECRET_BYTES) {
        let end: number = Math.min(offset + MAX_ASSET_SECRET_BYTES, value.length);
        let chunk: Uint8Array = value.length === 0 ? new Uint8Array([0]) : value.slice(offset, end);
        try {
          this.addChunk(generation, written, chunk);
        } finally {
          chunk.fill(0);
        }
        written += 1;
      }
      // The index is the publication point. Until this succeeds, readers keep
      // seeing the old index/direct value and the new chunks are unreachable.
      this.addOrUpdateIndex(key, index);
      published = true;
      try {
        this.deleteDirectValue(key);
      } catch (error) {
        // The new index already wins reads; an unreachable legacy value is
        // cleanup and must not turn a successful publication into a failure.
      }
      if (previousMetadata !== null && previousMetadata.generation !== generation) {
        this.cleanupChunks(previousMetadata.generation, previousMetadata.count);
      }
    } finally {
      value.fill(0);
      index.fill(0);
      if (!published && written > 0) {
        this.cleanupChunks(generation, written);
      }
      if (previousIndex !== null) {
        previousIndex.fill(0);
      }
    }
  }

  delete(key: string): void {
    // Remove the legacy direct value first. Removing the index first would
    // make a crash resurrect that direct value through the compatibility path.
    this.deleteDirectValue(key);
    let index: Uint8Array | null = this.readAsset(this.indexQuery(key, true));
    if (index === null) {
      return;
    }
    let metadata = this.decodeIndex(index);
    index.fill(0);
    this.removeAsset(this.indexQuery(key, false), 'secure_storage_delete');
    this.cleanupChunks(metadata.generation, metadata.count);
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

  private readAsset(query: asset.AssetMap): Uint8Array | null {
    try {
      let results: asset.AssetMap[] = asset.querySync(query);
      if (results.length === 0) {
        return null;
      }
      let value: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (value instanceof Uint8Array) {
        return new Uint8Array(value);
      }
      console.error('[secure-asset] invalid stage=3');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    } catch (error) {
      if (this.errorCode(error as Object) === ASSET_NOT_FOUND) {
        return null;
      }
      if (error instanceof EngineHostError) {
        throw error;
      }
      console.error('[secure-asset] invalid stage=4');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    }
  }

  private addChunk(generation: string, index: number, secret: Uint8Array): void {
    if (secret.length > MAX_ASSET_SECRET_BYTES) {
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
    }
    let attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, this.chunkAlias(generation, index));
    attributes.set(asset.Tag.SECRET, secret);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      asset.addSync(attributes);
    } catch (error) {
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
    }
  }

  private addOrUpdateIndex(key: string, secret: Uint8Array): void {
    try {
      let update: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      update.set(asset.Tag.SECRET, secret);
      asset.updateSync(this.indexQuery(key, false), update);
      return;
    } catch (error) {
      if (this.errorCode(error as Object) !== ASSET_NOT_FOUND) {
        console.error('[secure-asset] failed code=' + this.errorCode(error as Object));
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
      }
    }
    let attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, this.indexAlias(key));
    attributes.set(asset.Tag.SECRET, secret);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      asset.addSync(attributes);
    } catch (error) {
      if (this.errorCode(error as Object) !== ASSET_ALREADY_EXISTS) {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
      }
      try {
        let update: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        update.set(asset.Tag.SECRET, secret);
        asset.updateSync(this.indexQuery(key, false), update);
      } catch (updateError) {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
      }
    }
  }

  private deleteDirectValue(key: string): void {
    this.removeAsset(this.query(key, false), 'secure_storage_delete');
  }

  private removeAsset(query: asset.AssetMap, operation: string): void {
    try {
      asset.removeSync(query);
    } catch (error) {
      if (this.errorCode(error as Object) !== ASSET_NOT_FOUND) {
        console.error('[secure-asset] failed code=' + this.errorCode(error as Object));
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, operation);
      }
    }
  }

  private cleanupChunks(generation: string, count: number): void {
    if (count < 0 || count > MAX_CHUNK_COUNT) {
      return;
    }
    for (let index: number = 0; index < count; index += 1) {
      try {
        this.removeAsset(this.chunkQuery(generation, index, false), 'secure_storage_delete');
      } catch (error) {
        // A published value must not be reported as failed because an old,
        // unreachable chunk could not be deleted.
      }
    }
  }

  private readChunkedValue(key: string, index: Uint8Array): Uint8Array | null {
    let metadata = this.decodeIndex(index);
    if (metadata.count === 0) {
      if (key !== 'relay_configuration:transaction:v1') {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_empty_index');
      }
      // The affected versions published an empty transaction marker but never
      // wrote its payload. Keep persisted settings; there is no record to replay.
      this.removeAsset(this.indexQuery(key, false), 'secure_storage_repair_empty_transaction');
      console.warn('[secure-asset] removed empty transaction index from affected version');
      return null;
    }
    let value: Uint8Array = new Uint8Array(metadata.length);
    let offset: number = 0;
    try {
      for (let chunkIndex: number = 0; chunkIndex < metadata.count; chunkIndex += 1) {
        let chunk: Uint8Array | null = this.readAsset(this.chunkQuery(metadata.generation, chunkIndex, true));
        if (chunk === null || chunk.length < 1 || chunk.length > MAX_ASSET_SECRET_BYTES || (metadata.length > 0 && offset + chunk.length > value.length)) {
          console.error('[secure-asset] invalid stage=5');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
        }
        if (metadata.length > 0) {
          value.set(chunk, offset);
          offset += chunk.length;
        } else if (metadata.count !== 1 || chunk.length !== 1) {
          console.error('[secure-asset] invalid stage=6');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
        }
        chunk.fill(0);
      }
      if (offset !== metadata.length) {
        console.error('[secure-asset] invalid stage=7');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
      }
      return value;
    } catch (error) {
      value.fill(0);
      if (error instanceof EngineHostError) {
        throw error;
      }
      console.error('[secure-asset] invalid stage=8');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    }
  }

  private encodeIndex(generation: string, count: number, length: number): Uint8Array {
    if (generation.length !== UUID_BYTES || count < 1 || count > MAX_CHUNK_COUNT || length < 0 || length > count * MAX_ASSET_SECRET_BYTES) {
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_set');
    }
    let encoded: Uint8Array = new Uint8Array(INDEX_MAGIC.length + 1 + UUID_BYTES + 8);
    encoded.set(INDEX_MAGIC, 0);
    encoded[4] = INDEX_VERSION;
    let generationBytes: Uint8Array = this.encoder.encodeInto(generation);
    encoded.set(generationBytes, 5);
    this.writeU32(encoded, 5 + UUID_BYTES, count);
    this.writeU32(encoded, 9 + UUID_BYTES, length);
    return encoded;
  }

  private decodeIndex(encoded: Uint8Array): AssetChunkIndex {
    if (encoded.length !== INDEX_MAGIC.length + 1 + UUID_BYTES + 8 || encoded[4] !== INDEX_VERSION) {
      console.error('[secure-asset] invalid stage=9');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    }
    for (let index: number = 0; index < INDEX_MAGIC.length; index += 1) {
      if (encoded[index] !== INDEX_MAGIC[index]) {
        console.error('[secure-asset] invalid stage=10');
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
      }
    }
    let generationBytes: Uint8Array = encoded.slice(5, 5 + UUID_BYTES);
    let generation: string = this.decoder.decodeToString(generationBytes);
    let count: number = this.readU32(encoded, 5 + UUID_BYTES);
    let length: number = this.readU32(encoded, 9 + UUID_BYTES);
    if (generation.length === UUID_BYTES && count === 0 && length === 0) {
      return this.recoverLegacyChunkIndex(generation);
    }
    if (generation.length !== UUID_BYTES || count < 1 || count > MAX_CHUNK_COUNT || length > count * MAX_ASSET_SECRET_BYTES) {
      console.error('[secure-asset] invalid stage=11 uuidLength=' + generation.length + ' count=' + count + ' totalLength=' + length);
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_get');
    }
    return { generation, count, length };
  }

  // Versions 1.0.16–1.0.19 published valid UUIDs but zero integer fields.
  // Recover the retained chunks; native transaction parsing still validates
  // the reconstructed record before restoring any settings.
  private recoverLegacyChunkIndex(generation: string): AssetChunkIndex {
    let length: number = 0;
    for (let count: number = 0; count < 65536; count += 1) {
      let chunk: Uint8Array | null = this.readAsset(this.chunkQuery(generation, count, true));
      if (chunk === null) {
        if (count > 0) {
          return { generation, count, length };
        }
        return { generation, count: 0, length: 0 };
      }
      let size: number = chunk.length;
      chunk.fill(0);
      if (size < 1 || size > MAX_ASSET_SECRET_BYTES) {
        throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_legacy_chunk_size');
      }
      length += size;
      if (size < MAX_ASSET_SECRET_BYTES) {
        return { generation, count: count + 1, length };
      }
    }
    throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_legacy_chunk_limit');
  }
  private writeU32(target: Uint8Array, offset: number, value: number): void {
    new DataView(target.buffer, target.byteOffset, target.byteLength).setUint32(offset, value, false);
  }

  private readU32(source: Uint8Array, offset: number): number {
    return new DataView(source.buffer, source.byteOffset, source.byteLength).getUint32(offset, false);
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

  private indexQuery(key: string, includeSecret: boolean): asset.AssetMap {
    let query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.indexAlias(key));
    if (includeSecret) {
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      query.set(asset.Tag.RETURN_LIMIT, 1);
    }
    return query;
  }

  private chunkQuery(generation: string, index: number, includeSecret: boolean): asset.AssetMap {
    let query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.chunkAlias(generation, index));
    if (includeSecret) {
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      query.set(asset.Tag.RETURN_LIMIT, 1);
    }
    return query;
  }

  private indexAlias(key: string): Uint8Array {
    return this.alias(key + INDEX_SUFFIX);
  }

  private chunkAlias(generation: string, index: number): Uint8Array {
    return this.alias(CHUNK_ALIAS_PREFIX + generation + '.' + index, false);
  }

  private alias(key: string, scoped: boolean = true): Uint8Array {
    let scope: string = this.profileId === LEGACY_PROFILE_ID ? '' : 'profile.' + this.profileId + '.';
    let alias: Uint8Array = this.encoder.encodeInto(ALIAS_PREFIX + (scoped ? scope : '') + key);
    if (alias.length > MAX_ALIAS_BYTES) {
      throw new EngineHostError(EngineHostErrorCategory.UNAVAILABLE, 'secure_storage_alias');
    }
    return alias;
  }

  private errorCode(error: Object): number {
    return (error as BusinessError).code;
  }
}
