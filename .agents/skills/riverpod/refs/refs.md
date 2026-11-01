# Refs

**Ref**（Provider 内）和 **WidgetRef**（Widget 内）是与 Provider 交互的核心。

## 获取 Ref

- Provider 函数第一个参数 / Notifier 的 `this.ref`
- Widget: Consumer / ConsumerWidget / ConsumerStatefulWidget 的 `WidgetRef ref`

## 监听状态

```dart
// watch — 声明式订阅，值变化时重建 (build 中使用)
final value = ref.watch(myProvider);

// listen — 命令式监听副作用 (build 中安全使用)
ref.listen(myProvider, (previous, next) {
  showSnackBar('Changed from $previous to $next');
});

// listenManual — initState 等非 build 场景使用，需手动管理订阅
```

## 读取不订阅

```dart
// read — 事件处理器中使用
onPressed: () => ref.read(counterProvider.notifier).increment(),
```

## 重置状态

```dart
// invalidate — 丢弃缓存，下次读取时重算
ref.invalidate(myProvider);

// refresh — invalidate + read，立即返回新值
final newValue = await ref.refresh(myProvider.future);
```

### ref.refresh vs ref.invalidate

`refresh` = `invalidate` + `read`。不关心新值时用 `invalidate`（如 pull-to-refresh），需要结果时用 `refresh`。

## 生命周期

```dart
ref.onDispose(() => controller.close());  // 状态销毁时
ref.onCancel(() => print('no listeners')); // 最后监听者移除时
ref.onResume(() => print('new listener')); // 重新有监听者时
```

- `onDispose` 中不要触发修改其他 Provider 的副作用。
- 可多次调用 `onDispose`（每个资源一次）。
- 返回的函数可取消注册。

## Ref vs WidgetRef

Ref（Provider 内）和 WidgetRef（Widget 内）没有共享接口——这是有意设计。业务逻辑放 Notifier，UI 只调 notifier 方法。
