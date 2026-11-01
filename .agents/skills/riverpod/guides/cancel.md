# Cancel / Debounce

## 离开页面时取消请求

Provider 必须是 **autoDispose**。用户离开 → 监听者归零 → `onDispose` 执行 → 取消请求。

```dart
final provider = FutureProvider.autoDispose<Data>((ref) async {
  final client = http.Client();
  ref.onDispose(client.close);
  return fetchData(client);
});
```

## Debounce 刷新

```dart
// 1. ref.onDispose 设取消标志
// 2. await Future.delayed(duration)
// 3. 如果期间被 dispose，throw 中止
```

可通过 `extension on Ref` 封装可复用逻辑。
