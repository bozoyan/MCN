# 插件运行时 = fjs (JS) + A2UI/GenUI (Schema 渲染)

Reveric 需要支持第三方动态加载插件，同时保持 Flutter 原生 UI 一致性与跨平台（含 iOS 不支持 JIT）。我们选择 **fjs**（fluttercandies 的 Rust+QuickJS Flutter JS 引擎）作为第三方插件逻辑运行时，**A2UI 协议 + GenUI Adapter + 自定义 Reveric Catalog** 作为 UI 渲染路径。插件用 TypeScript 编写编译为 JS，UI 用 A2UI JSON 描述，宿主从 Catalog 渲染。JS 不直接 build Flutter widget。详见 [插件系统方案](../solutions/plugin-system/README.md) 与[插件架构](../solutions/plugin-system/architecture.md)。

## Considered Options

- **纯 Dart 编译期插件**（Pub package 编译进 app）：安全、性能好、可返回 Widget；但无动态加载、无第三方生态、更新需重新发版。不引入；内置插件同样使用 JS 实现（见[插件系统方案](../solutions/plugin-system/README.md)）。**拒绝作为插件实现方案**。
- **flutter_eval**（运行时 Dart 子集执行）：能直接 build Flutter widget；但与 Flutter SDK 绑定深、支持 widget/package 有限、安全边界差、升级成本高。**拒绝**。
- **WebView 主方案**（HTML/JS 渲染全部 UI）：跨平台、Web 生态；但与 Flutter 风格不一致、内存高、状态桥复杂、移动/桌面行为差异大。**拒绝作为主方案**，仅保留为可选 `webviewPage` 扩展点后置。
- **fjs + A2UI/GenUI**（chosen）：JS 跑逻辑 + Schema 描述 UI + Catalog 渲染。动态加载、受控安全、原生 UI 一致；代价是 UI 表达能力受 Catalog 限制、A2UI 仍 alpha。
- **纯自定义 Schema（不用 A2UI）**：稳定可控；但放弃开放协议生态与未来 GenUI 对齐。**拒绝**，改为自定义 Catalog 子集 + A2UI Adapter 渐进对齐。

## Consequences

- 第三方插件 UI 表达能力被 Catalog 限制在白名单组件内（`Text` / `Markdown` / `Button` / `Card` / `CharacterSelector` ...），无法创建任意 Flutter widget。这是有意的安全边界。
- A2UI 仍处于 alpha，API 可能变化；`plugin_ui/a2ui_adapter.dart` 必须吸收协议变化，GenUI 升级不得穿透到插件 Schema。Adapter 行为由单测锁定。
- manifest 的 `uiProtocol` 用 Reveric 自有名 `reveric-ui-v1`（非 `a2ui-v1`）：A2UI 版本号是 Adapter 内部实现细节，不泄漏进第三方永久契约。A2UI 破坏性升级由 Adapter 吸收，manifest 字段不变，已发布插件不受影响（见方案中的 [UI 协议与版本](../solutions/plugin-system/views.md#ui-协议与版本)）。
- fjs 的 fs / network / process builtins 在第三方插件 runtime 中**默认禁用**，能力仅通过 capability API 暴露。详见 [ADR-0008](0008-plugin-security-capability-allowlist.md)。
- 每个第三方插件运行在独立 JS Runtime，资源上限硬编码（内存 64MB / 栈 512KB / Surface 组件数 500 / 嵌套深度 20）。移动端同时启用插件数需限制，内存上界待 PR-2 性能测试确认。
- 内置页面不重构为插件形态；其底层 service 抽取为 Application Service 层，插件与内置页面共享同一 capability API。MVP 不引入内置 Dart Package 插件形态。
- 引入新依赖 `fjs`（Rust + flutter_rust_bridge + cargokit），增加构建复杂度（原生层编译），但跨平台覆盖 Android/iOS/macOS/Windows/Linux。

## 修订（2026-10-30）

- 不引入 `genui` 包。界面格式仍采用 A2UI，协议层使用官方纯 Dart 包 `a2ui_core`，Flutter 渲染层自行实现，采用 A2UI v1.0、`a2ui_core` 锁定 0.4.0；原因与渲染器职责见 [自定义 View](../solutions/plugin-system/views.md#渲染器与组件目录)。上文提到的 GenUI Adapter 及 `plugin_ui/a2ui_adapter.dart` 不再适用。
- 不扩展 A2UI 协议本身，只自定义组件目录，使插件页面与以后 AI 生成的界面共用同一渲染器和组件。
- 内置插件同样使用 JS 实现，见[插件系统方案](../solutions/plugin-system/README.md)。
