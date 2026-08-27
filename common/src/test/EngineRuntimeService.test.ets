import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  EngineHostCallbacks,
  EngineHostResult
} from '../main/ets/engine/EngineHostAdapter';
import {
  EngineRuntimeBackend,
  EngineActiveClipboard,
  EngineInvitationIssued,
  EngineMemberSyncPreferences,
  EngineNetworkSettings,
  EngineRuntimeEvent,
  EngineRuntimeHandle,
  EngineRuntimeHost,
  EngineSendReport,
  EngineSessionRecovery,
  EngineSpaceCreated,
  EngineSpaceJoined,
  EngineRuntimeService,
  EngineRuntimeStartConfig,
  EngineRuntimeState,
  EngineWorkspaceConvergence,
  normalizeMemberSyncPreferences
} from '../main/ets/service/EngineRuntimeService';
import { EngineClipboardObserver, EngineClipboardSnapshot } from '../main/ets/engine/EngineClipboardHost';
import { EngineFileMetadata } from '../main/ets/engine/EngineFileHandleRegistry';

class TestHostCallbacks implements EngineHostCallbacks {
  privateDataDirectory: string = '/test/data';
  cacheDirectory: string = '/test/cache';
  temporaryDirectory: string = '/test/temp';

  secureStorageGet(key: string): EngineHostResult<Uint8Array | null> {
    return { ok: true, value: null };
  }

  secureStorageSet(key: string, value: Uint8Array): EngineHostResult<void> {
    return { ok: true };
  }

  secureStorageDelete(key: string): EngineHostResult<void> {
    return { ok: true };
  }

  fileMetadata(handle: string): EngineHostResult<EngineFileMetadata> {
    let metadata: EngineFileMetadata = { displayName: 'test', sizeBytes: '0' };
    return { ok: true, value: metadata };
  }

  fileReadChunk(handle: string, offset: string, maxBytes: number): EngineHostResult<Uint8Array> {
    return { ok: true, value: new Uint8Array(0) };
  }

  fileWriteChunk(handle: string, offset: string, bytes: Uint8Array): EngineHostResult<void> {
    return { ok: true };
  }

  fileFinishWrite(handle: string): EngineHostResult<void> {
    return { ok: true };
  }

  clipboardRead(): EngineHostResult<EngineClipboardSnapshot> {
    let snapshot: EngineClipboardSnapshot = { observedAtMs: 0, representations: [] };
    return { ok: true, value: snapshot };
  }

  clipboardWrite(snapshot: EngineClipboardSnapshot): EngineHostResult<void> {
    return { ok: true };
  }
}

class TestRuntimeHost implements EngineRuntimeHost {
  shutdownCount: number = 0;
  clipboardPollingEnabled: boolean = false;

  prepare(context: common.UIAbilityContext): EngineHostCallbacks {
    return new TestHostCallbacks();
  }

  listenClipboard(observer: EngineClipboardObserver): void {
  }

  releaseClipboardListener(): void {
  }

  setClipboardPollingEnabled(enabled: boolean): void {
    this.clipboardPollingEnabled = enabled;
  }

  registerInputFile(uri: string, mimeType: string): string {
    return 'test-input';
  }

  registerOutputFile(uri: string, mimeType: string): string {
    return 'test-output';
  }

  releaseFile(handle: string): void {
  }

  shutdown(): void {
    this.shutdownCount += 1;
  }
}

class TestRuntimeHandle implements EngineRuntimeHandle {
  suspendCount: number = 0;
  resumeCount: number = 0;
  recoverNetworkCount: number = 0;
  recoverSessionCount: number = 0;
  deferSessionRecovery: boolean = false;
  shutdownCount: number = 0;
  nextEventCount: number = 0;
  failJoin: boolean = false;
  sendTextCount: number = 0;
  lastSentText: string = '';
  lastSendTargets: string[] = [];
  deviceTrustSnapshot: string = '{}';
  private eventResolver: ((event: EngineRuntimeEvent | null) => void) | null = null;
  private eventRejecter: ((reason: Object) => void) | null = null;
  private recoveryResolver: ((recovery: EngineSessionRecovery) => void) | null = null;

