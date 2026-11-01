# 第三方插件安全 = capability 白名单（非进程隔离）

fjs README 明确声明：「FJS is intended for application-owned or otherwise trusted scripts... memory/stack limits reduce accidental resource exhaustion, but they do not make QuickJS a hostile-code sandbox」。即 fjs 的资源限制是防意外耗尽，不是防恶意代码。但 Reveric 需要支持第三方插件，且第一版不做进程级隔离。决策：采用 **分级 capability 白名单** —— 内部脚本全能力、第三方插件走受控 capability API（fs/network/process builtins 禁用，每调用权限校验），依赖 fjs 资源限制兜底意外耗尽。不假装这是敌对代码沙箱；真正的进程级隔离后置到阶段 4 桌面高级插件。

## Considered Options

- **进程级隔离**（插件跑独立 isolate / 进程，IPC 通信）：最强隔离，可跑任意语言；但复杂度最高、IPC 开销大、移动端 isolate 能力受限、需重写运行时。**拒绝作为 MVP**，保留为阶段 4 桌面高级插件方案。
- **仅信任源**（白名单源 + 签名校验，不真沙箱）：最简单，符合 fjs 原生模型；但市场上线后来源不可控，签名被绕过即全暴露。**拒绝作为唯一手段**，作为阶段 4 补充层。
- **分级 capability 白名单**（chosen）：内部脚本全能力 / 第三方插件仅可调用受控 capability API，每调用校验权限。fjs builtins 中 fs/network/process 默认禁。资源限制（内存/CPU/组件数）兜底意外。
- **完全自定义 JS 沙箱**（不用 fjs，自建 QuickJS 隔离）：可控但重复造轮子，放弃 fjs 的 Rust 性能与 fluttercandies 维护。**拒绝**。

## Consequences

- 第三方插件无法直接访问 Drift DB / Riverpod Provider / 文件系统 / 任意网络 / 剪贴板 / 其他插件数据 / Flutter BuildContext。所有能力必须经 capability API（`documents.get` / `ai.generate` / `views.updateData` ...），每调用走 `permissionManager.require(plugin.id, permission)` + `apiRouter.invoke`。
- 权限在安装时显示给用户（`document.read` / `character.read` / `ai.invoke` ...），运行时每次调用复校验。权限模型见方案中的[运行时与权限边界](../solutions/plugin-system/architecture.md#运行时与权限边界)。
- capability API 只返回纯 JSON DTO，不暴露 Dart 对象引用，插件无法持有宿主内部状态。Application Service 层作为新抽象叠加在现有 service 之上，旧 service 调用方不改动（内置页面不重构）。
- **这不是敌对代码沙箱**。恶意插件若找到 capability API 的越权路径，理论上可读取授权范围内的数据。对策：每调用校验 + Adapter 单测 + 阶段 4 签名/审核。需要 OS 级隔离的场景（如运行未知第三方代码做高强度计算）走阶段 4 桌面进程插件。
- 资源限制（`maxScriptBytes` / `maxMemoryBytes` / `executionTimeout` / `maxApiCallsPerSecond` / `maxUiUpdatesPerSecond` ...）由 `plugin_security/resource_limiter.dart` 硬编码，防止插件意外耗尽资源。AI 请求不适用 30 秒总超时，由宿主创建异步任务返回 taskId，插件订阅结果。
- capability API 的版本化策略（semver + 兼容窗口 + 废弃周期）见 [ADR-0009](0009-plugin-capability-api-versioning.md)。
