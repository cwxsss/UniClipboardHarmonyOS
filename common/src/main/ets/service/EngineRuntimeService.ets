import { bundleManager, common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import engine from '@uniclipboard/engine';
import type {
  OhContentTypes,
  OhContentTypesPatch,
  OhHistoryEntryDetail,
  OhHistoryEntryResource,
  OhHistoryEntrySummary,
  OhInvitationIssued,
  OhJoinedSpace,
  OhJoinSpaceStatus,
  OhMemberSyncPreferences,
  OhMemberSyncPreferencesPatch,
  OhSendReport
} from '@uniclipboard/engine';
import nativeApi from 'uniclipboard_native';
import {
  EngineHostAdapter,
  EngineHostCallbacks
} from '../engine/EngineHostAdapter';
import {
  EngineClipboardObserver,
  EngineClipboardRepresentation,
  EngineClipboardSnapshot
} from '../engine/EngineClipboardHost';
import { EngineHostError } from '../engine/EngineHostError';
import { Logger } from '../util/Logger';

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

export interface EngineClipboardTextDecoder {
  decode(bytes: Uint8Array): string;
}

class SystemEngineClipboardTextDecoder implements EngineClipboardTextDecoder {
  decode(bytes: Uint8Array): string {
    let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
    return decoder.decodeToString(bytes);
  }
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

// These result classes isolate the native surface from pages and view models.
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

export class EngineHistoryEntrySummary {
  entryId: string;
  preview: string;
  sizeBytes: number;
  capturedAtMs: number;
  contentType: string;
  isFavorited: boolean;
  activeTimeMs: number;
  contentTags: string[];

  constructor(entryId: string, preview: string, sizeBytes: number, capturedAtMs: number,
    contentType: string, isFavorited: boolean, activeTimeMs: number, contentTags: string[]) {
    this.entryId = entryId;
    this.preview = preview;
    this.sizeBytes = sizeBytes;
    this.capturedAtMs = capturedAtMs;
    this.contentType = contentType;
    this.isFavorited = isFavorited;
    this.activeTimeMs = activeTimeMs;
    this.contentTags = contentTags;
  }
}

export class EngineHistoryEntryDetail {
  entryId: string;
  content: string;
  sizeBytes: number;
  createdAtMs: number;
  activeTimeMs: number;
  mimeType: string | undefined;

  constructor(entryId: string, content: string, sizeBytes: number, createdAtMs: number,
    activeTimeMs: number, mimeType: string | undefined) {
    this.entryId = entryId;
    this.content = content;
    this.sizeBytes = sizeBytes;
    this.createdAtMs = createdAtMs;
    this.activeTimeMs = activeTimeMs;
    this.mimeType = mimeType;
  }
}

export class EngineHistoryEntryResource {
  mimeType: string | undefined;
  sizeBytes: number;
  bytes: Uint8Array;

  constructor(mimeType: string | undefined, sizeBytes: number, bytes: Uint8Array) {
    this.mimeType = mimeType;
    this.sizeBytes = sizeBytes;
    this.bytes = bytes;
  }
}

export class EngineContentTypes {
  text: boolean;
  image: boolean;
  link: boolean;
  file: boolean;
  codeSnippet: boolean;
  richText: boolean;

  constructor(text: boolean, image: boolean, link: boolean, file: boolean,
    codeSnippet: boolean, richText: boolean) {
    this.text = text;
    this.image = image;
    this.link = link;
    this.file = file;
    this.codeSnippet = codeSnippet;
    this.richText = richText;
  }
}

export class EngineMemberSyncPreferences {
  sendEnabled: boolean;
  receiveEnabled: boolean;
  sendContentTypes: EngineContentTypes;
  receiveContentTypes: EngineContentTypes;

  constructor(sendEnabled: boolean, receiveEnabled: boolean,
    sendContentTypes: EngineContentTypes, receiveContentTypes: EngineContentTypes) {
    this.sendEnabled = sendEnabled;
    this.receiveEnabled = receiveEnabled;
    this.sendContentTypes = sendContentTypes;
    this.receiveContentTypes = receiveContentTypes;
  }
}

// The native binding serializes device-trust snapshots as JSON. Convert
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

export interface EngineRuntimeHandle {
  lifecycleState(): Promise<string>;
  suspend(): Promise<void>;
  resume(): Promise<void>;
  recoverNetwork(): Promise<void>;
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
  listHistoryEntries(limit: number, offset: number): Promise<EngineHistoryEntrySummary[]>;
  getHistoryEntry(entryId: string): Promise<EngineHistoryEntryDetail>;
  deleteHistoryEntry(entryId: string): Promise<void>;
  setHistoryEntryFavorite(entryId: string, isFavorited: boolean): Promise<void>;
  readHistoryEntryResource(entryId: string): Promise<EngineHistoryEntryResource>;
  restoreClipboard(entryId: string, mode: string): Promise<string>;
  exportEntry(entryId: string, destinationHandle: string): Promise<void>;
  removeMember(deviceId: string): Promise<EngineWorkspaceConvergence>;
  queryDeviceTrust(): Promise<string>;
  queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences>;
  updateMemberSyncPreferences(deviceId: string, preferences: EngineMemberSyncPreferences):
    Promise<EngineMemberSyncPreferences>;
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
  setClipboardPollingEnabled(enabled: boolean): void;
  registerInputFile(uri: string, mimeType: string): string;
  registerOutputFile(uri: string, mimeType: string): string;
  releaseFile(handle: string): void;
  shutdown(): void;
}

function mapContentTypes(types: OhContentTypes): EngineContentTypes {
  return new EngineContentTypes(types.text, types.image, types.link, types.file,
    types.codeSnippet, types.richText);
}

function mapMemberSyncPreferences(
  preferences: OhMemberSyncPreferences): EngineMemberSyncPreferences {
  return new EngineMemberSyncPreferences(preferences.sendEnabled, preferences.receiveEnabled,
    mapContentTypes(preferences.sendContentTypes),
    mapContentTypes(preferences.receiveContentTypes));
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
      (): Promise<void> => rawHandle.recoverNetwork(),
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
        let status: OhJoinSpaceStatus = await rawHandle.joinSpace(invitationCode, deviceName, passphrase,
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
        let nativeBytes: ArrayBuffer = nativeApi.createNapiBuffer(bytes);
        let result: OhSendReport = await rawHandle.sendImage(nativeBytes,
          mimeType, targetDevices);
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
      async (limit: number, offset: number): Promise<EngineHistoryEntrySummary[]> => {
        let entries: OhHistoryEntrySummary[] = await rawHandle.listHistoryEntries(limit, offset);
        return entries.map((entry: OhHistoryEntrySummary): EngineHistoryEntrySummary =>
          new EngineHistoryEntrySummary(entry.entryId, entry.preview, entry.sizeBytes,
            entry.capturedAtMs, entry.contentType, entry.isFavorited, entry.activeTimeMs,
            entry.contentTags));
      },
      async (entryId: string): Promise<EngineHistoryEntryDetail> => {
        let entry: OhHistoryEntryDetail = await rawHandle.getHistoryEntry(entryId);
        return new EngineHistoryEntryDetail(entry.entryId, entry.content, entry.sizeBytes,
          entry.createdAtMs, entry.activeTimeMs, entry.mimeType);
      },
      (entryId: string): Promise<void> => rawHandle.deleteHistoryEntry(entryId),
      (entryId: string, isFavorited: boolean): Promise<void> =>
        rawHandle.setHistoryEntryFavorite(entryId, isFavorited),
      async (entryId: string): Promise<EngineHistoryEntryResource> => {
        let resource: OhHistoryEntryResource = await rawHandle.readHistoryEntryResource(entryId);
        return new EngineHistoryEntryResource(resource.mimeType, resource.sizeBytes,
          new Uint8Array(resource.bytes));
      },
      (entryId: string, mode: string): Promise<string> =>
        rawHandle.restoreClipboard(entryId, mode as 'standard' | 'plain_text' | 'file_paths'),
      (entryId: string, destinationHandle: string): Promise<void> => rawHandle.exportEntry(entryId,
        destinationHandle),
      async (deviceId: string): Promise<EngineWorkspaceConvergence> => {
        let result = await rawHandle.removeMember(deviceId);
        return new EngineWorkspaceConvergence(result.phase, result.effectiveMemberCount,
          result.updatedAtMs);
      },
      async (deviceId: string): Promise<EngineMemberSyncPreferences> => {
        let result: OhMemberSyncPreferences = await rawHandle.queryMemberSyncPreferences(deviceId);
        return mapMemberSyncPreferences(result);
      },
      async (deviceId: string, preferences: EngineMemberSyncPreferences): Promise<EngineMemberSyncPreferences> => {
        let sendContentTypes: OhContentTypesPatch = {
          text: preferences.sendContentTypes.text,
          image: preferences.sendContentTypes.image,
          file: preferences.sendContentTypes.file,
          link: preferences.sendContentTypes.link,
          codeSnippet: preferences.sendContentTypes.codeSnippet,
          richText: preferences.sendContentTypes.richText
        };
        let receiveContentTypes: OhContentTypesPatch = {
          text: preferences.receiveContentTypes.text,
          image: preferences.receiveContentTypes.image,
          file: preferences.receiveContentTypes.file,
          link: preferences.receiveContentTypes.link,
          codeSnippet: preferences.receiveContentTypes.codeSnippet,
          richText: preferences.receiveContentTypes.richText
        };
        let patch: OhMemberSyncPreferencesPatch = {
          sendEnabled: preferences.sendEnabled,
          receiveEnabled: preferences.receiveEnabled,
          sendContentTypes: sendContentTypes,
          receiveContentTypes: receiveContentTypes
        };
        let result: OhMemberSyncPreferences = await rawHandle.updateMemberSyncPreferences(deviceId, patch);
        return mapMemberSyncPreferences(result);
      },
      (): Promise<string> => rawHandle.queryDeviceTrust(),
      (changeId: string, choice: string, confirmLocalRemoval: boolean): Promise<string> =>
        rawHandle.decideDeviceTrustChange(changeId,
          choice as 'apply_change' | 'keep_current_device_group', confirmLocalRemoval));
  }
}

class CallbackEngineRuntimeHandle implements EngineRuntimeHandle {
  private lifecycleStateCallback: () => Promise<string>;
  private suspendCallback: () => Promise<void>;
  private resumeCallback: () => Promise<void>;
  private recoverNetworkCallback: () => Promise<void>;
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
  private listHistoryEntriesCallback: (limit: number, offset: number) =>
    Promise<EngineHistoryEntrySummary[]>;
  private getHistoryEntryCallback: (entryId: string) => Promise<EngineHistoryEntryDetail>;
  private deleteHistoryEntryCallback: (entryId: string) => Promise<void>;
  private setHistoryEntryFavoriteCallback: (entryId: string, isFavorited: boolean) => Promise<void>;
  private readHistoryEntryResourceCallback: (entryId: string) => Promise<EngineHistoryEntryResource>;
  private restoreClipboardCallback: (entryId: string, mode: string) => Promise<string>;
  private exportEntryCallback: (entryId: string, destinationHandle: string) => Promise<void>;
  private removeMemberCallback: (deviceId: string) => Promise<EngineWorkspaceConvergence>;
  private queryMemberSyncPreferencesCallback: (deviceId: string) => Promise<EngineMemberSyncPreferences>;
  private updateMemberSyncPreferencesCallback: (deviceId: string,
    preferences: EngineMemberSyncPreferences) =>
    Promise<EngineMemberSyncPreferences>;
  private queryDeviceTrustCallback: () => Promise<string>;
  private decideDeviceTrustChangeCallback: (changeId: string, choice: string,
    confirmLocalRemoval: boolean) => Promise<string>;

  constructor(lifecycleStateCallback: () => Promise<string>, suspendCallback: () => Promise<void>,
    resumeCallback: () => Promise<void>,
    recoverNetworkCallback: () => Promise<void>,
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
    listHistoryEntriesCallback: (limit: number, offset: number) => Promise<EngineHistoryEntrySummary[]>,
    getHistoryEntryCallback: (entryId: string) => Promise<EngineHistoryEntryDetail>,
    deleteHistoryEntryCallback: (entryId: string) => Promise<void>,
    setHistoryEntryFavoriteCallback: (entryId: string, isFavorited: boolean) => Promise<void>,
    readHistoryEntryResourceCallback: (entryId: string) => Promise<EngineHistoryEntryResource>,
    restoreClipboardCallback: (entryId: string, mode: string) => Promise<string>,
    exportEntryCallback: (entryId: string, destinationHandle: string) => Promise<void>,
    removeMemberCallback: (deviceId: string) => Promise<EngineWorkspaceConvergence>,
    queryMemberSyncPreferencesCallback: (deviceId: string) => Promise<EngineMemberSyncPreferences>,
    updateMemberSyncPreferencesCallback: (deviceId: string,
      preferences: EngineMemberSyncPreferences) =>
      Promise<EngineMemberSyncPreferences>,
    queryDeviceTrustCallback: () => Promise<string>,
    decideDeviceTrustChangeCallback: (changeId: string, choice: string,
      confirmLocalRemoval: boolean) => Promise<string>) {
    this.lifecycleStateCallback = lifecycleStateCallback;
    this.suspendCallback = suspendCallback;
    this.resumeCallback = resumeCallback;
    this.recoverNetworkCallback = recoverNetworkCallback;
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
    this.listHistoryEntriesCallback = listHistoryEntriesCallback;
    this.getHistoryEntryCallback = getHistoryEntryCallback;
    this.deleteHistoryEntryCallback = deleteHistoryEntryCallback;
    this.setHistoryEntryFavoriteCallback = setHistoryEntryFavoriteCallback;
    this.readHistoryEntryResourceCallback = readHistoryEntryResourceCallback;
    this.restoreClipboardCallback = restoreClipboardCallback;
    this.exportEntryCallback = exportEntryCallback;
    this.removeMemberCallback = removeMemberCallback;
    this.queryMemberSyncPreferencesCallback = queryMemberSyncPreferencesCallback;
    this.updateMemberSyncPreferencesCallback = updateMemberSyncPreferencesCallback;
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

  async listHistoryEntries(limit: number, offset: number): Promise<EngineHistoryEntrySummary[]> {
    return await this.listHistoryEntriesCallback(limit, offset);
  }

  async getHistoryEntry(entryId: string): Promise<EngineHistoryEntryDetail> {
    return await this.getHistoryEntryCallback(entryId);
  }

  async deleteHistoryEntry(entryId: string): Promise<void> {
    await this.deleteHistoryEntryCallback(entryId);
  }

  async setHistoryEntryFavorite(entryId: string, isFavorited: boolean): Promise<void> {
    await this.setHistoryEntryFavoriteCallback(entryId, isFavorited);
  }

  async readHistoryEntryResource(entryId: string): Promise<EngineHistoryEntryResource> {
    return await this.readHistoryEntryResourceCallback(entryId);
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

  async queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return await this.queryMemberSyncPreferencesCallback(deviceId);
  }

  async updateMemberSyncPreferences(deviceId: string, preferences: EngineMemberSyncPreferences):
    Promise<EngineMemberSyncPreferences> {
    return await this.updateMemberSyncPreferencesCallback(deviceId, preferences);
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
  private state: EngineRuntimeState = EngineRuntimeState.IDLE;
  private lastErrorCategory: string = '';
  private callbacks: EngineHostCallbacks | null = null;
  private preparedHost: Object | null = null;
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
  private clipboardAutoSendTargets: string[] = [];
  private eventPolling: boolean = false;
  private observers: EngineRuntimeObserver[] = [];
  private eventObservers: EngineRuntimeEventObserver[] = [];
  private clipboardTextDecoder: EngineClipboardTextDecoder;

  private constructor(backend: EngineRuntimeBackend, host: EngineRuntimeHost,
    clipboardTextDecoder: EngineClipboardTextDecoder) {
    this.backend = backend;
    this.host = host;
    this.clipboardTextDecoder = clipboardTextDecoder;
  }

  static getInstance(): EngineRuntimeService {
    if (EngineRuntimeService.instance === null) {
      EngineRuntimeService.instance = new EngineRuntimeService(
        new OfficialEngineRuntimeBackend(), new OfficialEngineRuntimeHost(), new SystemEngineClipboardTextDecoder());
    }
    return EngineRuntimeService.instance;
  }

  static createForTesting(backend: EngineRuntimeBackend, host: EngineRuntimeHost,
    clipboardTextDecoder: EngineClipboardTextDecoder = new SystemEngineClipboardTextDecoder()): EngineRuntimeService {
    return new EngineRuntimeService(backend, host, clipboardTextDecoder);
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
    this.host.setClipboardPollingEnabled(enabled);
  }

  setClipboardAutoSendTargets(targetDevices: string[]): void {
    let sanitizedTargets: string[] = [];
    for (let index: number = 0; index < targetDevices.length; index += 1) {
      let deviceId: string = targetDevices[index].trim();
      if (deviceId.length > 0 && sanitizedTargets.indexOf(deviceId) < 0) {
        sanitizedTargets.push(deviceId);
      }
    }
    this.clipboardAutoSendTargets = sanitizedTargets;
    logger.info('Clipboard automatic send target count=' + sanitizedTargets.length.toString());
  }

  async queryActiveClipboard(): Promise<EngineActiveClipboard | null> {
    return await this.executeReadOnly('query_active_clipboard',
      (handle: EngineRuntimeHandle): Promise<EngineActiveClipboard | null> => handle.queryActiveClipboard());
  }

  async listHistoryEntries(limit: number, offset: number): Promise<EngineHistoryEntrySummary[]> {
    return await this.executeReadOnly('list_history_entries',
      (handle: EngineRuntimeHandle): Promise<EngineHistoryEntrySummary[]> =>
        handle.listHistoryEntries(limit, offset));
  }

  async getHistoryEntry(entryId: string): Promise<EngineHistoryEntryDetail> {
    return await this.executeReadOnly('get_history_entry',
      (handle: EngineRuntimeHandle): Promise<EngineHistoryEntryDetail> =>
        handle.getHistoryEntry(entryId));
  }

  async deleteHistoryEntry(entryId: string): Promise<void> {
    await this.executeFeature('delete_history_entry',
      (handle: EngineRuntimeHandle): Promise<void> => handle.deleteHistoryEntry(entryId));
  }

  async setHistoryEntryFavorite(entryId: string, isFavorited: boolean): Promise<void> {
    await this.executeFeature('set_history_entry_favorite',
      (handle: EngineRuntimeHandle): Promise<void> =>
        handle.setHistoryEntryFavorite(entryId, isFavorited));
  }

  async readHistoryEntryResource(entryId: string): Promise<EngineHistoryEntryResource> {
    return await this.executeReadOnly('read_history_entry_resource',
      (handle: EngineRuntimeHandle): Promise<EngineHistoryEntryResource> =>
        handle.readHistoryEntryResource(entryId));
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

  async queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return await this.executeReadOnly('query_member_sync_preferences',
      (handle: EngineRuntimeHandle): Promise<EngineMemberSyncPreferences> =>
        handle.queryMemberSyncPreferences(deviceId));
  }

  async updateMemberSyncPreferences(deviceId: string, preferences: EngineMemberSyncPreferences):
    Promise<EngineMemberSyncPreferences> {
    return await this.executeFeature('update_member_sync_preferences',
      (handle: EngineRuntimeHandle): Promise<EngineMemberSyncPreferences> =>
        handle.updateMemberSyncPreferences(deviceId, preferences));
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
      this.releaseSnapshotFileHandles(snapshot);
      return;
    }
    if (this.clipboardCaptureTask !== null) {
      let previousPending: EngineClipboardSnapshot | null = this.pendingClipboardSnapshot;
      if (previousPending !== null) {
        this.releaseSnapshotFileHandles(previousPending);
      }
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
      logger.warn('Clipboard automatic send task failed.');
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
    let pendingSnapshot: EngineClipboardSnapshot | null = this.pendingClipboardSnapshot;
    this.pendingClipboardSnapshot = null;
    if (pendingSnapshot !== null) {
      this.releaseSnapshotFileHandles(pendingSnapshot);
    }
    this.clipboardWriteSuppression = false;
    this.eventPolling = false;
  }

  private async sendClipboardSnapshotFromHost(snapshot: EngineClipboardSnapshot): Promise<void> {
    try {
      if (this.clipboardAutoSendTargets.length === 0) {
        logger.warn('Automatic clipboard send skipped reason=no_target');
        return;
      }
      let handle: EngineRuntimeHandle = this.requireRunningHandle('capture_clipboard');
      let report: EngineSendReport;
      let image: EngineClipboardRepresentation | null = this.findClipboardImage(snapshot);
      let files: string[] = this.findClipboardFileHandles(snapshot);
      if (image !== null && image.bytes !== undefined) {
        let mimeType: string = image.mimeType === undefined ? image.format : image.mimeType;
        report = await handle.sendImage(image.bytes, mimeType, this.clipboardAutoSendTargets);
      } else if (files.length > 0) {
        report = await handle.sendFiles(files, this.clipboardAutoSendTargets);
      } else {
        let text: string = this.extractClipboardText(snapshot);
        if (text.length === 0) {
          logger.info('Automatic clipboard send skipped reason=unsupported_content');
          return;
        }
        report = await handle.sendText(text, this.clipboardAutoSendTargets);
      }
      logger.info('Automatic clipboard send completed accepted=' + report.totalAccepted.toString() +
        ' pending=' + report.totalPending.toString() +
        ' offline=' + report.totalOffline.toString() +
        ' errored=' + report.totalErrored.toString());
    } catch (error) {
      let runtimeError: EngineRuntimeError = this.toRuntimeError('send_clipboard', error as Object);
      logger.warn('Automatic clipboard send failed category=' + runtimeError.category);
    } finally {
      this.releaseSnapshotFileHandles(snapshot);
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
    for (let index: number = 0; index < snapshot.representations.length; index += 1) {
      let representation = snapshot.representations[index];
      if (representation.kind === 'inline' && representation.format === 'text/plain' &&
        representation.bytes !== undefined) {
        return this.clipboardTextDecoder.decode(representation.bytes);
      }
    }
    return '';
  }

  private findClipboardImage(snapshot: EngineClipboardSnapshot): EngineClipboardRepresentation | null {
    for (let index: number = 0; index < snapshot.representations.length; index += 1) {
      let representation: EngineClipboardRepresentation = snapshot.representations[index];
      let mimeType: string = representation.mimeType === undefined ? representation.format :
        representation.mimeType;
      if (representation.kind === 'inline' && mimeType.startsWith('image/') &&
        representation.bytes !== undefined) {
        return representation;
      }
    }
    return null;
  }

  private findClipboardFileHandles(snapshot: EngineClipboardSnapshot): string[] {
    let handles: string[] = [];
    for (let index: number = 0; index < snapshot.representations.length; index += 1) {
      let representation: EngineClipboardRepresentation = snapshot.representations[index];
      if (representation.kind === 'file' && representation.handle !== undefined) {
        handles.push(representation.handle);
      }
    }
    return handles;
  }

  private releaseSnapshotFileHandles(snapshot: EngineClipboardSnapshot): void {
    let handles: string[] = this.findClipboardFileHandles(snapshot);
    for (let index: number = 0; index < handles.length; index += 1) {
      try {
        this.host.releaseFile(handles[index]);
      } catch (error) {
      }
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
