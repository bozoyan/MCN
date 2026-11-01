# ProviderObservers

监听 Provider 生命周期事件（值变化、创建、销毁）。用于日志、分析、调试。

## 实现

```dart
final class Logger extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    print('{"provider": "${context.provider}", "newValue": "$newValue"}');
  }
}

void main() {
  runApp(
    ProviderScope(
      observers: [Logger()],
      child: const MyApp(),
    ),
  );
}
```

## 命名 Provider

```dart
final myProvider = Provider<int>((ref) => 0, name: 'MyProvider');
// Codegen 自动命名
```

## 注意

原地修改状态（如 List 不重新赋值）时 `previousValue` 和 `newValue` 可能是同一引用。先 clone 再修改以获得区分。
