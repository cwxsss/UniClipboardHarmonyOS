# Contributing

感谢你改进 UniClipboard for HarmonyOS。

## 开始之前

1. 先在 Issue 中说明较大的功能或协议变更，避免重复工作。
2. 不要提交签名证书、私钥、口令、真实连接二维码、剪贴板数据库或设备日志。
3. 修改上游派生代码时，保留原有版权与许可证说明，并在提交或 PR 中说明修改范围。
4. 贡献到本仓库的代码必须能够按 AGPL-3.0-only 分发。

## 本地检查

ArkTS 或资源改动至少运行：

```powershell
devecocli build
```

更新官方 Engine HAR 或 NAPI 声明时先运行：

```powershell
$env:DEVECO_SDK_HOME = '<your-openharmony-sdk-path>'
.\tools\verify-engine-release.ps1
devecocli build
```

Engine 原生库和 HAR 的生成属于 Engine 仓库；本仓库只提交经过校验的固定版本
HAR、NAPI 类型声明和鸿蒙端适配代码。

请在 PR 中写明测试设备、HarmonyOS/API 版本、实际执行的命令，以及仍未覆盖的场景。UI 改动请附手机和大屏截图，并同时检查浅色、深色与中英文界面。

## 代码约定

- 遵守 ArkTS 静态类型限制，不使用 `any`、`unknown`、对象动态字段、解构或不受支持的 TypeScript 语法；
- 用户可见文案必须放入资源文件，并同步更新 `base` 与 `en_US`；
- 优先使用 HarmonyOS 官方 API，新增权限或依赖时说明用途和最低 API；
- 不在动画过程中频繁改变布局尺寸；
- Rust 代码应保持 `cargo fmt` 通过，并为协议或安全边界改动补充测试。

## 提交说明

建议使用简洁、命令式的提交标题，例如：

```text
fix: avoid duplicate clipboard history entries
feat: add tablet pairing status
docs: clarify native build prerequisites
```
