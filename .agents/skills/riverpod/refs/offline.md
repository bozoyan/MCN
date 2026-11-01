# Offline Persistence (experimental)

将 Provider 状态持久化到设备，支持离线访问和应用重启后恢复。**仅 Notifier 可持久化。API 可能变更。**

## Storage

```dart
final storageProvider = FutureProvider<Storage<String, String>>((ref) async {
  return JsonSqFliteStorage.open(
    join(await getDatabasesPath(), 'riverpod.db'),
  );
});
```

## persist 调用

在 Notifier 的 `build()` 中调用：

```dart
class TodoList extends AsyncNotifier<List<Todo>> {
  @override
  Future<List<Todo>> build() async {
    persist(
      ref.watch(storageProvider.future),
      key: 'todo_list',
      encode: (todos) => todos.map((t) => {'task': t.task}).toList(),
      decode: (json) => (json as List).map((t) => Todo(task: t['task'])).toList(),
    );
    return fetchTodosFromServer();
  }
}
```

**不要 `await` persist**——Riverpod 会异步处理。

## JsonPersist (codegen)

```dart
@riverpod
@JsonPersist()
class TodoList extends _$TodoList {
  @override
  Future<List<Todo>> build() async {
    persist(ref.watch(storageProvider.future));
    return fetchTodosFromServer();
  }
}
```

## Key 规则

- 全局唯一（重复会 assert）。
- 跨重启稳定（变了会导致恢复失败）。
- Family Provider 必须在 key 中包含参数。

## 缓存时长

默认 2 天。可改为永不过期：

```dart
persist(..., options: const StorageOptions(
  cacheTime: StorageCacheTime.unsafe_forever,
));
```

## Destroy Key（数据迁移）

```dart
options: const StorageOptions(destroyKey: '1.0'),
```

版本更新时改 destroyKey，旧数据会被丢弃。

## 等待解码

```dart
await persist(...).future;
// 然后拿 state.value 初始化
```

## 测试

```dart
storageProvider.overrideWith((ref) => Storage<String, String>.inMemory())
```
