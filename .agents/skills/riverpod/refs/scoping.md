# Scoping Providers

**Scoping** 通过非根级 `ProviderScope` + `overrides` 改变部分 Widget 子树中 Provider 的行为。**API 可能在未来版本重构，谨慎使用。**

## Opt-in: dependencies

```dart
final currentItemIdProvider = Provider<String?>(
  dependencies: const [],
  (ref) => null,
);
```

Provider 必须显式声明 `dependencies` 才能被 scope。其他 Provider 如果要 watch 一个 scoped provider，也必须将它加入 `dependencies`。

## 使用

```dart
ProviderScope(
  overrides: [
    currentItemIdProvider.overrideWithValue('123'),
  ],
  child: const DetailPageView(),
)
```

子树中 `currentItemIdProvider` 的值将是 `'123'`，无需手动传参。
