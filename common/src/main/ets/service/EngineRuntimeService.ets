import { bundleManager, common } from '@kit.AbilityKit';
import engine from '@uniclipboard/engine';
import {
  EngineHostAdapter,
  EngineHostCallbacks
} from '../engine/EngineHostAdapter';
import { EngineHostError } from '../engine/EngineHostError';

const ENGINE_EVENT_TIMEOUT_MS: number = 1000;
const ENGINE_SHUTDOWN_DEADLINE_MS: number = 3000;
const ENGINE_PROFILE_SUFFIX: string = '.default';

export enum EngineRuntimeState {
  IDLE = 'idle',
  PREPARING = 'preparing',
  RUNNING = 'running',
  SUSPENDED = 'suspended',
  STOPPING = 'stopping',
  FAILED = 'failed'
}

export class EngineRuntimeSnapshot {
  state: EngineRuntimeState;
  errorCategory: string;

  constructor(state: EngineRuntimeState, errorCategory: string = '') {
    this.state = state;
    this.errorCategory = errorCategory;
  }
}

export interface EngineRuntimeObserver {
  onEngineRuntimeStateChanged(snapshot: EngineRuntimeSnapshot): void;
}

export class EngineRuntimeEvent {
  kind: string = '';
  state: string | undefined = undefined;
  refreshReason: string | undefined = undefined;
  operationId: string | undefined = undefined;
  terminal: string | undefined = undefined;
  lifecycleAction: string | undefined = undefined;
  errorCode: number | undefined = undefined;
  errorCategory: string | undefined = undefined;
  retryable: boolean | undefined = undefined;
  networkRecoveryPhase: string | undefined = undefined;
  nextRetryInMs: number | undefined = undefined;

  constructor(kind: string) {
    this.kind = kind;
  }
}

export interface EngineRuntimeEventObserver {
  onEngineRuntimeEvent(event: EngineRuntimeEvent): void;
}

export class EngineRuntimeError extends Error {
  category: string;
  operation: string;

  constructor(category: string, operation: string) {
    super('ENGINE_RUNTIME_' + category.toUpperCase() + ':' + operation);
    this.name = 'EngineRuntimeError';
    this.category = category;
    this.operation = operation;
  }
}

export class EngineRuntimeStartConfig {
  appVersion: string;
  profileId: string;

  constructor(appVersion: string, profileId: string) {
    this.appVersion = appVersion;
    this.profileId = profileId;
  }
}

export interface EngineRuntimeHandle {
  lifecycleState(): Promise<string>;
  suspend(): Promise<void>;
  resume(): Promise<void>;
  nextEvent(timeoutMs: number): Promise<EngineRuntimeEvent | null>;
  shutdown(deadlineMs: number): Promise<void>;
}

export interface EngineRuntimeBackend {
  prepareHost(host: EngineHostCallbacks): Object;
  startEngine(config: EngineRuntimeStartConfig, preparedHost: Object): Promise<EngineRuntimeHandle>;
}

export interface EngineRuntimeHost {
  prepare(context: common.UIAbilityContext): EngineHostCallbacks;
  shutdown(): void;
}

class OfficialEngineRuntimeBackend implements EngineRuntimeBackend {
  prepareHost(host: EngineHostCallbacks): Object {
    return engine.prepareHost(host);
  }

  async startEngine(config: EngineRuntimeStartConfig, preparedHost: Object): Promise<EngineRuntimeHandle> {
    let rawHandle = await engine.startEngine(config, preparedHost);
    return new CallbackEngineRuntimeHandle(
      (): Promise<string> => rawHandle.lifecycleState(),
      (): Promise<void> => rawHandle.suspend(),
      (): Promise<void> => rawHandle.resume(),
      async (timeoutMs: number): Promise<EngineRuntimeEvent | null> => {
        let rawEvent = await rawHandle.nextEvent(timeoutMs);
        if (rawEvent === null) {
          return null;
        }
        let event: EngineRuntimeEvent = new EngineRuntimeEvent(rawEvent.kind);
        event.state = rawEvent.state;
        event.refreshReason = rawEvent.refreshReason;
        event.operationId = rawEvent.operationId;
        event.terminal = rawEvent.terminal;
        event.lifecycleAction = rawEvent.lifecycleAction;
        event.errorCode = rawEvent.errorCode;
        event.errorCategory = rawEvent.errorCategory;
        event.retryable = rawEvent.retryable;
        event.networkRecoveryPhase = rawEvent.networkRecoveryPhase;
        event.nextRetryInMs = rawEvent.nextRetryInMs;
        return event;
      },
      (deadlineMs: number): Promise<void> => rawHandle.shutdown(deadlineMs));
  }
}

