# Provider Overrides

所有 Provider 都可以被覆盖，用于测试、调试、不同环境或 scoping。

## 设置位置

```dart
// Flutter
ProviderScope(
  overrides: [
    counterProvider.overrideWith((ref) => 42),
  ],
  child: MyApp(),
)

// Dart
final container = ProviderContainer(
  overrides: [
    counterProvider.overrideWith((ref) => 42),
  ],
);
```

## 覆盖方法

- **overrideWith** — 提供新的实现（如返回值的函数）。
- **overrideWithValue** — 替换为固定值（适合 FutureProvider / StreamProvider）。

```dart
counterProvider.overrideWith((ref) => 42);
futureProvider.overrideWithValue(Future.value('mock'));
```

## Family 覆盖

```dart
// 单参数
userProvider('123').overrideWith((ref) => User(name: 'Mock'));

// 所有参数
userProvider.overrideWith((ref, arg) => User(name: 'User $arg'));
```
