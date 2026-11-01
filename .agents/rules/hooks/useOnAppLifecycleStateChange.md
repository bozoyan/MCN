# useOnAppLifecycleStateChange

## 签名

```dart
void useOnAppLifecycleStateChange(LifecycleCallback? onStateChanged)
```

其中 `LifecycleCallback` 定义为：

```dart
typedef LifecycleCallback = FutureOr<void> Function(
  AppLifecycleState? previous,
  AppLifecycleState current,
);
```

## 用途

监听应用生命周期状态变化并执行回调，**不触发** widget 重建。

## 说明

- 当应用生命周期状态变化时，执行 `onStateChanged` 回调
- **不会**触发 widget 重建
- 回调接收前一个状态和当前状态
- 适合执行副作用（如保存数据、暂停游戏、释放资源等）

## 示例

### 基本用法 - 监听前后台切换

```dart
useOnAppLifecycleStateChange((previous, current) {
  print('App lifecycle: $previous -> $current');

  if (current == AppLifecycleState.paused) {
    print('App went to background');
  } else if (current == AppLifecycleState.resumed) {
    print('App came to foreground');
  }
});
```

### 保存数据

```dart
final store = useContext().read(dataStoreProvider);

useOnAppLifecycleStateChange((previous, current) async {
  if (current == AppLifecycleState.paused) {
    // 应用进入后台时保存数据
    await store.saveData();
    print('Data saved');
  }
});
```

### 暂停/恢复游戏或计时器

```dart
final gameTimer = useRef<Timer?>(null);

useOnAppLifecycleStateChange((previous, current) {
  if (current == AppLifecycleState.paused) {
    // 暂停游戏
    gameTimer.value?.cancel();
  } else if (current == AppLifecycleState.resumed) {
    // 恢复游戏
    gameTimer.value = Timer.periodic(Duration(seconds: 1), (_) {
      // 游戏逻辑
    });
  }
});
```

## 与 useAppLifecycleState 对比

```dart
// useAppLifecycleState - 返回值 + 触发重建
final state = useAppLifecycleState();
// state 变化时会重建 widget

// useOnAppLifecycleStateChange - 只执行回调（不重建）
useOnAppLifecycleStateChange((prev, curr) {
  print('State changed: $prev -> $curr');
});
```

## 注意事项

- 不会触发 widget 重建，只执行回调
- 回调可以是异步的（`FutureOr<void>`）
- 如果需要访问 context 或更新 UI，使用 `useAppLifecycleState`
- 适合执行不需要 UI 反馈的副作用
