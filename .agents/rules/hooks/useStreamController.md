# useStreamController

## 签名

```dart
StreamController<T> useStreamController<T>({
  bool sync = false,
  VoidCallback? onListen,
  VoidCallback? onCancel,
})
```

## 用途

创建并自动管理 `StreamController` 的生命周期，widget dispose 时自动关闭。

## 说明

- 返回一个 `StreamController<T>` 实例（broadcast 类型）
- Widget dispose 时自动调用 `controller.close()`
- 可以通过 `controller.stream` 获取流
- 适合需要手动控制 Stream 的场景

## 示例

### 基本用法 - 创建 Stream

```dart
final controller = useStreamController<int>();

// 向 stream 添加数据
useEffect(() {
  controller.add(1);
  controller.add(2);
  controller.add(3);
  return null;
}, []);

final snapshot = useStream(controller.stream);

return Text('Latest: ${snapshot.data ?? "none"}');
```

### 配合按钮触发

```dart
final controller = useStreamController<int>();
final counter = useState(0);

return Column(
  children: [
    StreamBuilder<int>(
      stream: controller.stream,
      builder: (context, snapshot) {
        return Text('Value: ${snapshot.data ?? "none"}');
      },
    ),
    ElevatedButton(
      onPressed: () {
        counter.value++;
        controller.add(counter.value);
      },
      child: Text('Add value'),
    ),
  ],
);
```

### 自定义监听回调

```dart
final controller = useStreamController<String>(
  onListen: () => print('Stream listened to'),
  onCancel: () => print('Stream cancelled'),
);

// 使用 controller.stream
```

## 注意事项

- 创建的是 broadcast StreamController，可以有多个监听者
- 配合 `useStream` 来监听创建的 stream
- dispose 时自动 close，无需手动管理