class CallbackEngineRuntimeHandle implements EngineRuntimeHandle {
  private lifecycleStateCallback: () => Promise<string>;
  private suspendCallback: () => Promise<void>;
  private resumeCallback: () => Promise<void>;
  private nextEventCallback: (timeoutMs: number) => Promise<EngineRuntimeEvent | null>;
  private shutdownCallback: (deadlineMs: number) => Promise<void>;

  constructor(lifecycleStateCallback: () => Promise<string>, suspendCallback: () => Promise<void>,
    resumeCallback: () => Promise<void>,
    nextEventCallback: (timeoutMs: number) => Promise<EngineRuntimeEvent | null>,
    shutdownCallback: (deadlineMs: number) => Promise<void>) {
    this.lifecycleStateCallback = lifecycleStateCallback;
    this.suspendCallback = suspendCallback;
    this.resumeCallback = resumeCallback;
    this.nextEventCallback = nextEventCallback;
    this.shutdownCallback = shutdownCallback;
  }

  async lifecycleState(): Promise<string> {
    return await this.lifecycleStateCallback();
  }

  async suspend(): Promise<void> {
    await this.suspendCallback();
  }

  async resume(): Promise<void> {
    await this.resumeCallback();
  }

  async nextEvent(timeoutMs: number): Promise<EngineRuntimeEvent | null> {
    return await this.nextEventCallback(timeoutMs);
  }

  async shutdown(deadlineMs: number): Promise<void> {
    await this.shutdownCallback(deadlineMs);
  }
}

class OfficialEngineRuntimeHost implements EngineRuntimeHost {
  private adapter: EngineHostAdapter = new EngineHostAdapter();

  prepare(context: common.UIAbilityContext): EngineHostCallbacks {
    return this.adapter.prepare(context);
  }

  shutdown(): void {
    this.adapter.shutdown();
  }
}

export class EngineRuntimeService {
  private static instance: EngineRuntimeService | null = null;

  private backend: EngineRuntimeBackend;
  private host: EngineRuntimeHost;
  private state: EngineRuntimeState = EngineRuntimeState.IDLE;
  private lastErrorCategory: string = '';
  private callbacks: EngineHostCallbacks | null = null;
  private preparedHost: Object | null = null;
  private startConfig: EngineRuntimeStartConfig | null = null;
  private handle: EngineRuntimeHandle | null = null;
  private prepareTask: Promise<void> | null = null;
  private startTask: Promise<void> | null = null;
  private suspendTask: Promise<void> | null = null;
  private resumeTask: Promise<void> | null = null;
  private shutdownTask: Promise<void> | null = null;
  private eventPollTask: Promise<void> | null = null;
  private eventPolling: boolean = false;
  private observers: EngineRuntimeObserver[] = [];
  private eventObservers: EngineRuntimeEventObserver[] = [];

  private constructor(backend: EngineRuntimeBackend, host: EngineRuntimeHost) {
    this.backend = backend;
    this.host = host;
  }

  static getInstance(): EngineRuntimeService {
    if (EngineRuntimeService.instance === null) {
      EngineRuntimeService.instance = new EngineRuntimeService(
        new OfficialEngineRuntimeBackend(), new OfficialEngineRuntimeHost());
    }
    return EngineRuntimeService.instance;
  }

  static createForTesting(backend: EngineRuntimeBackend, host: EngineRuntimeHost): EngineRuntimeService {
    return new EngineRuntimeService(backend, host);
  }

