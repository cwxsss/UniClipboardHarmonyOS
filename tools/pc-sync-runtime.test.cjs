// Runs actual ArkTS service code with external platform/network boundaries replaced.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('D:/DevEco/DevEco Studio 26.0.0.821/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');

function loader(stubs, globals = {}) {
  const cache = new Map();
  function load(file) {
    if (stubs[file]) return stubs[file];
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} };
    cache.set(file, mod);
    let sourceFile = file;
    if (process.argv.includes('--clipboard-baseline') && file === enginePath('EngineClipboardHost.ets')) {
      sourceFile = 'D:/下载/codedit/UniClipboardHarmonyOS-wx-ime-rc22/common/src/main/ets/engine/EngineClipboardHost.ets';
    }
    if (process.argv.includes('--incoming-baseline') && file.endsWith('ClipboardFeatureController.ets')) {
      sourceFile = 'D:/下载/codedit/UniClipboardHarmonyOS-wx-ime-rc22/features/clipboard/src/main/ets/viewmodel/ClipboardFeatureController.ets';
    }
    const code = ts.transpileModule(fs.readFileSync(sourceFile, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText;
    const context = vm.createContext({ console, Uint8Array, Map, Date, Promise,
      setTimeout, clearTimeout, ...globals });
    const wrapper = vm.runInContext(`(function(require,module,exports){${code}\n})`, context);
    wrapper((name) => {
      if (stubs[name]) return stubs[name];
      if (!name.startsWith('.')) throw new Error(`Unmocked platform boundary: ${name}`);
      const resolved = path.resolve(path.dirname(file), name);
      for (const ext of ['.ets', '.ts']) if (fs.existsSync(resolved + ext)) return load(resolved + ext);
      throw new Error(`Cannot resolve ${name}`);
    }, mod, mod.exports);
    return mod.exports;
  }
  return load;
}
const servicePath = (name) => path.join(root, 'common/src/main/ets/service', name);
const enginePath = (name) => path.join(root, 'common/src/main/ets/engine', name);
const arkUtil = { util: {
  TextEncoder: { create: () => ({ encodeInto: (text) => new TextEncoder().encode(text) }) },
  TextDecoder: { create: () => ({ decodeToString: (bytes) => new TextDecoder().decode(bytes) }) }
}};

test('relay save reports startup failure even when the page has a stale running state', async () => {
  let updates = 0, probes = 0;
  const common = { Logger: class { info() {} warn() {} error() {} },
    EngineRuntimeState: { RUNNING: 'running' },
    engineRuntimeService: {
      getSnapshot: () => ({ state: 'running' }),
      updateNetworkSettings: async (enabled, urls) => {
        updates++; return { allowRelayFallback: enabled, customRelayUrls: urls };
      },
      probeRelayUrl: async () => { probes++; throw new Error('transient probe failure'); }
    } };
  const stubs = { common, '@kit.ArkTS': arkUtil };
  for (const kit of ['ArkUI','AbilityKit','BasicServicesKit','NetworkKit','ScanKit','CoreVisionKit',
    'ImageKit','CoreFileKit','MediaKit','MediaLibraryKit','TelephonyKit','PreviewKit','ShareKit','ArkData','UIDesignKit']) {
    stubs[`@kit.${kit}`] = {};
  }
  const load = loader(stubs, { Observed: type => type });
  const { ClipboardFeatureController } = load(path.join(root,
    'features/clipboard/src/main/ets/viewmodel/ClipboardFeatureController.ets'));
  const controller = Object.create(ClipboardFeatureController.prototype);
  Object.assign(controller, { engineRuntime: common.engineRuntimeService,
    spaceRelaySettingsBusy: false, spaceRelaySettingsState: 0,
    spaceNodeState: 2, spaceRelayFallbackEnabled: true, spaceRelayUrlsText: 'https://relay.chatsss.top',
    ensureOfficialEngineRunning: async () => { throw new Error('UC_ENGINE:1101:unavailable:true'); },
    reportError: () => {} });
  await controller.saveSpaceNetworkSettings();
  assert.equal(controller.spaceRelaySettingsState, 3);
  assert.equal(controller.spaceRelaySettingsBusy, false);
  assert.equal(updates, 0);
  assert.equal(probes, 0);
  controller.ensureOfficialEngineRunning = async () => {};
  controller.refreshSpaceRelayOverview = async () => {};
  controller.spaceNodeState = 3;
  await controller.saveSpaceNetworkSettings();
  assert.equal(controller.spaceRelaySettingsState, 1);
  assert.equal(controller.spaceRelaySettingsBusy, false);
  assert.equal(updates, 1);
  assert.equal(probes, 1);
});

