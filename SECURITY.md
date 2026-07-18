# Security policy

## Supported version

当前仓库仍处于技术预览阶段，只维护默认分支的最新版本，不承诺对旧提交提供安全更新。

## Reporting a vulnerability

请不要通过公开 Issue、讨论区或包含真实凭据的日志报告漏洞。

在仓库启用 GitHub Private Vulnerability Reporting 后，请使用仓库 Security 页面中的私密报告入口。启用前，可通过上游公开的安全联系渠道联系 UniClipboard 维护者，并明确说明问题发生在 HarmonyOS 社区移植版；如果问题只涉及本仓库，请联系仓库所有者处理。

报告时请提供：受影响提交、HarmonyOS/API 版本、设备类型、最小复现步骤、影响范围，以及经过脱敏的日志。不要附带真实空间口令、邀请码、Basic Auth 凭据、证书或剪贴板内容。

## Security notes for users

- 短时邀请码和空间口令应通过不同渠道传递；
- 旧移动同步模式的 HTTP + Basic Auth 只应在可信局域网中使用；
- 跨网络访问旧协议时应使用 HTTPS 反向代理或可信 VPN；
- 安装包只应来自你信任的仓库 Release，并核对发布者与校验值。
