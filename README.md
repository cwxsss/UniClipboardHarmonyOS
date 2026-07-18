# UniClipboard for HarmonyOS

UniClipboard 的 HarmonyOS 原生社区客户端，使用 ArkTS/ArkUI 构建，并通过 Rust Node-API 桥接复用上游空间核心和移动同步协议。

> 当前为技术预览版，并非 UniClipboard 官方发行版。请勿将它用于唯一副本或关键数据；已知限制见下文。

![UniClipboard 在 HarmonyOS 多设备上的界面](./uniclipboard_devices_final.jpeg)

## 与上游项目的关系

本仓库基于 [UniClipboard/UniClipboard](https://github.com/UniClipboard/UniClipboard) 的 AGPL-3.0 代码进行 HarmonyOS 适配，保留并修改了部分 Rust 空间核心与移动同步协议实现。上游快照来自 `0.19.0-alpha.3` 开发阶段的源码归档；原始归档没有保留精确 Git 提交号。

主要修改包括：

- 新增 HarmonyOS ArkTS/ArkUI 应用、系统剪贴板接入和多设备响应式界面；
- 新增基于 `ohos-rs` 的 Rust Node-API 桥接与 arm64-v8a 构建脚本；
- 适配 HarmonyOS Asset Store、Preferences、Image Kit 与应用沙箱；
- 对上游空间邀请、P2P 文本同步和旧移动同步协议进行移动端封装。

详细归属与修改说明见 [NOTICE.md](./NOTICE.md)。本仓库整体按 AGPL-3.0-only 发布，完整条款见 [LICENSE](./LICENSE)。

## 已实现

- 使用 `XXXX-XXXX` 短时邀请码和空间口令加入 UniClipboard 空间；
- 通过端到端加密 P2P 空间链路收发 UTF-8 文本；
- 空间身份、成员关系和密钥保存在 HarmonyOS 应用沙箱中；
- 通过旧移动同步协议拉取/推送文本与 PNG 图片；
- 大文本自动转为文件载荷，支持桌面端历史查询、搜索、收藏、置顶和软删除；
- SSE 前台通知、中文/英文资源、深色/浅色主题；
- 手机、平板和二合一设备布局；
- 连接配置使用 Preferences，用户名和密码使用 HarmonyOS Asset Store。

## 正确使用方式

### 推荐：加入加密空间

1. 在桌面端安装并打开官方 UniClipboard，在第一台设备创建空间并设置空间口令。
2. 在空间内的已有设备打开“设备”，生成短时邀请码。
3. 在 HarmonyOS 客户端进入“设置 → 加入空间”，扫码或输入邀请码，并填写同一个空间口令。
4. 加入成功后，在“同步”页主动发送或拉取内容。首次读取系统剪贴板时，按系统提示授权。

邀请码是短时凭据，不应截图后长期保存或公开；空间口令不要通过与邀请码相同的渠道发送。

### 兼容模式：旧移动同步协议

只有在需要连接旧版桌面移动服务时，才使用 `uniclipboard://connect` 二维码或手动填写服务地址、用户名和一次性密码。该模式默认使用局域网 HTTP + Basic Auth，只应在可信局域网中使用；跨网络使用时，应由你自己提供 HTTPS 反向代理或可信 VPN。

## 从源码构建

### 环境要求

- DevEco Studio 与 HarmonyOS SDK；本工程当前目标 API 24，兼容 API 23；
- PowerShell 与 `devecocli`；
- 仅在修改 Rust 原生层时需要 Rust 工具链、`cargo` 和 `ohrs`。

克隆后，仓库中已包含 arm64-v8a 原生库，可直接构建 ArkTS 工程：

```powershell
git clone https://github.com/haohaoai0/UniClipboardHarmonyOS.git
cd UniClipboardHarmonyOS
devecocli build
```

真机安装需要在 DevEco Studio 中为你自己的应用配置调试或发布签名。仓库不会保存证书、私钥或签名口令。

如果修改了 `rust/` 下的原生代码，先设置 SDK 路径并重建本地包：

```powershell
$env:DEVECO_SDK_HOME = 'C:\path\to\openharmony'
.\rust\build-native.ps1
devecocli build
```

也可以显式传入 SDK 路径：

```powershell
.\rust\build-native.ps1 -NativeSdk 'C:\path\to\openharmony'
```

连接调试设备后运行：

```powershell
devecocli run --module entry
```

## 源码结构

- `entry/`：HarmonyOS ArkTS/ArkUI 客户端；
- `AppScope/`：应用级资源与元数据；
- `rust/uniclipboard-native/`：HarmonyOS Node-API 桥；
- `rust/uc-mobile/`：移动同步客户端封装；
- `rust/space-core/`：为本移植版保留的上游 Rust 核心快照；
- `rust/build-native.ps1`：arm64-v8a 原生库构建与本地包装配脚本。

## 当前边界

- P2P 空间目前仅稳定支持内联文本；空间图片、大文本和文件传输仍在完善；
- HTTP 兼容模式仍支持文本和 PNG 图片，但不会替代 P2P 空间传输；
- 空间节点随应用进程运行，尚未注册 HarmonyOS 长时后台任务；
- 桌面历史查询/管理目前主要处理文本记录；
- 当前仓库只提供 arm64-v8a 原生库；
- 这是开发预览版，没有应用市场发布签名或稳定版兼容性承诺。

## 参与贡献与安全问题

提交代码前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。安全漏洞不要公开提交 Issue，请按 [SECURITY.md](./SECURITY.md) 中的方式报告。

## 许可证

本仓库整体按 [GNU Affero General Public License v3.0 only](./LICENSE) 发布。分发修改版或通过网络向用户提供修改版服务时，需要同时提供相应源码并保留许可证、版权和修改声明。`UniClipboard` 名称及上游原始素材仅用于说明兼容关系；本社区仓库不代表上游官方背书。