function runtimeHarness() {
  let timerId = 0;
  const timers = new Map();
  const load = loader({
    '@kit.AbilityKit': {}, '@kit.ArkTS': arkUtil, '@kit.CoreFileKit': {},
    '@uniclipboard/engine': {},
    [enginePath('EngineHostAdapter.ets')]: { EngineHostAdapter: class {} },
    [path.join(root, 'common/src/main/ets/util/Logger.ets')]: { Logger: class { info() {} warn() {} error() {} } }
  }, {
    setTimeout: callback => { timers.set(++timerId, callback); return timerId; },
    clearTimeout: id => timers.delete(id)
  });
  const { EngineRuntimeService, EngineRuntimeState, EngineRuntimeError } =
    load(servicePath('EngineRuntimeService.ets'));
  const runtime = EngineRuntimeService.createForTesting({}, {});
  runtime.state = EngineRuntimeState.RUNNING;
  // updateNetworkSettings owns the recovery boundary; keep the test focused on
  // its retry policy by injecting the host adapter and native handle directly.
  const host = { prepareRelayConfiguration: () => {} };
  runtime.host = host;
  // Avoid starting the unrelated event poller after a successful feature call.
  runtime.eventPollTask = Promise.resolve();
  const snapshot = text => ({ observedAtMs: 1,
    representations: [{ kind: 'inline', format: 'text/plain', bytes: new TextEncoder().encode(text) }] });
  return { runtime, timers, snapshot, EngineRuntimeError,
    tick: () => { const [id, callback] = timers.entries().next().value; timers.delete(id); callback(); } };
}

test('relay settings recover one internal transaction failure before succeeding', async () => {
  const h = runtimeHarness(), calls = [];
  let attempts = 0, prepares = 0;
  h.runtime.host.prepareRelayConfiguration = () => { prepares++; };
  h.runtime.handle = { updateNetworkSettings: async (enabled, urls) => {
    attempts++;
    calls.push({ enabled, urls });
    if (attempts === 1) {
      throw new h.EngineRuntimeError('internal', 'update_network_settings', 'stale transaction', 1392, false);
    }
    return { allowRelayFallback: enabled, customRelayUrls: urls };
  }};
  const result = await h.runtime.updateNetworkSettings(true, ['https://relay.chatsss.top']);
  assert.deepEqual(result, { allowRelayFallback: true, customRelayUrls: ['https://relay.chatsss.top'] });
  assert.equal(attempts, 2);
  assert.equal(prepares, 2);
  assert.equal(calls.length, 2);
});

test('persistent internal relay transaction failure is attempted twice and then stops', async () => {
  const h = runtimeHarness();
  let attempts = 0, prepares = 0;
  h.runtime.host.prepareRelayConfiguration = () => { prepares++; };
  h.runtime.handle = { updateNetworkSettings: async () => {
    attempts++;
    throw new h.EngineRuntimeError('internal', 'update_network_settings', 'transaction remains invalid', 1392, true);
  }};
  const failure = await assert.rejects(
    h.runtime.updateNetworkSettings(true, ['https://relay.chatsss.top']),
    error => error instanceof h.EngineRuntimeError && error.category === 'internal' &&
      error.errorCode === 1392 && error.detail === 'transaction remains invalid');
  assert.equal(failure, undefined);
  assert.equal(attempts, 2);
  assert.equal(prepares, 2);
});

