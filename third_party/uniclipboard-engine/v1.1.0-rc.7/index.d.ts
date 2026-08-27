export interface OhEngineConfig {
  appVersion: string
  profileId: string
}

export interface OhFileMetadata {
  displayName: string
  sizeBytes: string
  mimeType?: string
}

export interface OhClipboardRepresentation {
  kind: string
  format: string
  mimeType?: string
  bytes?: Uint8Array
  handle?: string
  displayName?: string
  sizeBytes?: string
}

export interface OhClipboardSnapshot {
  observedAtMs: number
  representations: OhClipboardRepresentation[]
}

export interface OhHost {
  privateDataDirectory: string
  cacheDirectory: string
  temporaryDirectory: string
  secureStorageGet(key: string): OhHostResult<Uint8Array | null>
  secureStorageSet(key: string, value: Uint8Array): OhHostResult<void>
  secureStorageDelete(key: string): OhHostResult<void>
  fileMetadata(handle: string): OhHostResult<OhFileMetadata>
  fileReadChunk(handle: string, offset: string, maxBytes: number): OhHostResult<Uint8Array>
  fileWriteChunk(handle: string, offset: string, bytes: Uint8Array): OhHostResult<void>
  fileFinishWrite(handle: string): OhHostResult<void>
  clipboardRead(): OhHostResult<OhClipboardSnapshot>
  clipboardWrite(snapshot: OhClipboardSnapshot): OhHostResult<void>
}

export interface OhHostResult<T> {
  ok: boolean
  value?: T
  errorCategory?: string
}

export type PreparedHost = object

export interface OhSendReport {
  entryId: string
  atMs: number
  totalAccepted: number
  totalDuplicate: number
  totalOffline: number
  totalErrored: number
  totalPending: number
}

export interface OhSessionRecovery {
  unlocked: boolean
  resumed: boolean
}

export interface OhNetworkRecoveryStatus {
  phase: string
  retryable: boolean
  nextRetryInMs?: number
}

export interface OhNetworkSettings {
  allowRelayFallback: boolean
  customRelayUrls: string[]
}

export interface OhLocalDevice {
  deviceId: string
  displayName: string
}

export interface OhContentTypes {
  text: boolean
  image: boolean
  link: boolean
  file: boolean
  codeSnippet: boolean
  richText: boolean
}

export interface OhContentTypesPatch {
  text?: boolean
  image?: boolean
  link?: boolean
  file?: boolean
  codeSnippet?: boolean
  richText?: boolean
}

export interface OhMemberSyncPreferences {
  sendEnabled: boolean
  receiveEnabled: boolean
  sendContentTypes: OhContentTypes
  receiveContentTypes: OhContentTypes
}

export interface OhMemberSyncPreferencesPatch {
  sendEnabled?: boolean
  receiveEnabled?: boolean
  sendContentTypes?: OhContentTypesPatch
  receiveContentTypes?: OhContentTypesPatch
}

export interface OhWorkspaceConvergence {
  phase: string
  revision: number
  historyEventCount: number
  effectiveMemberCount: number
  pendingRemovalDecisionDeviceIds: string[]
  pendingRemovalDecisionEventId?: string
  divergedPeerDeviceIds: string[]
  upgradeRequiredPeerDeviceIds: string[]
  convergenceDigest?: string
  removed: boolean
  updatedAtMs: number
  failureCategory?: string
}

export interface OhEngineEvent {
  kind: string
  state?: string
  refreshReason?: string
  operationId?: string
  terminal?: string
  lifecycleAction?: string
  errorCode?: number
  errorCategory?: string
  retryable?: boolean
  workspaceConvergence?: OhWorkspaceConvergence
  deviceTrustRevision?: number
  networkRecoveryPhase?: string
  nextRetryInMs?: number
  rePairingScope?: string
}

export interface OhSpaceCreated {
  spaceId: string
  selfDeviceId: string
  identityFingerprint: string
}

export interface OhActiveClipboard {
  entryId: string
  activatedBy: string
}

export interface OhInvitationIssued {
  invitationCode: string
  expiresAtMs: number
  availability: string
}

export interface OhJoinedSpace {
  sponsorDeviceId: string
  sponsorIdentityFingerprint: string
  spaceId: string
  selfDeviceId: string
  selfIdentityFingerprint: string
  migratedRecords?: string
  preservedUnreadableRecords?: string
}

export interface OhJoinSpaceStatus {
  status: string
  joinId: string
  joinedSpace?: OhJoinedSpace
  targetSpaceId?: string
  sponsorDeviceId?: string
  sponsorIdentityFingerprint?: string
  cancelRequested?: boolean
  rejectionReason?: string
}

export interface OhEngine {
  createSpace(deviceName: string | null, passphrase: string): Promise<OhSpaceCreated>
  recoverSession(allowSecureStorageUnlock: boolean): Promise<OhSessionRecovery>
  recoverNetwork(): Promise<void>
  queryNetworkRecoveryStatus(): Promise<OhNetworkRecoveryStatus>
  queryNetworkSettings(): Promise<OhNetworkSettings>
  updateNetworkSettings(allowRelayFallback: boolean, customRelayUrls: string[]): Promise<OhNetworkSettings>
  probeRelayUrl(url: string): Promise<number>
  queryLocalDevice(): Promise<OhLocalDevice>
  queryMemberSyncPreferences(deviceId: string): Promise<OhMemberSyncPreferences>
  updateMemberSyncPreferences(deviceId: string, patch: OhMemberSyncPreferencesPatch): Promise<OhMemberSyncPreferences>
  queryDeviceTrust(): Promise<string>
  decideDeviceTrustChange(
    changeId: string,
    choice: string,
    confirmLocalRemoval: boolean
  ): Promise<string>
  removeMember(deviceId: string): Promise<OhWorkspaceConvergence>
  issueInvitation(): Promise<OhInvitationIssued>
  joinSpace(
    invitationCode: string,
    deviceName: string | null,
    passphrase: string,
    preserveUnreadableHistory: boolean
  ): Promise<OhJoinSpaceStatus>
  cancelJoinSpace(joinId: string): Promise<OhJoinSpaceStatus>
  queryActiveClipboard(): Promise<OhActiveClipboard | null>
  lifecycleState(): Promise<string>
  suspend(): Promise<void>
  resume(): Promise<void>
  sendText(text: string, targetDevices: string[]): Promise<OhSendReport>
  sendImage(bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<OhSendReport>
  sendFiles(fileHandles: string[], targetDevices: string[]): Promise<OhSendReport>
  captureCurrentClipboard(): Promise<string | null>
  restoreClipboard(
    entryId: string,
    mode: string
  ): Promise<string>
  exportEntry(entryId: string, destinationHandle: string): Promise<void>
  nextEvent(timeoutMs: number): Promise<OhEngineEvent | null>
  shutdown(deadlineMs: number): Promise<void>
}

declare const engine: {
  coreVersion(): string
  prepareHost(host: OhHost): PreparedHost
  startEngine(config: OhEngineConfig, preparedHost: PreparedHost): Promise<OhEngine>
}

export default engine