  async prepareForTesting(callbacks: EngineHostCallbacks, config: EngineRuntimeStartConfig): Promise<void> {
    if (this.state === EngineRuntimeState.FAILED) {
      await this.resetResources();
    }
    this.callbacks = callbacks;
    this.startConfig = config;
    this.lastErrorCategory = '';
    this.setState(EngineRuntimeState.IDLE);
  }

  getSnapshot(): EngineRuntimeSnapshot {
    return new EngineRuntimeSnapshot(this.state, this.lastErrorCategory);
  }

  addObserver(observer: EngineRuntimeObserver): void {
    if (this.observers.indexOf(observer) < 0) {
      this.observers.push(observer);
    }
    observer.onEngineRuntimeStateChanged(this.getSnapshot());
  }

  removeObserver(observer: EngineRuntimeObserver): void {
    let index: number = this.observers.indexOf(observer);
    if (index >= 0) {
      this.observers.splice(index, 1);
    }
  }

  addEventObserver(observer: EngineRuntimeEventObserver): void {
    if (this.eventObservers.indexOf(observer) < 0) {
      this.eventObservers.push(observer);
    }
  }

  removeEventObserver(observer: EngineRuntimeEventObserver): void {
    let index: number = this.eventObservers.indexOf(observer);
    if (index >= 0) {
      this.eventObservers.splice(index, 1);
    }
  }

  async prepare(context: common.UIAbilityContext): Promise<void> {
    let activeTask: Promise<void> | null = this.prepareTask;
    if (activeTask !== null) {
      await activeTask;
      return;
    }
    if (this.state === EngineRuntimeState.RUNNING || this.state === EngineRuntimeState.SUSPENDED ||
      (this.callbacks !== null && this.startConfig !== null && this.state === EngineRuntimeState.IDLE)) {
      return;
    }
    activeTask = this.performPrepare(context);
    this.prepareTask = activeTask;
    try {
      await activeTask;
    } finally {
      if (this.prepareTask === activeTask) {
        this.prepareTask = null;
      }
    }
  }

  async start(): Promise<void> {
    let pendingShutdown: Promise<void> | null = this.shutdownTask;
    if (pendingShutdown !== null) {
      await pendingShutdown;
    }
    if (this.state === EngineRuntimeState.RUNNING) {
      return;
    }
    if (this.state === EngineRuntimeState.SUSPENDED) {
      await this.resume();
      return;
    }
    let activeTask: Promise<void> | null = this.startTask;
    if (activeTask === null) {
      activeTask = this.performStart();
      this.startTask = activeTask;
    }
    try {
      await activeTask;
    } finally {
      if (this.startTask === activeTask) {
        this.startTask = null;
      }
    }
  }

  async suspend(): Promise<void> {
    let activeTask: Promise<void> | null = this.suspendTask;
    if (activeTask === null) {
      activeTask = this.performSuspend();
      this.suspendTask = activeTask;
    }
    try {
      await activeTask;
    } finally {
      if (this.suspendTask === activeTask) {
        this.suspendTask = null;
      }
    }
  }

  private async performSuspend(): Promise<void> {
    if (this.state === EngineRuntimeState.SUSPENDED || this.state === EngineRuntimeState.IDLE ||
      this.state === EngineRuntimeState.FAILED || this.state === EngineRuntimeState.STOPPING) {
      return;
    }
    let pendingStart: Promise<void> | null = this.startTask;
    if (pendingStart !== null) {
      await pendingStart;
    }
    if (this.state !== EngineRuntimeState.RUNNING || this.handle === null) {
      return;
    }
    try {
      await this.handle.suspend();
      this.setState(EngineRuntimeState.SUSPENDED);
    } catch (error) {
      throw this.fail('suspend', error);
    }
  }

  async resume(): Promise<void> {
    let activeTask: Promise<void> | null = this.resumeTask;
    if (activeTask === null) {
      activeTask = this.performResume();
      this.resumeTask = activeTask;
    }
    try {
      await activeTask;
    } finally {
      if (this.resumeTask === activeTask) {
        this.resumeTask = null;
      }
    }
  }

