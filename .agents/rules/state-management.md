# State Management

## Provider 与 Hooks 分工

- Riverpod Provider 只管理**全局 / 共享状态**与依赖注入，例如认证信息、主题、数据库、跨页面共享数据。
- Hooks 只管理 **Widget 局部状态**，例如 `TextEditingController`、`FocusNode`、`AnimationController`、弹窗开关、表单临时输入。
- 不要把纯局部 UI 状态塞进 Provider；也不要把跨页面共享状态留在页面内部。

## Widget 基类选择

- 同时需要 Riverpod 与 Hooks 时，优先使用 `HookConsumerWidget`。
- 只读 Riverpod 时使用 `ConsumerWidget`。
- 只需要 Hooks 时使用 `HookWidget`。
- 仅在确实需要生命周期对象且 Hook 不合适时，再使用 `StatefulWidget` / `ConsumerStatefulWidget`。
- 对于动画、controller、focus、局部开关、一次性 effect 等典型局部 UI 状态，默认优先用 hooks 实现；不要在 Hook 能清晰表达的场景下退回 `StatefulWidget`。
- 如果选择 `StatefulWidget` / `ConsumerStatefulWidget` 而不是 hooks，代码里或说明中应能明确解释原因，例如需要 `TickerProviderStateMixin` 以外的复杂生命周期控制、错误恢复流程，或 Hook 表达会更差。

## Widget 本地资源生命周期

- Timer、`StreamSubscription`、controller、`WidgetsBindingObserver` 等页面资源必须成对创建和释放；在 `dispose` 前取消，并在前后台切换时停止不需要继续运行的轮询或动画。
- 周期性平台调用、网络请求和后台刷新必须具备 single-flight 防重入，上一轮未完成时不得叠加同类请求。
- 平台能力属于可选信息时（如电量、传感器或系统状态），不可用时应保持主流程可用并展示明确占位，不得因辅助信息阻塞页面或抛出未处理异常。对已知的暂时不可用错误最多记录一次诊断日志。
- 涉及原生插件的新增依赖，必须以完整重启后的真实平台构建验证；`hot reload` / `hot restart` 不能用于验证原生注册、channel 或 lifecycle 行为。

## Provider 粒度

- Provider 按功能拆分，保持小而专注，例如 `userProvider`、`novelsProvider`、`novelActionsProvider`。
- 不要创建一个巨大的 `AppProvider` 承载所有状态。
- 共享状态、查询状态、动作入口应分开建模，避免无关组件跟着一起重建。
- 对话框 / 设置页 / 表单页里会被多个 widget 反复 watch 的核心状态，必须明确评估是否需要 `keepAlive`；如果需要跨 rebuild / 页面切换保留加载结果，不要使用默认 `autoDispose`。
- 谨慎添加 `keepAlive`，尤其是 family provider。family 的每组参数都会有独立缓存；如果整体 `keepAlive`，所有被访问过的参数实例都可能常驻内存。使用前必须说明：为什么不能 autoDispose、最多会保留多少实例、何时释放、保留对象是否持有 controller / stream / client / 大列表等高成本资源。
- 优先考虑 `keepAlive` 的替代方案：
  - 把真正需要跨页面保留的轻量状态抽到单独 provider，重资源仍随页面释放。
  - 用持久层（DB / SharedPreferences / 文件）保存可恢复状态，页面回来后重建 runtime。
  - 对运行中任务使用 `ref.keepAlive()` 返回的 `KeepAliveLink` 做临时保活，任务完成、取消、暂停后立即 `close()`。
  - 用全局轻量 tracker 记录任务 id / 状态，UI 通过 tracker 展示后台状态，而不是保活完整 session UI 状态。
  - 对列表/详情数据使用分页、stream watch 或显式 invalidate，避免为了缓存读取结果而保活大量 family 实例。
- `loading` 态禁止返回可编辑表单使用的"伪默认值"来替代真实数据。对只读展示可以给 fallback，对可交互设置表单必须显式显示 loading / disabled 态，等真实状态完成加载后再允许编辑。
- 会被 UI 写回持久层的 provider action 必须做基本前置校验，不能只依赖界面层约束。例如启用 AI provider 前要检查必要字段是否已填写。

## Async Provider Action 生命周期

- `ref.read(provider.notifier).action()` 不会保活 `autoDispose` provider；action 不能假设调用方正在 `watch` 同一个 provider。
- 对外暴露的 async action 如果跨 `await` 后仍需使用 `ref` / `state` / 启动后台任务 / 返回业务 ID，必须由 action 自己保证生命周期，而不是要求 UI 额外 watch。
- 短操作使用操作级 `ref.keepAlive()`：action 进入时 retain，action 完成或失败时 release。
- 长任务使用任务级 `ref.keepAlive()`：任务启动成功后 retain，任务 completed / cancelled / paused / error 后 release。
- 后台任务不能裸用 `autoDispose` provider 里创建并在 `onDispose` 关闭的资源，例如 `http.Client`、DB handle、stream controller、runtime session。只保活入口 provider 不会自动保活它 `ref.read(...)` 出来的其它 provider。
- 长任务如果跨 `await` 使用可关闭资源，必须二选一：
  - 调用方持有依赖 provider 的显式 listener / keepAlive lease，并在任务结束后释放；
  - 资源工厂返回独占 lease（如 `client + release()`），由同一条调用链在 `finally` 中释放。
