# Testing

## Unit Tests

```dart
void main() {
  test('counter starts at 0', () {
    final container = ProviderContainer.test();
    expect(container.read(counterProvider), 0);
  });
}
```

Container.listen 用于自动释放的 Provider：

```dart
final sub = container.listen<String>(provider, (_, _) {});
expect(sub.read(), 'Some value');
```

## Widget Tests

```dart
testWidgets('my test', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MyWidget()),
  );
  final container = tester.container();
  expect(container.read(provider), 'value');
});
```

## Mocking

```dart
final container = ProviderContainer.test(
  overrides: [
    exampleProvider.overrideWith((ref) => 'Hello from tests'),
  ],
);
```

### Mock Notifier 最佳实践

优先 mock Notifier 的依赖（如 repository），而不是 mock Notifier 本身。如必须 mock，**subclass** 而非 implement。Codegen 的 mock 需要与被 mock 的 Notifier 同文件才能访问生成的基类。