  private async performResume(): Promise<void> {
    if (this.state === EngineRuntimeState.RUNNING || this.state === EngineRuntimeState.IDLE ||
      this.state === EngineRuntimeState.FAILED || this.state === EngineRuntimeState.STOPPING) {
      return;
    }
    if (this.state !== EngineRuntimeState.SUSPENDED || this.handle === null) {
      return;
    }
    try {
      await this.handle.resume();
      this.setState(EngineRuntimeState.RUNNING);
    } catch (error) {
      throw this.fail('resume', error);
    }
  }

  async shutdown(): Promise<void> {
    let activeTask: Promise<void> | null = this.shutdownTask;
    if (activeTask === null) {
      activeTask = this.performShutdown();
      this.shutdownTask = activeTask;
    }
    try {
      await activeTask;
    } finally {
      if (this.shutdownTask === activeTask) {
        this.shutdownTask = null;
      }
    }
  }

  private async performPrepare(context: common.UIAbilityContext): Promise<void> {
    if (this.shutdownTask !== null) {
      await this.shutdownTask;
    }
    if (this.state === EngineRuntimeState.FAILED) {
      await this.resetResources();
    }
    this.setState(EngineRuntimeState.PREPARING);
    try {
      this.callbacks = this.host.prepare(context);
      let bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.startConfig = new EngineRuntimeStartConfig(
        bundleInfo.versionName, bundleInfo.name + ENGINE_PROFILE_SUFFIX);
      this.lastErrorCategory = '';
      this.setState(EngineRuntimeState.IDLE);
    } catch (error) {
      throw this.fail('prepare', error);
    }
  }

  private async performStart(): Promise<void> {
    if (this.prepareTask !== null) {
      await this.prepareTask;
    }
    let callbacks: EngineHostCallbacks | null = this.callbacks;
    let config: EngineRuntimeStartConfig | null = this.startConfig;
    if (callbacks === null || config === null) {
      throw this.failWithCategory('not_prepared', 'start');
    }
    this.setState(EngineRuntimeState.PREPARING);
    try {
      this.preparedHost = this.backend.prepareHost(callbacks);
      let preparedHost: Object = this.preparedHost;
      let startedHandle: EngineRuntimeHandle = await this.backend.startEngine(config, preparedHost);
      this.handle = startedHandle;
      this.startEventPolling(startedHandle);
      this.lastErrorCategory = '';
      this.setState(EngineRuntimeState.RUNNING);
    } catch (error) {
      throw this.fail('start', error);
    }
  }

  private async performShutdown(): Promise<void> {
    let pendingPrepare: Promise<void> | null = this.prepareTask;
    if (pendingPrepare !== null) {
      try {
        await pendingPrepare;
      } catch (error) {
      }
    }
    let pendingStart: Promise<void> | null = this.startTask;
    if (pendingStart !== null) {
      try {
        await pendingStart;
      } catch (error) {
      }
    }
    let pendingSuspend: Promise<void> | null = this.suspendTask;
    if (pendingSuspend !== null) {
      try {
        await pendingSuspend;
      } catch (error) {
      }
    }
    let pendingResume: Promise<void> | null = this.resumeTask;
    if (pendingResume !== null) {
      try {
        await pendingResume;
      } catch (error) {
      }
    }
    if (this.state === EngineRuntimeState.IDLE && this.callbacks === null && this.handle === null) {
      return;
    }
    this.setState(EngineRuntimeState.STOPPING);
    this.eventPolling = false;
    let shutdownError: EngineRuntimeError | null = null;
    let activeHandle: EngineRuntimeHandle | null = this.handle;
    if (activeHandle !== null) {
      try {
        await activeHandle.shutdown(ENGINE_SHUTDOWN_DEADLINE_MS);
      } catch (error) {
        shutdownError = this.toRuntimeError('shutdown', error);
      }
    }
    let pollTask: Promise<void> | null = this.eventPollTask;
    if (pollTask !== null) {
      try {
        await pollTask;
      } catch (error) {
      }
    }
    try {
      this.host.shutdown();
    } catch (error) {
      if (shutdownError === null) {
        shutdownError = this.toRuntimeError('host_shutdown', error);
      }
    }
    this.clearRuntimeResources();
    if (shutdownError !== null) {
      this.lastErrorCategory = shutdownError.category;
      this.setState(EngineRuntimeState.FAILED);
      throw shutdownError;
    }
    this.lastErrorCategory = '';
    this.setState(EngineRuntimeState.IDLE);
  }