- `ref.read(autoDisposeResourceProvider)` 读出的对象禁止被保存到后台任务、orchestrator、unawaited future 或跨批次缓存中长期使用，除非同时保存并管理对应的生命周期 lease。
- 修复这类生命周期问题时必须补 regression test：只通过 `ref.read(provider.notifier).action()` 发起 command、不 `watch` 该 runtime/session provider，任务仍能完成，且 lease/release 被调用。
- `ref.mounted` 是 await 后的安全检查，不是业务兜底。禁止用空字符串、空列表、默认对象等伪成功值掩盖 provider 已 dispose。
- 有明确返回契约的 action 必须保持强契约：成功返回真实业务结果，失败抛领域异常或取消异常。
- 如果使用 `Completer` 表达运行完成、取消或 dispose 唤醒，必须有明确同步语义：谁 complete、谁 await、dispose 时代表什么结果。不能只为了"看起来等待过"而添加无人消费的 completer。

## Dialog / Bottom Sheet 发起 Command 生命周期

- Dialog、bottom sheet、popover、临时 route 只管理局部表单状态、loading 态和用户输入；不要为了保活 provider command 而额外 `watch` runtime/session provider。
- 弹窗内提交按钮可以 `ref.read(...notifier).action()` 发起保存、创建、启动任务，但被调用的 provider action 必须自行处理 async 生命周期、校验和错误契约。
- 弹窗关闭、route pop、设备旋转、父页面 rebuild 都不能影响已确认提交的 command 完整性；如果 command 必须继续运行，生命周期归 command/provider 管，不归弹窗管。
- 提交成功后弹窗只消费明确业务结果，例如真实实体 ID / runId；禁止把 `null`、空字符串、默认对象当成成功结果传给 `Navigator.pop`。
- 弹窗只在 `context.mounted` 时更新本地 UI、关闭自身或展示 SnackBar；这不能替代 provider action 内部的 `ref.mounted` / keepAlive 处理。
- 同一功能有 desktop dialog 与 mobile sheet 两个入口时，两端只应共享 command 契约，不应各自用 watcher、延迟关闭、额外刷新等 UI 手段修补 provider 生命周期。

## FutureProvider / StreamProvider 缓存与 invalidate

- `FutureProvider` 和 `StreamProvider` 首次 resolve 后会**缓存结果**，后续 `ref.watch` 直接返回缓存值，不会重新执行 provider 内的异步逻辑。
- 当通过 service / DAO / 外部写入修改了 provider 所依赖的底层数据源（数据库、文件、SharedPreferences 等）时，provider 不会自动感知变化，必须显式调用 `ref.invalidate(provider)` 使其重新查询。
- **排查步骤**（出现"写入成功但读取仍是旧值"时）：
  1. 先确认写入侧参数正确（日志打 `novelId`、`sessionId` 等关键标识）
  2. 在读取侧（DB 查询方法、provider body）加日志，确认是否真的触发了 DB 查询
  3. 若写了却没读，检查 provider 是否被 invalidate
- 如果 `ref.invalidate` 不方便接入（比如在 service 层没有 `Ref`），考虑以下方案之一：
  - 在调用 service 的 provider/回调中，写完后立即 `ref.invalidate(provider)`
  - 将 service 的写入方法和 invalidate 封装为一个 `Notifier` action
  - 让 provider 监听 DB 变更流（`watch()` / stream）而非一次性查询

### 唯一写入入口与「写入绕过缓存」反模式

- **典型症状**：数据已成功写入数据库，但 UI 列表/详情不刷新（需重进页面才更新）。根因几乎都是：UI 监听的是「一次性加载的缓存 provider」（`FutureProvider` / `AsyncNotifier` / `@riverpod` class），而某条写入路径**绕过该 provider 直接写了 DAO/service**，缓存的 state 从未失效。
- **唯一写入入口**：由缓存 provider 提供的实体表，只能通过拥有它的 notifier 写入。AI run 工具回调、orchestrator、后台任务等**禁止用 `AppDatabase()` + DAO 直接写**。给已有实体新增写入路径时，走 notifier 方法（写库 + 更新/失效 state），并把 `ProviderContainer` / `Ref` 传进回调（参考 `lib/desktop/widgets/ai/chat/agent_factory.dart` 中 agent-skills 的 run 回调写法）。
- **多写入方的读模型优先用 Drift `watch` 流**：列表/详情只要会被「本页面之外」（AI、后台任务、其它页面）修改，优先用 `StreamProvider` + `dao.watch...()`。同一 DB 实例的任何写入都会自动推送，从机制上消除「绕过 → 不刷新」，且无需手写 `invalidate`。`locations` / `novel` / `agent-rules` 已是此模式。
- **自检口诀**：新建列表 provider 前先问「除了当前页面，还有谁会改这张表？」只要答案不止 UI 自己，就别用一次性缓存 provider + 手写 invalidate，改用 watch 流。

