# Notices and attribution

## Upstream project

This repository contains and modifies code from:

- Project: UniClipboard
- Upstream repository: https://github.com/UniClipboard/UniClipboard
- Upstream license: GNU Affero General Public License v3.0 only
- Imported snapshot: source archive from the `0.19.0-alpha.3` development stage; the archive did not preserve an exact Git commit identifier

The vendored upstream-derived Rust sources are primarily under `rust/space-core/` and `rust/uc-mobile/`. Original copyright notices remain applicable.

## HarmonyOS modifications

The HarmonyOS port contributors made substantial modifications in July 2026, including:

- an ArkTS/ArkUI client for HarmonyOS phones, tablets, and 2-in-1 devices;
- HarmonyOS clipboard, image, secure credential, preferences, and application-sandbox integration;
- a Rust Node-API bridge built with `ohos-rs`;
- HarmonyOS packaging, resources, responsive UI, and native build tooling;
- adaptations for encrypted-space pairing, P2P text sync, and the legacy mobile companion protocol.

The combined work is distributed under AGPL-3.0-only. See `LICENSE` for the complete terms. This community port is not an official UniClipboard release and does not imply endorsement by the upstream maintainers.
