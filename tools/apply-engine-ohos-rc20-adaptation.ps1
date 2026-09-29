param(
  [Parameter(Mandatory = $true)]
  [string]$EngineRoot
)

$ErrorActionPreference = 'Stop'
$expectedCommit = '3f3eef7450e06013c3178b716eee9d5a3c419349'
$engineRootPath = [System.IO.Path]::GetFullPath($EngineRoot)
$actualCommit = (& git -C $engineRootPath rev-parse HEAD).Trim()
if ($actualCommit -ne $expectedCommit) {
  throw "Expected Engine rc20 commit $expectedCommit, got $actualCommit"
}
$lf = [string][char]10
$crlf = [string][char]13 + $lf
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$runtimePath = Join-Path $engineRootPath 'bindings/uc-ohos-napi/src/runtime.rs'
$declarationPath = Join-Path $engineRootPath 'bindings/uc-ohos-napi/ohos/index.d.ts'
$runtime = [System.IO.File]::ReadAllText($runtimePath)
$runtimeHadCrLf = $runtime.Contains($crlf)
$runtime = $runtime.Replace($crlf, $lf)
if ($runtime.Contains('pub async fn query_network_settings')) {
  throw 'The Harmony rc20 N-API adaptation is already applied to runtime.rs'
}

$runtimeInsert = @'
    #[napi]
    pub async fn query_network_settings(&self) -> napi::Result<String> {
        match self
            .engine
            .execute(Operation::QuerySettings)
            .await
            .map_err(engine_error)?
        {
            OperationResult::Settings(settings) => serde_json::to_string(&serde_json::json!({
                "allowRelayFallback": settings.network.allow_relay_fallback,
                "customRelayUrls": settings.network.custom_relay_urls,
            }))
            .map_err(|_| unexpected_result()),
            _ => Err(unexpected_result()),
        }
    }

    #[napi]
    pub async fn update_network_settings(
        &self,
        allow_relay_fallback: bool,
        custom_relay_urls: Vec<String>,
    ) -> napi::Result<String> {
        let patch = uc_engine::SettingsPatch {
            network: Some(uc_engine::NetworkSettingsPatch {
                allow_relay_fallback: Some(allow_relay_fallback),
                custom_relay_urls: Some(custom_relay_urls),
                ..Default::default()
            }),
            ..Default::default()
        };
        match self
            .engine
            .execute(Operation::UpdateSettings(Box::new(patch)))
            .await
            .map_err(engine_error)?
        {
            OperationResult::SettingsUpdated(uc_engine::SettingsUpdateOutcome::Updated(settings)) => {
                serde_json::to_string(&serde_json::json!({
                    "allowRelayFallback": settings.network.allow_relay_fallback,
                    "customRelayUrls": settings.network.custom_relay_urls,
                }))
                .map_err(|_| unexpected_result())
            }
            OperationResult::SettingsUpdated(uc_engine::SettingsUpdateOutcome::Rejected { .. }) => {
                Err(napi::Error::new(Status::InvalidArg, "OHOS_NETWORK_SETTINGS_REJECTED"))
            }
            _ => Err(unexpected_result()),
        }
    }

    #[napi]
    pub async fn probe_relay_url(&self, url: String) -> napi::Result<u32> {
        match self
            .engine
            .execute(Operation::ProbeRelay(uc_engine::RelayProbeInput {
                url,
                credential: uc_engine::RelayProbeCredential::Stored,
            }))
            .await
            .map_err(engine_error)?
        {
            OperationResult::RelayProbed(uc_engine::RelayProbeOutcome::Success { latency_ms }) => {
                Ok(latency_ms)
            }
            OperationResult::RelayProbed(_) => Err(napi::Error::new(
                Status::GenericFailure,
                "UC_ENGINE:1393:unavailable:true",
            )),
            _ => Err(unexpected_result()),
        }
    }

    #[napi]
    pub async fn query_member_sync_preferences(&self, device_id: String) -> napi::Result<String> {
        match self
            .engine
            .execute(Operation::QueryMemberSyncPreferences(
                uc_engine::QueryMemberSyncPreferencesInput { device_id },
            ))
            .await
            .map_err(engine_error)?
        {
            OperationResult::MemberSyncPreferences(preferences) => {
                member_sync_preferences_json(preferences)
            }
            _ => Err(unexpected_result()),
        }
    }

    #[napi]
    pub async fn update_member_sync_preferences(
        &self,
        device_id: String,
        patch_json: String,
    ) -> napi::Result<String> {
        let patch = serde_json::from_str::<uc_engine::MemberSyncPreferencesPatch>(&patch_json)
            .map_err(|_| {
                napi::Error::new(Status::InvalidArg, "OHOS_INVALID_MEMBER_SYNC_PREFERENCES_PATCH")
            })?;
        match self
            .engine
            .execute(Operation::UpdateMemberSyncPreferences(
                uc_engine::UpdateMemberSyncPreferencesInput { device_id, patch },
            ))
            .await
            .map_err(engine_error)?
        {
            OperationResult::MemberSyncPreferences(preferences) => {
                member_sync_preferences_json(preferences)
            }
            _ => Err(unexpected_result()),
        }
    }

    #[napi]
    pub async fn list_devices(&self) -> napi::Result<String> {
        match self
            .engine
            .execute(Operation::ListDevices)
            .await
            .map_err(engine_error)?
        {
            OperationResult::Devices(devices) => serde_json::to_string(
                &devices
                    .into_iter()
                    .map(|device| {
                        serde_json::json!({
                            "deviceId": device.device_id,
                            "displayName": device.display_name,
                            "isLocal": device.is_local,
                            "online": device.online,
                        })
                    })
                    .collect::<Vec<_>>(),
            )
            .map_err(|_| unexpected_result()),
            _ => Err(unexpected_result()),
        }
    }

    #[napi]
    pub async fn refresh_peer_connections(&self) -> napi::Result<()> {
        match self
            .engine
            .execute(Operation::RefreshPeerConnections)
            .await
            .map_err(engine_error)?
        {
            OperationResult::PeerConnectionsRefreshed(_) => Ok(()),
            _ => Err(unexpected_result()),
        }
    }
