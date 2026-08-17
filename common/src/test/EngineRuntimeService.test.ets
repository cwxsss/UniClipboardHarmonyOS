import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  EngineHostCallbacks,
  EngineHostResult
} from '../main/ets/engine/EngineHostAdapter';
import {
  EngineRuntimeBackend,
  EngineRuntimeEvent,
  EngineRuntimeHandle,
  EngineRuntimeHost,
  EngineRuntimeService,
  EngineRuntimeStartConfig,
  EngineRuntimeState
} from '../main/ets/service/EngineRuntimeService';
import { EngineClipboardSnapshot } from '../main/ets/engine/EngineClipboardHost';
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

  prepare(context: common.UIAbilityContext): EngineHostCallbacks {
    return new TestHostCallbacks();
  }

  shutdown(): void {
    this.shutdownCount += 1;
  }
}

class TestRuntimeHandle implements EngineRuntimeHandle {
  suspendCount: number = 0;
  resumeCount: number = 0;
  shutdownCount: number = 0;
  nextEventCount: number = 0;
  private eventResolver: ((event: EngineRuntimeEvent | null) => void) | null = null;

  async lifecycleState(): Promise<string> {
    return 'running';
  }

  async suspend(): Promise<void> {
    this.suspendCount += 1;
  }

  async resume(): Promise<void> {
    this.resumeCount += 1;
  }

  nextEvent(timeoutMs: number): Promise<EngineRuntimeEvent | null> {
    this.nextEventCount += 1;
    return new Promise<EngineRuntimeEvent | null>((resolve: (event: EngineRuntimeEvent | null) => void): void => {
      this.eventResolver = resolve;
    });
  }

  async shutdown(deadlineMs: number): Promise<void> {
    this.shutdownCount += 1;
    let resolver: ((event: EngineRuntimeEvent | null) => void) | null = this.eventResolver;
    this.eventResolver = null;
    if (resolver !== null) {
      resolver(null);
    }
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
  });
}
