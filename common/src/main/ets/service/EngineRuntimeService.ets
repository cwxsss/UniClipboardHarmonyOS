import { bundleManager, common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import engine from '@uniclipboard/engine';
import type {
  OhActiveClipboard,
  OhEngine,
  OhEngineEvent,
  OhInvitationIssued,
  OhJoinSpaceStatus,
  OhJoinedSpace,
  OhLocalDevice,
  OhMemberRemoval,
  OhMemberSyncPreferences,
  OhMembershipConvergence,
  OhNetworkSettings,
  OhNetworkRecoveryStatus,
  OhSendReport,
  OhSessionRecovery,
  OhHostDirectories,
  OhSharedDeviceRefresh,
  OhSpaceCreated,
  PreparedHost
} from 'libuc_ohos_napi.so';
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
const ENGINE_DIAGNOSTIC_DETAIL_MAX_LENGTH: number = 256;
const logger: Logger = new Logger('EngineRuntime');

function diagnosticDetailSummary(detail: string): string {
  let summary: string = detail.replace(/\s+/g, ' ').trim();
  summary = summary.replace(/(passphrase|password|secret|token|authorization)(\s*[:=]\s*)[^\s,;]+/gi,
    '$1$2[redacted]');
  summary = summary.replace(/[A-Za-z]:[\\/][^\s,;]+|\/data\/[^\s,;]+/g, '[path]');
  if (summary.length === 0) {
    return 'none';
  }
  if (summary.length > ENGINE_DIAGNOSTIC_DETAIL_MAX_LENGTH) {
    return summary.substring(0, ENGINE_DIAGNOSTIC_DETAIL_MAX_LENGTH) + '...';
  }
  return summary;
}

function diagnosticErrorCategory(error: Object): string {
  if (error instanceof EngineRuntimeError) {
    return (error as EngineRuntimeError).category;
  }
  if (error instanceof EngineHostError) {
    return (error as EngineHostError).category;
  }
  return 'native_error';
}

function diagnosticErrorDetail(error: Object): string {
  if (error instanceof EngineRuntimeError) {
    return diagnosticDetailSummary((error as EngineRuntimeError).detail);
  }
  if (error instanceof Error) {
    return diagnosticDetailSummary((error as Error).message);
  }
  return 'unknown_error';
}

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
  memberRemoval: string | undefined = undefined;
  sharedDeviceRefresh: string | undefined = undefined;
  networkRecoveryPhase: string | undefined = undefined;
  nextRetryInMs: number | undefined = undefined;
  rePairingScope: string | undefined = undefined;

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

export class EngineNetworkRecoveryStatus {
  phase: string;
  retryable: boolean;
  nextRetryInMs: number | undefined;

  constructor(phase: string, retryable: boolean, nextRetryInMs: number | undefined) {
    this.phase = phase;
    this.retryable = retryable;
    this.nextRetryInMs = nextRetryInMs;
  }
}

export class EngineLocalDevice {
  deviceId: string;
  displayName: string;

  constructor(deviceId: string, displayName: string) {
    this.deviceId = deviceId;
    this.displayName = displayName;
  }
}

export class EngineMembershipConvergence {
  state: string;
  pendingCount: number;
  waitingForPeerCount: number;
  waitingForUpdateCount: number;
  versionIncompatibleCount: number;
  blockedCount: number;
  rejectedCount: number;

  constructor(state: string, pendingCount: number, waitingForPeerCount: number,
    waitingForUpdateCount: number, versionIncompatibleCount: number, blockedCount: number,
    rejectedCount: number) {
    this.state = state;
    this.pendingCount = pendingCount;
    this.waitingForPeerCount = waitingForPeerCount;
    this.waitingForUpdateCount = waitingForUpdateCount;
    this.versionIncompatibleCount = versionIncompatibleCount;
    this.blockedCount = blockedCount;
    this.rejectedCount = rejectedCount;
  }
}

export class EngineJoinSpaceStatus {
  status: string;
  joinId: string;
  peerUpgradeRequired: boolean;
  rejectionReason: string | undefined;

  constructor(status: string, joinId: string, peerUpgradeRequired: boolean,
    rejectionReason: string | undefined) {
    this.status = status;
    this.joinId = joinId;
    this.peerUpgradeRequired = peerUpgradeRequired;
    this.rejectionReason = rejectionReason;
  }
}

export class EngineMemberRemoval {
  phase: string;
  intentCount: number;
  effectiveMemberCount: number;
  convergenceDigest: string | undefined;
  updatedAtMs: number;

  constructor(phase: string, intentCount: number, effectiveMemberCount: number,
    convergenceDigest: string | undefined, updatedAtMs: number) {
    this.phase = phase;
    this.intentCount = intentCount;
    this.effectiveMemberCount = effectiveMemberCount;
    this.convergenceDigest = convergenceDigest;
    this.updatedAtMs = updatedAtMs;
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

export class EnginePairingCandidateDiagnostic {
  kind: string;
  addressHint: string;
  port: number;

  constructor(kind: string, addressHint: string, port: number) {
    this.kind = kind;
    this.addressHint = addressHint;
    this.port = port;
  }
}

export class EnginePairingInboundDiagnostics {
  eventsDelivered: number;
  lastStage: string;
  lastStageElapsedMs: number;
  lastFailure: string;

  constructor(eventsDelivered: number, lastStage: string, lastStageElapsedMs: number, lastFailure: string) {
    this.eventsDelivered = eventsDelivered;
    this.lastStage = lastStage;
    this.lastStageElapsedMs = lastStageElapsedMs;
    this.lastFailure = lastFailure;
  }
}

export class EnginePairingDiagnostics {
  candidateCount: number;
  candidates: EnginePairingCandidateDiagnostic[];
  inbound: EnginePairingInboundDiagnostics;

  constructor(candidateCount: number, candidates: EnginePairingCandidateDiagnostic[],
    inbound: EnginePairingInboundDiagnostics) {
    this.candidateCount = candidateCount;
    this.candidates = candidates;
    this.inbound = inbound;
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

interface EngineDeviceGroupChoicesPayload {
  device_trust?: EngineDeviceTrustSnapshotPayload;
  revision?: number;
  devices?: EngineDeviceTrustRelationshipPayload[];
  local_device_id?: string;
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

interface LegacyContentTypesPayload {
  text: boolean;
  image: boolean;
  file: boolean;
  link: boolean;
  codeSnippet: boolean;
  richText: boolean;
}

interface LegacyMemberSyncPreferencesPayload {
  sendEnabled: boolean;
  receiveEnabled: boolean;
  sendContentTypes: LegacyContentTypesPayload;
  receiveContentTypes: LegacyContentTypesPayload;
}

export function normalizeMemberSyncPreferences(
  preferences: LegacyMemberSyncPreferencesPayload): EngineMemberSyncPreferences {
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
  queryNetworkRecoveryStatus?(): Promise<EngineNetworkRecoveryStatus>;
  queryLocalDevice?(): Promise<EngineLocalDevice>;
  queryDeviceGroupChoices?(): Promise<string>;
  queryMembershipConvergence?(): Promise<EngineMembershipConvergence>;
  cancelJoinSpace?(joinId: string): Promise<EngineJoinSpaceStatus>;
  refreshSharedDevices?(): Promise<string>;
  querySharedDeviceRefresh?(requestId: string): Promise<string | null>;
  queryMemberRemoval?(): Promise<EngineMemberRemoval>;
  queryNetworkSettings(): Promise<EngineNetworkSettings>;
  queryPairingDiagnostics(): Promise<EnginePairingDiagnostics>;
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

function unsupportedEngineOperation(operation: string): Promise<never> {
  return Promise.reject(new EngineRuntimeError('unsupported_by_engine', operation));
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
      (): Promise<EngineNetworkSettings> => rawHandle.queryNetworkSettings().then((result: OhNetworkSettings) =>
        new EngineNetworkSettings(result.allowRelayFallback, result.customRelayUrls)),
      (): Promise<EnginePairingDiagnostics> => unsupportedEngineOperation('query_pairing_diagnostics'),
      (allowRelayFallback: boolean, customRelayUrls: string[]): Promise<EngineNetworkSettings> =>
        rawHandle.updateNetworkSettings(allowRelayFallback, customRelayUrls).then((result: OhNetworkSettings) =>
          new EngineNetworkSettings(result.allowRelayFallback, result.customRelayUrls)),
      (url: string): Promise<number> => rawHandle.probeRelayUrl(url),
      async (timeoutMs: number): Promise<EngineRuntimeEvent | null> => {
        let rawEvent: OhEngineEvent | null = await rawHandle.nextEvent(timeoutMs);
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
        event.memberRemoval = rawEvent.memberRemoval === undefined ? undefined : JSON.stringify(rawEvent.memberRemoval);
        event.sharedDeviceRefresh = rawEvent.sharedDeviceRefresh === undefined ?
          undefined : JSON.stringify(rawEvent.sharedDeviceRefresh);
        event.networkRecoveryPhase = rawEvent.networkRecoveryPhase;
        event.nextRetryInMs = rawEvent.nextRetryInMs;
        event.rePairingScope = rawEvent.rePairingScope;
        return event;
      },
      (deadlineMs: number): Promise<void> => rawHandle.shutdown(deadlineMs),
      async (deviceName: string | null, passphrase: string): Promise<EngineSpaceCreated> => {
        let result: OhSpaceCreated = await rawHandle.createSpace(deviceName, passphrase);
        return new EngineSpaceCreated(result.spaceId, result.selfDeviceId, result.identityFingerprint);
      },
      async (allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery> => {
        let result: OhSessionRecovery = await rawHandle.recoverSession(allowSecureStorageUnlock);
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
        let result: OhSendReport = await rawHandle.sendText(text, targetDevices);
        return new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
          result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending);
      },
      (bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<EngineSendReport> =>
        rawHandle.sendImage(bytes, mimeType, targetDevices).then((result: OhSendReport) =>
          new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
            result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending)),
      (fileHandles: string[], targetDevices: string[]): Promise<EngineSendReport> =>
        rawHandle.sendFiles(fileHandles, targetDevices).then((result: OhSendReport) =>
          new EngineSendReport(result.entryId, result.atMs, result.totalAccepted,
            result.totalDuplicate, result.totalOffline, result.totalErrored, result.totalPending)),
      (): Promise<string | null> => rawHandle.captureCurrentClipboard(),
      async (): Promise<EngineActiveClipboard | null> => {
        let result: OhActiveClipboard | null = await rawHandle.queryActiveClipboard();
        if (result === null) {
          return null;
        }
        return new EngineActiveClipboard(result.entryId, result.activatedBy);
      },
      (deviceId: string): Promise<EngineMemberSyncPreferences> => rawHandle.queryMemberSyncPreferences(deviceId).then(
        (result: OhMemberSyncPreferences) => new EngineMemberSyncPreferences(result.sendEnabled,
          result.sendContentTypes.text, result.sendContentTypes.image, result.sendContentTypes.file,
          result.sendContentTypes.link, result.sendContentTypes.codeSnippet, result.sendContentTypes.richText,
          result.receiveEnabled, result.receiveContentTypes.text, result.receiveContentTypes.image,
          result.receiveContentTypes.file, result.receiveContentTypes.link,
          result.receiveContentTypes.codeSnippet, result.receiveContentTypes.richText)),
      (deviceId: string, sendEnabled: boolean, text: boolean, imageEnabled: boolean, file: boolean,
        link: boolean, richText: boolean): Promise<EngineMemberSyncPreferences> => rawHandle.updateMemberSyncPreferences(
        deviceId, {
          sendEnabled: sendEnabled,
          sendContentTypes: { text: text, image: imageEnabled, file: file, link: link, richText: richText }
        }).then((result: OhMemberSyncPreferences) => new EngineMemberSyncPreferences(result.sendEnabled,
          result.sendContentTypes.text, result.sendContentTypes.image, result.sendContentTypes.file,
          result.sendContentTypes.link, result.sendContentTypes.codeSnippet, result.sendContentTypes.richText,
          result.receiveEnabled, result.receiveContentTypes.text, result.receiveContentTypes.image,
          result.receiveContentTypes.file, result.receiveContentTypes.link,
          result.receiveContentTypes.codeSnippet, result.receiveContentTypes.richText)),
      (deviceId: string): Promise<EngineMemberSyncPreferences> => rawHandle.updateMemberSyncPreferences(deviceId, {
        sendEnabled: true,
        receiveEnabled: true,
        sendContentTypes: { text: true, image: true, file: true, link: true, richText: true },
        receiveContentTypes: { text: true, image: true, file: true, link: true, richText: true }
      }).then((result: OhMemberSyncPreferences) => new EngineMemberSyncPreferences(result.sendEnabled,
        result.sendContentTypes.text, result.sendContentTypes.image, result.sendContentTypes.file,
        result.sendContentTypes.link, result.sendContentTypes.codeSnippet, result.sendContentTypes.richText,
        result.receiveEnabled, result.receiveContentTypes.text, result.receiveContentTypes.image,
        result.receiveContentTypes.file, result.receiveContentTypes.link,
        result.receiveContentTypes.codeSnippet, result.receiveContentTypes.richText)),
      (entryId: string, mode: string): Promise<string> => rawHandle.restoreClipboard(entryId, mode),
      (entryId: string, destinationHandle: string): Promise<void> => rawHandle.exportEntry(entryId,
        destinationHandle),
      async (deviceId: string): Promise<EngineWorkspaceConvergence> => {
        let result: OhMemberRemoval = await rawHandle.removeMember(deviceId);
        return new EngineWorkspaceConvergence(result.phase, result.effectiveMemberCount,
          result.updatedAtMs);
      },
      (): Promise<string> => rawHandle.queryDeviceGroupChoices(),
      (): Promise<string> => unsupportedEngineOperation('decide_device_trust_change'),
      async (): Promise<EngineNetworkRecoveryStatus> => {
        let result: OhNetworkRecoveryStatus = await rawHandle.queryNetworkRecoveryStatus();
        return new EngineNetworkRecoveryStatus(result.phase, result.retryable, result.nextRetryInMs);
      },
      async (): Promise<EngineLocalDevice> => {
        let result: OhLocalDevice = await rawHandle.queryLocalDevice();
        return new EngineLocalDevice(result.deviceId, result.displayName);
      },
      (): Promise<string> => rawHandle.queryDeviceGroupChoices(),
      async (): Promise<EngineMembershipConvergence> => {
        let result: OhMembershipConvergence = await rawHandle.queryMembershipConvergence();
        return new EngineMembershipConvergence(result.state, result.pendingCount,
          result.waitingForPeerCount, result.waitingForUpdateCount, result.versionIncompatibleCount,
          result.blockedCount, result.rejectedCount);
      },
      async (joinId: string): Promise<EngineJoinSpaceStatus> => {
        let result: OhJoinSpaceStatus = await rawHandle.cancelJoinSpace(joinId);
        return new EngineJoinSpaceStatus(result.status, result.joinId, result.peerUpgradeRequired,
          result.rejectionReason);
      },
      async (): Promise<string> => (await rawHandle.refreshSharedDevices()).requestId,
      async (requestId: string): Promise<string | null> => {
        let result: OhSharedDeviceRefresh | null = await rawHandle.querySharedDeviceRefresh(requestId);
        return result === null ? null : JSON.stringify(result);
      },
      async (): Promise<EngineMemberRemoval> => {
        let result: OhMemberRemoval = await rawHandle.queryMemberRemoval();
        return new EngineMemberRemoval(result.phase, result.intentCount, result.effectiveMemberCount,
          result.convergenceDigest, result.updatedAtMs);
      });
  }
}

class CallbackEngineRuntimeHandle implements EngineRuntimeHandle {
  private lifecycleStateCallback: () => Promise<string>;
  private suspendCallback: () => Promise<void>;
  private resumeCallback: () => Promise<void>;
  private recoverNetworkCallback: () => Promise<void>;
  private queryNetworkSettingsCallback: () => Promise<EngineNetworkSettings>;
  private queryPairingDiagnosticsCallback: () => Promise<EnginePairingDiagnostics>;
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
  private queryNetworkRecoveryStatusCallback: (() => Promise<EngineNetworkRecoveryStatus>) | null = null;
  private queryLocalDeviceCallback: (() => Promise<EngineLocalDevice>) | null = null;
  private queryDeviceGroupChoicesCallback: (() => Promise<string>) | null = null;
  private queryMembershipConvergenceCallback: (() => Promise<EngineMembershipConvergence>) | null = null;
  private cancelJoinSpaceCallback: ((joinId: string) => Promise<EngineJoinSpaceStatus>) | null = null;
  private refreshSharedDevicesCallback: (() => Promise<string>) | null = null;
  private querySharedDeviceRefreshCallback: ((requestId: string) => Promise<string | null>) | null = null;
  private queryMemberRemovalCallback: (() => Promise<EngineMemberRemoval>) | null = null;

  constructor(lifecycleStateCallback: () => Promise<string>, suspendCallback: () => Promise<void>,
    resumeCallback: () => Promise<void>,
    recoverNetworkCallback: () => Promise<void>,
    queryNetworkSettingsCallback: () => Promise<EngineNetworkSettings>,
    queryPairingDiagnosticsCallback: () => Promise<EnginePairingDiagnostics>,
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
      confirmLocalRemoval: boolean) => Promise<string>,
    queryNetworkRecoveryStatusCallback: (() => Promise<EngineNetworkRecoveryStatus>) | null = null,
    queryLocalDeviceCallback: (() => Promise<EngineLocalDevice>) | null = null,
    queryDeviceGroupChoicesCallback: (() => Promise<string>) | null = null,
    queryMembershipConvergenceCallback: (() => Promise<EngineMembershipConvergence>) | null = null,
    cancelJoinSpaceCallback: ((joinId: string) => Promise<EngineJoinSpaceStatus>) | null = null,
    refreshSharedDevicesCallback: (() => Promise<string>) | null = null,
    querySharedDeviceRefreshCallback: ((requestId: string) => Promise<string | null>) | null = null,
    queryMemberRemovalCallback: (() => Promise<EngineMemberRemoval>) | null = null) {
    this.lifecycleStateCallback = lifecycleStateCallback;
    this.suspendCallback = suspendCallback;
    this.resumeCallback = resumeCallback;
    this.recoverNetworkCallback = recoverNetworkCallback;
    this.queryNetworkSettingsCallback = queryNetworkSettingsCallback;
    this.queryPairingDiagnosticsCallback = queryPairingDiagnosticsCallback;
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
    this.queryNetworkRecoveryStatusCallback = queryNetworkRecoveryStatusCallback;
    this.queryLocalDeviceCallback = queryLocalDeviceCallback;
    this.queryDeviceGroupChoicesCallback = queryDeviceGroupChoicesCallback;
    this.queryMembershipConvergenceCallback = queryMembershipConvergenceCallback;
    this.cancelJoinSpaceCallback = cancelJoinSpaceCallback;
    this.refreshSharedDevicesCallback = refreshSharedDevicesCallback;
    this.querySharedDeviceRefreshCallback = querySharedDeviceRefreshCallback;
    this.queryMemberRemovalCallback = queryMemberRemovalCallback;
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

  async queryPairingDiagnostics(): Promise<EnginePairingDiagnostics> {
    return await this.queryPairingDiagnosticsCallback();
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

  async queryNetworkRecoveryStatus(): Promise<EngineNetworkRecoveryStatus> {
    if (this.queryNetworkRecoveryStatusCallback === null) {
      return await unsupportedEngineOperation('query_network_recovery_status');
    }
    return await this.queryNetworkRecoveryStatusCallback();
  }

  async queryLocalDevice(): Promise<EngineLocalDevice> {
    if (this.queryLocalDeviceCallback === null) {
      return await unsupportedEngineOperation('query_local_device');
    }
    return await this.queryLocalDeviceCallback();
  }

  async queryDeviceGroupChoices(): Promise<string> {
    if (this.queryDeviceGroupChoicesCallback === null) {
      return await this.queryDeviceTrust();
    }
    return await this.queryDeviceGroupChoicesCallback();
  }

  async queryMembershipConvergence(): Promise<EngineMembershipConvergence> {
    if (this.queryMembershipConvergenceCallback === null) {
      return await unsupportedEngineOperation('query_membership_convergence');
    }
    return await this.queryMembershipConvergenceCallback();
  }

  async cancelJoinSpace(joinId: string): Promise<EngineJoinSpaceStatus> {
    if (this.cancelJoinSpaceCallback === null) {
      return await unsupportedEngineOperation('cancel_join_space');
    }
    return await this.cancelJoinSpaceCallback(joinId);
  }

  async refreshSharedDevices(): Promise<string> {
    if (this.refreshSharedDevicesCallback === null) {
      return await unsupportedEngineOperation('refresh_shared_devices');
    }
    return await this.refreshSharedDevicesCallback();
  }

  async querySharedDeviceRefresh(requestId: string): Promise<string | null> {
    if (this.querySharedDeviceRefreshCallback === null) {
      return await unsupportedEngineOperation('query_shared_device_refresh');
    }
    return await this.querySharedDeviceRefreshCallback(requestId);
  }

  async queryMemberRemoval(): Promise<EngineMemberRemoval> {
    if (this.queryMemberRemovalCallback === null) {
      return await unsupportedEngineOperation('query_member_removal');
    }
    return await this.queryMemberRemovalCallback();
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
  private processObservabilityInstalled: boolean = false;
  private processObservabilityLogDirectory: string = '';

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

  async prepareProcessDiagnosticExport(deadlineMs: number = 3000): Promise<string> {
    try {
      let report = await engine.prepareLocalDiagnosticExport(deadlineMs);
      return 'engine_local_diagnostic_export=' + report.status + '\n' +
        'engine_local_diagnostic_flush=' + report.flush + '\n' +
        'engine_local_diagnostic_requested_at=' + report.requestedAtUtc + '\n' +
        'engine_local_diagnostic_completed_at=' + report.completedAtUtc + '\n' +
        'engine_local_diagnostic_other_processes_flushed=' +
        report.otherProcessesFlushed.toString() + '\n';
    } catch (error) {
      logger.warn('Engine local diagnostic export failed');
      return 'engine_local_diagnostic_export=unavailable\n';
    }
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

  async queryPairingDiagnostics(): Promise<EnginePairingDiagnostics> {
    return await this.executeReadOnly('query_pairing_diagnostics',
      (handle: EngineRuntimeHandle): Promise<EnginePairingDiagnostics> =>
        handle.queryPairingDiagnostics());
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
    let decoded: EngineDeviceGroupChoicesPayload = JSON.parse(serialized) as EngineDeviceGroupChoicesPayload;
    let snapshot: EngineDeviceTrustSnapshotPayload = decoded.device_trust === undefined ?
      decoded as EngineDeviceTrustSnapshotPayload : decoded.device_trust;
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

  async queryDeviceGroupChoices(): Promise<string> {
    return await this.queryDeviceTrust();
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
      let runtimeError: EngineRuntimeError = this.fail('resume', error);
      logger.error('Engine resume failed category=' + runtimeError.category +
        ' operation=' + runtimeError.operation + ' detail=' + diagnosticDetailSummary(runtimeError.detail));
      throw runtimeError;
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
      this.installProcessObservabilityIfSupported(this.callbacks, bundleInfo.versionName);
      this.lastErrorCategory = '';
      this.setState(EngineRuntimeState.IDLE);
    } catch (error) {
      let runtimeError: EngineRuntimeError = this.fail('prepare', error);
      logger.error('Engine prepare failed category=' + runtimeError.category +
        ' operation=' + runtimeError.operation + ' detail=' + diagnosticDetailSummary(runtimeError.detail));
      throw runtimeError;
    }
  }

  private installProcessObservabilityIfSupported(callbacks: EngineHostCallbacks | null,
    appVersion: string): void {
    if (this.processObservabilityInstalled || callbacks === null ||
      !(this.backend instanceof OfficialEngineRuntimeBackend)) {
      return;
    }
    let directories: OhHostDirectories = {
      privateDataDirectory: callbacks.privateDataDirectory,
      cacheDirectory: callbacks.cacheDirectory,
      temporaryDirectory: callbacks.temporaryDirectory
    };
    try {
      let setup = engine.installProcessObservability({
        serviceVersion: appVersion,
        environment: 'development',
        appChannel: 'development',
        remoteDiagnosticsEnabled: false
      }, directories);
      this.processObservabilityInstalled = true;
      this.processObservabilityLogDirectory = directories.cacheDirectory + '/logs';
      logger.info('Engine process observability installed localFile=' + setup.localFile +
        ' reused=' + setup.reused.toString());
    } catch (error) {
      logger.warn('Engine process observability unavailable category=' + diagnosticErrorCategory(error) +
        ' operation=install_process_observability detail=' + diagnosticErrorDetail(error));
    }
  }

  private async logNativeDiagnosticTail(): Promise<void> {
    if (this.processObservabilityLogDirectory.length === 0) {
      return;
    }
    try {
      try {
        await engine.prepareLocalDiagnosticExport(1500);
      } catch (error) {
      }
      let date: string = new Date().toISOString().substring(0, 10);
      let path: string = this.processObservabilityLogDirectory + '/engine.' + date + '.jsonl';
      let file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        let stat: fileIo.Stat = fileIo.statSync(file.fd);
        let length: number = Math.min(stat.size, 65536);
        let offset: number = Math.max(0, stat.size - length);
        let buffer: ArrayBuffer = new ArrayBuffer(length);
        fileIo.readSync(file.fd, buffer, { offset: offset, length: length });
        let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', {
          fatal: false,
          ignoreBOM: true
        });
        let content: string = decoder.decodeToString(new Uint8Array(buffer));
        let pattern: RegExp = /(uc-engine startup failed|engine startup failed|dependency wiring|clipboard background|p2p session|application runtime|profile storage|startup_error)/i;
        let emitted: number = 0;
        let lines: string[] = content.split('\n');
        for (let index: number = 0; index < lines.length && emitted < 8; index += 1) {
          let line: string = lines[index].trim();
          if (line.length > 0 && pattern.test(line)) {
            logger.error('Engine native diagnostic line=' + diagnosticDetailSummary(line));
            emitted += 1;
          }
        }
        logger.info('Engine native diagnostic tail scanned_bytes=' + length.toString() +
          ' matched_lines=' + emitted.toString());
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (error) {
      logger.warn('Engine native diagnostic tail unavailable category=' +
        diagnosticErrorCategory(error) + ' detail=' + diagnosticErrorDetail(error));
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
      let runtimeError: EngineRuntimeError = this.fail('start', error);
      await this.logNativeDiagnosticTail();
      logger.error('Engine start failed category=' + runtimeError.category +
        ' operation=' + runtimeError.operation + ' detail=' + diagnosticDetailSummary(runtimeError.detail));
      throw runtimeError;
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
    let handle: EngineRuntimeHandle;
    try {
      handle = this.requireRunningHandle(operation);
    } catch (error) {
      let runtimeError: EngineRuntimeError = this.toRuntimeError(operation, error as Object);
      logger.error('Engine operation failed operation=' + operation + ' category=' + runtimeError.category);
      throw runtimeError;
    }
    try {
      let result: T = await action(handle);
      if (this.state === EngineRuntimeState.RUNNING && this.handle === handle && this.eventPollTask === null) {
        this.startEventPolling(handle);
      }
      return result;
    } catch (error) {
      // An operation failure such as a stale invitation must not tear down a healthy runtime.
      let runtimeError: EngineRuntimeError = this.toRuntimeError(operation, error);
      logger.error('Engine operation failed operation=' + operation + ' category=' + runtimeError.category);
      throw runtimeError;
    }
  }

  private async executeReadOnly<T>(operation: string,
    action: (handle: EngineRuntimeHandle) => Promise<T>): Promise<T> {
    let handle: EngineRuntimeHandle;
    try {
      handle = this.requireRunningHandle(operation);
    } catch (error) {
      let runtimeError: EngineRuntimeError = this.toRuntimeError(operation, error as Object);
      logger.error('Engine read-only operation failed operation=' + operation +
        ' category=' + runtimeError.category);
      throw runtimeError;
    }
    try {
      return await action(handle);
    } catch (error) {
      let runtimeError: EngineRuntimeError = this.toRuntimeError(operation, error);
      logger.error('Engine read-only operation failed operation=' + operation +
        ' category=' + runtimeError.category);
      throw runtimeError;
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
      return new EngineRuntimeError(hostError.category, operation, hostError.message);
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
