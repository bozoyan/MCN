# useOnStreamChange

## 签名

```dart
StreamSubscription<T>? useOnStreamChange<T>(
  Stream<T>? stream, {
  void Function(T event)? onData,
  void Function(Object error, StackTrace stackTrace)? onError,
  void Function()? onDone,
  bool? cancelOnError,
})
```

## 用途

订阅 `Stream`，注册监听器，并自动管理订阅的生命周期。**不触发** widget 重建。

## 说明

- 返回 `StreamSubscription<T>?`
- 当 `stream` 变化时，取消旧的订阅并建立新的
- Widget dispose 时自动取消订阅
- **不会**触发 widget 重建，只执行回调

## 示例

### 基本用法 - 监听数据

```dart
final stream = getSomeStream();

useOnStreamChange(
  stream,
  onData: (data) {
    print('Received: $data');
  },
  onDone: () => print('Stream done'),
);
```

### 监听错误和完成

```dart
useOnStreamChange(
  someStream,
  onData: (data) {
    // 处理数据
  },
  onError: (error, stackTrace) {
    print('Error: $error');
  },
  onDone: () {
    print('Stream completed');
  },
  cancelOnError: false,
);
```

### 与 useStream 对比

```dart
final stream = someStream;

// useStream - 返回值 + 触发重建
final snapshot = useStream(stream);
// snapshot 包含数据，widget 会重建

// useOnStreamChange - 只执行回调（不重建）
useOnStreamChange(
  stream,
  onData: (data) {
    print('Data: $data');
  },
);
```

## 注意事项

- 不会触发 widget 重建，适合执行副作用
- 如果需要数据并更新 UI，使用 `useStream`
- `stream` 变化时，会自动取消旧订阅并建立新订阅
- 返回值是 `StreamSubscription?`，可以用于手动操作（如 pause/resume）
