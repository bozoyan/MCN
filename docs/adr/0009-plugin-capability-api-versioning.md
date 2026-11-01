# capability API 版本化 = semver major + 多 major 共存

插件 capability API 是长期契约，破坏兼容会让已发布插件崩。决策：**pluginApiVersion 用 semver major**（v1 / v2 / v3 ...），宿主同时支持**当前 major + 上一个 major**作为过渡期，旧 major 在 **2 个 release 周期**后废弃。插件在 manifest 声明 `pluginApiVersion: "^1"`。MVP 只有 v1，但契约设计遵循"能力可加不可改"原则：新增 capability 不升 major、不破坏旧插件；删除 / 改签名 / 改语义才升 major。

## Considered Options

- **semver major + 共存**（chosen）：业界验证（VS Code `engines.vscode`、npm `peerDependencies`）。MVP 只 v1 无需多版本共存代码，但契约设计为未来留余地。代价是 transition 期需维护 2 个 major 的兼容层。
- **proposed API 机制**（stable + proposed flag，无版本号）：新能力先 proposed（插件声明 `proposed: true`），稳定后转 stable。轻量、适合小生态；但无显式版本号，breaking 仍需处理，且 proposed 状态管理复杂。**拒绝**，MVP 生态规模不足以支撑。
- **semver + proposed 结合**（VS Code 完整模式）：版本号 + proposed 机制。完整但复杂度过高，MVP 不需要。**拒绝**，留作生态规模化后再评估。
- **MVP 不做版本化**（破坏即弃）：最简单、风险高。AI 生成插件量起来后，一次 breaking 就让大量插件失效。**拒绝**。

## Consequences

- plugin_api 包的契约设计遵循"能力可加不可改"：新增 method / 新增可选参数 / 新增 DTO 字段不升 major；删除 method / 改参数类型 / 改语义 / 删 DTO 字段才升 major。
- 宿主 `compatibility_checker.dart` 在加载时校验 `pluginApiVersion` 是否落在支持范围（当前 major + 上一个 major）。范围外拒绝加载并提示版本不匹配。
- 旧 major 进入废弃周期后，文档标注 deprecation，2 个 release 周期后移除。废弃期间插件可运行但启动时给开发者警告日志。
- capability API 的 DTO 版本化：DTO 字段只增不删；如需结构性变更，新建 DTO v2 + 新 method，旧 method 保留走 v1 DTO。
- 未来若需 proposed API 机制（生态规模化后），可在 semver 之上叠加，不冲突。
- MVP 阶段 1 只实现 v1 契约与 compatibility_checker 的范围校验；多 major 共存的兼容层代码留到 v2 发布时才需要。