  async lifecycleState(): Promise<string> {
    return 'running';
  }

  async suspend(): Promise<void> {
    this.suspendCount += 1;
  }

  async resume(): Promise<void> {
    this.resumeCount += 1;
  }

  async recoverNetwork(): Promise<void> {
    this.recoverNetworkCount += 1;
  }

  async queryNetworkSettings(): Promise<EngineNetworkSettings> {
    return new EngineNetworkSettings(true, []);
  }

  async updateNetworkSettings(allowRelayFallback: boolean, customRelayUrls: string[]):
    Promise<EngineNetworkSettings> {
    return new EngineNetworkSettings(allowRelayFallback, customRelayUrls.slice());
  }

  async probeRelayUrl(url: string): Promise<number> {
    return 1;
  }

  nextEvent(timeoutMs: number): Promise<EngineRuntimeEvent | null> {
    this.nextEventCount += 1;
    return new Promise<EngineRuntimeEvent | null>((resolve: (event: EngineRuntimeEvent | null) => void,
      reject: (reason: Object) => void): void => {
      this.eventResolver = resolve;
      this.eventRejecter = reject;
    });
  }

  rejectPendingEvent(reason: Object): void {
    let rejecter: ((reason: Object) => void) | null = this.eventRejecter;
    this.eventResolver = null;
    this.eventRejecter = null;
    if (rejecter !== null) {
      rejecter(reason);
    }
  }

  async shutdown(deadlineMs: number): Promise<void> {
    this.shutdownCount += 1;
    let resolver: ((event: EngineRuntimeEvent | null) => void) | null = this.eventResolver;
    this.eventResolver = null;
    this.eventRejecter = null;
    if (resolver !== null) {
      resolver(null);
    }
  }

  async createSpace(deviceName: string | null, passphrase: string): Promise<EngineSpaceCreated> {
    return new EngineSpaceCreated('space', 'device', 'fingerprint');
  }

  async recoverSession(allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery> {
    this.recoverSessionCount += 1;
    if (this.deferSessionRecovery) {
      return await new Promise<EngineSessionRecovery>(
        (resolve: (recovery: EngineSessionRecovery) => void): void => {
          this.recoveryResolver = resolve;
        });
    }
    return new EngineSessionRecovery(true, true);
  }

  completeSessionRecovery(): void {
    let resolver: ((recovery: EngineSessionRecovery) => void) | null = this.recoveryResolver;
    this.recoveryResolver = null;
    if (resolver !== null) {
      resolver(new EngineSessionRecovery(true, true));
    }
  }

  async issueInvitation(): Promise<EngineInvitationIssued> {
    return new EngineInvitationIssued('invitation', 1, 'cross_network');
  }

  async joinSpace(invitationCode: string, deviceName: string | null, passphrase: string,
    preserveUnreadableHistory: boolean): Promise<EngineSpaceJoined> {
    if (this.failJoin) {
      throw new Error('invitation not found');
    }
    return new EngineSpaceJoined('sponsor', 'fingerprint', 'space', 'device', 'self-fingerprint',
      undefined, undefined);
  }

  async sendText(text: string, targetDevices: string[]): Promise<EngineSendReport> {
    this.sendTextCount += 1;
    this.lastSentText = text;
    this.lastSendTargets = targetDevices.slice();
    return new EngineSendReport('entry', 1, 1, 0, 0, 0, 0);
  }

  async sendImage(bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<EngineSendReport> {
    return new EngineSendReport('entry', 1, 1, 0, 0, 0, 0);
  }

  async sendFiles(fileHandles: string[], targetDevices: string[]): Promise<EngineSendReport> {
    return new EngineSendReport('entry', 1, 1, 0, 0, 0, 0);
  }

  async captureCurrentClipboard(): Promise<string | null> {
    return 'entry';
  }

  async queryActiveClipboard(): Promise<EngineActiveClipboard | null> {
    return new EngineActiveClipboard('entry', 'device');
  }

  async queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return new EngineMemberSyncPreferences(true, true, true, true, true, true, true,
      false, true, false, true, false, true, false);
  }

  async updateMemberSendPreferences(deviceId: string, sendEnabled: boolean, text: boolean, imageEnabled: boolean,
    file: boolean, link: boolean, richText: boolean): Promise<EngineMemberSyncPreferences> {
    return new EngineMemberSyncPreferences(sendEnabled, text, imageEnabled, file, link, true, richText,
      false, true, false, true, false, true, false);
  }

  async resetMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return new EngineMemberSyncPreferences(true, true, true, true, true, true, true);
  }

