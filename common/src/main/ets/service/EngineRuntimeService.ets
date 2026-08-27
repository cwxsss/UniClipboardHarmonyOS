import { bundleManager, common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import engine, {
  OhEngine,
  OhInvitationIssued,
  OhJoinSpaceStatus,
  OhJoinedSpace,
  OhMemberSyncPreferences,
  OhMemberSyncPreferencesPatch,
  OhNetworkSettings,
  OhSendReport,
  PreparedHost
} from '@uniclipboard/engine';
import {
  EngineHostAdapter,
  EngineHostCallbacks
} from '../engine/EngineHostAdapter';
import { EngineClipboardObserver, EngineClipboardSnapshot } from '../engine/EngineClipboardHost';
import { EngineHostError } from '../engine/EngineHostError';
import { Logger } from '../util/Logger';
import {
  EngineDeviceTrustRelationshipPayload,
  EngineDeviceTrustSnapshotPayload,
  projectActionableDeviceTrustRows
} from './DeviceTrustProjection';

const ENGINE_EVENT_TIMEOUT_MS: number = 1000;
const ENGINE_SHUTDOWN_DEADLINE_MS: number = 3000;
const ENGINE_PROFILE_SUFFIX: string = '.engine-v1-1';
const logger: Logger = new Logger('EngineRuntime');

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

// These result classes isolate the Engine binding surface from pages and view models.
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

export class EngineNetworkSettings {
  allowRelayFallback: boolean;
  customRelayUrls: string[];

  constructor(allowRelayFallback: boolean, customRelayUrls: string[]) {
    this.allowRelayFallback = allowRelayFallback;
    this.customRelayUrls = customRelayUrls;
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

export class EngineMemberSyncPreferences {
  sendEnabled: boolean;
  receiveEnabled: boolean;
  text: boolean;
  image: boolean;
  file: boolean;
  link: boolean;
  codeSnippet: boolean;
  richText: boolean;
  receiveText: boolean;
  receiveImage: boolean;
  receiveFile: boolean;
  receiveLink: boolean;
  receiveCodeSnippet: boolean;
  receiveRichText: boolean;

  constructor(sendEnabled: boolean, text: boolean, imageEnabled: boolean, file: boolean,
    link: boolean, codeSnippet: boolean, richText: boolean, receiveEnabled: boolean = true,
    receiveText: boolean = true, receiveImage: boolean = true, receiveFile: boolean = true,
    receiveLink: boolean = true, receiveCodeSnippet: boolean = true, receiveRichText: boolean = true) {
    this.sendEnabled = sendEnabled;
    this.receiveEnabled = receiveEnabled;
    this.text = text;
    this.image = imageEnabled;
    this.file = file;
    this.link = link;
    this.codeSnippet = codeSnippet;
    this.richText = richText;
    this.receiveText = receiveText;
    this.receiveImage = receiveImage;
    this.receiveFile = receiveFile;
    this.receiveLink = receiveLink;
    this.receiveCodeSnippet = receiveCodeSnippet;
    this.receiveRichText = receiveRichText;
  }
}

export function normalizeMemberSyncPreferences(
  preferences: OhMemberSyncPreferences): EngineMemberSyncPreferences {
  return new EngineMemberSyncPreferences(
    preferences.sendEnabled,
    preferences.sendContentTypes.text,
    preferences.sendContentTypes.image,
    preferences.sendContentTypes.file,
    preferences.sendContentTypes.link,
    preferences.sendContentTypes.codeSnippet,
    preferences.sendContentTypes.richText,
    preferences.receiveEnabled,
    preferences.receiveContentTypes.text,
    preferences.receiveContentTypes.image,
    preferences.receiveContentTypes.file,
    preferences.receiveContentTypes.link,
    preferences.receiveContentTypes.codeSnippet,
    preferences.receiveContentTypes.richText);
}

export interface EngineRuntimeHandle {
  lifecycleState(): Promise<string>;
  suspend(): Promise<void>;
  resume(): Promise<void>;
  recoverNetwork(): Promise<void>;
  queryNetworkSettings(): Promise<EngineNetworkSettings>;
  updateNetworkSettings(allowRelayFallback: boolean, customRelayUrls: string[]): Promise<EngineNetworkSettings>;
  probeRelayUrl(url: string): Promise<number>;
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
  queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences>;
  updateMemberSendPreferences(deviceId: string, sendEnabled: boolean, text: boolean, imageEnabled: boolean,
    file: boolean, link: boolean, richText: boolean): Promise<EngineMemberSyncPreferences>;
  resetMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences>;
  restoreClipboard(entryId: string, mode: string): Promise<string>;
  exportEntry(entryId: string, destinationHandle: string): Promise<void>;
  removeMember(deviceId: string): Promise<EngineWorkspaceConvergence>;
  queryDeviceTrust(): Promise<string>;
  decideDeviceTrustChange(changeId: string, choice: string,
    confirmLocalRemoval: boolean): Promise<string>;
}

export interface EngineRuntimeBackend {
  prepareHost(host: EngineHostCallbacks): PreparedHost;
  startEngine(config: EngineRuntimeStartConfig, preparedHost: PreparedHost): Promise<EngineRuntimeHandle>;
}

export interface EngineRuntimeHost {
  prepare(context: common.UIAbilityContext): EngineHostCallbacks;
  listenClipboard(observer: EngineClipboardObserver): void;
  releaseClipboardListener(): void;
  setClipboardPollingEnabled(enabled: boolean): void;
  registerInputFile(uri: string, mimeType: string): string;
  registerOutputFile(uri: string, mimeType: string): string;
  releaseFile(handle: string): void;
  shutdown(): void;
}

class OfficialEngineRuntimeBackend implements EngineRuntimeBackend {
  prepareHost(host: EngineHostCallbacks): PreparedHost {
    return engine.prepareHost(host);
  }

  async startEngine(config: EngineRuntimeStartConfig, preparedHost: PreparedHost): Promise<EngineRuntimeHandle> {
    let rawHandle: OhEngine = await engine.startEngine(config, preparedHost);
    return new CallbackEngineRuntimeHandle(
      (): Promise<string> => rawHandle.lifecycleState(),
      (): Promise<void> => rawHandle.suspend(),
      (): Promise<void> => rawHandle.resume(),
      (): Promise<void> => rawHandle.recoverNetwork(),
      async (): Promise<EngineNetworkSettings> => {
        let result: OhNetworkSettings = await rawHandle.queryNetworkSettings();
        return new EngineNetworkSettings(result.allowRelayFallback, result.customRelayUrls);
      },
      async (allowRelayFallback: boolean, customRelayUrls: string[]): Promise<EngineNetworkSettings> => {
        let result: OhNetworkSettings = await rawHandle.updateNetworkSettings(
          allowRelayFallback, customRelayUrls);
        return new EngineNetworkSettings(result.allowRelayFallback, result.customRelayUrls);
      },
      (url: string): Promise<number> => rawHandle.probeRelayUrl(url),
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
        let result: OhInvitationIssued = await rawHandle.issueInvitation();
        return new EngineInvitationIssued(result.invitationCode, result.expiresAtMs, result.availability);
      },
      async (invitationCode: string, deviceName: string | null, passphrase: string,
        preserveUnreadableHistory: boolean): Promise<EngineSpaceJoined> => {
        let normalizedDeviceName: string | null = deviceName === null || deviceName.trim().length === 0 ?
          null : deviceName.trim();
        let status: OhJoinSpaceStatus = await rawHandle.joinSpace(invitationCode,
          normalizedDeviceName, passphrase,
          preserveUnreadableHistory);
        if (status.status !== 'active' || status.joinedSpace === undefined) {
          let reason: string = status.rejectionReason === undefined ? status.status : status.rejectionReason;
          throw new Error('join_space_' + reason);
        }
        let result: OhJoinedSpace = status.joinedSpace;
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
        let result: OhSendReport = await rawHandle.sendImage(bytes, mimeType, targetDevices);
        return new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
          result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending);
      },
      async (fileHandles: string[], targetDevices: string[]): Promise<EngineSendReport> => {
        let result: OhSendReport = await rawHandle.sendFiles(fileHandles, targetDevices);
        return new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
          result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending);
      },
      (): Promise<string | null> => rawHandle.captureCurrentClipboard(),
      async (): Promise<EngineActiveClipboard | null> => {
        let result = await rawHandle.queryActiveClipboard();
        if (result === null) {
          return null;
        }
        return new EngineActiveClipboard(result.entryId, result.activatedBy);
      },
      async (deviceId: string): Promise<EngineMemberSyncPreferences> => {
        let result: OhMemberSyncPreferences = await rawHandle.queryMemberSyncPreferences(deviceId);
        return normalizeMemberSyncPreferences(result);
      },
      async (deviceId: string, sendEnabled: boolean, text: boolean, imageEnabled: boolean,
        file: boolean, link: boolean, richText: boolean): Promise<EngineMemberSyncPreferences> => {
        let patch: OhMemberSyncPreferencesPatch = {
          sendEnabled: sendEnabled,
          sendContentTypes: {
            text: text,
            image: imageEnabled,
            file: file,
            link: link,
            richText: richText
          }
        };
        let result: OhMemberSyncPreferences = await rawHandle.updateMemberSyncPreferences(deviceId, patch);
        return normalizeMemberSyncPreferences(result);
      },
      async (deviceId: string): Promise<EngineMemberSyncPreferences> => {
        let patch: OhMemberSyncPreferencesPatch = {
          sendEnabled: true,
          receiveEnabled: true,
          sendContentTypes: {
            text: true,
            image: true,
            file: true,
            link: true,
            codeSnippet: true,
            richText: true
          },
          receiveContentTypes: {
            text: true,
            image: true,
            file: true,
            link: true,
            codeSnippet: true,
            richText: true
          }
        };
        let result: OhMemberSyncPreferences = await rawHandle.updateMemberSyncPreferences(deviceId, patch);
        return normalizeMemberSyncPreferences(result);
      },
      (entryId: string, mode: string): Promise<string> => rawHandle.restoreClipboard(entryId, mode),
      (entryId: string, destinationHandle: string): Promise<void> => rawHandle.exportEntry(entryId,
        destinationHandle),
      async (deviceId: string): Promise<EngineWorkspaceConvergence> => {
        let result = await rawHandle.removeMember(deviceId);
        return new EngineWorkspaceConvergence(result.phase, result.effectiveMemberCount,
          result.updatedAtMs);
      },
      (): Promise<string> => rawHandle.queryDeviceTrust(),
      (changeId: string, choice: string, confirmLocalRemoval: boolean): Promise<string> =>
        rawHandle.decideDeviceTrustChange(changeId, choice, confirmLocalRemoval));
  }
}