'@.Trim([char]10)

$runtimeAnchor = '    #[napi]' + $lf + '    pub async fn query_network_recovery_status'
if (($runtime.IndexOf($runtimeAnchor) -lt 0) -or
    ($runtime.IndexOf($runtimeAnchor, $runtime.IndexOf($runtimeAnchor) + 1) -ge 0)) {
  throw 'Could not uniquely locate the N-API runtime insertion point'
}
$runtime = $runtime.Replace($runtimeAnchor, $runtimeInsert + $lf + $lf + $runtimeAnchor)

$helperInsert = @'
fn member_sync_preferences_json(
    preferences: uc_engine::MemberSyncPreferencesSummary,
) -> napi::Result<String> {
    serde_json::to_string(&serde_json::json!({
        "sendEnabled": preferences.send_enabled,
        "receiveEnabled": preferences.receive_enabled,
        "sendContentTypes": {
            "text": preferences.send_content_types.text,
            "image": preferences.send_content_types.image,
            "file": preferences.send_content_types.file,
            "link": preferences.send_content_types.link,
            "codeSnippet": preferences.send_content_types.code_snippet,
            "richText": preferences.send_content_types.rich_text,
        },
        "receiveContentTypes": {
            "text": preferences.receive_content_types.text,
            "image": preferences.receive_content_types.image,
            "file": preferences.receive_content_types.file,
            "link": preferences.receive_content_types.link,
            "codeSnippet": preferences.receive_content_types.code_snippet,
            "richText": preferences.receive_content_types.rich_text,
        },
    }))
    .map_err(|_| unexpected_result())
}
'@.Trim([char]10)
$helperAnchor = 'fn workspace_convergence('
if (($runtime.IndexOf($helperAnchor) -lt 0) -or
    ($runtime.IndexOf($helperAnchor, $runtime.IndexOf($helperAnchor) + 1) -ge 0)) {
  throw 'Could not uniquely locate the N-API helper insertion point'
}
$runtime = $runtime.Replace($helperAnchor, $helperInsert + $lf + $lf + $helperAnchor)
if ($runtimeHadCrLf) {
  $runtime = $runtime.Replace($lf, $crlf)
}
[System.IO.File]::WriteAllText($runtimePath, $runtime, $utf8NoBom)

