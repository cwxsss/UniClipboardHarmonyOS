# HarmonyOS Device List and Engine Recovery Design

## Problem

HarmonyOS currently maps every relationship returned by `queryDeviceTrust()` into the paired-device list. Engine intentionally includes historical `removed` relationships for diagnostics, so a successfully removed device is immediately re-added to the UI as an offline device. A second removal then fails with `member_removal_target_not_found` (`1382`).

The HarmonyOS package also vendors Engine `v1.1.0-rc.5`, while the Windows client uses later admission-recovery fixes. This leaves sponsor/joiner restart behavior inconsistent and can preserve an incomplete member fingerprint record that rejects Windows clipboard traffic.

## Scope

- HarmonyOS UI, runtime service, and vendored Engine only.
- Show only the local device and effective active paired members in the ordinary paired-device list.
- Keep historical removed relationships available to diagnostics, not to normal device actions.
- Update the vendored Engine to the reviewed recovery commit used by Windows.
- Do not clear user data or silently accept unknown device identities.

## Design

### Device projection

`EngineRuntimeService.queryDevices()` will classify relationship state before creating `EngineRuntimeDevice` values. The normal UI receives:

- the local device;
- effective active members whose membership is `active` and whose sync relationship is not `removed_peer_device`.

Relationships marked `removed`, `removed_peer_device`, or other non-effective historical states are excluded from actionable lists. A helper with table-driven tests owns this projection so expanded, compact, and share-target views use the same behavior.

### Removal behavior

`revokeSpaceDevice()` continues to call Engine for effective members, removes the local row optimistically, and refreshes from the filtered projection. Offline effective members remain removable. Historical records never expose a remove action because they are absent from the actionable list. Engine error `1382` is still treated as an actual not-found result if reached through stale UI state.

### Engine integration

The vendored `rust/space-core` is updated to the reviewed Engine recovery revision. HarmonyOS startup continues to restore the active profile first and background joined profiles afterward. Each profile retains its own storage and secure identity scope. The update must preserve the legacy profile's existing identity alias and database path so an application upgrade does not create a new endpoint key.

### Observability

Runtime logs identify profile id, operation kind, and stable error category while redacting invitation material, secure-store values, and raw fingerprints. Receiver rejection diagnostics distinguish membership recovery failures from malformed clipboard data.

## Verification

- A failing projection test proves `removed` and `removed_peer_device` relationships currently leak into the UI; the production filter makes it pass.
- Tests retain offline active members and the local device.
- Controller test proves a removed device does not reappear after refresh.
- Vendored Engine revision and HarmonyOS HAR build are verified.
- Signed HAP is installed on the connected phone and tested against the Windows client for text copy, restart recovery, new-device admission, offline-member removal, and unknown-device rejection.

