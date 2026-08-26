# HarmonyOS Device List and Engine Recovery Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use subagent-driven-development to execute this plan task-by-task. Follow test-driven-development for each production behavior and verification-before-completion before installing or publishing.

**Goal:** Make the HarmonyOS client hide historical/removed trust records, remove offline active peers permanently from the visible list, and consume the verified Engine identity-recovery revision so Windows clipboard frames are accepted after normal pairing and restart without resets.

**Architecture:** Convert the Engine device-trust snapshot into an actionable UI projection at the runtime-service boundary: always include the local device and only effective active remote memberships. The controller remains responsible for user confirmation and selection cleanup, while refresh becomes idempotent because historical records are filtered centrally. Replace the vendored immutable Engine bundle with a reproducibly built, checksum-verified bundle from the reviewed Engine commit; preserve profile/path aliases so the same local cryptographic identity is reused.

**Tech Stack:** ArkTS, Hypium, Hvigor, HarmonyOS API 24, Rust Engine HAR, HDC wireless device testing.

---

### Task 1: Filter device-trust history at the runtime-service boundary

**Files:**
- Modify: `common/src/main/ets/service/EngineRuntimeService.ets`
- Modify: `common/src/test/EngineRuntimeService.test.ets`

**Step 1: Write failing projection tests**

Make `TestRuntimeHandle.queryDeviceTrust()` configurable, then add tests covering one mixed snapshot with:

- local device;
- active online remote;
- active offline remote;
- `membership=removed` remote;
- `sync_relationship=removed_peer_device` remote;
- history-only/unknown remote;
- duplicate stale and active rows for the same device ID.

Assert that `queryDevices()` returns local plus both active remotes, keeps the offline active peer removable, excludes every removed/history-only row, and emits one effective row per device ID. Also test a snapshot that omits the local row but supplies `local_device_id`.

**Step 2: Run the selected test and verify RED**

Run from the ASCII-only worktree with DevEco JBR configured:

```powershell
$env:DEVECO_SDK_HOME='E:\software\DevEco Studio\sdk'
$env:JAVA_HOME='E:\software\DevEco Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
& 'E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=common@default -p product=default test --no-daemon
```

If this Hvigor version exposes only the concrete task, run:

```powershell
& 'E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat' :common:default@UnitTestArkTS --mode module -p module=common@default -p product=default --no-daemon
```

Expected: new assertions fail because removed/history rows are currently returned. If the runner cannot execute tests in CLI, compile the test target with `UnitTestArkTS`, preserve the RED assertion evidence through a pure exported projection function test, and record the runner limitation explicitly; do not replace behavioral tests with a normal build.

**Step 3: Implement the minimum actionable projection**

Add a small pure helper near the trust payload models. Rules:

1. local row always wins and is visible;
2. remote row is visible only when effective membership/sync relationship is active/admitted/current;
3. `removed`, `removed_peer_device`, revoked, history-only, and unknown remote rows are excluded;
4. offline reachability never excludes an otherwise active remote;
5. duplicate rows choose the actionable active row deterministically;
6. display name, address, or prior history never upgrades trust state.

Keep `queryDevices()` responsible only for parsing, projection, and the synthetic local fallback.

**Step 4: Run GREEN**

Run the same selected test command and:

```powershell
& 'E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=common@default -p product=default assembleHar --no-daemon
```

Expected: tests pass and the common HAR compiles.

**Step 5: Commit**

```powershell
git add common/src/main/ets/service/EngineRuntimeService.ets common/src/test/EngineRuntimeService.test.ets
git commit -m "fix: hide removed devices from HarmonyOS roster"
```

### Task 2: Keep offline active-peer removal stable across refresh

**Files:**
- Modify: `features/clipboard/src/main/ets/viewmodel/ClipboardFeatureController.ets`
- Add or modify: `features/clipboard/src/test/ClipboardFeatureController.test.ets`
- Modify only if needed for testability: constructor/service injection seam in the controller

**Step 1: Write the failing controller test**

Create a focused controller test with a fake runtime service:

1. initial list contains an offline active remote;
2. confirmation returns the destructive button;
3. `removeMember` succeeds and the next runtime snapshot contains both the historical removed row and remaining active rows;
4. refresh runs;
5. removed peer stays absent, selected target is cleared, and auto-send targets become empty;
6. the operation reports success once.

Also assert cancel/no-op for local devices.

**Step 2: Run the selected controller test and verify RED**

Run:

```powershell
& 'E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=clipboard_feature@default -p product=default test --no-daemon
```

Or use the concrete `:clipboard_feature:default@UnitTestArkTS` task if required.

Expected: test fails before the runtime projection is applied/injected or because refresh can resurrect the historical row.

**Step 3: Implement the minimum controller correction**

Keep the optimistic local removal and selected-target cleanup. Make refresh consume the actionable runtime projection and treat Engine `not_found` for an already-removed peer as idempotent success only when a subsequent authoritative refresh confirms the peer absent. Do not suppress other Engine errors.

**Step 4: Run GREEN and module compile**

Run the selected controller test and:

```powershell
& 'E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=clipboard_feature@default -p product=default assembleHar --no-daemon
```

Expected: tests and module compile pass.

**Step 5: Commit**

```powershell
git add features/clipboard/src/main/ets/viewmodel/ClipboardFeatureController.ets features/clipboard/src/test/ClipboardFeatureController.test.ets
git commit -m "fix: make offline device removal idempotent"
```

Stage only files that exist and changed.

### Task 3: Vendor the reviewed Engine recovery revision

**Depends on:** Engine plan Task 4 handoff with a reviewed 40-character source commit.

