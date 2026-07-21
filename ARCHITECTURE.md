# UniClipboard HarmonyOS 分层架构

工程采用产品定制层、基础特性层、公共能力层和底层原生实现组成的单向依赖架构。

## 模块

| 层级 | 模块 | 产物 | 职责 |
| --- | --- | --- | --- |
| 产品定制层 | `products/default` | Entry HAP | Ability、断点装配、Compact/Expanded 设备视图、应用身份资源和产品配置 |
| 基础特性层 | `features/clipboard` | HAR | 可观察的剪贴板共享状态、业务流程编排和产品层稳定接口 |
| 公共能力层 | `common` | HAR | 数据模型、存储、剪贴板、通知、网络同步和原生协议适配 |
| 底层实现 | `rust/uniclipboard-native/package` | Native HAR | Rust/C++ 原生协议和跨设备节点能力 |

## 依赖方向

```text
products/default（Compact / Expanded UI）
  ├─> clipboard_feature（ClipboardFeatureController）
  └─> common

clipboard_feature ──> common ──> uniclipboard_native
```

下层模块不得导入上层模块。产品层不直接访问 `uniclipboard_native`，原生能力由 `common/Index.ets` 暴露稳定接口。

## 扩展约定

- 新产品或设备定制：在 `products/` 下增加 Entry HAP，并按需组合特性模块；设备专属视图留在对应产品目录。
- 新的独立业务：在 `features/` 下增加 HAR；跨产品共享的业务状态、流程和通用 UI 保留在特性层。
- 同一产品内的响应式设备分支由产品入口选择，Compact 与 Expanded 视图共享同一个特性 Controller，不复制同步和存储逻辑。
- 多个特性复用的模型、服务、外部 I/O 或工具：放入 `common`，通过 `common/Index.ets` 导出。
- 产品身份资源放在产品层；业务文案、颜色和尺寸资源随对应特性维护，并同步所有语言与深浅色主题。
