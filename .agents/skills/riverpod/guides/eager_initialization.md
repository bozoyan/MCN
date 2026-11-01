# Eager Initialization

Provider 默认**惰性初始化**——首次被读取时才执行。没有内置 eager 标志（为了 tree-shaking）。

## 做法

在 ProviderScope 下放一个 Consumer 专门 watch 要预加载的 Provider：

```dart
class _EagerInitialization extends ConsumerWidget {
  const _EagerInitialization({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(myProvider);  // 预加载
    return child;
  }
}
```

只有 initializer widget 会因 Provider 变化重建；`child` 不受影响。

## Async 处理

Async Provider 可在 initializer 中显示 loading / error，直到 ready 才渲染真正的 child。