  private startEventPolling(startedHandle: EngineRuntimeHandle): void {
    if (this.eventPollTask !== null) {
      return;
    }
    this.eventPolling = true;
    this.eventPollTask = this.pollEvents(startedHandle);
  }

  private async pollEvents(startedHandle: EngineRuntimeHandle): Promise<void> {
    try {
      while (this.eventPolling && this.handle === startedHandle) {
        let event: EngineRuntimeEvent | null = await startedHandle.nextEvent(ENGINE_EVENT_TIMEOUT_MS);
        if (!this.eventPolling || this.handle !== startedHandle) {
          break;
        }
        if (event !== null) {
          this.notifyEventObservers(event);
        }
      }
    } catch (error) {
      if (this.eventPolling && this.handle === startedHandle) {
        this.fail('event_poll', error);
      }
    } finally {
      this.eventPolling = false;
      this.eventPollTask = null;
    }
  }

  private async resetResources(): Promise<void> {
    this.eventPolling = false;
    let activeHandle: EngineRuntimeHandle | null = this.handle;
    if (activeHandle !== null) {
      try {
        await activeHandle.shutdown(ENGINE_SHUTDOWN_DEADLINE_MS);
      } catch (error) {
      }
    }
    let pollTask: Promise<void> | null = this.eventPollTask;
    if (pollTask !== null) {
      try {
        await pollTask;
      } catch (error) {
      }
    }
    try {
      this.host.shutdown();
    } catch (error) {
    }
    this.clearRuntimeResources();
  }

  private clearRuntimeResources(): void {
    this.handle = null;
    this.preparedHost = null;
    this.callbacks = null;
    this.startConfig = null;
    this.eventPollTask = null;
    this.eventPolling = false;
  }

  private fail(operation: string, error: Object): EngineRuntimeError {
    let runtimeError: EngineRuntimeError = this.toRuntimeError(operation, error);
    this.lastErrorCategory = runtimeError.category;
    this.setState(EngineRuntimeState.FAILED);
    return runtimeError;
  }

  private failWithCategory(category: string, operation: string): EngineRuntimeError {
    let runtimeError: EngineRuntimeError = new EngineRuntimeError(category, operation);
    this.lastErrorCategory = runtimeError.category;
    this.setState(EngineRuntimeState.FAILED);
    return runtimeError;
  }

  private toRuntimeError(operation: string, error: Object): EngineRuntimeError {
    if (error instanceof EngineRuntimeError) {
      return error as EngineRuntimeError;
    }
    if (error instanceof EngineHostError) {
      let hostError: EngineHostError = error as EngineHostError;
      return new EngineRuntimeError(hostError.category, operation);
    }
    return new EngineRuntimeError('engine_unavailable', operation);
  }

  private setState(nextState: EngineRuntimeState): void {
    this.state = nextState;
    let snapshot: EngineRuntimeSnapshot = this.getSnapshot();
    for (let index: number = 0; index < this.observers.length; index += 1) {
      try {
        this.observers[index].onEngineRuntimeStateChanged(snapshot);
      } catch (error) {
      }
    }
  }

  private notifyEventObservers(event: EngineRuntimeEvent): void {
    for (let index: number = 0; index < this.eventObservers.length; index += 1) {
      try {
        this.eventObservers[index].onEngineRuntimeEvent(event);
      } catch (error) {
      }
    }
  }
}

export const engineRuntimeService: EngineRuntimeService = EngineRuntimeService.getInstance();
