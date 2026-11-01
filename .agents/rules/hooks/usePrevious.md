# usePrevious

## 签名

```dart
T? usePrevious<T>(T value)
```

## 用途

返回上一次调用时的 `value`，首次调用返回 `null`。

## 说明

- 保存上一次传入的 `value`，并在下次调用时返回
- 首次调用返回 `null`（因为没有"上一次"）
- 适合比较值的前后变化，或执行依赖于旧值的操作
- 类似于 React 的 `usePrevious` hook

## 示例

### 检测值是否变化

```dart
final counter = useState(0);
final prevCounter = usePrevious(counter.value);

return Column(
  children: [
    Text('Current: ${counter.value}'),
    Text('Previous: ${prevCounter ?? "none"}'),
    ElevatedButton(
      onPressed: () => counter.value++,
      child: Text('Increment'),
    ),
  ],
);
```

### 监听变化并执行操作

```dart
final userId = useState('user1');
final prevUserId = usePrevious(userId.value);

useEffect(() {
  if (prevUserId != null && prevUserId != userId.value) {
    print('User changed from $prevUserId to ${userId.value}');
    // 执行用户切换逻辑
  }
  return null;
}, [userId.value]);
```

### 比较状态变化

```dart
final data = useStream(someStream);
final prevData = usePrevious(data.data);

useEffect(() {
  if (prevData != null && data.hasData) {
    if (prevData != data.data) {
      print('Data changed');
    }
  }
  return null;
}, [data.data]);
```

## 注意事项

- 首次调用一定返回 `null`
- 返回类型是 `T?`（可空），需要处理 `null` 情况
- 与 `useValueChanged` 不同，`usePrevious` 只是保存旧值，不自动执行回调