test('invalid relay settings are not retried or prepared twice', async () => {
  const h = runtimeHarness();
  let attempts = 0, prepares = 0;
  h.runtime.host.prepareRelayConfiguration = () => { prepares++; };
  h.runtime.handle = { updateNetworkSettings: async () => {
    attempts++;
    throw new h.EngineRuntimeError('bad_request', 'update_network_settings', 'invalid relay URL', 1392, false);
  }};
  await assert.rejects(
    h.runtime.updateNetworkSettings(true, ['not-a-url']),
    error => error instanceof h.EngineRuntimeError && error.category === 'bad_request');
  assert.equal(attempts, 1);
  assert.equal(prepares, 1);
});

test('secondary space startup failure cannot disable the active PC connection and is cleaned up', async () => {
  let cleaned = 0;
  const load = loader({
    '@kit.AbilityKit': {},
    [servicePath('EngineRuntimeService.ets')]: {
      engineRuntimeService: { getProfileId: () => 'main',
        activateProfile: async () => ({ resumed: true, unlocked: true }) },
      EngineRuntimeService: { createForProfile: () => ({
        prepare: async () => {}, start: async () => { throw new Error('secondary offline'); },
        shutdown: async () => { cleaned++; }
      }) }
    },
    [servicePath('SpaceProfileStore.ets')]: {},
    [path.join(root, 'common/src/main/ets/util/Logger.ets')]: { Logger: class { warn() {} } }
  });
  const { SpaceRuntimeSupervisor } = load(servicePath('SpaceRuntimeSupervisor.ets'));
  const supervisor = new SpaceRuntimeSupervisor();
  const result = await supervisor.restore({}, { activeProfileId: () => 'main', profiles: [
    { profileId: 'main', enabled: true, joined: true },
    { profileId: 'secondary', enabled: true, joined: true }
  ] });
  assert.equal(result.resumed, true);
  assert.equal(cleaned, 1);
  assert.equal(supervisor.backgroundRuntimes.size, 0);
});

test('network recovery starts a failed PC connection before notifying native Engine', async () => {
  const calls = [], app = new Map();
  const common = {
    AppearanceStorageService: class {}, BackgroundSyncPreferenceService: class {},
    BackgroundSyncTaskService: class {},
    pcConnectionService: { isEnabled: () => true, isInBackground: () => false,
      ensureActive: async () => { calls.push('start'); } },
    engineRuntimeService: { setClipboardPollingEnabled() {},
      notifyConnectivityOpportunity: async () => { calls.push('notify'); } }
  };
  const load = loader({ common,
    clipboard_feature: {}, '@kit.AbilityKit': { UIAbility: class { context = {}; } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {} } },
    '@kit.ArkUI': {}, '@kit.BasicServicesKit': {}, '@kit.NetworkKit': {}, '@kit.ShareKit': {}
  }, { AppStorage: { get: key => app.get(key) } });
  const { default: EntryAbility } = load(path.join(root, 'products/default/src/main/ets/entryability/EntryAbility.ets'));
  const ability = new EntryAbility();
  ability.networkOpportunityCallback();
  for (let i = 0; i < 15; i++) await Promise.resolve();
  assert.deepEqual(calls, ['start', 'notify']);
});

