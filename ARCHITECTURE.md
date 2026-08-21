# UniClipboard HarmonyOS 分层架构

工程采用产品定制层、基础特性层、公共能力层和底层原生实现组成的单向依赖架构。

## 模块

| 层级 | 模块 | 产物 | 职责 |
| --- | --- | --- | --- |
| 产品定制层 | `products/default` | Entry HAP | Ability、断点装配、Compact/Expanded 设备视图、应用身份资源和产品配置 |
| 基础特性层 | `features/clipboard` | HAR | 可观察的剪贴板共享状态、业务流程编排和产品层稳定接口 |
| 公共能力层 | `common` | HAR | 数据模型、系统剪贴板宿主、通知、Engine 运行时和移动端接入服务适配 |
| Engine | `third_party/uniclipboard-engine` | HAR | 加密历史、空间身份、成员偏好和 P2P 同步的唯一实现 |
| 本地原生扩展 | `rust/uniclipboard-native/package` | Native HAR | 移动端接入服务及 HarmonyOS 辅助能力 |

## 依赖方向

```text
products/default（Compact / Expanded UI）
  ├─> clipboard_feature（ClipboardFeatureController）
  └─> common

clipboard_feature ──> common ──> UniClipboard Engine
                           └───> uniclipboard_native（辅助能力）
```

下层模块不得导入上层模块。产品层不直接访问 Engine 或 `uniclipboard_native`，原生能力由 `common/Index.ets` 暴露稳定接口。空间状态、成员偏好和历史记录只以 Engine 为事实来源。

## 扩展约定

- 新产品或设备定制：在 `products/` 下增加 Entry HAP，并按需组合特性模块；设备专属视图留在对应产品目录。
- 新的独立业务：在 `features/` 下增加 HAR；跨产品共享的业务状态、流程和通用 UI 保留在特性层。
- 同一产品内的响应式设备分支由产品入口选择，Compact 与 Expanded 视图共享同一个特性 Controller，不复制同步和存储逻辑。
- 多个特性复用的模型、服务、外部 I/O 或工具：放入 `common`，通过 `common/Index.ets` 导出。
- 产品身份资源放在产品层；业务文案、颜色和尺寸资源随对应特性维护，并同步所有语言与深浅色主题。
