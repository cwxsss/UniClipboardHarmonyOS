$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root 'common/src/main/ets/service/EngineRuntimeService.ets'
$controllerPath = Join-Path $root 'features/clipboard/src/main/ets/viewmodel/ClipboardFeatureController.ets'
function Read-Utf8Source([string]$path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  $offset = if ($bom) { 3 } else { 0 }
  [pscustomobject]@{ Text = [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset); Bom = $bom }
}
function Replace-Once([string]$text, [string]$old, [string]$new, [string]$label) {
  $old = $old.Replace('`n', [string][char]10)
  $new = $new.Replace('`n', [string][char]10)
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { throw "Expected one match for $label, found $count" }
  return $text.Replace($old, $new)
}
function Write-Utf8Source([string]$path, [string]$text, [bool]$bom) {
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($bom))
}
$s = Read-Utf8Source $servicePath
$nl = if ($s.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
$t = $s.Text.Replace("`r`n", "`n")
$t = Replace-Once $t '  OhMemberRemoval,`n' '' 'remove obsolete OhMemberRemoval import'
$t = Replace-Once $t '  OhMemberSyncPreferences,`n' '' 'remove obsolete OhMemberSyncPreferences import'
$t = Replace-Once $t '  OhMembershipConvergence,`n' '' 'remove obsolete OhMembershipConvergence import'
$t = Replace-Once $t '  OhNetworkSettings,`n' '' 'remove obsolete OhNetworkSettings import'
$t = Replace-Once $t '  OhSharedDeviceRefresh,`n' '' 'remove obsolete OhSharedDeviceRefresh import'
$t = Replace-Once $t '  OhStartupLifecycle,`n' '  OhStartupLifecycle,`n  OhWorkspaceConvergence,`n' 'add rc20 convergence type'
$t = Replace-Once $t 'import {`n  EngineDeviceTrustRelationshipPayload,`n  EngineDeviceTrustSnapshotPayload,`n  projectActionableDeviceTrustRows`n} from ''./DeviceTrustProjection'';`n' '' 'remove old device-trust projection import'
$t = Replace-Once $t '  memberRemoval: string | undefined = undefined;`n  sharedDeviceRefresh: string | undefined = undefined;`n' '  workspaceConvergence: string | undefined = undefined;`n  deviceTrustRevision: number | undefined = undefined;`n' 'replace obsolete event fields'
$t = Replace-Once $t '        event.memberRemoval = rawEvent.memberRemoval === undefined ? undefined : JSON.stringify(rawEvent.memberRemoval);`n        event.sharedDeviceRefresh = rawEvent.sharedDeviceRefresh === undefined ?`n          undefined : JSON.stringify(rawEvent.sharedDeviceRefresh);`n' '        event.workspaceConvergence = rawEvent.workspaceConvergence === undefined ?`n          undefined : JSON.stringify(rawEvent.workspaceConvergence);`n        event.deviceTrustRevision = rawEvent.deviceTrustRevision;`n' 'map rc20 runtime events'
$old = @"
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
"@
$new = @"
interface EngineDeviceSummaryPayload {
  deviceId: string;
  displayName: string;
  isLocal: boolean;
  online: boolean;
}

export class EngineWorkspaceConvergence {
  phase: string;
  revision: number;
  historyEventCount: number;
  effectiveMemberCount: number;
  pendingRemovalDecisionDeviceIds: string[];
  pendingRemovalDecisionEventId: string | undefined;
  divergedPeerDeviceIds: string[];
  upgradeRequiredPeerDeviceIds: string[];
  convergenceDigest: string | undefined;
  removed: boolean;
  updatedAtMs: number;
  failureCategory: string | undefined;

  constructor(result: OhWorkspaceConvergence) {
    this.phase = result.phase;
    this.revision = result.revision;
    this.historyEventCount = result.historyEventCount;
    this.effectiveMemberCount = result.effectiveMemberCount;
    this.pendingRemovalDecisionDeviceIds = result.pendingRemovalDecisionDeviceIds;
    this.pendingRemovalDecisionEventId = result.pendingRemovalDecisionEventId;
    this.divergedPeerDeviceIds = result.divergedPeerDeviceIds;
    this.upgradeRequiredPeerDeviceIds = result.upgradeRequiredPeerDeviceIds;
    this.convergenceDigest = result.convergenceDigest;
    this.removed = result.removed;
    this.updatedAtMs = result.updatedAtMs;
    this.failureCategory = result.failureCategory;
  }
}
"@
$t = Replace-Once $t $old $new 'replace rc17 convergence/device payload models'
$t = Replace-Once $t '      (): Promise<EngineNetworkSettings> => rawHandle.queryNetworkSettings().then((result: OhNetworkSettings) =>`n        new EngineNetworkSettings(result.allowRelayFallback, result.customRelayUrls)),`n' '      (): Promise<EngineNetworkSettings> => rawHandle.queryNetworkSettings().then((serialized: string) =>`n        JSON.parse(serialized) as EngineNetworkSettings),`n' 'decode rc20 network settings JSON'
$t = Replace-Once $t '      (allowRelayFallback: boolean, customRelayUrls: string[]): Promise<EngineNetworkSettings> =>`n        rawHandle.updateNetworkSettings(allowRelayFallback, customRelayUrls).then((result: OhNetworkSettings) =>`n          new EngineNetworkSettings(result.allowRelayFallback, result.customRelayUrls)),`n' '      (allowRelayFallback: boolean, customRelayUrls: string[]): Promise<EngineNetworkSettings> =>`n        rawHandle.updateNetworkSettings(allowRelayFallback, customRelayUrls).then((serialized: string) =>`n          JSON.parse(serialized) as EngineNetworkSettings),`n' 'decode updated rc20 network settings JSON'
$old = @"
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
"@
$new = @"
      (deviceId: string): Promise<EngineMemberSyncPreferences> => rawHandle.queryMemberSyncPreferences(deviceId).then(
        (serialized: string) => normalizeMemberSyncPreferences(JSON.parse(serialized) as LegacyMemberSyncPreferencesPayload)),
      (deviceId: string, sendEnabled: boolean, text: boolean, imageEnabled: boolean, file: boolean,
        link: boolean, richText: boolean): Promise<EngineMemberSyncPreferences> => rawHandle.updateMemberSyncPreferences(
        deviceId, JSON.stringify({
          send_enabled: sendEnabled,
          send_content_types: { text: text, image: imageEnabled, file: file, link: link, rich_text: richText }
        })).then((serialized: string) =>
          normalizeMemberSyncPreferences(JSON.parse(serialized) as LegacyMemberSyncPreferencesPayload)),
      (deviceId: string): Promise<EngineMemberSyncPreferences> => rawHandle.updateMemberSyncPreferences(deviceId,
        JSON.stringify({
          send_enabled: true,
          receive_enabled: true,
          send_content_types: { text: true, image: true, file: true, link: true, code_snippet: true, rich_text: true },
          receive_content_types: { text: true, image: true, file: true, link: true, code_snippet: true, rich_text: true }
        })).then((serialized: string) =>
          normalizeMemberSyncPreferences(JSON.parse(serialized) as LegacyMemberSyncPreferencesPayload)),
"@
$t = Replace-Once $t $old $new 'adapt member sync preferences JSON and snake_case patch'
$old = @"
      async (deviceId: string): Promise<EngineWorkspaceConvergence> => {
        let result: OhMemberRemoval = await rawHandle.removeMember(deviceId);
        return new EngineWorkspaceConvergence(result.phase, result.effectiveMemberCount,
          result.updatedAtMs);
      },
      (): Promise<string> => rawHandle.queryDeviceGroupChoices(),
"@
$new = @"
      async (deviceId: string): Promise<EngineWorkspaceConvergence> => {
        let result: OhWorkspaceConvergence = await rawHandle.removeMember(deviceId);
        return new EngineWorkspaceConvergence(result);
      },
      (): Promise<string> => rawHandle.listDevices(),
"@
$t = Replace-Once $t $old $new 'map member removal and official device list'
$old = @"
      (): Promise<string> => rawHandle.queryDeviceGroupChoices(),
      async (): Promise<EngineMembershipConvergence> => {
        let result: OhMembershipConvergence = await rawHandle.queryMembershipConvergence();
        return new EngineMembershipConvergence(result.state, result.pendingCount,
          result.waitingForPeerCount, result.waitingForUpdateCount, result.versionIncompatibleCount,
          result.blockedCount, result.rejectedCount);
      },
"@
$new = @"
      (): Promise<string> => rawHandle.queryDeviceGroupChoices(),
      null,
"@
$t = Replace-Once $t $old $new 'disable removed membership convergence operation'
$old = @"
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
"@
$new = @"
      null,
      null,
      null);