$declarations = [System.IO.File]::ReadAllText($declarationPath)
$declarationsHadCrLf = $declarations.Contains($crlf)
$declarations = $declarations.Replace($crlf, $lf)
if ($declarations.Contains('workspaceConvergence?: OhWorkspaceConvergence')) {
  throw 'The Harmony rc20 N-API declaration adaptation is already applied'
}
$oldRemoval = @'
export interface OhMemberRemoval {
  phase: 'applied' | 'converging' | 'complete' | 'recovery_required'
  intentCount: number
  effectiveMemberCount: number
  convergenceDigest?: string
  updatedAtMs: number
}
'@.Trim([char]10)
$newConvergence = @'
export interface OhWorkspaceConvergence {
  phase: 'locally_applied' | 'converging' | 'complete' | 'recovery_required'
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
'@.Trim([char]10)
$first = $declarations.IndexOf($oldRemoval)
if (($first -lt 0) -or ($declarations.IndexOf($oldRemoval, $first + 1) -ge 0)) {
  throw 'Could not uniquely locate the old member removal declaration'
}
$declarations = $declarations.Remove($first, $oldRemoval.Length).Insert($first, $newConvergence)

$oldEvent = @'
  memberRemoval?: OhMemberRemoval
  sharedDeviceRefresh?: OhSharedDeviceRefresh
'@.Trim([char]10)
$newEvent = @'
  workspaceConvergence?: OhWorkspaceConvergence
  deviceTrustRevision?: number
'@.Trim([char]10)
$first = $declarations.IndexOf($oldEvent)
if (($first -lt 0) -or ($declarations.IndexOf($oldEvent, $first + 1) -ge 0)) {
  throw 'Could not uniquely locate the old engine event fields'
}
$declarations = $declarations.Remove($first, $oldEvent.Length).Insert($first, $newEvent)
$declarations = $declarations.Replace(
  "status: 'active' | 'pending' | 'processing' | 'rejected' | 'terminated'",
  "status: 'active' | 'pending' | 'processing' | 'needs_attention' | 'rejected' | 'terminated'")
$declarations = $declarations.Replace(
  "  terminationReason?: 'cancelled' | 'expired' | 'superseded'" + $lf + '}',
  "  terminationReason?: 'cancelled' | 'expired' | 'superseded'" + $lf +
    '  attentionReason?: string' + $lf + '  attentionRecovery?: string' + $lf +
    '  nextRetryAtMs?: number' + $lf + '}')

$engineStart = $declarations.IndexOf('export interface OhEngine {')
$engineEnd = $declarations.IndexOf('export interface OhStartupLifecycle', $engineStart)
if (($engineStart -lt 0) -or ($engineEnd -lt 0) -or
    ($declarations.IndexOf('export interface OhEngine {', $engineStart + 1) -ge 0)) {
  throw 'Could not uniquely locate the OhEngine declaration'
}
$newEngine = @'
export interface OhEngine {
  createSpace(deviceName: string | null, passphrase: string): Promise<OhSpaceCreated>
  recoverSession(allowSecureStorageUnlock: boolean): Promise<OhSessionRecovery>
  notifyConnectivityOpportunity(reason: 'foreground' | 'system_wake' | 'network_changed'): Promise<void>
  recoverNetwork(): Promise<void>
  queryNetworkSettings(): Promise<string>
  updateNetworkSettings(allowRelayFallback: boolean, customRelayUrls: string[]): Promise<string>
  probeRelayUrl(url: string): Promise<number>
  queryMemberSyncPreferences(deviceId: string): Promise<string>
  updateMemberSyncPreferences(deviceId: string, patchJson: string): Promise<string>
  listDevices(): Promise<string>
  refreshPeerConnections(): Promise<void>
  queryNetworkRecoveryStatus(): Promise<OhNetworkRecoveryStatus>
  queryLocalDevice(): Promise<OhLocalDevice>
  queryDeviceGroupChoices(): Promise<string>
  chooseDeviceGroup(issueId: string, choiceId: string, expectedRevision: number, confirmLocalRemoval: boolean): Promise<string>
  issueInvitation(): Promise<OhInvitationIssued>
  changeEncryptionPassphrase(passphrase: string, passphraseConfirmation: string): Promise<void>
  joinSpace(
    invitationCode: string,
    deviceName: string | null,
    passphrase: string,
    preserveUnreadableHistory: boolean
  ): Promise<OhJoinSpaceStatus>
  cancelJoinSpace(joinId: string): Promise<OhJoinSpaceStatus>
  removeMember(deviceId: string): Promise<OhWorkspaceConvergence>
  queryActiveClipboard(): Promise<OhActiveClipboard | null>
  captureCurrentClipboard(): Promise<string | null>
  restoreClipboard(entryId: string, mode: 'standard' | 'plain_text' | 'file_paths'): Promise<string>
  lifecycleState(): Promise<string>
  suspend(): Promise<void>
  suspendWithDeadline(deadlineMs: number): Promise<void>
  resume(): Promise<void>
  sendText(text: string, targetDevices: string[]): Promise<OhSendReport>
  sendImage(bytes: Uint8Array, mimeType: string, targetDevices: string[]): Promise<OhSendReport>
  sendFiles(fileHandles: string[], targetDevices: string[]): Promise<OhSendReport>
  exportEntry(entryId: string, destinationHandle: string): Promise<void>
  nextEvent(timeoutMs: number): Promise<OhEngineEvent | null>
  shutdown(deadlineMs: number): Promise<void>
  shutdownUntilComplete(): Promise<void>
}
'@.Trim([char]10)
$declarations = $declarations.Substring(0, $engineStart) + $newEngine + $lf + $lf +
  $declarations.Substring($engineEnd)
if ($declarationsHadCrLf) {
  $declarations = $declarations.Replace($lf, $crlf)
}
[System.IO.File]::WriteAllText($declarationPath, $declarations, $utf8NoBom)
Write-Output "Applied Harmony OHOS N-API adapter to Engine $expectedCommit"
