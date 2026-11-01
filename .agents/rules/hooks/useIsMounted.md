# useIsMounted

> ⚠️ **已废弃**：自 Flutter 3.7 起，建议直接使用 `context.mounted`。

## 签名

```dart
@Deprecated("Use BuildContext.mounted instead if you're on Flutter 3.7.0 or greater")
IsMounted useIsMounted()
```

其中 `IsMounted` 是 `bool Function()` 类型。

## 用途

检查 widget 是否已挂载（mounted），等效于 `State.mounted`。

## 说明

- 返回一个 `IsMounted`（即 `bool Function()`），调用它可检查 widget 是否仍然挂载
- 适合在异步操作完成后检查是否需要更新 UI
- 避免在 widget dispose 后调用 `setState` 或更新状态导致的错误
- 通常在 `useEffect` 或异步回调中使用

## 示例

### 基本用法 - 异步操作后检查

```dart
final isMounted = useIsMounted();
final data = useState<String?>(null);

useEffect(() {
  fetchData().then((result) {
    if (isMounted()) { // 检查 widget 是否还在
      data.value = result;
    }
  });
  return null;
}, []);

return Text(data.value ?? 'Loading...');
```

### 推荐替代方案（Flutter 3.7+）

```dart
// ✅ 推荐：使用 context.mounted
Widget build(BuildContext context) {
  Future.delayed(Duration(seconds: 2)).then((_) {
    if (context.mounted) { // 直接检查 context
      // 更新 UI
    }
  });
  // ...
}
```

## 注意事项

- 返回的是**函数**而非 `bool`，必须调用 `isMounted()` 获取结果
- 已废弃，Flutter 3.7+ 推荐使用 `context.mounted`
