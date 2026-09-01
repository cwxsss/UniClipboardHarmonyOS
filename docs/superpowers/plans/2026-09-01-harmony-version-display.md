# 鸿蒙版本信息展示与 HAP 版本递增实现计划

> **面向 AI 代理的工作者：** 本计划用于当前 UniClipboard HarmonyOS 工程；修改必须保留现有未提交业务变更，并在声明完成前提供测试、构建和 HAP 元数据证据。

**目标：** 将鸿蒙 HAP 版本递增到 `1.0.6 / 1000007`，并让手机端“关于”页面显示实际安装包的版本名和版本号。

**架构：** 版本展示从 HarmonyOS `bundleManager` 读取已安装应用元数据，统一格式为“版本名（versionCode）”；紧凑手机布局和展开布局共用控制器上的动态展示值。版本配置仍由 `AppScope/app.json5` 管理，后续每次发布同步递增该配置，避免继续使用静态 `1.0.0` 文案。

**技术栈：** ArkTS、HarmonyOS AbilityKit `bundleManager`、Hypium、Hvigor HAP release 构建。

---

### 任务 1：版本格式化与元数据读取

**文件：**
- 创建：`common/src/main/ets/service/ApplicationVersionService.ets`
- 修改：`common/Index.ets`
- 测试：`common/src/test/ApplicationVersionService.test.ets`
- 修改：`common/src/test/List.test.ets`

- [ ] 编写版本名与 versionCode 的格式化测试，并覆盖空版本名降级。
- [ ] 运行 common 单元测试确认新增测试先失败。
- [ ] 实现从 `bundleManager.getBundleInfoForSelfSync` 读取应用元数据和统一格式化。
- [ ] 运行 common 单元测试确认测试通过。

### 任务 2：版本配置与关于页接入

**文件：**
- 修改：`AppScope/app.json5`
- 修改：`features/clipboard/src/main/resources/base/element/string.json`
- 修改：`features/clipboard/src/main/resources/en_US/element/string.json`
- 修改：`features/clipboard/src/main/ets/viewmodel/ClipboardFeatureController.ets`
- 修改：`products/default/src/main/ets/view/compact/CompactClipboardView.ets`
- 修改：`products/default/src/main/ets/view/expanded/ExpandedClipboardView.ets`

- [ ] 将版本递增为 `1.0.6`、`1000007`，并把静态版本徽章替换为控制器动态值。
- [ ] 在控制器启动时读取实际安装包版本，读取失败时显示明确的未知状态而不是伪造旧版本。
- [ ] 在手机紧凑布局和展开布局的关于页同时显示“版本名（versionCode）”。
- [ ] 校验资源与 ArkTS 引用无旧版本静态显示残留。

### 任务 3：HAP 构建与交付核对

**文件：**
- 产物：`products/default/build/default/outputs/default/entry-default-unsigned.hap` 或签名等价物
- 文档：`.codex/PROJECT_MEMO.md`

- [ ] 使用 ASCII-only 构建路径运行依赖安装和 release HAP 构建。
- [ ] 解包 HAP 核对 `bundleName`、`versionName=1.0.6`、`versionCode=1000007`，并计算 SHA-256。
- [ ] 明确记录签名状态；没有华为签名配置时不得将 unsigned HAP 描述为可直接安装。
- [ ] 更新项目备忘，记录代码变更、验证证据、签名边界和未完成真机验证。