test('failed automatic copy retries the latest text without resending native queued reports', async () => {
  const h = runtimeHarness(), sent = [];
  let fail = true;
  h.runtime.handle = { sendText: async text => {
    sent.push(text);
    if (fail) throw new Error('capture temporarily failed');
    return { totalAccepted: 0, totalPending: 1, totalOffline: 1, totalErrored: 0 };
  } };
  h.runtime.onClipboardChanged(h.snapshot('A'));
  await h.runtime.clipboardCaptureTask;
  await Promise.resolve();
  assert.equal(h.timers.size, 1);
  fail = false;
  h.runtime.onClipboardChanged(h.snapshot('B'));
  await h.runtime.clipboardCaptureTask;
  await Promise.resolve();
  assert.deepEqual(sent, ['A', 'B']);
  assert.equal(h.timers.size, 0);
  assert.equal(h.runtime.pendingClipboardSnapshot, null);
});

test('retry timer resends a failed copy and shutdown clears the retry', async () => {
  const h = runtimeHarness(), sent = [];
  let fail = true;
  h.runtime.handle = { sendText: async text => {
    sent.push(text);
    if (fail) throw new Error('temporary failure');
    return { totalAccepted: 1, totalPending: 0, totalOffline: 0, totalErrored: 0 };
  } };
  h.runtime.onClipboardChanged(h.snapshot('A'));
  await h.runtime.clipboardCaptureTask;
  await Promise.resolve();
  fail = false;
  h.tick();
  await h.runtime.clipboardCaptureTask;
  await Promise.resolve();
  assert.deepEqual(sent, ['A', 'A']);
  fail = true;
  h.runtime.onClipboardChanged(h.snapshot('C'));
  await h.runtime.clipboardCaptureTask;
  await Promise.resolve();
  h.runtime.clearRuntimeResources();
  assert.equal(h.timers.size, 0);
  assert.equal(h.runtime.pendingClipboardSnapshot, null);
});

test('suspend waits for in-flight copy and resumes the newer pending copy', async () => {
  const h = runtimeHarness(), calls = [];
  let complete;
  h.runtime.handle = {
    sendText: async text => {
      calls.push(text);
      if (text === 'A') await new Promise(resolve => { complete = resolve; });
      return { totalAccepted: 1, totalPending: 0, totalOffline: 0, totalErrored: 0 };
    },
    suspend: async () => { calls.push('suspend'); }, resume: async () => { calls.push('resume'); }
  };
  h.runtime.onClipboardChanged(h.snapshot('A'));
  const suspending = h.runtime.suspend();
  await Promise.resolve();
  h.runtime.onClipboardChanged(h.snapshot('B'));
  assert.deepEqual(calls, ['A']);
  complete();
  await suspending;
  assert.deepEqual(calls, ['A', 'suspend']);
  await h.runtime.resume();
  await h.runtime.clipboardCaptureTask;
  assert.deepEqual(calls, ['A', 'suspend', 'resume', 'B']);
});

test('shutdown drains an in-flight send and leaves no retry task', async () => {
  const h = runtimeHarness(), calls = [];
  let complete;
  h.runtime.host = { shutdown() {} };
  h.runtime.handle = {
    sendText: async () => {
      calls.push('send');
      await new Promise(resolve => { complete = resolve; });
      throw new Error('send failed');
    }, shutdown: async () => { calls.push('shutdown'); }
  };
  h.runtime.onClipboardChanged(h.snapshot('A'));
  const stopping = h.runtime.shutdown();
  await Promise.resolve();
  assert.deepEqual(calls, ['send']);
  complete();
  await stopping;
  assert.deepEqual(calls, ['send', 'shutdown']);
  assert.equal(h.timers.size, 0);
  assert.equal(h.runtime.clipboardCaptureTask, null);
  assert.equal(h.runtime.pendingClipboardSnapshot, null);
});

