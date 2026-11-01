# 插件 UI 状态边界 = DataModel 隔离 + DB 共享层 + PluginSurfaceHost 挂载

插件 UI 状态由 GenUI 的 DataModel 管理，宿主 UI 状态由 Riverpod 管理。两者不直接互操作。决策采用 **C+D 混合**：插件 UI 内部状态（草稿、选中、临时视图）封闭在 SurfaceController 的 DataModel 内，不镜像 Riverpod；业务数据读写走 capability API → Application Service → Drift，宿主 Riverpod provider 通过现有 invalidate / Stream 机制 observe DB 变化，DB 作为 single source of truth；插件公开状态（当前激活 view、注册的 command 列表）由 PluginManager 维护并暴露为 Riverpod provider，供宿主 UI 使用，不暴露给插件本身。插件 view 通过 `PluginSurfaceHost` widget 挂载到宿主页面扩展点，宿主控制生命周期，插件不感知 Riverpod。

## Considered Options

- **C+D 混合**（chosen）：DataModel 封闭内部状态 + DB 共享业务数据 + PluginManager 受控暴露公开状态。符合 ADR-0008「插件不直接操作 Riverpod」原则，DB 作为共享层保证一致性。
- **A 完全隔离**（DataModel 不镜像、不暴露任何状态）：最简单、隔离最强；但宿主 UI 无法知道"当前哪个插件 view 激活""插件注册了哪些 command"，无法驱动菜单 / 工具栏等宿主 UI。**拒绝**，宿主 UI 集成需要少量公开状态。
- **B 镜像到 Riverpod**（DataModel path → Riverpod provider）：宿主可 observe 插件内部状态；但双向同步复杂、性能开销、调试困难，且违反 ADR-0008。**拒绝**。
- **全局 SurfaceController 单例**（所有插件 view 共享）：实现简单；但插件间状态可能串、隔离弱、单点故障影响所有插件。**拒绝**。
- **插件 view 作为 Riverpod ConsumerWidget**：view 直接是 Riverpod consumer。**拒绝**，破坏隔离（插件持有 ProviderRef）。

## Consequences

- **Riverpod 不进插件**：插件代码不持有 `ProviderRef`、不读 Riverpod provider。所有宿主数据访问走 capability API。
- **DataModel 不进 Riverpod**：DataModel 的 path 不镜像为 Riverpod state。DataModel 由 SurfaceController 管理，生命周期与 Surface 绑定。
- **DB 是共享层**：插件写数据 → capability → Application Service → Drift；宿主 Riverpod provider 通过 `invalidate` 或 `StreamProvider` observe DB 变化。双方各自 observe DB，不直接互操作。
- **PluginManager 公开状态 → Riverpod**：`activePluginViewProvider`（当前激活的插件 view id）、`pluginCommandsProvider`（已注册 command 列表）等由 PluginManager 维护，暴露为 Riverpod provider 供宿主 UI（菜单、工具栏、命令面板）使用。这些 provider 是只读的宿主侧状态，插件不能写。
- **PluginSurfaceHost widget**：宿主页面在扩展点（sidebar.right / settings.page / fullPage / dialog）放 `PluginSurfaceHost` widget，参数为 `viewId` / `location`。内部根据 viewId 从 PluginManager 取对应 SurfaceController，渲染插件 Surface。插件不感知 Riverpod，宿主控制生命周期（mount/unmount/dispose）。
- **插件 UI 重建隔离**：DataModel path 变化只重建依赖该 path 的 Surface widget，不重建宿主页面树。`PluginSurfaceHost` 是隔离边界，宿主页面重建不波及插件 Surface（除非 viewId 变化）。
- **宿主 → 插件通知走 EventBridge**：宿主状态变化（如 `document.saved`）通过 EventBridge 推送 JS event，插件 JS 自己决定是否调 `views.updateData` 更新 DataModel。宿主不直接操作插件 DataModel。
- **插件崩溃不影响宿主 Riverpod**：插件 JS 抛错被 PluginManager 捕获，标记插件 disabled；宿主 Riverpod state 完全不受影响。
- `PluginSurfaceHost` 的实现细节（如何与 Riverpod scope 整合、SurfaceController 是 per-view 还是 per-plugin）留到 PR-6 阶段 2 设计时决定，但边界原则在此确定。