### 读写同源（禁止混用两种 provider 模式）

- **典型症状**：保存/删除抛 `Cannot use the Ref of ...Provider after it has been disposed`，或数据已写入 DB 但 UI 不刷新。根因往往是 **列表 watch 的 provider 与保存 read 的 provider 不是同一个**，且写侧是默认 `autoDispose` 的 `AsyncNotifier`，编辑页只有 `ref.read(...).notifier`、没有长期 listener；async 写库完成后调用 `invalidateSelf()` 或更新 `state` 时，provider 已被 dispose。
- **禁止组合**：`watch(*StreamProvider)` 读 + `read(另一个 AsyncNotifierProvider.notifier)` 写。这不是「绕过缓存」，但比绕过更隐蔽——写路径看似走了 notifier，实际与读路径生命周期脱节。
- **两种合法模式（二选一，同一实体不得混用）**：
  1. **Stream 读 + Service 写**（`agent-rules` / `locations` / `novel`）：列表 `watch` `*StreamProvider`（Drift `dao.watch...()`）；保存/删除直接写 `novelContentServiceProvider` 或对应 service；刷新由 watch 流自动推送，**不需要**也不应再引入平行的缓存 notifier + `invalidateSelf`。参考：`lib/desktop/pages/novel_editor_agent_editing.dart`、移动端 `novel_agent_rule_manage_page.dart`。
  2. **单一 Notifier 读写**（`agent-skills`）：列表与编辑页都 `watch` 同一个 `AsyncNotifierProvider`；保存走该 notifier 的 action，action 内写库后直接 `state = AsyncValue.data(...)`；每个 `await` 后必须 `if (ref.mounted)` 再更新 state。编辑页若只有 `ref.read` 而无 `watch`，async 期间 provider 可能被 dispose。
- **新增/改 CRUD 页面前自检三问**：
  1. 列表 `watch` 的是哪个 provider？
  2. 保存 `read` 的是不是同一个？若不是，是否走 service 写 + stream 读？
  3. 若走 notifier 写，是否有至少一处 `ref.watch` 保活？每个 `await` 后是否检查了 `ref.mounted`？
- **跨平台复制时**：mobile 新页面对照 desktop 同功能的读/写路径；不要只复制列表的 stream watch，却另写一套 notifier 保存逻辑。

## 代码生成

- 复杂 Provider，尤其是 `Notifier` / `AsyncNotifier` / 参数化 Provider，优先使用 `riverpod_generator`。
- 只要 provider 生命周期、参数、返回类型、依赖关系发生变化，都要重新运行代码生成并检查生成结果是否符合预期，例如 `isAutoDispose` 是否正确。
- 修改 `@riverpod` / `@DriftAccessor` 等注解后，运行 `make codegen` 或 `flutter pub run build_runner build` 重新生成文件并检查 diff。禁止使用 `dart run build_runner ...`，避免脱离 Flutter SDK 依赖上下文。

## Hooks Rules

通用 hooks 使用规则（调用顺序、`useEffect` 依赖、InheritedWidget 读取限制等）请参考 `.agents/rules/hooks.md`，**写 hooks 前先阅读**。

以下为 Reveric 项目特有规则：

### 状态同步规则

- 当 controller / focus / animation 等 hook 对象需要跟随外部 props 或 provider 数据变化时，使用 `useEffect` 或等价同步逻辑显式更新。
- 表单类 hook 状态只保存局部、临时、尚未提交的 UI 状态；一旦数据已经提交到 provider，就要考虑 provider 反向更新时如何同步回 hook，避免 controller 持有旧值继续脏写。
- 涉及 i18n 的 prompt/template/状态文案：不要在 `useEffect` 里调用 `context.t(...)` 组装字符串。先在 build 顶层取翻译结果，或提前构造成纯字符串模板，再在 effect 中做 `replaceAll` / 拼接。

### 编辑面板 useForm keys

常驻编辑面板的 `id + updatedAt` keys 规则以 `.agents/rules/form.md` 为唯一正文；本文件只负责 form 与 Provider 的状态边界。

### 外部 TextEditingController 编辑面板

- UI 绑定外部 `TextEditingController` 时，form/controller 同步、dirty、postFrame 和 IME 合成规则以 `.agents/rules/text-input-ime.md` 为唯一正文。

### 向父级注册回调的 useEffect

父级 inline closure、稳定 keys 和 `useRef` 转发规则以 `.agents/rules/hooks.md` 为唯一正文；不要在本文件复制第二份 effect 依赖规则。

### Provider 写规则

- 不要在 build 或同步 `useEffect` 中触发 provider 写操作。写入只能来自用户事件、Notifier / Provider action，或明确脱离 build 的异步生命周期；需要从 effect 安排外部写入时，必须 post-frame 或调度到 build 结束后，并遵循 `.agents/rules/hooks.md`。
