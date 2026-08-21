# UniClipboard Rust core for HarmonyOS

This directory contains the HarmonyOS Node-API bridge and the Engine workspace
snapshot used by the retained mobile-access server.

The native boundary now exposes only capabilities still owned by the
HarmonyOS shell:

- the embedded encrypted-space compatibility runtime used during migration;
- the mobile-access HTTP server that lets another mobile client connect to
  this device;
- bounded file-descriptor and in-memory payload bridges for those services.

The obsolete HarmonyOS-to-desktop HTTP/SSE client was removed. Desktop pairing,
history, clipboard transfer, and member preferences are owned by the official
Engine HAR.

Build the phone (`arm64-v8a`) artifact with:

```powershell
.\rust\build-native.ps1
```

For direct Cargo cross-builds on Windows, set `OHOS_NATIVE_HOME` to the
DevEco OpenHarmony `native` SDK directory and use the wrappers under
`rust/uniclipboard-native/tools/` as the target linker, `CC`, and `CXX`.

The script stages the generated type declaration and shared library into the
local `uniclipboard_native` HAR package consumed by the product module.
