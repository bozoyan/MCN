# Automatic Retry

Provider 失败时自动重试。默认最多 10 次，指数退避 200ms → 6.4s。

## 自定义 retry 函数

签名: `Duration? Function(int retryCount, Object error)`

返回 `Duration` 为下次重试延迟，返回 `null` 停止重试。

```dart
Duration? myRetry(int retryCount, Object error) {
  if (retryCount >= 5) return null;
  if (error is ProviderException) return null; // 依赖失败不重试
  return Duration(milliseconds: 200 * (1 << retryCount));
}
```

## 应用位置

```dart
// 全局
ProviderScope(retry: myRetry, child: MyApp())

// 按 Provider (manual)
final myProvider = Provider<int>(retry: myRetry, (ref) => 0);

// 按 Provider (codegen)
@Riverpod(retry: myRetry)
int myProvider(Ref ref) => 0;
```

## 禁用重试

```dart
ProviderScope(retry: (retryCount, error) => null, child: MyApp())
```

## 默认行为

- **Error** 不重试（表示 bug，重试无用）
- **ProviderException** 不重试（表示依赖的 Provider 失败了，不应替它重试）

## await 与重试

`await ref.watch(myProvider.future)` 会持续等待直到重试耗尽或成功，中间失败被跳过。
