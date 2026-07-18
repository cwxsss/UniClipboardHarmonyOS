# UniClipboard Rust core for HarmonyOS

This directory vendors the upstream `uc-mobile-proto` crate from
`UniClipboard-main.zip` (`0.19.0-alpha.3`) and exposes the first HarmonyOS
bindings through the community-maintained `ohos-rs` Node-API adapter.

The current native boundary exposes:

- `parseConnectUri` validates and decodes the upstream
  `uniclipboard://connect` protocol.
- `sha256HexUpper` computes the exact uppercase SHA-256 used by
  `SyncClipboard.json`.
- `probeServer`, `getLatestText`, and `putText` run through the upstream
  `uc-mobile` reqwest/rustls/Tokio client. Long text automatically follows the
  upstream 10240-grapheme overflow upload sequence.
- `startSse`, `drainSseEvents`, and `stopSse` keep the upstream SSE client in
  Rust and expose a bounded event queue to ArkTS.
- History query and PATCH operations keep multipart filters, split path IDs,
  `isDelete`, and optimistic-lock versions inside the Rust protocol boundary.

Build the phone (`arm64-v8a`) artifact with:

```powershell
.\rust\build-native.ps1
```

The script stages the generated type declaration and shared library into the
local `uniclipboard_native` HAR package consumed by the `entry` module.

The HarmonyOS bridge currently exposes connection parsing, server probing,
latest-text pull, text push, searchable/mutable text history, and SSE notifications. The
vendored `uc-mobile` also contains cache and sync-engine logic. Those surfaces
can be exported incrementally after the Node-API runtime lifecycle has been
exercised on a real device.
