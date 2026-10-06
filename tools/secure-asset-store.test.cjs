const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('D:/DevEco/DevEco Studio 26.0.0.821/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');

const root = path.resolve(__dirname, '..');
const sourcePath = process.argv.includes('--baseline')
  ? 'D:/下载/codedit/UniClipboardHarmonyOS-wx-ime-rc22/common/src/main/ets/engine/EngineSecureAssetStore.ets'
  : path.join(root, 'common/src/main/ets/engine/EngineSecureAssetStore.ets');
const NOT_FOUND = 24000002;
const ALREADY_EXISTS = 24000003;

function createAssetMock() {
  const records = new Map();
  const calls = { adds: [], updates: [], removes: [] };
  const controls = { failUpdate: false, failRemove: false, failAddAt: null };
  const Tag = { ALIAS: 'alias', SECRET: 'secret', ACCESSIBILITY: 'accessibility', RETURN_TYPE: 'returnType', RETURN_LIMIT: 'returnLimit' };
  const aliasOf = query => new TextDecoder().decode(query.get(Tag.ALIAS));
  const clone = bytes => new Uint8Array(bytes);
  const asset = {
    Tag,
    ReturnType: { ALL: 'all' },
    Accessibility: { DEVICE_FIRST_UNLOCKED: 'first' },
    querySync(query) {
      const value = records.get(aliasOf(query));
      if (value === undefined) return [];
      return query.has(Tag.RETURN_TYPE) ? [new Map([[Tag.SECRET, clone(value)]])] : [new Map()];
    },
    addSync(attributes) {
      const alias = new TextDecoder().decode(attributes.get(Tag.ALIAS));
      const secret = attributes.get(Tag.SECRET);
      calls.adds.push({ alias, size: secret.length });
      if (controls.failAddAt !== null && calls.adds.length === controls.failAddAt) throw { code: 1904 };
      if (secret.length < 1 || secret.length > 1024) throw { code: 1711 };
      if (records.has(alias)) throw { code: ALREADY_EXISTS };
      records.set(alias, clone(secret));
    },
    updateSync(query, update) {
      const alias = aliasOf(query);
      calls.updates.push(alias);
      if (controls.failUpdate) throw { code: 1901 };
      if (!records.has(alias)) throw { code: NOT_FOUND };
      const secret = update.get(Tag.SECRET);
      if (secret.length < 1 || secret.length > 1024) throw { code: 1711 };
      records.set(alias, clone(secret));
    },
    removeSync(query) {
      const alias = aliasOf(query);
      calls.removes.push(alias);
      if (query.has(Tag.RETURN_TYPE) || query.has(Tag.RETURN_LIMIT)) throw { code: 1903 };
      if (controls.failRemove) throw { code: 1902 };
      if (!records.delete(alias)) throw { code: NOT_FOUND };
    }
  };
  return { asset, records, calls, controls, aliasOf };
}