test('clipboard event reception recovers after a transient poll failure without page activity', async () => {
  const h = runtimeHarness(), events = [];
  let attempts = 0;
  const handle = { nextEvent: async () => {
    attempts++;
    if (attempts === 1) throw new Error('temporary event failure');
    h.runtime.eventPolling = false;
    return { kind: 'active_clipboard_changed' };
  } };
  h.runtime.handle = handle;
  h.runtime.eventPolling = true;
  h.runtime.eventObservers = [{ onEngineRuntimeEvent: event => events.push(event.kind) }];
  const task = h.runtime.pollEvents(handle);
  for (let i = 0; i < 10 && h.timers.size === 0; i++) await Promise.resolve();
  h.tick();
  // Stop only after delivering the recovered event.
  handle.nextEvent = async () => {
    attempts++;
    if (attempts === 2) return { kind: 'active_clipboard_changed' };
    h.runtime.eventPolling = false; return null;
  };
  await task;
  assert.deepEqual(events, ['active_clipboard_changed']);
  assert.equal(h.runtime.eventPolling, false);
});

function connectionHarness(saved = 'uniclipboard') {
  const preferences = saved === null ? new Map() : new Map([['mode', saved]]);
  const app = new Map(), calls = [];
  let state = 'stopped', failStart = false, startGate = null;
  const load = loader({
    '@kit.AbilityKit': {},
    '@kit.ArkData': { preferences: { getPreferencesSync: () => ({
      getSync: (key, fallback) => preferences.get(key) ?? fallback,
      putSync: (key, value) => preferences.set(key, value), flushSync: () => {}
    }) } },
    [servicePath('EngineRuntimeService.ets')]: {
      EngineRuntimeState: { SUSPENDED: 'suspended', RUNNING: 'running' },
      engineRuntimeService: { getSnapshot: () => ({ state }),
        resume: async () => { calls.push('resume'); state = 'running'; } }
    },
    [servicePath('SpaceRuntimeSupervisor.ets')]: { spaceRuntimeSupervisor: {
      shutdown: async () => { calls.push('stop'); state = 'stopped'; },
      restore: async () => {
        calls.push('start');
        if (startGate) await startGate;
        if (failStart) throw new Error('network unavailable');
        state = 'running'; return { resumed: true };
      }
    } },
    [servicePath('SpaceProfileStore.ets')]: { SpaceProfileStore: class { load() { return {}; } } },
    [servicePath('BackgroundSyncService.ets')]: { BackgroundSyncPreferenceService: class {
      save(_, enabled) { app.set('savedBackgroundEnabled', enabled); }
    } }
  }, { AppStorage: { setOrCreate: (key, value) => app.set(key, value) } });
  const { PcConnectionService } = load(servicePath('PcConnectionService.ets'));
  return { service: new PcConnectionService(), preferences, app, calls,
    setState: value => { state = value; }, setGate: value => { startGate = value; },
    failStart: value => { failStart = value; } };
}

test('obsolete WeChat selection migrates to the sole UniClipboard channel', async () => {
  const h = connectionHarness('wx-ime');
  await h.service.ensureActive({});
  assert.equal(h.preferences.get('mode'), 'uniclipboard');
  assert.equal(h.service.isEnabled(), true);
  assert.equal(h.app.get('spaceJoined'), true);
  assert.equal(h.app.get('backgroundSyncEnabled'), true);
});

test('concurrent starts share one operation and foreground resumes without resetting identity', async () => {
  const h = connectionHarness(null);
  await Promise.all([h.service.ensureActive({}), h.service.ensureActive({})]);
  assert.equal(h.calls.filter(value => value === 'start').length, 1);
  await h.service.ensureActive({});
  assert.equal(h.calls.filter(value => value === 'start').length, 1);
  h.setState('suspended');
  await Promise.all([h.service.ensureActive({}), h.service.ensureActive({})]);
  assert.equal(h.calls.filter(value => value === 'resume').length, 1);
  assert.equal(h.calls.filter(value => value === 'stop').length, 1);
});