**Files:**
- Replace: `third_party/uniclipboard-engine/v1.1.0-rc.5/UniClipboardEngine.har`
- Replace: `third_party/uniclipboard-engine/v1.1.0-rc.5/UniClipboardEngine.har.checksum.txt`
- Replace: `third_party/uniclipboard-engine/v1.1.0-rc.5/index.d.ts` if changed
- Replace: `third_party/uniclipboard-engine/v1.1.0-rc.5/release-manifest.json`
- Replace: `third_party/uniclipboard-engine/v1.1.0-rc.5/engine-release.json`
- Replace: `third_party/uniclipboard-engine/v1.1.0-rc.5/source-commit.txt`
- Modify: `rust/space-core/` vendored source to exactly match the reviewed Engine commit
- Verify/modify: `oh-package.json5`, `oh-package-lock.json5`, `rust/verify-engine-release.ps1`

**Step 1: Add a failing provenance check before replacing artifacts**

Run:

```powershell
& .\rust\verify-engine-release.ps1
Get-Content .\third_party\uniclipboard-engine\v1.1.0-rc.5\source-commit.txt
```

Expected: current bundle verifies internally but reports old source commit `31c149c5bfb8a8edfe80c94944c8255157a3a3af`, so it fails the new requirement to consume the reviewed recovery commit.

Add/extend a repository test or verifier argument that asserts the expected reviewed commit, then observe that assertion fail.

**Step 2: Rebuild Engine HarmonyOS assets reproducibly**

Use Engine's `tests/hosts/ohos/build-emulator.sh` on the supported DevEco/macOS runner when available. If local Windows cannot execute the OHOS Rust linker pipeline, dispatch the Engine release/build workflow from the reviewed branch and download the resulting `harmonyos-assets`; never hand-edit binary metadata or claim a local Windows build produced the HAR.

Verify that HAR contains:

- `package/libs/arm64-v8a/libuc_ohos_napi.so`;
- `package/src/main/cpp/types/libuc_ohos_napi/index.d.ts`;
- package version matching the Engine version.

**Step 3: Replace the complete immutable artifact set**

Copy the HAR, checksum, declarations, manifests, license inventory, source commit, and version files as one reviewed set. Synchronize `rust/space-core` with the same Engine commit using an auditable archive/copy script that excludes `.git` and build outputs. Do not mix artifacts from different commits.

**Step 4: Run GREEN provenance checks**

Run:

```powershell
& .\rust\verify-engine-release.ps1
& .\rust\build-native.ps1
git diff --check
```

Expected: all checks pass and every metadata file names the reviewed Engine commit.

**Step 5: Commit**

```powershell
git add third_party/uniclipboard-engine/v1.1.0-rc.5 rust/space-core rust/verify-engine-release.ps1 rust/build-native.ps1 oh-package.json5 oh-package-lock.json5
git commit -m "chore: update HarmonyOS to recovered Engine revision"
```

Stage only changed paths.

### Task 4: Build the signed HarmonyOS app and run static verification

**Files:**
- Verify: `hvigorfile.ts`
- Verify: `build-profile.json5`
- Generated, do not commit unless already tracked: `products/default/build/`

**Step 1: Run repository guards**

```powershell
& .\rust\verify-engine-release.ps1
& .\tools\verify-background-sync-mode.ps1
git diff --check
```

Expected: all pass.

**Step 2: Run ArkTS tests and release build**

```powershell
$env:DEVECO_SDK_HOME='E:\software\DevEco Studio\sdk'
$env:JAVA_HOME='E:\software\DevEco Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
& 'E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat' test --no-daemon
& 'E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p product=default -p module=entry@default -p buildMode=release --no-daemon
```

Expected: tests and signed HAP build pass. If local signing material is absent or belongs to another Windows profile, build a debug-signed HAP for device verification and report the release-signing blocker without changing signing secrets in source control.

**Step 3: Inspect output**

Locate the generated HAP, calculate SHA-256, and inspect package/version/bundle identity as `com.sss.uniclipboard`. Do not print signing passwords or private key material.

### Task 5: Real-device Windows ↔ HarmonyOS acceptance test

**Environment:**
- HarmonyOS wireless HDC target: `172.16.0.146:45327`
- HDC local server: `127.0.0.1:18710`
- Windows desktop worktree/app: `E:\文档\uniclipboard\UniClipboard-upstream-join-recovery`

**Step 1: Install without clearing profiles first**

Install the new HAP over the current package and start `com.sss.uniclipboard`. Preserve existing paired profiles to prove the recovery migration works. Only clear data if the test explicitly isolates a fresh-pair scenario, and record that separately.

**Step 2: Verify runtime identity and roster**

Collect filtered HDC/hilog evidence showing:

- Engine starts with the expected version/source commit;
- same local profile/device identity is reused after restart;
- removed/history-only devices are not projected;
- an offline active peer is still visible and removable.

Do not log invitation passphrases, private keys, or full fingerprints.

**Step 3: Verify clipboard delivery both directions**

1. copy unique text on Windows and confirm it appears on HarmonyOS;
2. copy different unique text on HarmonyOS and confirm it appears on Windows;
3. restart both apps without resetting and repeat both directions;
4. confirm no `Rejected ack` occurs for the admitted peer;
5. confirm an unknown/removed peer remains rejected.

**Step 4: Verify offline removal**

Make a paired Windows device offline, long-press it on HarmonyOS, remove it, refresh and restart the phone app, and confirm it does not reappear. A later legitimate re-pair must create a current active relationship without requiring either unrelated device to reset.

**Step 5: Final review and commit cleanliness**

```powershell
git diff 0729bae...HEAD --stat
git diff 0729bae...HEAD
git status --short
```

Request final code review for trust filtering, idempotency, profile compatibility, generated binary provenance, and accidental signing-secret changes. Resolve all must-fix findings and rerun Tasks 4-5.
