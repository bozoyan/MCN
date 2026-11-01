# Providers

Provider 是 Riverpod 的核心——memoized functions，缓存计算结果，多 widget/provider 共享同一值。声明为**顶层 final 变量**，状态存在 ProviderContainer 中。

## 6 种变体

| | Synchronous | Future | Stream |
|---|---|---|---|
| Unmodifiable | Provider | FutureProvider | StreamProvider |
| Modifiable | NotifierProvider | AsyncNotifierProvider | StreamNotifierProvider |

- **Sync / Future / Stream**: 匹配函数返回类型。
- **Unmodifiable**: UI 只读。适用于计算或请求的数据。
- **Modifiable**: Notifier 暴露 `build()` + 自定义方法；UI 调用 `ref.read(provider.notifier).method()`。

## 声明方式

### 函数式 (Unmodifiable)

```dart
// Manual
final userProvider = FutureProvider<User>((ref) async {
  final response = await http.get('https://api.example.com/user/123');
  return User.fromJson(response.body);
});

// Codegen
@riverpod
Future<User> user(Ref ref) async { ... }
```

### 类式 (Modifiable / Notifier)

```dart
// Manual
final counterProvider = NotifierProvider<CounterNotifier, int>(CounterNotifier.new);

class CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

// Codegen
@riverpod
class CounterNotifier extends _$CounterNotifier {
  @override
  int build() => 0;
  void increment() => state++;
}
```

### Notifier 规则

- **构造函数中不要放逻辑** — `ref` 和 `state` 尚不可用。初始化放 `build()`。
- `build()` 由框架调用，不要直接调用。
- 多个 Provider 可返回同一类型，互不冲突（区别于 `package:provider`）。

### 修饰符

- `.autoDispose` — 无监听时自动释放缓存（codegen 默认开启，`@Riverpod(keepAlive: true)` 关闭）。
- `.family` — 支持传参，按参数独立缓存。

## 使用

- **Flutter**: `ProviderScope` → Consumer / ConsumerWidget → `ref.watch(provider)`
- **Dart**: `ProviderContainer` → `container.read(provider)` → `container.dispose()`
- **Provider 内**: 用 `ref.watch` / `ref.read` 组合其他 Provider。