class CallbackEngineRuntimeHandle implements EngineRuntimeHandle {
  private lifecycleStateCallback: () => Promise<string>;
  private suspendCallback: () => Promise<void>;
  private resumeCallback: () => Promise<void>;
  private recoverNetworkCallback: () => Promise<void>;
  private queryNetworkSettingsCallback: () => Promise<EngineNetworkSettings>;
  private updateNetworkSettingsCallback: (allowRelayFallback: boolean, customRelayUrls: string[]) =>
    Promise<EngineNetworkSettings>;
  private probeRelayUrlCallback: (url: string) => Promise<number>;
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
  private queryMemberSyncPreferencesCallback: (deviceId: string) => Promise<EngineMemberSyncPreferences>;
  private updateMemberSendPreferencesCallback: (deviceId: string, sendEnabled: boolean, text: boolean,
    imageEnabled: boolean, file: boolean, link: boolean, richText: boolean) => Promise<EngineMemberSyncPreferences>;
  private resetMemberSyncPreferencesCallback: (deviceId: string) => Promise<EngineMemberSyncPreferences>;
  private restoreClipboardCallback: (entryId: string, mode: string) => Promise<string>;
  private exportEntryCallback: (entryId: string, destinationHandle: string) => Promise<void>;
  private removeMemberCallback: (deviceId: string) => Promise<EngineWorkspaceConvergence>;
  private queryDeviceTrustCallback: () => Promise<string>;
  private decideDeviceTrustChangeCallback: (changeId: string, choice: string,
    confirmLocalRemoval: boolean) => Promise<string>;

