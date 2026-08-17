import { bundleManager, common } from '@kit.AbilityKit';
import engine from '@uniclipboard/engine';
import {
  EngineHostAdapter,
  EngineHostCallbacks
} from '../engine/EngineHostAdapter';
import { EngineClipboardObserver } from '../engine/EngineClipboardHost';
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
  detail: string;

  constructor(category: string, operation: string, detail: string = '') {
    super('ENGINE_RUNTIME_' + category.toUpperCase() + ':' + operation +
      (detail.length > 0 ? ':' + detail : ''));
    this.name = 'EngineRuntimeError';
    this.category = category;
    this.operation = operation;
    this.detail = detail;
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

// These result classes isolate the rc.3 native surface from pages and view models.
export class EngineSpaceCreated {
  spaceId: string;
  selfDeviceId: string;
  identityFingerprint: string;

  constructor(spaceId: string, selfDeviceId: string, identityFingerprint: string) {
    this.spaceId = spaceId;
    this.selfDeviceId = selfDeviceId;
    this.identityFingerprint = identityFingerprint;
  }
}

export class EngineSessionRecovery {
  unlocked: boolean;
  resumed: boolean;

  constructor(unlocked: boolean, resumed: boolean) {
    this.unlocked = unlocked;
    this.resumed = resumed;
  }
}

export class EngineInvitationIssued {
  invitationCode: string;
  expiresAtMs: number;
  availability: string;

  constructor(invitationCode: string, expiresAtMs: number, availability: string) {
    this.invitationCode = invitationCode;
    this.expiresAtMs = expiresAtMs;
    this.availability = availability;
  }
}

export class EngineSpaceJoined {
  sponsorDeviceId: string;
  sponsorIdentityFingerprint: string;
  spaceId: string;
  selfDeviceId: string;
  selfIdentityFingerprint: string;
  migratedRecords: string | undefined;
  preservedUnreadableRecords: string | undefined;

  constructor(sponsorDeviceId: string, sponsorIdentityFingerprint: string, spaceId: string,
    selfDeviceId: string, selfIdentityFingerprint: string, migratedRecords: string | undefined,
    preservedUnreadableRecords: string | undefined) {
    this.sponsorDeviceId = sponsorDeviceId;
    this.sponsorIdentityFingerprint = sponsorIdentityFingerprint;
    this.spaceId = spaceId;
    this.selfDeviceId = selfDeviceId;
    this.selfIdentityFingerprint = selfIdentityFingerprint;
    this.migratedRecords = migratedRecords;
    this.preservedUnreadableRecords = preservedUnreadableRecords;
  }
}

export class EngineSendReport {
  entryId: string;
  atMs: number;
  totalAccepted: number;
  totalDuplicate: number;
  totalOffline: number;
  totalErrored: number;
  totalPending: number;

  constructor(entryId: string, atMs: number, totalAccepted: number, totalDuplicate: number,
    totalOffline: number, totalErrored: number, totalPending: number) {
    this.entryId = entryId;
    this.atMs = atMs;
    this.totalAccepted = totalAccepted;
    this.totalDuplicate = totalDuplicate;
    this.totalOffline = totalOffline;
    this.totalErrored = totalErrored;
    this.totalPending = totalPending;
  }
}

export class EngineActiveClipboard {
  entryId: string;
  activatedBy: string;

  constructor(entryId: string, activatedBy: string) {
    this.entryId = entryId;
    this.activatedBy = activatedBy;
  }
}

// The native rc.3 binding serializes device-trust snapshots as JSON. Convert
// them here so views only see a stable ArkTS model, never native JSON.
class EngineDeviceTrustRelationshipPayload {
  device_id: string = '';
  display_name: string = '';
  is_local: boolean = false;
  reachability: string = 'unknown';
  membership: string = 'unknown';
  sync_relationship: string = 'unknown';
}

class EngineDeviceTrustSnapshotPayload {
  local_device_id: string = '';
  devices: EngineDeviceTrustRelationshipPayload[] = [];
}

export class EngineRuntimeDevice {
  deviceId: string;
  deviceName: string;
  deviceType: string;
  isLocal: boolean;
  online: boolean;
  state: string;
  channel: string;

  constructor(deviceId: string, deviceName: string, isLocal: boolean, online: boolean,
    state: string, channel: string) {
    this.deviceId = deviceId;
    this.deviceName = deviceName;
    this.deviceType = 'unknown';
    this.isLocal = isLocal;
    this.online = online;
    this.state = state;
    this.channel = channel;
  }
}

export class EngineWorkspaceConvergence {
  phase: string;
  effectiveMemberCount: number;
  updatedAtMs: number;

  constructor(phase: string, effectiveMemberCount: number, updatedAtMs: number) {
    this.phase = phase;
    this.effectiveMemberCount = effectiveMemberCount;
    this.updatedAtMs = updatedAtMs;
  }
}

// rc.3 exports these methods from libuc_ohos_napi.so, but omits them from
// OhEngine in Index.d.ets. Keep the compatibility contract private to this
// adapter so the rest of the product never touches the native object.
interface EngineCompatibilityNativeInvitation {
  invitationCode: string;
  expiresAtMs: number;
  availability: string;
}

interface EngineCompatibilityNativeSpaceJoined {
  sponsorDeviceId: string;
  sponsorIdentityFingerprint: string;
  spaceId: string;
  selfDeviceId: string;
  selfIdentityFingerprint: string;
  migratedRecords: string | undefined;
  preservedUnreadableRecords: string | undefined;
}

interface EngineCompatibilityNativeSendReport {
  entryId: string;
  atMs: number;
  totalAccepted: number;
  totalDuplicate: number;
  totalOffline: number;
  totalErrored: number;
  totalPending: number;
}

interface EngineCompatibilityNativeHandle {
  issueInvitation(): Promise<EngineCompatibilityNativeInvitation>;
  joinSpace(invitationCode: string, deviceName: string | null, passphrase: string,
    preserveUnreadableHistory: boolean): Promise<EngineCompatibilityNativeSpaceJoined>;
  sendImage(bytes: Uint8Array, mimeType: string, targetDevices: string[]):
    Promise<EngineCompatibilityNativeSendReport>;
  sendFiles(fileHandles: string[], targetDevices: string[]): Promise<EngineCompatibilityNativeSendReport>;
  captureCurrentClipboard(): Promise<string | null>;
  restoreClipboard(entryId: string, mode: string): Promise<string>;
  queryDeviceTrust(): Promise<string>;
  decideDeviceTrustChange(changeId: string, choice: string,
    confirmLocalRemoval: boolean): Promise<string>;
}

export interface EngineRuntimeHandle {
  lifecycleState(): Promise<string>;
  suspend(): Promise<void>;
  resume(): Promise<void>;
  nextEvent(timeoutMs: number): Promise<EngineRuntimeEvent | null>;
  shutdown(deadlineMs: number): Promise<void>;
  createSpace(deviceName: string | null, passphrase: string): Promise<EngineSpaceCreated>;
  recoverSession(allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery>;
  issueInvitation(): Promise<EngineInvitationIssued>;
  joinSpace(invitationCode: string, deviceName: string | null, passphrase: string,
    preserveUnreadableHistory: boolean): Promise<EngineSpaceJoined>;
  sendText(text: string, targetDevices: string[]): Promise<EngineSendReport>;
  sendImage(bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<EngineSendReport>;
  sendFiles(fileHandles: string[], targetDevices: string[]): Promise<EngineSendReport>;
  captureCurrentClipboard(): Promise<string | null>;
  queryActiveClipboard(): Promise<EngineActiveClipboard | null>;
  restoreClipboard(entryId: string, mode: string): Promise<string>;
  exportEntry(entryId: string, destinationHandle: string): Promise<void>;
  removeMember(deviceId: string): Promise<EngineWorkspaceConvergence>;
  queryDeviceTrust(): Promise<string>;
  decideDeviceTrustChange(changeId: string, choice: string,
    confirmLocalRemoval: boolean): Promise<string>;
}

export interface EngineRuntimeBackend {
  prepareHost(host: EngineHostCallbacks): Object;
  startEngine(config: EngineRuntimeStartConfig, preparedHost: Object): Promise<EngineRuntimeHandle>;
}

export interface EngineRuntimeHost {
  prepare(context: common.UIAbilityContext): EngineHostCallbacks;
  listenClipboard(observer: EngineClipboardObserver): void;
  registerInputFile(uri: string, mimeType: string): string;
  registerOutputFile(uri: string, mimeType: string): string;
  releaseFile(handle: string): void;
  shutdown(): void;
}

class OfficialEngineRuntimeBackend implements EngineRuntimeBackend {
  prepareHost(host: EngineHostCallbacks): Object {
    return engine.prepareHost(host);
  }

  async startEngine(config: EngineRuntimeStartConfig, preparedHost: Object): Promise<EngineRuntimeHandle> {
    let rawHandle = await engine.startEngine(config, preparedHost);
    let nativeObject: Object = rawHandle as Object;
    let compatibilityHandle: EngineCompatibilityNativeHandle = nativeObject as EngineCompatibilityNativeHandle;
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
      (deadlineMs: number): Promise<void> => rawHandle.shutdown(deadlineMs),
      async (deviceName: string | null, passphrase: string): Promise<EngineSpaceCreated> => {
        let result = await rawHandle.createSpace(deviceName, passphrase);
        return new EngineSpaceCreated(result.spaceId, result.selfDeviceId, result.identityFingerprint);
      },
      async (allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery> => {
        let result = await rawHandle.recoverSession(allowSecureStorageUnlock);
        return new EngineSessionRecovery(result.unlocked, result.resumed);
      },
      async (): Promise<EngineInvitationIssued> => {
        let result: EngineCompatibilityNativeInvitation = await compatibilityHandle.issueInvitation();
        return new EngineInvitationIssued(result.invitationCode, result.expiresAtMs, result.availability);
      },
      async (invitationCode: string, deviceName: string | null, passphrase: string,
        preserveUnreadableHistory: boolean): Promise<EngineSpaceJoined> => {
        let result: EngineCompatibilityNativeSpaceJoined = await compatibilityHandle.joinSpace(invitationCode, deviceName, passphrase,
          preserveUnreadableHistory);
        return new EngineSpaceJoined(result.sponsorDeviceId, result.sponsorIdentityFingerprint,
          result.spaceId, result.selfDeviceId, result.selfIdentityFingerprint,
          result.migratedRecords, result.preservedUnreadableRecords);
      },
      async (text: string, targetDevices: string[]): Promise<EngineSendReport> => {
        let result = await rawHandle.sendText(text, targetDevices);
        return new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
          result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending);
      },
      async (bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<EngineSendReport> => {
        let result: EngineCompatibilityNativeSendReport = await compatibilityHandle.sendImage(bytes, mimeType, targetDevices);
        return new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
          result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending);
      },
      async (fileHandles: string[], targetDevices: string[]): Promise<EngineSendReport> => {
        let result: EngineCompatibilityNativeSendReport = await compatibilityHandle.sendFiles(fileHandles, targetDevices);
        return new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
          result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending);
      },
      (): Promise<string | null> => compatibilityHandle.captureCurrentClipboard(),
      async (): Promise<EngineActiveClipboard | null> => {
        let result = await rawHandle.queryActiveClipboard();
        if (result === null) {
          return null;
        }
        return new EngineActiveClipboard(result.entryId, result.activatedBy);
      },
      (entryId: string, mode: string): Promise<string> => compatibilityHandle.restoreClipboard(entryId, mode),
      (entryId: string, destinationHandle: string): Promise<void> => rawHandle.exportEntry(entryId,
        destinationHandle),
      async (deviceId: string): Promise<EngineWorkspaceConvergence> => {
        let result = await rawHandle.removeMember(deviceId);
        return new EngineWorkspaceConvergence(result.phase, result.effectiveMemberCount,
          result.updatedAtMs);
      },
      (): Promise<string> => compatibilityHandle.queryDeviceTrust(),
      (changeId: string, choice: string, confirmLocalRemoval: boolean): Promise<string> =>
        compatibilityHandle.decideDeviceTrustChange(changeId, choice, confirmLocalRemoval));
  }
}

class CallbackEngineRuntimeHandle implements EngineRuntimeHandle {
  private lifecycleStateCallback: () => Promise<string>;
  private suspendCallback: () => Promise<void>;
  private resumeCallback: () => Promise<void>;
  private nextEventCallback: (timeoutMs: number) => Promise<EngineRuntimeEvent | null>;
  private shutdownCallback: (deadlineMs: number) => Promise<void>;
  private createSpaceCallback: (deviceName: string | null, passphrase: string) => Promise<EngineSpaceCreated>;
  private recoverSessionCallback: (allowSecureStorageUnlock: boolean) => Promise<EngineSessionRecovery>;
  private issueInvitationCallback: () => Promise<EngineInvitationIssued>;
  private joinSpaceCallback: (invitationCode: string, deviceName: string | null, passphrase: string,
    preserveUnreadableHistory: boolean) => Promise<EngineSpaceJoined>;
  private sendTextCallback: (text: string, targetDevices: string[]) => Promise<EngineSendReport>;
  private sendImageCallback: (bytes: Uint8Array, mimeType: string, targetDevices: string[]) =>
    Promise<EngineSendReport>;
  private sendFilesCallback: (fileHandles: string[], targetDevices: string[]) => Promise<EngineSendReport>;
  private captureCurrentClipboardCallback: () => Promise<string | null>;
  private queryActiveClipboardCallback: () => Promise<EngineActiveClipboard | null>;
  private restoreClipboardCallback: (entryId: string, mode: string) => Promise<string>;
  private exportEntryCallback: (entryId: string, destinationHandle: string) => Promise<void>;
  private removeMemberCallback: (deviceId: string) => Promise<EngineWorkspaceConvergence>;
  private queryDeviceTrustCallback: () => Promise<string>;
  private decideDeviceTrustChangeCallback: (changeId: string, choice: string,
    confirmLocalRemoval: boolean) => Promise<string>;

  constructor(lifecycleStateCallback: () => Promise<string>, suspendCallback: () => Promise<void>,
    resumeCallback: () => Promise<void>,
    nextEventCallback: (timeoutMs: number) => Promise<EngineRuntimeEvent | null>,
    shutdownCallback: (deadlineMs: number) => Promise<void>,
    createSpaceCallback: (deviceName: string | null, passphrase: string) => Promise<EngineSpaceCreated>,
    recoverSessionCallback: (allowSecureStorageUnlock: boolean) => Promise<EngineSessionRecovery>,
    issueInvitationCallback: () => Promise<EngineInvitationIssued>,
    joinSpaceCallback: (invitationCode: string, deviceName: string | null, passphrase: string,
      preserveUnreadableHistory: boolean) => Promise<EngineSpaceJoined>,
    sendTextCallback: (text: string, targetDevices: string[]) => Promise<EngineSendReport>,
    sendImageCallback: (bytes: Uint8Array, mimeType: string, targetDevices: string[]) => Promise<EngineSendReport>,
    sendFilesCallback: (fileHandles: string[], targetDevices: string[]) => Promise<EngineSendReport>,
    captureCurrentClipboardCallback: () => Promise<string | null>,
    queryActiveClipboardCallback: () => Promise<EngineActiveClipboard | null>,
    restoreClipboardCallback: (entryId: string, mode: string) => Promise<string>,
    exportEntryCallback: (entryId: string, destinationHandle: string) => Promise<void>,
    removeMemberCallback: (deviceId: string) => Promise<EngineWorkspaceConvergence>,
    queryDeviceTrustCallback: () => Promise<string>,
    decideDeviceTrustChangeCallback: (changeId: string, choice: string,
      confirmLocalRemoval: boolean) => Promise<string>) {
    this.lifecycleStateCallback = lifecycleStateCallback;
    this.suspendCallback = suspendCallback;
    this.resumeCallback = resumeCallback;
    this.nextEventCallback = nextEventCallback;
    this.shutdownCallback = shutdownCallback;
    this.createSpaceCallback = createSpaceCallback;
    this.recoverSessionCallback = recoverSessionCallback;
    this.issueInvitationCallback = issueInvitationCallback;
    this.joinSpaceCallback = joinSpaceCallback;
    this.sendTextCallback = sendTextCallback;
    this.sendImageCallback = sendImageCallback;
    this.sendFilesCallback = sendFilesCallback;
    this.captureCurrentClipboardCallback = captureCurrentClipboardCallback;
    this.queryActiveClipboardCallback = queryActiveClipboardCallback;
    this.restoreClipboardCallback = restoreClipboardCallback;
    this.exportEntryCallback = exportEntryCallback;
    this.removeMemberCallback = removeMemberCallback;
    this.queryDeviceTrustCallback = queryDeviceTrustCallback;
    this.decideDeviceTrustChangeCallback = decideDeviceTrustChangeCallback;
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

  async createSpace(deviceName: string | null, passphrase: string): Promise<EngineSpaceCreated> {
    return await this.createSpaceCallback(deviceName, passphrase);
  }

  async recoverSession(allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery> {
    return await this.recoverSessionCallback(allowSecureStorageUnlock);
  }

  async issueInvitation(): Promise<EngineInvitationIssued> {
    return await this.issueInvitationCallback();
  }

  async joinSpace(invitationCode: string, deviceName: string | null, passphrase: string,
    preserveUnreadableHistory: boolean): Promise<EngineSpaceJoined> {
    return await this.joinSpaceCallback(invitationCode, deviceName, passphrase, preserveUnreadableHistory);
  }

  async sendText(text: string, targetDevices: string[]): Promise<EngineSendReport> {
    return await this.sendTextCallback(text, targetDevices);
  }

  async sendImage(bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<EngineSendReport> {
    return await this.sendImageCallback(bytes, mimeType, targetDevices);
  }

  async sendFiles(fileHandles: string[], targetDevices: string[]): Promise<EngineSendReport> {
    return await this.sendFilesCallback(fileHandles, targetDevices);
  }

  async captureCurrentClipboard(): Promise<string | null> {
    return await this.captureCurrentClipboardCallback();
  }

  async queryActiveClipboard(): Promise<EngineActiveClipboard | null> {
    return await this.queryActiveClipboardCallback();
  }

  async restoreClipboard(entryId: string, mode: string): Promise<string> {
    return await this.restoreClipboardCallback(entryId, mode);
  }

  async exportEntry(entryId: string, destinationHandle: string): Promise<void> {
    await this.exportEntryCallback(entryId, destinationHandle);
  }

  async removeMember(deviceId: string): Promise<EngineWorkspaceConvergence> {
    return await this.removeMemberCallback(deviceId);
  }

  async queryDeviceTrust(): Promise<string> {
    return await this.queryDeviceTrustCallback();
  }

  async decideDeviceTrustChange(changeId: string, choice: string,
    confirmLocalRemoval: boolean): Promise<string> {
    return await this.decideDeviceTrustChangeCallback(changeId, choice, confirmLocalRemoval);
  }
}

class OfficialEngineRuntimeHost implements EngineRuntimeHost {
  private adapter: EngineHostAdapter = new EngineHostAdapter();

  prepare(context: common.UIAbilityContext): EngineHostCallbacks {
    return this.adapter.prepare(context);
  }

  listenClipboard(observer: EngineClipboardObserver): void {
    this.adapter.listenClipboard(observer);
  }

  registerInputFile(uri: string, mimeType: string): string {
    return this.adapter.registerInput(uri, mimeType);
  }

  registerOutputFile(uri: string, mimeType: string): string {
    return this.adapter.registerOutput(uri, mimeType);
  }

  releaseFile(handle: string): void {
    this.adapter.releaseFile(handle);
  }

  shutdown(): void {
    this.adapter.shutdown();
  }
}

export class EngineRuntimeService implements EngineClipboardObserver {
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
  private clipboardCaptureTask: Promise<void> | null = null;
  private clipboardWriteSuppression: boolean = false;
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

  async createSpace(deviceName: string | null, passphrase: string): Promise<EngineSpaceCreated> {
    return await this.executeFeature('create_space',
      (handle: EngineRuntimeHandle): Promise<EngineSpaceCreated> => handle.createSpace(deviceName, passphrase));
  }

  async recoverSession(allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery> {
    return await this.executeFeature('recover_session',
      (handle: EngineRuntimeHandle): Promise<EngineSessionRecovery> =>
        handle.recoverSession(allowSecureStorageUnlock));
  }

  async issueInvitation(): Promise<EngineInvitationIssued> {
    return await this.executeFeature('issue_invitation',
      (handle: EngineRuntimeHandle): Promise<EngineInvitationIssued> => handle.issueInvitation());
  }

  async joinSpace(invitationCode: string, deviceName: string | null, passphrase: string,
    preserveUnreadableHistory: boolean): Promise<EngineSpaceJoined> {
    return await this.executeFeature('join_space',
      (handle: EngineRuntimeHandle): Promise<EngineSpaceJoined> => handle.joinSpace(invitationCode,
        deviceName, passphrase, preserveUnreadableHistory));
  }

  async sendText(text: string, targetDevices: string[]): Promise<EngineSendReport> {
    return await this.executeFeature('send_text',
      (handle: EngineRuntimeHandle): Promise<EngineSendReport> => handle.sendText(text, targetDevices));
  }

  async sendImage(bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<EngineSendReport> {
    return await this.executeFeature('send_image',
      (handle: EngineRuntimeHandle): Promise<EngineSendReport> => handle.sendImage(bytes, mimeType, targetDevices));
  }

  async sendFiles(fileHandles: string[], targetDevices: string[]): Promise<EngineSendReport> {
    return await this.executeFeature('send_files',
      (handle: EngineRuntimeHandle): Promise<EngineSendReport> => handle.sendFiles(fileHandles, targetDevices));
  }

  async sendFileFromUri(uri: string, mimeType: string, targetDevices: string[]): Promise<EngineSendReport> {
    this.requireRunningHandle('send_file');
    let fileHandle: string = '';
    try {
      fileHandle = this.host.registerInputFile(uri, mimeType);
      let handles: string[] = [fileHandle];
      return await this.sendFiles(handles, targetDevices);
    } catch (error) {
      throw this.fail('send_file', error);
    } finally {
      if (fileHandle.length > 0) {
        try {
          this.host.releaseFile(fileHandle);
        } catch (error) {
        }
      }
    }
  }

  async captureCurrentClipboard(): Promise<string | null> {
    return await this.executeFeature('capture_clipboard',
      (handle: EngineRuntimeHandle): Promise<string | null> => handle.captureCurrentClipboard());
  }

  async queryActiveClipboard(): Promise<EngineActiveClipboard | null> {
    return await this.executeReadOnly('query_active_clipboard',
      (handle: EngineRuntimeHandle): Promise<EngineActiveClipboard | null> => handle.queryActiveClipboard());
  }

  async queryDevices(): Promise<EngineRuntimeDevice[]> {
    let serialized: string = await this.executeReadOnly('query_device_trust',
      (handle: EngineRuntimeHandle): Promise<string> => handle.queryDeviceTrust());
    if (serialized.trim().length === 0) {
      return [];
    }
    let snapshot: EngineDeviceTrustSnapshotPayload = JSON.parse(serialized) as EngineDeviceTrustSnapshotPayload;
    let devices: EngineRuntimeDevice[] = [];
    let hasLocalDevice: boolean = false;
    let sources: EngineDeviceTrustRelationshipPayload[] = snapshot.devices === undefined ? [] : snapshot.devices;
    let localDeviceId: string = snapshot.local_device_id === undefined ? '' : snapshot.local_device_id;
    for (let index: number = 0; index < sources.length; index++) {
      let source: EngineDeviceTrustRelationshipPayload = sources[index];
      let isLocal: boolean = source.is_local || source.device_id === localDeviceId;
      let name: string = source.display_name.length > 0 ? source.display_name : source.device_id;
      let online: boolean = source.reachability === 'online';
      devices.push(new EngineRuntimeDevice(source.device_id, name, isLocal, online,
        source.sync_relationship.length > 0 ? source.sync_relationship : source.membership,
        source.reachability));
      if (isLocal) {
        hasLocalDevice = true;
      }
    }
    if (!hasLocalDevice && localDeviceId.length > 0) {
      devices.push(new EngineRuntimeDevice(localDeviceId, localDeviceId,
        true, true, 'active', 'local'));
    }
    return devices;
  }

  async restoreClipboard(entryId: string, mode: string): Promise<string> {
    this.clipboardWriteSuppression = true;
    try {
      return await this.executeFeature('restore_clipboard',
        (handle: EngineRuntimeHandle): Promise<string> => handle.restoreClipboard(entryId, mode));
    } finally {
      this.clipboardWriteSuppression = false;
    }
  }

  async exportEntry(entryId: string, destinationHandle: string): Promise<void> {
    await this.executeFeature('export_entry',
      (handle: EngineRuntimeHandle): Promise<void> => handle.exportEntry(entryId, destinationHandle));
  }

  async exportEntryToUri(entryId: string, destinationUri: string, mimeType: string = ''): Promise<void> {
    this.requireRunningHandle('export_entry');
    let fileHandle: string = '';
    try {
      fileHandle = this.host.registerOutputFile(destinationUri, mimeType);
      await this.exportEntry(entryId, fileHandle);
    } catch (error) {
      throw this.fail('export_entry', error);
    } finally {
      if (fileHandle.length > 0) {
        try {
          this.host.releaseFile(fileHandle);
        } catch (error) {
        }
      }
    }
  }

  async removeMember(deviceId: string): Promise<EngineWorkspaceConvergence> {
    return await this.executeFeature('remove_member',
      (handle: EngineRuntimeHandle): Promise<EngineWorkspaceConvergence> => handle.removeMember(deviceId));
  }

  async queryDeviceTrust(): Promise<string> {
    return await this.executeReadOnly('query_device_trust',
      (handle: EngineRuntimeHandle): Promise<string> => handle.queryDeviceTrust());
  }

  async decideDeviceTrustChange(changeId: string, choice: string,
    confirmLocalRemoval: boolean): Promise<string> {
    return await this.executeFeature('decide_device_trust_change',
      (handle: EngineRuntimeHandle): Promise<string> => handle.decideDeviceTrustChange(changeId,
        choice, confirmLocalRemoval));
  }

  onClipboardChanged(): void {
    if (this.clipboardWriteSuppression || this.clipboardCaptureTask !== null ||
      this.state !== EngineRuntimeState.RUNNING) {
      return;
    }
    let task: Promise<void> = this.captureCurrentClipboardFromHost();
    this.clipboardCaptureTask = task;
    task.then((): void => {
      if (this.clipboardCaptureTask === task) {
        this.clipboardCaptureTask = null;
      }
    }).catch((): void => {
      if (this.clipboardCaptureTask === task) {
        this.clipboardCaptureTask = null;
      }
    });
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
      this.host.listenClipboard(this);
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
    this.clipboardCaptureTask = null;
    this.clipboardWriteSuppression = false;
    this.eventPolling = false;
  }

  private async captureCurrentClipboardFromHost(): Promise<void> {
    try {
      let handle: EngineRuntimeHandle = this.requireRunningHandle('capture_clipboard');
      await handle.captureCurrentClipboard();
    } catch (error) {
      // Clipboard reads can be denied when the app is not running behind a
      // user-authorized PasteButton. A denied capture must not stop the
      // official Engine event loop or invalidate an already joined session.
    }
  }

  private requireRunningHandle(operation: string): EngineRuntimeHandle {
    if (this.state !== EngineRuntimeState.RUNNING || this.handle === null) {
      throw new EngineRuntimeError('not_running', operation);
    }
    return this.handle;
  }

  private async executeFeature<T>(operation: string,
    action: (handle: EngineRuntimeHandle) => Promise<T>): Promise<T> {
    let handle: EngineRuntimeHandle = this.requireRunningHandle(operation);
    try {
      return await action(handle);
    } catch (error) {
      throw this.fail(operation, error);
    }
  }

  private async executeReadOnly<T>(operation: string,
    action: (handle: EngineRuntimeHandle) => Promise<T>): Promise<T> {
    let handle: EngineRuntimeHandle = this.requireRunningHandle(operation);
    try {
      return await action(handle);
    } catch (error) {
      throw this.toRuntimeError(operation, error);
    }
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
    if (error instanceof Error) {
      let nativeError: Error = error as Error;
      return new EngineRuntimeError('engine_unavailable', operation, nativeError.message);
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
