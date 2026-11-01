# Service 命名规则

## 名称约定

- **Service** 类：必须是**单例**（通过 `Provider<T>` / `Provider.family<T, P>` 管理生命周期），通过构造函数注入依赖（database、api 等）。例如 `NovelContentService`、`MemoryService`、`AiSessionPersistenceService`。
- **Orchestrator** 类：**短生命周期**操作编排类，没有构造函数依赖或所有输入通过方法参数传入，每次操作创建干净实例。例如 `AgentCouncilOrchestrator`、`TheaterOrchestrator`。
- **禁止**使用 `ServiceImpl` 后缀。如果只有一个实现，直接取功能描述名即可，不需要接口+实现两层。

## 判断标准

| 特征 | Service | Orchestrator |
|---|---|---|
| 有无构造函数依赖 | 有（db, api, config 等） | 无（或全部通过方法参数传入） |
| 生命周期 | Provider 管理，全局/共享 | Notifier 私有字段，每次操作新建 |
| 可变状态 | 无运行态状态 | 有 `_cancelled`、`_activeOrchestrator` 等 |
| 实例数量 | 一个 Provider 一个实例 | 每次操作一个实例 |
| 暴露方式 | `ref.watch(xxxProvider)` | 不暴露，仅在 Notifier 内部持有 |

## 示例

```dart
// ✅ Service：有依赖、单例、Provider 管理
final novelContentServiceProvider =
    Provider.family<NovelContentService, String>((ref, dbPath) {
  final db = ref.watch(novelContentDatabaseProvider(dbPath));
  return NovelContentService(db);
});

// ✅ Orchestrator：无依赖、短生命周期、Notifier 私有字段
class CouncilSessionNotifier extends _$CouncilSessionNotifier {
  AgentCouncilOrchestrator? _orchestrator;

  Future<void> start() async {
    _orchestrator?.cancel();
    _orchestrator = AgentCouncilOrchestrator();
    await _orchestrator!.startDiscussion(...);
  }
}

// ❌ 禁止：ServiceImpl 命名
class AgentCouncilServiceImpl implements AgentCouncilService { ... }
```
