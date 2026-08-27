# Engine v1.1.0-rc.7

本目录保存 HarmonyOS Engine `v1.1.0-rc.7` 的固定版本声明、校验清单和依赖许可证。

`UniClipboardEngine.har` 体积超过 GitHub 普通 Git 对单个文件的限制，因此作为鸿蒙端 Release 资产分发，不直接提交到 Git 历史。构建前将 Release 中的同名文件下载到本目录，然后执行校验：

```powershell
gh release download v1.0.5-engine-rc7-20260828 --repo cwxsss/UniClipboardHarmonyOS --pattern UniClipboardEngine.har --dir third_party/uniclipboard-engine/v1.1.0-rc.7
powershell -NoProfile -File tools/verify-engine-release.ps1
```

校验清单要求 HAR 的 SHA-256 为 `54966b6867746f6a85ed5049e3642e6f40a48cd3af1eee9746f9c91a42fcf05d`，来源 Engine 提交为 `ff493cfa8563cdd7fbf8615ed0a95b9058714176`。