"@
$t = Replace-Once $t $old $new 'disable removed shared refresh and member removal status APIs'
$old = @"
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
"@
$new = @"
  async queryDevices(): Promise<EngineRuntimeDevice[]> {
    let serialized: string = await this.executeReadOnly('list_devices',
      (handle: EngineRuntimeHandle): Promise<string> => handle.queryDeviceTrust());
    if (serialized.trim().length === 0) {
      return [];
    }
    let sources: EngineDeviceSummaryPayload[] = JSON.parse(serialized) as EngineDeviceSummaryPayload[];
    let devices: EngineRuntimeDevice[] = [];
    for (let index: number = 0; index < sources.length; index++) {
      let source: EngineDeviceSummaryPayload = sources[index];
      let name: string = source.displayName.length > 0 ? source.displayName : source.deviceId;
      let state: string = source.isLocal ? 'local' : (source.online ? 'online' : 'offline');
      let channel: string = source.isLocal ? 'local' : (source.online ? 'unknown' : 'offline');
      devices.push(new EngineRuntimeDevice(source.deviceId, name, source.isLocal,
        source.online, state, channel));
    }
    return devices;
  }
"@
$t = Replace-Once $t $old $new 'consume rc20 ListDevices summary'
$old = @"
  async queryDeviceGroupChoices(): Promise<string> {
    return await this.queryDeviceTrust();
  }
"@
$new = @"
  async queryDeviceGroupChoices(): Promise<string> {
    return await this.executeReadOnly('query_device_group_choices',
      (handle: EngineRuntimeHandle): Promise<string> => handle.queryDeviceGroupChoices());
  }
"@
$t = Replace-Once $t $old $new 'separate device choices from device list'
$t = $t.Replace("`n", $nl)
Write-Utf8Source $servicePath $t $s.Bom
$c = Read-Utf8Source $controllerPath
$nl2 = if ($c.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
$ct = $c.Text.Replace("`r`n", "`n")
$ct = Replace-Once $ct '        this.spacePassphrase, true);' '        this.spacePassphrase, false);' 'match PC default for unreadable history migration'
$ct = $ct.Replace("`n", $nl2)
Write-Utf8Source $controllerPath $ct $c.Bom
Write-Output 'Applied Harmony Engine rc20 runtime and join-default adaptations.'