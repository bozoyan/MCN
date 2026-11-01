# Mutations (experimental)

Mutations 用于 UI 驱动的异步操作（如表单提交），避免把 loading/error/success 状态混入业务 state 中。**API 可能变更。**

## 定义

```dart
final addTodo = Mutation<Todo>();
```

通常存为全局变量或 Notifier 的 `static final` 字段。

## 监听

```dart
final addTodoState = ref.watch(addTodo);

switch (addTodoState) {
  case MutationIdle():   // 未触发或已重置
  case MutationPending(): // 进行中
  case MutationError(:final error):   // 失败
  case MutationSuccess(:final value): // 成功
}
```

## 触发

```dart
addTodo.run(ref, (tsx) async {
  final todoNotifier = tsx.get(todoNotifierProvider.notifier);
  final createdTodo = await todoNotifier.addTodo('Eat a cookie');
  return createdTodo;
});
```

`tsx` (MutationTransaction) 在读 Provider 时保持其存活，直到 mutation 完成。

## Keyed Mutations

```dart
final removeTodo = Mutation<void>();
final removeTodoWithId = removeTodo(todo.id);
```

每个 key 独立追踪状态。

## 重置

Mutation 在**完成且所有监听者移除后**自动回到 Idle。也可以手动：

```dart
addTodo.reset(ref);
```