  constructor(lifecycleStateCallback: () => Promise<string>, suspendCallback: () => Promise<void>,
    resumeCallback: () => Promise<void>,
    recoverNetworkCallback: () => Promise<void>,
    queryNetworkSettingsCallback: () => Promise<EngineNetworkSettings>,
    updateNetworkSettingsCallback: (allowRelayFallback: boolean, customRelayUrls: string[]) =>
      Promise<EngineNetworkSettings>,
    probeRelayUrlCallback: (url: string) => Promise<number>,
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
    queryMemberSyncPreferencesCallback: (deviceId: string) => Promise<EngineMemberSyncPreferences>,
    updateMemberSendPreferencesCallback: (deviceId: string, sendEnabled: boolean, text: boolean,
      imageEnabled: boolean, file: boolean, link: boolean, richText: boolean) => Promise<EngineMemberSyncPreferences>,
    resetMemberSyncPreferencesCallback: (deviceId: string) => Promise<EngineMemberSyncPreferences>,
    restoreClipboardCallback: (entryId: string, mode: string) => Promise<string>,
    exportEntryCallback: (entryId: string, destinationHandle: string) => Promise<void>,
    removeMemberCallback: (deviceId: string) => Promise<EngineWorkspaceConvergence>,
    queryDeviceTrustCallback: () => Promise<string>,
    decideDeviceTrustChangeCallback: (changeId: string, choice: string,
      confirmLocalRemoval: boolean) => Promise<string>) {
    this.lifecycleStateCallback = lifecycleStateCallback;
    this.suspendCallback = suspendCallback;
    this.resumeCallback = resumeCallback;
    this.recoverNetworkCallback = recoverNetworkCallback;
    this.queryNetworkSettingsCallback = queryNetworkSettingsCallback;
    this.updateNetworkSettingsCallback = updateNetworkSettingsCallback;
    this.probeRelayUrlCallback = probeRelayUrlCallback;
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
    this.queryMemberSyncPreferencesCallback = queryMemberSyncPreferencesCallback;
    this.updateMemberSendPreferencesCallback = updateMemberSendPreferencesCallback;
    this.resetMemberSyncPreferencesCallback = resetMemberSyncPreferencesCallback;
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

  async recoverNetwork(): Promise<void> {
    await this.recoverNetworkCallback();
  }

  async queryNetworkSettings(): Promise<EngineNetworkSettings> {
    return await this.queryNetworkSettingsCallback();
  }

  async updateNetworkSettings(allowRelayFallback: boolean, customRelayUrls: string[]):
    Promise<EngineNetworkSettings> {
    return await this.updateNetworkSettingsCallback(allowRelayFallback, customRelayUrls);
  }

  async probeRelayUrl(url: string): Promise<number> {
    return await this.probeRelayUrlCallback(url);
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

  async queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return await this.queryMemberSyncPreferencesCallback(deviceId);
  }

  async updateMemberSendPreferences(deviceId: string, sendEnabled: boolean, text: boolean, imageEnabled: boolean,
    file: boolean, link: boolean, richText: boolean): Promise<EngineMemberSyncPreferences> {
    return await this.updateMemberSendPreferencesCallback(deviceId, sendEnabled, text, imageEnabled,
      file, link, richText);
  }

  async resetMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return await this.resetMemberSyncPreferencesCallback(deviceId);
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
  private profileId: string;

  constructor(profileId: string) {
    this.profileId = profileId;
  }

  prepare(context: common.UIAbilityContext): EngineHostCallbacks {
    return this.adapter.prepare(context, this.profileId);
  }

  listenClipboard(observer: EngineClipboardObserver): void {
    this.adapter.listenClipboard(observer);
  }

  releaseClipboardListener(): void {
    this.adapter.releaseClipboardListener();
  }

  setClipboardPollingEnabled(enabled: boolean): void {
    this.adapter.setClipboardPollingEnabled(enabled);
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
  private profileId: string;
  private clipboardCaptureEnabled: boolean;
  private state: EngineRuntimeState = EngineRuntimeState.IDLE;
  private lastErrorCategory: string = '';
  private callbacks: EngineHostCallbacks | null = null;
  private preparedHost: PreparedHost | null = null;
  private startConfig: EngineRuntimeStartConfig | null = null;
  private handle: EngineRuntimeHandle | null = null;
  private prepareTask: Promise<void> | null = null;
  private startTask: Promise<void> | null = null;
  private recoverSessionTask: Promise<EngineSessionRecovery> | null = null;
  private suspendTask: Promise<void> | null = null;
  private resumeTask: Promise<void> | null = null;
  private shutdownTask: Promise<void> | null = null;
  private eventPollTask: Promise<void> | null = null;
  private clipboardCaptureTask: Promise<void> | null = null;
  private pendingClipboardSnapshot: EngineClipboardSnapshot | null = null;
  private clipboardWriteSuppression: boolean = false;
  private eventPolling: boolean = false;
  private observers: EngineRuntimeObserver[] = [];
  private eventObservers: EngineRuntimeEventObserver[] = [];

  private constructor(backend: EngineRuntimeBackend, host: EngineRuntimeHost,
    profileId: string = ENGINE_PROFILE_SUFFIX, clipboardCaptureEnabled: boolean = true) {
    this.backend = backend;
    this.host = host;
    this.profileId = profileId;
    this.clipboardCaptureEnabled = clipboardCaptureEnabled;
  }

  static getInstance(): EngineRuntimeService {
    if (EngineRuntimeService.instance === null) {
      EngineRuntimeService.instance = new EngineRuntimeService(
        new OfficialEngineRuntimeBackend(), new OfficialEngineRuntimeHost(ENGINE_PROFILE_SUFFIX));
    }
    return EngineRuntimeService.instance;
  }

  static createForTesting(backend: EngineRuntimeBackend, host: EngineRuntimeHost): EngineRuntimeService {
    return new EngineRuntimeService(backend, host);
  }

  static createForProfile(profileId: string, clipboardCaptureEnabled: boolean): EngineRuntimeService {
    return new EngineRuntimeService(new OfficialEngineRuntimeBackend(), new OfficialEngineRuntimeHost(profileId),
      profileId, clipboardCaptureEnabled);
  }

  getProfileId(): string {
    return this.profileId;
  }

  async activateProfile(context: common.UIAbilityContext, profileId: string): Promise<EngineSessionRecovery> {
    if (profileId.length === 0) {
      throw new EngineRuntimeError('invalid_profile', 'activate_profile');
    }
    if (this.profileId !== profileId) {
      await this.shutdown();
      if (!(this.host instanceof OfficialEngineRuntimeHost)) {
        throw new EngineRuntimeError('invalid_runtime', 'activate_profile');
      }
      this.profileId = profileId;
      this.host = new OfficialEngineRuntimeHost(profileId);
    }
    await this.prepare(context);
    await this.start();
    return await this.recoverSession(true);
  }

  setClipboardCaptureEnabled(enabled: boolean): void {
    if (this.clipboardCaptureEnabled === enabled) {
      return;
    }
    this.clipboardCaptureEnabled = enabled;
    if (this.state !== EngineRuntimeState.RUNNING && this.state !== EngineRuntimeState.SUSPENDED) {
      return;
    }
    if (enabled) {
      this.host.listenClipboard(this);
    } else {
      this.host.releaseClipboardListener();
    }
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
    let activeTask: Promise<EngineSessionRecovery> | null = this.recoverSessionTask;
    if (activeTask === null) {
      activeTask = this.performRecoverSession(allowSecureStorageUnlock);
      this.recoverSessionTask = activeTask;
    }
    try {
      return await activeTask;
    } finally {
      if (this.recoverSessionTask === activeTask) {
        this.recoverSessionTask = null;
      }
    }
  }

  private async performRecoverSession(allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery> {
    return await this.executeFeature('recover_session',
      (handle: EngineRuntimeHandle): Promise<EngineSessionRecovery> =>
        handle.recoverSession(allowSecureStorageUnlock));
  }

  async recoverNetwork(): Promise<void> {
    await this.executeFeature('recover_network',
      (handle: EngineRuntimeHandle): Promise<void> => handle.recoverNetwork());
  }

  async queryNetworkSettings(): Promise<EngineNetworkSettings> {
    return await this.executeReadOnly('query_network_settings',
      (handle: EngineRuntimeHandle): Promise<EngineNetworkSettings> => handle.queryNetworkSettings());
  }

  async updateNetworkSettings(allowRelayFallback: boolean, customRelayUrls: string[]):
    Promise<EngineNetworkSettings> {
    return await this.executeFeature('update_network_settings',
      (handle: EngineRuntimeHandle): Promise<EngineNetworkSettings> =>
        handle.updateNetworkSettings(allowRelayFallback, customRelayUrls));
  }

  async probeRelayUrl(url: string): Promise<number> {
    return await this.executeReadOnly('probe_relay_url',
      (handle: EngineRuntimeHandle): Promise<number> => handle.probeRelayUrl(url));
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

  setClipboardPollingEnabled(enabled: boolean): void {
    this.host.setClipboardPollingEnabled(enabled && this.clipboardCaptureEnabled);
  }

  async queryActiveClipboard(): Promise<EngineActiveClipboard | null> {
    return await this.executeReadOnly('query_active_clipboard',
      (handle: EngineRuntimeHandle): Promise<EngineActiveClipboard | null> => handle.queryActiveClipboard());
  }

  async queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return await this.executeReadOnly('query_member_sync_preferences',
      (handle: EngineRuntimeHandle): Promise<EngineMemberSyncPreferences> =>
        handle.queryMemberSyncPreferences(deviceId));
  }

  async updateMemberSendPreferences(deviceId: string, sendEnabled: boolean, text: boolean, imageEnabled: boolean,
    file: boolean, link: boolean, richText: boolean): Promise<EngineMemberSyncPreferences> {
    return await this.executeFeature('update_member_sync_preferences',
      (handle: EngineRuntimeHandle): Promise<EngineMemberSyncPreferences> =>
        handle.updateMemberSendPreferences(deviceId, sendEnabled, text, imageEnabled, file, link, richText));
  }

  async resetMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return await this.executeFeature('reset_member_sync_preferences',
      (handle: EngineRuntimeHandle): Promise<EngineMemberSyncPreferences> =>
        handle.resetMemberSyncPreferences(deviceId));
  }

  async queryDevices(): Promise<EngineRuntimeDevice[]> {
    let serialized: string = await this.executeReadOnly('query_device_trust',
      (handle: EngineRuntimeHandle): Promise<string> => handle.queryDeviceTrust());
    if (serialized.trim().length === 0) {
      return [];
    }
    let snapshot: EngineDeviceTrustSnapshotPayload = JSON.parse(serialized) as EngineDeviceTrustSnapshotPayload;
    let sources: EngineDeviceTrustRelationshipPayload[] = snapshot.devices === undefined ? [] : snapshot.devices;
    let localDeviceId: string = snapshot.local_device_id === undefined ? '' : snapshot.local_device_id;
    let actionableSources: EngineDeviceTrustRelationshipPayload[] =
      projectActionableDeviceTrustRows(sources, localDeviceId);
    let devices: EngineRuntimeDevice[] = [];
    let hasLocalDevice: boolean = false;
    for (let index: number = 0; index < actionableSources.length; index++) {
      let source: EngineDeviceTrustRelationshipPayload = actionableSources[index];
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

  onClipboardChanged(snapshot: EngineClipboardSnapshot): void {
    logger.info('Clipboard observer invoked state=' + this.state);
    if (this.clipboardWriteSuppression || this.state !== EngineRuntimeState.RUNNING) {
      return;
    }
    if (this.clipboardCaptureTask !== null) {
      this.pendingClipboardSnapshot = snapshot;
      return;
    }
    let task: Promise<void> = this.drainClipboardSnapshots(snapshot);
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
    let pendingRecovery: Promise<EngineSessionRecovery> | null = this.recoverSessionTask;
    if (pendingRecovery !== null) {
      try {
        await pendingRecovery;
      } catch (error) {
      }
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
      this.startConfig = new EngineRuntimeStartConfig(bundleInfo.versionName, this.profileId);
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
      let preparedHost: PreparedHost | null = this.preparedHost;
      if (preparedHost === null) {
        throw new EngineRuntimeError('not_prepared', 'start');
      }
      let startedHandle: EngineRuntimeHandle = await this.backend.startEngine(config, preparedHost);
      this.handle = startedHandle;
      if (this.clipboardCaptureEnabled) {
        this.host.listenClipboard(this);
      }
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
    let pendingRecovery: Promise<EngineSessionRecovery> | null = this.recoverSessionTask;
    if (pendingRecovery !== null) {
      try {
        await pendingRecovery;
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
          logger.info('Engine event kind=' + event.kind);
          this.notifyEventObservers(event);
        }
      }
    } catch (error) {
      if (this.eventPolling && this.handle === startedHandle) {
        let runtimeError: EngineRuntimeError = this.toRuntimeError('event_poll', error as Object);
        logger.warn('Engine event polling stopped category=' + runtimeError.category);
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
    this.pendingClipboardSnapshot = null;
    this.clipboardWriteSuppression = false;
    this.eventPolling = false;
  }

  private async sendClipboardSnapshotFromHost(snapshot: EngineClipboardSnapshot): Promise<void> {
    let text: string = this.extractClipboardText(snapshot);
    if (text.length === 0) {
      logger.info('Automatic clipboard send skipped reason=no_text');
      return;
    }
    try {
      let handle: EngineRuntimeHandle = this.requireRunningHandle('capture_clipboard');
      let report: EngineSendReport = await handle.sendText(text, []);
      logger.info('Automatic clipboard send completed accepted=' + report.totalAccepted.toString() +
        ' pending=' + report.totalPending.toString() +
        ' offline=' + report.totalOffline.toString() +
        ' errored=' + report.totalErrored.toString());
    } catch (error) {
      let runtimeError: EngineRuntimeError = this.toRuntimeError('send_clipboard', error as Object);
      logger.warn('Automatic clipboard send failed category=' + runtimeError.category);
    }
  }

  private async drainClipboardSnapshots(initialSnapshot: EngineClipboardSnapshot): Promise<void> {
    let snapshot: EngineClipboardSnapshot | null = initialSnapshot;
    while (snapshot !== null) {
      await this.sendClipboardSnapshotFromHost(snapshot);
      snapshot = this.pendingClipboardSnapshot;
      this.pendingClipboardSnapshot = null;
    }
  }

  private extractClipboardText(snapshot: EngineClipboardSnapshot): string {
    let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
    for (let index: number = 0; index < snapshot.representations.length; index += 1) {
      let representation = snapshot.representations[index];
      if (representation.kind === 'inline' && representation.format === 'text/plain' &&
        representation.bytes !== undefined) {
        return decoder.decodeToString(representation.bytes);
      }
    }
    return '';
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
      let result: T = await action(handle);
      if (this.state === EngineRuntimeState.RUNNING && this.handle === handle && this.eventPollTask === null) {
        this.startEventPolling(handle);
      }
      return result;
    } catch (error) {
      // An operation failure such as a stale invitation must not tear down a healthy runtime.
      throw this.toRuntimeError(operation, error);
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
