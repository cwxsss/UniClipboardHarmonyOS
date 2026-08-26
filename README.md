# UniClipboard for HarmonyOS

UniClipboard 的 HarmonyOS 原生社区客户端，使用 ArkTS/ArkUI 构建，并通过 Rust Node-API 桥接复用上游空间核心和移动同步协议。

> 本项目是社区维护的 HarmonyOS 客户端，并非 UniClipboard 上游官方发行版。请勿将剪贴板历史作为关键数据的唯一副本；已知限制见下文。

## 下载

UniClipboard 已正式上架华为应用市场，可直接在 HarmonyOS 手机、平板和电脑上安装：

**[前往华为应用市场下载 UniClipboard](https://appgallery.huawei.com/app/detail?id=com.uniclipboard.hmos&channelId=SHARE&source=appshare)**

当前应用版本为 `1.0.3`。应用市场版本适合日常安装使用；开发者也可以按照下文说明自行构建最新源码。

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
- 首次启动引导，以及按屏幕宽度切换的 Compact/Expanded 产品视图；
- 支持从系统分享面板接收文本、链接、图片和文件，并发送到全部在线设备或指定设备；
- 支持按设备设置发送方向及文本、图片、文件、链接和富文本等内容类型；
- 提供连接诊断，检查网络、权限、空间节点和直连/中继状态，并可导出脱敏诊断日志；
- 历史库支持按设备、标签和常用片段筛选，自定义标签、批量收藏/删除、保留期限及重复记录合并；
- 支持图片文字识别，并从识别结果中提取链接、电话号码和二维码等智能操作；
- 支持通过官方 Engine 接收桌面端图片和文件；图片会显示预览并可写入系统剪贴板或进行文字识别，文件可预览和保存；
- 连接配置使用 Preferences，用户名和密码使用 HarmonyOS Asset Store。

## 分层架构

工程采用单向依赖的四层结构，产品 UI 与业务状态、公共服务和原生协议实现相互分离：

```text
products/default (Entry HAP)
  ├─> features/clipboard (HAR)
  └─> common (HAR) ──> rust/uniclipboard-native/package (Native HAR)
```

- 产品定制层负责 Ability、响应式设备视图、应用身份资源和产品配置；
- 基础特性层负责剪贴板共享状态与业务流程编排；
- 公共能力层提供数据模型、存储、系统剪贴板、通知和同步服务；
- 原生实现层复用 Rust 协议核心，并通过 Node-API 向 ArkTS 暴露能力。

模块边界、依赖方向和扩展约定详见 [ARCHITECTURE.md](./ARCHITECTURE.md)。

## 正确使用方式

### 推荐：加入加密空间

1. 在桌面端安装并打开官方 UniClipboard，在第一台设备创建空间并设置空间口令。
2. 在空间内的已有设备打开“设备”，生成短时邀请码。
3. 在 HarmonyOS 客户端进入“设置 → 加入空间”，扫码或输入邀请码，并填写同一个空间口令。
4. 加入成功后，桌面端复制的文本、图片和文件会进入“同步”页；图片可写入本机剪贴板或识别文字，文件可预览和保存。首次读取系统剪贴板时，按系统提示授权。

邀请码是短时凭据，不应截图后长期保存或公开；空间口令不要通过与邀请码相同的渠道发送。

### 兼容模式：旧移动同步协议

只有在需要连接旧版桌面移动服务时，才使用 `uniclipboard://connect` 二维码或手动填写服务地址、用户名和一次性密码。该模式默认使用局域网 HTTP + Basic Auth，只应在可信局域网中使用；跨网络使用时，应由你自己提供 HTTPS 反向代理或可信 VPN。

## 从源码构建

### 环境要求

- DevEco Studio 与 HarmonyOS SDK；本工程当前目标和最低兼容 API 均为 24（Engine `v1.1.0-rc.6` 要求 API 24）；
- PowerShell 与 `devecocli`；
- 仅在修改 Rust 原生层时需要 Rust 工具链、`cargo` 和 `ohrs`。

克隆后，仓库中已包含 arm64-v8a 原生库，可直接构建 ArkTS 工程：

```powershell
git clone https://github.com/haohaoai0/UniClipboardHarmonyOS.git
cd UniClipboardHarmonyOS
devecocli build
```

只构建当前产品入口及其依赖时，可以显式指定模块和目标：

```powershell
devecocli build --modules entry@default
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
devecocli run --module entry --product default
```

### 真机 HAP 打包与签名排障

下面流程用于在 Windows 上生成可安装到真实 HarmonyOS 设备的 signed HAP。不要把 `*-unsigned.hap` 当作最终交付物；它只能用于中间检查或模拟器场景。

#### 1. 先确认工程和依赖

- 在 DevEco Studio 打开本工程，确认项目包名为 `com.sss.uniclipboard`；不要复用其他应用（例如 ClashBox）的签名配置。
- 修改 Engine 原生层后，先生成匹配版本的 `UniClipboardEngine.har`，并更新 `third_party/uniclipboard-engine/<version>/` 下的 HAR 与 `index.d.ts`，然后执行 `ohpm install --all`。
- 构建前检查后台同步模式仍为 `dataTransfer`；根构建脚本会在模式不一致时失败。

#### 2. 连接无线调试设备

DevEco Studio 和其他 HDC 工具可能使用不同的本机 HDC 服务端口。先选一个没有被占用的端口，例如 `18711`，然后重启 DevEco Studio：

```powershell
$env:OHOS_HDC_SERVER_PORT = '18711'
```

使用 DevEco 自带的 HDC 将手机接入该服务（把地址替换为手机当前显示的无线调试地址）：

```powershell
$deveco = 'E:\software\DevEco Studio' # 按本机 DevEco Studio 安装目录修改
$hdc = Join-Path $deveco 'sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -s 127.0.0.1:18711 tconn 172.16.0.146:45327
& $hdc -s 127.0.0.1:18711 list targets -v
```

必须看到设备状态为 `TCP Connected`，再进行自动签名。若同时运行小白助手或其他 HDC 客户端，不要让两个工具争用同一个服务端口；可分别使用不同端口。

#### 3. 生成正确的自动签名

在 DevEco Studio 选择 `文件 → 项目结构 → 签名配置`：

1. 勾选“自动生成签名文件”，先通过设备 ACL 权限提示；
2. 将签名配置中的包名校正为 `com.sss.uniclipboard`；
3. 点击“应用/确定”，确认生成的 `.p12` 和 `.p7b` 路径属于 UniClipboard 当前工程；
4. 如果界面仍显示 `org.xbgroup.clashboxLTS` 或 `sss-chalsh-harmony-copy`，立即取消，不要构建。那是其他项目的证书，必然导致 bundleName 不匹配。

签名文件和口令只保存在本机，不提交到仓库。切换电脑时需要在新电脑上重新生成或导入与 `com.sss.uniclipboard` 匹配的签名配置。

#### 4. 命令行构建

PowerShell 7 中执行：

```powershell
$harmony = (Get-Location).Path
$deveco = 'E:\software\DevEco Studio'
$env:DEVECO_SDK_HOME = "$deveco\sdk"
$env:JAVA_HOME = "$deveco\jbr"
$env:Path = "$env:JAVA_HOME\bin;$deveco\tools\ohpm\bin;$deveco\tools\hvigor\bin;$env:Path"
Set-Location $harmony
& "$deveco\tools\ohpm\bin\ohpm.bat" install --all
& "$deveco\tools\hvigor\bin\hvigorw.bat" assembleHap --mode module -p product=default -p module=entry@default -p buildMode=release --no-daemon
```

成功标志必须包含 `SignHap` 和 `BUILD SUCCESSFUL`。常见的 ArkTS `WARN` 不等于构建失败，但 `SignHap` 失败或只生成 unsigned HAP 时不能交付。

#### 5. 产物核验与安装

最终文件通常位于：

```text
products/default/build/default/outputs/default/entry-default-signed.hap
```

构建后检查文件名、时间、大小和 SHA-256；同时解包检索关键接口，确认新 Engine 已进入 HAP：

```powershell
$hap = 'products/default/build/default/outputs/default/entry-default-signed.hap'
Get-FileHash -Algorithm SHA256 $hap
```

本次修复至少应能在 ArkTS 字节码或 arm64 native 库中找到 `queryMemberSyncPreferences`、`updateMemberSyncPreferences`、`receiveEnabled` 和 `receiveContentTypes`。安装测试时使用 `hdc install -r` 更新现有应用，保留用户数据；不要为了签名问题直接清空手机数据。

#### 本次问题复盘

- “设备-内容类型”不可操作的直接原因是鸿蒙源码调用了成员同步偏好接口，但旧版 Engine `v1.1.0-rc.6` HAR 的公开声明/二进制没有这些接口；只改 ArkTS 或只做 mock 测试都不能解决运行时问题。
- HAP 曾经生成成功但签名失败，原因是误用了另一个项目的 ClashBox 证书；包名和证书的 bundleName 必须同时是 `com.sss.uniclipboard`。
- DevEco 启动失败 `UnixDomainSockets.bind` 时，先检查旧的 DevEco 进程和 HDC 端口；本次通过隔离 `idea.system.path` 启动恢复 IDE，未修改项目源码。缓存锁只能在确认无 DevEco 进程后移动到备份目录，不能随意删除用户配置。
- DevEco 提示 HDC 端口已被占用时，优先设置 `OHOS_HDC_SERVER_PORT` 后重启 IDE，再用同一端口的 `hdc -s` 连接手机；不要反复重置手机应用或重新安装来替代 HDC 连接修复。

### 后台同步不变量

应用通过 iroh/QUIC 数据通道传输剪贴板内容，因此 HarmonyOS 持续任务必须在入口清单和运行时服务中同时使用 `dataTransfer`。不要改回 `multiDeviceConnection`：该模式虽然能够启动，但应用进入后台约 65 秒后会被系统挂起，表现为电脑复制的内容到达不了手机系统剪贴板。此问题与普通剪贴板授权无关。

根构建入口会自动执行 `tools/verify-background-sync-mode.ps1`。产品入口、兼容入口或任一后台服务出现模式不一致时，构建将直接失败，避免同类回归再次进入 HAP。

### 产品入口回归约束

当前 HAP 的唯一产品入口是 `products/default/`，共享业务状态和 Engine 编排位于 `features/clipboard/`。根目录 `entry/` 只是重构前的兼容源码快照，不是运行时事实来源。修复同步、设备或媒体接收功能时必须先沿 `products/default -> features/clipboard -> common` 跟踪真实调用链；涉及界面交互时必须同时覆盖 Compact 和 Expanded 视图，不能只修改 `entry/src/main/ets/pages/Index.ets`。

每次生成真机 HAP 前至少验证以下路径：应用退到后台后接收桌面文本、桌面图片显示预览和图片识别入口、桌面文件显示预览和保存入口、远端设备同步类型开关可操作并能重新读取已保存状态。后台任务模式由上面的构建检查自动保证，其余路径需要在连接真实 Engine 设备后验证。

## 源码结构

- `products/default/`：默认产品的 Entry HAP、Ability 和 Compact/Expanded 响应式界面；
- `features/clipboard/`：剪贴板特性 HAR，封装共享状态和业务流程；
- `common/`：公共能力 HAR，包含模型、存储、通知与同步服务；
- `AppScope/`：应用级资源与元数据；
- `rust/uniclipboard-native/`：HarmonyOS Node-API 桥；
- `rust/uc-mobile/`：移动同步客户端封装；
- `rust/space-core/`：为本移植版保留的上游 Rust 核心快照；
- `rust/build-native.ps1`：arm64-v8a 原生库构建与本地包装配脚本。

根目录的 `entry/` 保留为重构前的兼容源码快照；当前构建入口由根 `build-profile.json5` 指向 `products/default/`。

## 当前边界

- 官方 Engine 空间已支持桌面到 HarmonyOS 的文本、图片和单文件传输；收到的图片和文件保存在应用受管缓存中，用户可从同步页写入剪贴板、预览或保存；
- 当前 HarmonyOS Engine 的 `exportEntry` 接口只导出载荷字节，不返回原始文件名和媒体类型，因此接收文件暂时使用通用显示名；该限制应通过扩展 Engine 公共契约解决，客户端不会根据内容任意猜测原文件名；
- HTTP 兼容模式仍支持文本和 PNG 图片，但不会替代 P2P 空间传输；
- 空间节点随应用进程运行，并通过 `dataTransfer` 持续任务维持后台文本接收；系统仍可能依据省电策略终止长期闲置进程；
- 当前仓库只提供 arm64-v8a 原生库；
- 应用市场发布不代表 UniClipboard 上游官方背书；协议兼容性仍可能随上游预览版本变化。

## 参与贡献与安全问题

提交代码前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。安全漏洞不要公开提交 Issue，请按 [SECURITY.md](./SECURITY.md) 中的方式报告。

## 许可证

本仓库整体按 [GNU Affero General Public License v3.0 only](./LICENSE) 发布。分发修改版或通过网络向用户提供修改版服务时，需要同时提供相应源码并保留许可证、版权和修改声明。`UniClipboard` 名称及上游原始素材仅用于说明兼容关系；本社区仓库不代表上游官方背书。
