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
  EngineWorkspaceConvergence
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
  shutdownCount: number = 0;
  nextEventCount: number = 0;
  failJoin: boolean = false;
  sendTextCount: number = 0;
  lastSentText: string = '';
  lastSendTargets: string[] = [];
  private eventResolver: ((event: EngineRuntimeEvent | null) => void) | null = null;
  private eventRejecter: ((reason: Object) => void) | null = null;

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
    return new EngineSessionRecovery(true, true);
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

  async restoreClipboard(entryId: string, mode: string): Promise<string> {
    return 'restored';
  }

  async exportEntry(entryId: string, destinationHandle: string): Promise<void> {
  }

  async removeMember(deviceId: string): Promise<EngineWorkspaceConvergence> {
    return new EngineWorkspaceConvergence('complete', 1, 1);
  }

  async queryDeviceTrust(): Promise<string> {
    return '{}';
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
      await service.recoverNetwork();

      expect(invitation.invitationCode).assertEqual('invitation');
      expect(report.totalAccepted).assertEqual(1);
      expect(backend.handle.recoverNetworkCount).assertEqual(1);
      await service.shutdown();
    });

    it('sends observed clipboard text to the selected desktop', 0, async (): Promise<void> => {
      let backend: TestRuntimeBackend = new TestRuntimeBackend();
      let service: EngineRuntimeService = EngineRuntimeService.createForTesting(backend, new TestRuntimeHost());
      await service.prepareForTesting(new TestHostCallbacks(), new EngineRuntimeStartConfig('1.0.0', 'test'));
      await service.start();
      service.setClipboardAutoSendTargets(['desktop-device']);
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
      expect(backend.handle.lastSendTargets.length).assertEqual(1);
      expect(backend.handle.lastSendTargets[0]).assertEqual('desktop-device');
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
