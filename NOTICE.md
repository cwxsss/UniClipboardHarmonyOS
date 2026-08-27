# Notices and attribution

## Upstream project

This repository contains and modifies code from:

- Project: UniClipboard
- Upstream repository: https://github.com/UniClipboard/UniClipboard
- Upstream license: GNU Affero General Public License v3.0 only
- Imported snapshot: source archive from the `0.19.0-alpha.3` development stage; the archive did not preserve an exact Git commit identifier

本仓库不再复制或编译 Engine 的 Rust 核心源码；鸿蒙端通过
`third_party/uniclipboard-engine/v1.1.0-rc.7/` 中固定提交生成的官方 HAR 使用
Engine。该 HAR 及其依赖许可证清单保留了上游版权与许可证信息。

## HarmonyOS modifications

The HarmonyOS port contributors made substantial modifications in July 2026, including:

- an ArkTS/ArkUI client for HarmonyOS phones, tablets, and 2-in-1 devices;
- HarmonyOS clipboard, image, secure credential, preferences, and application-sandbox integration;
- an official Engine HAR and NAPI bridge for encrypted-space networking;
- HarmonyOS packaging, resources, responsive UI, and native build tooling;
- adaptations for encrypted-space pairing, text synchronization, and explicit media transfer.

The combined work is distributed under AGPL-3.0-only. See `LICENSE` for the complete terms. This community port is not an official UniClipboard release and does not imply endorsement by the upstream maintainers.
