# Containers / Scopes

Provider 本身是无状态的——状态存储在 **ProviderContainer** 中。

## Flutter: ProviderScope

```dart
void main() {
  runApp(
    ProviderScope(
      // 可选
      overrides: [...],
      observers: [Logger()],
      child: MyApp(),
    ),
  );
}
```

支持子树级嵌套 `ProviderScope`（见 scoping）。

## Dart: ProviderContainer

```dart
final container = ProviderContainer();
try {
  final value = container.read(myProvider);
  final sub = container.listen(myProvider, (prev, next) {});
} finally {
  container.dispose();
}
```

## 测试

使用 `ProviderContainer.test()` 让测试结束时自动 dispose：

```dart
test('counter', () {
  final container = ProviderContainer.test();
  expect(container.read(counterProvider), 0);
  container.read(counterProvider.notifier).increment();
  expect(container.read(counterProvider), 1);
});
```

Widget 测试中用 `tester.container()` 获取当前 ProviderContainer。
