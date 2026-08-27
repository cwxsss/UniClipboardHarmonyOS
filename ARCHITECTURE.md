# UniClipboard HarmonyOS 分层架构

工程采用产品定制层、基础特性层、公共能力层和官方 Engine 运行时组成的单向依赖架构。鸿蒙客户端不再编译或接入旧的本地 P2P、LAN/HTTP 同步栈。

## 模块

| 层级 | 模块 | 产物 | 职责 |
| --- | --- | --- | --- |
| 产品定制层 | `products/default` | Entry HAP | Ability、断点装配、Compact/Expanded 设备视图、应用身份资源和产品配置 |
| 基础特性层 | `features/clipboard` | HAR | 可观察的剪贴板共享状态、业务流程编排和产品层稳定接口 |
| 公共能力层 | `common` | HAR | 数据模型、存储、剪贴板、通知和 Engine 运行时适配 |
| 运行时实现 | `@uniclipboard/engine` | 官方 Engine HAR | 空间、配对、加密同步、历史和文件传输 |

## 依赖方向

```text
products/default（Compact / Expanded UI）
  ├─> clipboard_feature（ClipboardFeatureController）
  └─> common

clipboard_feature ──> common ──> @uniclipboard/engine
```

下层模块不得导入上层模块。产品层不直接访问 Engine 原始 N-API 对象，Engine 能力由 `common/Index.ets` 和 `EngineRuntimeService` 暴露稳定接口。

## 扩展约定

- 新产品或设备定制：在 `products/` 下增加 Entry HAP，并按需组合特性模块；设备专属视图留在对应产品目录。
- 新的独立业务：在 `features/` 下增加 HAR；跨产品共享的业务状态、流程和通用 UI 保留在特性层。
- 同一产品内的响应式设备分支由产品入口选择，Compact 与 Expanded 视图共享同一个特性 Controller，不复制同步和存储逻辑。
- 多个特性复用的模型、服务、外部 I/O 或工具：放入 `common`，通过 `common/Index.ets` 导出。
- Engine 版本、HAR、N-API 类型声明和原生库必须来自同一个固定提交；客户端不得复制 Engine 内部 Rust 包或重新维护一套空间协议。
- 文字自动同步由 Engine 的本地捕获链路负责；图片和文件只有在用户指定目标设备后才调用显式发送接口。
