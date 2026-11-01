# useAppLifecycleState

## 签名

```dart
AppLifecycleState? useAppLifecycleState()
```

## 用途

返回当前的 `AppLifecycleState`，并在状态变化时重建 widget。

## 说明

- 返回当前的 `AppLifecycleState?`（如 `resumed`、`paused`、`inactive` 等）
- 当应用生命周期状态变化时，自动触发 widget 重建
- 适合根据应用前后台状态调整 UI 或暂停/恢复操作
- 状态包括：`detached`、`resumed`、`inactive`、`paused`、`hidden`（不同平台可能不同）

## 示例

### 基本用法 - 检测应用前后台

```dart
final lifecycleState = useAppLifecycleState();

return Scaffold(
  body: Center(
    child: Text(
      'App is: ${lifecycleState?.name ?? "unknown"}',
    ),
  ),
);
```

### 根据状态暂停/恢复

```dart
final lifecycleState = useAppLifecycleState();
final timer = useRef<Timer?>(null);

useEffect(() {
  if (lifecycleState == AppLifecycleState.paused) {
    // 应用进入后台，暂停定时器
    timer.value?.cancel();
  } else if (lifecycleState == AppLifecycleState.resumed) {
    // 应用回到前台，恢复定时器
    timer.value = Timer.periodic(Duration(seconds: 1), (_) {
      print('Tick');
    });
  }
  return null;
}, [lifecycleState]);

return SomeWidget();
```

### 显示不同 UI

```dart
final lifecycleState = useAppLifecycleState();

if (lifecycleState == AppLifecycleState.paused) {
  return Container(
    color: Colors.grey,
    child: Center(child: Text('App is in background')),
  );
}

return MainContent();
```

## 生命周期状态说明

| 状态 | 说明 |
|---|---|
| `detached` | 应用被销毁 |
| `resumed` | 应用在前台，可交互 |
| `inactive` | 应用处于非活跃状态（如来电话、画中画） |
| `paused` | 应用进入后台 |
| `hidden` | 应用被隐藏（某些平台） |

## 注意事项

- 返回值是 `AppLifecycleState?`，可能为 `null`（初始状态未知）
- 如果需要监听变化执行副作用而不重建，使用 `useOnAppLifecycleStateChange`
- 通常与 `useOnAppLifecycleStateChange` 配合使用