  async restoreClipboard(entryId: string, mode: string): Promise<string> {
    return 'restored';
  }

  async exportEntry(entryId: string, destinationHandle: string): Promise<void> {
  }

  async removeMember(deviceId: string): Promise<EngineWorkspaceConvergence> {
    return new EngineWorkspaceConvergence('complete', 1, 1);
  }

  async queryDeviceTrust(): Promise<string> {
    return this.deviceTrustSnapshot;
  }

  async decideDeviceTrustChange(changeId: string, choice: string,
    confirmLocalRemoval: boolean): Promise<string> {
    return '{}';
  }
}

class TestRuntimeBackend implements EngineRuntimeBackend {
  startCount: number = 0;
  failStart: boolean = false;
  handle: TestRuntimeHandle = new TestRuntimeHandle();

  prepareHost(host: EngineHostCallbacks): Object {
    return new Object();
  }

  async startEngine(config: EngineRuntimeStartConfig, preparedHost: Object): Promise<EngineRuntimeHandle> {
    this.startCount += 1;
    if (this.failStart) {
      throw new Error('start failed');
    }
    return this.handle;
  }
}

export default function engineRuntimeServiceTest(): void {
  describe('EngineRuntimeService', (): void => {
    it('shares concurrent startup and owns one event loop', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let host: TestRuntimeHost = new TestRuntimeHost();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, host);
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));

      await Promise.all([service.start(), service.start(), service.start()]);

      expect(backend.startCount).assertEqual(1);
      expect(backend.handle.nextEventCount).assertEqual(1);
      expect(service.getSnapshot().state).assertEqual(EngineRuntimeState.RUNNING);
      await service.shutdown();
    });

    it('makes suspend resume and shutdown idempotent', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      await Promise.all([service.suspend(), service.suspend()]);
      await Promise.all([service.resume(), service.resume()]);
      await service.shutdown();
      await service.shutdown();

      expect(backend.handle.suspendCount).assertEqual(1);
      expect(backend.handle.resumeCount).assertEqual(1);
      expect(backend.handle.shutdownCount).assertEqual(1);
      expect(service.getSnapshot().state).assertEqual(EngineRuntimeState.IDLE);
    });

    it('shares session recovery and waits before suspending', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();
      backend.handle.deferSessionRecovery = true;

      let firstRecovery: Promise<EngineSessionRecovery> = service.recoverSession(true);
      let secondRecovery: Promise<EngineSessionRecovery> = service.recoverSession(true);
      let suspension: Promise<void> = service.suspend();
      await Promise.resolve();

      expect(backend.handle.recoverSessionCount).assertEqual(1);
      expect(backend.handle.suspendCount).assertEqual(0);
      backend.handle.completeSessionRecovery();
      await Promise.all([firstRecovery, secondRecovery, suspension]);

      expect(backend.handle.suspendCount).assertEqual(1);
      expect(service.getSnapshot().state).assertEqual(EngineRuntimeState.SUSPENDED);
      await service.shutdown();
    });

    it('recovers after startup failure', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      backend.failStart = true;
      try {
        await service.start();
      } catch (error) {
      }
      expect(service.getSnapshot().state).assertEqual(EngineRuntimeState.FAILED);

      backend.failStart = false;
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      expect(service.getSnapshot().state).assertEqual(EngineRuntimeState.RUNNING);
      expect(backend.startCount).assertEqual(2);
      await service.shutdown();
    });

    it('runs official feature calls only after startup', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      let invitation: EngineInvitationIssued = await service.issueInvitation();
      let report: EngineSendReport = await service.sendText('hello', []);
      let preferences: EngineMemberSyncPreferences = await service.queryMemberSyncPreferences('desktop');
      let updated: EngineMemberSyncPreferences = await service.updateMemberSendPreferences(
        'desktop', true, true, false, true, true, true);
      await service.recoverNetwork();

      expect(invitation.invitationCode).assertEqual('invitation');
      expect(report.totalAccepted).assertEqual(1);
      expect(preferences.image).assertTrue();
      expect(preferences.receiveEnabled).assertFalse();
      expect(preferences.receiveImage).assertFalse();
      expect(updated.image).assertFalse();
      expect(backend.handle.recoverNetworkCount).assertEqual(1);
      await service.shutdown();
    });

    it('maps the formal Engine member preference contract including receive fields', 0,
      async (): Promise<void> => {
        let nativePreferences = {
          sendEnabled: false,
          receiveEnabled: true,
          sendContentTypes: {
            text: false,
            image: true,
            link: false,
            file: true,
            codeSnippet: false,
            richText: true
          },
          receiveContentTypes: {
            text: true,
            image: false,
            link: true,
            file: false,
            codeSnippet: true,
            richText: false
          }
        };

        let preferences: EngineMemberSyncPreferences = normalizeMemberSyncPreferences(nativePreferences);

        expect(preferences.sendEnabled).assertFalse();
        expect(preferences.receiveEnabled).assertTrue();
        expect(preferences.image).assertTrue();
        expect(preferences.receiveImage).assertFalse();
        expect(preferences.receiveLink).assertTrue();
        expect(preferences.receiveCodeSnippet).assertTrue();
        expect(preferences.receiveRichText).assertFalse();
      });

    it('projects only unique actionable device trust rows', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      backend.handle.deviceTrustSnapshot = '{"local_device_id":"local-device","devices":[' +
        '{"device_id":"local-device","display_name":"This Harmony device","is_local":true,' +
        '"reachability":"online","membership":"unknown","sync_relationship":"removed_local_device"},' +
        '{"device_id":"online-remote","display_name":"Stale online device","is_local":false,' +
        '"reachability":"offline","membership":"removed","sync_relationship":"usable"},' +
        '{"device_id":"online-remote","display_name":"Active online device","is_local":false,' +
        '"reachability":"online","membership":"active","sync_relationship":"usable"},' +
        '{"device_id":"offline-remote","display_name":"Active offline device","is_local":false,' +
        '"reachability":"offline","membership":"active","sync_relationship":"usable"},' +
        '{"device_id":"removed-membership","display_name":"Removed member","is_local":false,' +
        '"reachability":"online","membership":"removed","sync_relationship":"usable"},' +
        '{"device_id":"removed-peer","display_name":"Removed peer","is_local":false,' +
        '"reachability":"online","membership":"active","sync_relationship":"removed_peer_device"},' +
        '{"device_id":"history-only","display_name":"Named historic device","address":"wss://history.example",' +
        '"is_local":false,"reachability":"online","membership":"unknown","sync_relationship":"unknown"}]}';
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      let devices = await service.queryDevices();

      expect(devices.length).assertEqual(3);
      expect(devices[0].deviceId).assertEqual('local-device');
      expect(devices[0].isLocal).assertTrue();
      expect(devices[1].deviceId).assertEqual('online-remote');
      expect(devices[1].deviceName).assertEqual('Active online device');
      expect(devices[1].online).assertTrue();
      expect(devices[2].deviceId).assertEqual('offline-remote');
      expect(devices[2].isLocal).assertFalse();
      expect(devices[2].online).assertFalse();
      await service.shutdown();
    });

    it('keeps an explicit local row ahead of later inferred history', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      backend.handle.deviceTrustSnapshot = '{"local_device_id":"local-device","devices":[' +
        '{"device_id":"local-device","display_name":"Explicit local device","is_local":true,' +
        '"reachability":"online","membership":"active","sync_relationship":"usable"},' +
        '{"device_id":"local-device","display_name":"Historical local device","is_local":false,' +
        '"reachability":"offline","membership":"removed","sync_relationship":"removed_local_device"}]}';
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      let devices = await service.queryDevices();

      expect(devices.length).assertEqual(1);
      expect(devices[0].deviceName).assertEqual('Explicit local device');
      expect(devices[0].online).assertTrue();
      expect(devices[0].state).assertEqual('usable');
      expect(devices[0].channel).assertEqual('online');
      await service.shutdown();
    });

    it('promotes an explicit local row over earlier inferred history', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      backend.handle.deviceTrustSnapshot = '{"local_device_id":"local-device","devices":[' +
        '{"device_id":"local-device","display_name":"Historical local device","is_local":false,' +
        '"reachability":"offline","membership":"removed","sync_relationship":"removed_local_device"},' +
        '{"device_id":"local-device","display_name":"Explicit local device","is_local":true,' +
        '"reachability":"online","membership":"active","sync_relationship":"usable"}]}';
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      let devices = await service.queryDevices();

      expect(devices.length).assertEqual(1);
      expect(devices[0].deviceName).assertEqual('Explicit local device');
      expect(devices[0].online).assertTrue();
      expect(devices[0].state).assertEqual('usable');
      expect(devices[0].channel).assertEqual('online');
      await service.shutdown();
    });

    it('synthesizes the local device when the trust snapshot omits its row', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      backend.handle.deviceTrustSnapshot = '{"local_device_id":"local-device","devices":[' +
        '{"device_id":"remote-device","display_name":"Current remote","is_local":false,' +
        '"reachability":"online","membership":"active","sync_relationship":"usable"}]}';
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      let devices = await service.queryDevices();

      expect(devices.length).assertEqual(2);
      expect(devices[0].deviceId).assertEqual('remote-device');
      expect(devices[1].deviceId).assertEqual('local-device');
      expect(devices[1].isLocal).assertTrue();
      await service.shutdown();
    });

    it('broadcasts observed clipboard text to every eligible device', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();
      let bytes: Uint8Array = new Uint8Array([104, 101, 108, 108, 111]);
      let snapshot: EngineClipboardSnapshot = {
        observedAtMs: 1,
        representations: [{
          kind: 'inline',
          format: 'text/plain',
          mimeType: 'text/plain',
          bytes: bytes
        }]
      };

      service.onClipboardChanged(snapshot);

      expect(backend.handle.sendTextCount).assertEqual(1);
      expect(backend.handle.lastSentText).assertEqual('hello');
      expect(backend.handle.lastSendTargets.length).assertEqual(0);
      await service.shutdown();
    });

    it('keeps the runtime running after a feature operation fails', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      backend.handle.failJoin = true;
      try {
        await service.joinSpace('expired-invitation', null, 'passphrase', true);
      } catch (error) {
      }
      expect(service.getSnapshot().state).assertEqual(EngineRuntimeState.RUNNING);

      backend.handle.failJoin = false;
      let joined: EngineSpaceJoined = await service.joinSpace('fresh-invitation', null, 'passphrase', true);
      expect(joined.spaceId).assertEqual('space');
      await service.shutdown();
    });

    it('keeps the runtime available when event polling stops before pairing', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();

      backend.handle.rejectPendingEvent(new Error('workspace is not active'));
      await Promise.resolve();
      await Promise.resolve();
      expect(service.getSnapshot().state).assertEqual(EngineRuntimeState.RUNNING);

      await service.issueInvitation();
      expect(backend.handle.nextEventCount).assertEqual(2);
      await service.shutdown();
    });
  });
}