function loadStore(mock) {
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const context = vm.createContext({ console, Uint8Array, Map, Object, String, Math });
  const wrapper = vm.runInContext(`(function(require,module,exports){${code}\n})`, context);
  wrapper(name => {
    if (name === '@kit.AssetStoreKit') return mock;
    if (name === '@kit.BasicServicesKit') return {};
    if (name === '@kit.ArkTS') return { util: {
      TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) },
      TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) },
      generateRandomUUID: (() => { let n = 0; return () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`; })()
    } };
    if (name.endsWith('./EngineHostError')) {
      return { EngineHostError: class EngineHostError extends Error {
        constructor(category, operation) { super(operation); this.category = category; }
      }, EngineHostErrorCategory: { UNAVAILABLE: 'unavailable' } };
    }
    throw new Error(`Unmocked import ${name}`);
  }, module, module.exports);
  return module.exports.EngineSecureAssetStore;
}

function bytes(length, seed) {
  const value = new Uint8Array(length);
  for (let i = 0; i < value.length; i += 1) value[i] = (i * 17 + seed) & 0xff;
  return value;
}

function assertBytes(actual, expected) {
  assert.deepEqual(Array.from(actual), Array.from(expected));
}

test('1711-byte relay transaction is rejected by old code and chunked by current code', () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  const value = bytes(1711, 7);
  if (process.argv.includes('--baseline')) {
    assert.throws(() => store.set('relay_configuration:transaction:v1', value));
    return;
  }
  store.set('relay_configuration:transaction:v1', value);
  assertBytes(store.get('relay_configuration:transaction:v1'), value);
  assert.ok(mock.calls.adds.some(call => call.size === 1024));
  assert.ok(mock.calls.adds.every(call => call.size >= 1 && call.size <= 1024));
});

test('legacy direct asset remains readable', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const value = bytes(17, 3);
  mock.records.set('app.uniclipboard.engine.v1-1.legacy-direct', value);
  assertBytes(new Store().get('legacy-direct'), value);
});

test('failed publication keeps the old value and removes unpublished chunks', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  const oldValue = bytes(1711, 11);
  const newValue = bytes(1711, 19);
  store.set('relay', oldValue);
  const before = mock.records.size;
  mock.controls.failUpdate = true;
  assert.throws(() => store.set('relay', newValue));
  mock.controls.failUpdate = false;
  assertBytes(store.get('relay'), oldValue);
  assert.equal(mock.records.size, before);
});

test('second chunk failure keeps a legacy direct value and removes the first chunk', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  const oldValue = bytes(17, 41);
  mock.records.set('app.uniclipboard.engine.v1-1.legacy-failure', oldValue);
  mock.controls.failAddAt = 2;
  assert.throws(() => store.set('legacy-failure', bytes(1711, 43)));
  mock.controls.failAddAt = null;
  assertBytes(store.get('legacy-failure'), oldValue);
  assert.equal(mock.records.size, 1);
  assert.equal(mock.calls.adds.filter(call => call.alias.startsWith('app.uniclipboard.engine.v1-1.chunk.')).length, 2);
});

test('overwrite and delete publish through the index', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  const oldValue = bytes(1300, 23);
  const newValue = bytes(3, 29);
  store.set('relay', oldValue);
  store.set('relay', newValue);
  assertBytes(store.get('relay'), newValue);
  store.delete('relay');
  assert.equal(store.get('relay'), null);
});

test('old chunk cleanup failure does not fail a published write', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  store.set('relay', bytes(1300, 31));
  mock.controls.failRemove = true;
  store.set('relay', bytes(1300, 37));
  mock.controls.failRemove = false;
  assertBytes(store.get('relay'), bytes(1300, 37));
});

test('empty values round-trip and verifyAccess uses the same protocol', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  store.set('empty', new Uint8Array(0));
  assert.equal(store.get('empty').length, 0);
  store.verifyAccess();
  assert.equal(store.get('empty').length, 0);
});

test('zero integer fields from 1.0.16 are recovered from retained chunks', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  const value = bytes(1711, 43);
  store.set('relay_configuration:transaction:v1', value);
  const marker = [...mock.records.keys()].find(key => key.endsWith('.uc-index-v1'));
  mock.records.get(marker).fill(0, 41, 49);
  assertBytes(store.get('relay_configuration:transaction:v1'), value);
  store.delete('relay_configuration:transaction:v1');
  assert.equal(mock.records.size, 0);
});

test('native ArrayBuffer input is normalized before chunk lengths are computed', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  const value = bytes(1711, 51);
  store.set('relay_configuration:transaction:v1', value.buffer);
  assertBytes(store.get('relay_configuration:transaction:v1'), value);
});

test('empty transaction marker from affected versions is repaired without touching other assets', { skip: process.argv.includes('--baseline') }, () => {
  const mock = createAssetMock();
  const Store = loadStore(mock);
  const store = new Store();
  store.set('relay_configuration:transaction:v1', bytes(1711, 59));
  const marker = [...mock.records.keys()].find(key => key.endsWith('.uc-index-v1'));
  mock.records.get(marker).fill(0, 41, 49);
  for (const key of [...mock.records.keys()]) if (key.includes('.chunk.')) mock.records.delete(key);
  mock.records.set('unrelated', bytes(11, 1));
  assert.equal(store.get('relay_configuration:transaction:v1'), null);
  assert.equal(mock.records.size, 1);
  assert.equal(mock.records.has('unrelated'), true);
});