test('failed startup can retry and stopped work uses a new connection generation', async () => {
  const h = connectionHarness();
  h.failStart(true);
  await assert.rejects(h.service.ensureActive({}), /network unavailable/);
  h.failStart(false);
  await h.service.ensureActive({});
  const oldGeneration = h.service.getGeneration();
  await h.service.shutdown({});
  assert.equal(h.service.isEnabled(), false);
  await h.service.ensureActive({});
  assert.equal(h.service.isEnabled(), true);
  assert.ok(h.service.getGeneration() > oldGeneration);
});

test('shutdown drains a pending start and leaves clipboard traffic blocked', async () => {
  const h = connectionHarness();
  let release;
  h.setGate(new Promise(resolve => { release = resolve; }));
  const starting = h.service.ensureActive({});
  await Promise.resolve();
  await Promise.resolve();
  const stopping = h.service.shutdown({});
  assert.equal(h.service.isEnabled(), false);
  release();
  await Promise.all([starting, stopping]);
  assert.equal(h.service.isEnabled(), false);
  assert.equal(h.calls.at(-1), 'stop');
});
function clipboardHarness(initialReadDenied = false) {
  let value = 'old', changeCount = 0, rejectWrite = false;
  let rejectRead = initialReadDenied;
  const updates = [];
  function data(text) { return { getRecordCount: () => 1,
    getRecord: () => ({ toPlainText: () => text }), getPrimaryText: () => text,
    getPrimaryUri: () => '' }; }
  const board = {
    getDataSync: () => { if (rejectRead) throw new Error('read permission denied'); return data(value); },
    getChangeCount: () => changeCount,
    setDataSync: (next) => {
      if (rejectWrite) throw { code: 201 };
      value = next.getPrimaryText(); changeCount++;
      for (const callback of updates) callback();
    },
    on: (_, callback) => updates.push(callback), off: () => {}
  };
  const load = loader({
    '@kit.BasicServicesKit': { pasteboard: { getSystemPasteboard: () => board,
      createData: (_, text) => data(text), MIMETYPE_TEXT_PLAIN: 'text/plain' } },
    '@kit.ArkTS': arkUtil,
    [path.join(root, 'common/src/main/ets/util/Logger.ets')]: { Logger: class {
      info() {} warn() {} error() {}
    } }
  });
  const { EngineClipboardHost } = load(enginePath('EngineClipboardHost.ets'));
  const host = new EngineClipboardHost();
  const observed = [];
  host.listen({ onClipboardChanged: (snapshot) => {
    observed.push(new TextDecoder().decode(snapshot.representations[0].bytes));
  } });
  return { host, observed, current: () => value, reject: (flag) => { rejectWrite = flag; },
    grantRead: () => { rejectRead = false; },
    localCopy: (text) => board.setDataSync(data(text)),
    remote: (text) => host.write({ observedAtMs: 1, representations: [{
      kind: 'inline', format: 'text/plain', bytes: new TextEncoder().encode(text) }] }) };
}

test('first explicit copy after permission grant is sent even when initial baseline read failed', () => {
  const h = clipboardHarness(true);
  h.grantRead();
  h.localCopy('first phone copy');
  assert.deepEqual(h.observed, ['first phone copy']);
});

test('passive polling after permission grant does not send an old clipboard value', () => {
  const h = clipboardHarness(true);
  h.grantRead();
  h.host.notifyClipboardChange();
  assert.deepEqual(h.observed, []);
});

test('remote text becomes pasteable without being sent back, and later local copy is observed', () => {
  const h = clipboardHarness();
  h.remote('from PC');
  assert.equal(h.current(), 'from PC');
  assert.deepEqual(h.observed, []);
  h.localCopy('from phone');
  assert.deepEqual(h.observed, ['from phone']);
});

test('failed platform write remains retryable and does not corrupt the capture baseline', () => {
  const h = clipboardHarness();
  h.reject(true);
  assert.throws(() => h.remote('from PC'));
  assert.equal(h.current(), 'old');
  h.reject(false);
  h.remote('from PC');
  assert.equal(h.current(), 'from PC');
  assert.deepEqual(h.observed, []);
});

