# Engine 迁移与全量代码审计

## 审计范围

本次审计覆盖 HarmonyOS 产品入口、Compact/Expanded 界面、特性控制器、公共服务、原生扩展、Engine HAR 契约、构建清单和文档。审计基线是：空间、成员偏好、历史和 P2P 传输由 Engine 统一负责；任何持久化业务负载必须先经过 MasterKey AEAD 加密。

## 已完成

- 删除未参与构建的根目录 `entry/` 快照，产品入口只保留 `products/default`。
- 删除 ArkTS 旧桌面 `MobileSyncClient`、`NativeProtocolService`、`SpaceNodeService` 及对应导出，移除旧 HTTP/SSE 设置入口、自动恢复、发送回退和轮询。
- 保留移动端接入服务端；该能力允许其他移动设备连接当前设备，不属于已移除的旧桌面客户端链路。
- 修正 Engine NAPI 运行时与声明文件不一致的问题，并从 HAR 包入口导出正式契约类型。
- 为 HarmonyOS 补齐成员发送/接收偏好、加密历史列表、详情、资源读取、收藏和删除接口。
- 历史界面改用 Engine 加密历史；收藏和删除会写回 Engine，不再只修改内存。
- 禁止在 Preferences、应用文件目录和缓存目录写入明文剪贴板负载；升级时清理旧明文历史、接收导出和文件缓存。
- 修复后台任务中硬编码包名，改为读取当前应用包名。
- 移除仓库内作者机器签名路径，更新 Engine 产物提交、哈希和大小校验链。
- Compact/Expanded 设备设置补齐接收总开关和接收内容类型，历史摘要不再误标为“已接收”。

## 仍需处理

### 高优先级

- 系统剪贴板宿主目前自动捕获文本。图片和文件记录需要异步读取，而 Engine `clipboardRead` 主机回调当前是同步契约；应在 Engine 增加异步宿主读取，或在 HarmonyOS 监听层预取并缓存不可变快照后再提交。
- `rust/uniclipboard-native` 仍包含旧桌面客户端的未调用 NAPI 符号。应将 `uc-mobile` 拆分为客户端和服务端 Cargo feature，关闭客户端 feature 后删除这些导出，避免影响仍在使用的移动端接入服务。
- `ClipboardService`、迁移清理和文件预览存在较多 ArkTS“可能抛出异常”警告，应逐个收敛到边界层并提供明确错误分类。

### 中优先级

- `ClipboardFeatureController` 同时承担连接、历史、媒体预览、分享、诊断和设置状态，体积过大。建议按 Engine 会话、历史库、媒体预览和移动接入拆分控制器。
- Compact 与 Expanded 视图存在大量重复业务布局。设备同步偏好、历史列表和连接诊断应抽成共享组件，只保留断点排版差异。
- 旧连接配置清理器仅为升级迁移保留；经过一个迁移周期后应连同 `ConfigStorageService`、旧字段和隐藏兼容构建器一起删除。
- Engine 包版本 `1.1.0-rc.5` 会触发 ohpm SemVer 警告。后续发布应改用 ohpm 接受的预发布标识并同步版本校验脚本。
- Hvigor 单元测试任务曾在测试报告包含运行错误时仍返回成功退出码。CI 除检查进程退出码外，还必须解析测试报告并拒绝任何 `Error in` 或失败用例。

### 低优先级

- 光学传输扫码 API 需要统一 `canIUse` 能力判断和不支持状态。
- 将当前人工维护的 Engine HAR 清单生成过程做成脚本，自动写入源码提交、嵌入文件哈希和大小，减少混装风险。