test('UniClipboard marks an incoming entry handled only after its text is actually pasteable', async () => {
  let rejectWrite = true, clipboard = 'old', writes = 0, histories = 0;
  const active = { entryId: 'pc-message', activatedBy: 'pc-device' };
  const common = {
    Logger: class { info() {} warn() {} error() {} },
    pcConnectionService: { isEnabled: () => true, getGeneration: () => 1 },
    engineRuntimeService: {
      queryActiveClipboard: async () => active,
      writeIncomingClipboardText: async (text) => {
        writes++;
        if (rejectWrite) throw new Error('platform denied write');
        clipboard = text;
      }
    }
  };
  const stubs = { common, '@kit.ArkTS': arkUtil };
  for (const kit of ['ArkUI', 'AbilityKit', 'BasicServicesKit', 'NetworkKit', 'ScanKit', 'CoreVisionKit',
    'ImageKit', 'CoreFileKit', 'MediaKit', 'MediaLibraryKit', 'TelephonyKit', 'PreviewKit', 'ShareKit',
    'ArkData', 'UIDesignKit']) stubs[`@kit.${kit}`] = {};
  const load = loader(stubs, { Observed: (type) => type });
  const { ClipboardFeatureController } = load(path.join(root,
    'features/clipboard/src/main/ets/viewmodel/ClipboardFeatureController.ets'));
  const controller = Object.create(ClipboardFeatureController.prototype);
  Object.assign(controller, {
    spaceJoined: true, lastOfficialActiveEntryId: '', desktopSelectedId: 'selected',
    incomingFileNamesByEntry: new Map(),
    clipboardService: { readFile: () => ({ data: new TextEncoder().encode('from PC') }),
      writeText: common.engineRuntimeService.writeIncomingClipboardText },
    ensureOfficialEngineRunning: async () => {},
    exportOfficialEngineEntry: async () => 'private-test-file',
    tryDecodeOfficialEngineImage: async () => null,
    isOfficialEngineLocalDevice: () => false,
    addHistory: () => { histories++; }, notifyReceivedContent: () => {}, animateLatestContent: () => {}
  });
  assert.equal(await controller.consumeOfficialEngineClipboard(), false);
  assert.equal(controller.lastOfficialActiveEntryId, '');
  assert.equal(clipboard, 'old');
  assert.equal(histories, 0);
  rejectWrite = false;
  assert.equal(await controller.consumeOfficialEngineClipboard(), true);
  assert.equal(clipboard, 'from PC');
  assert.equal(controller.lastOfficialActiveEntryId, 'pc-message');
  assert.equal(histories, 1);
  assert.equal(await controller.consumeOfficialEngineClipboard(), false);
  assert.equal(writes, 2);
});

test('permission denial during relay preflight does not retry or write configuration', async () => {
  const h = runtimeHarness();
  let prepares = 0, writes = 0;
  h.runtime.host.prepareRelayConfiguration = () => {
    prepares++;
    throw new h.EngineRuntimeError('permission_denied', 'update_network_settings');
  };
  h.runtime.handle = { updateNetworkSettings: async () => { writes++; } };
  await assert.rejects(h.runtime.updateNetworkSettings(true, []), error => error.category === 'permission_denied');
  assert.equal(prepares, 1);
  assert.equal(writes, 0);
});

test('relay configuration is not retried when the runtime stops after a failed write', async () => {
  const h = runtimeHarness();
  let attempts = 0;
  h.runtime.host.prepareRelayConfiguration = () => {};
  h.runtime.handle = { updateNetworkSettings: async () => {
    attempts++;
    h.runtime.state = 'suspended';
    throw new h.EngineRuntimeError('internal', 'update_network_settings', '', 1392, true);
  }};
  await assert.rejects(h.runtime.updateNetworkSettings(true, []));
  assert.equal(attempts, 1);
});
