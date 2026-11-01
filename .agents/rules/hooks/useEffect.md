# useEffect

## 签名

```dart
void useEffect(Dispose? Function() effect, [List<Object?>? keys])
```

## 用途

处理副作用（订阅、定时器、事件监听等），并可选择性地在依赖变化时重新执行或清理。

## 说明

- `effect` 回调在每次 build 后同步调用（如果 `keys` 为 null）
- 如果提供了 `keys`，只有当 `keys` 中任一值变化时才会重新执行 `effect`
- `effect` 可以返回一个清理函数（`Dispose?`），在 effect 重新执行前或 widget dispose 时调用
- 适合处理需要清理的资源（StreamSubscription、Timer、监听器等）

## 示例

### 基本用法 - 订阅 Stream

```dart
final stream = useStreamController<int>().stream;

useEffect(() {
  final subscription = stream.listen((data) {
    print('Received: $data');
  });

  // 返回清理函数
  return () {
    subscription.cancel();
    print('Subscription cancelled');
  };
}, [stream]); // 当 stream 变化时，先取消旧的订阅，再建立新的
```

### 定时器

```dart
final counter = useState(0);

useEffect(() {
  final timer = Timer.periodic(Duration(seconds: 1), (_) {
    counter.value++;
  });

  return timer.cancel; // 清理定时器
});
// 不传 keys，每次 build 都会重新执行（谨慎使用）
```

### 监听外部值变化

```dart
final controller = useTextEditingController();
final agent = useValueListenable(agentNotifier);

useEffect(() {
  controller.text = agent.name;
  return null; // 不需要清理
}, [agent.id]); // 只有当 agent.id 变化时才重新执行
```

### 错误示例 - 漏写依赖

```dart
// ❌ 错误：effect 中读取了 agent.enabled，但没加入依赖列表
useEffect(() {
  controller.text = agent.name;
  enabled.value = agent.enabled; // 这里读取了 agent.enabled
  return null;
}, [agent.id]); // 漏掉了 agent.enabled 或整个 agent

// ✅ 正确
useEffect(() {
  controller.text = agent.name;
  enabled.value = agent.enabled;
  return null;
}, [agent]); // 或者 [agent.id, agent.enabled]
```

## 注意事项

- `keys` 列表必须包含 effect 函数体内读取的所有外部变量
- 如果不传 `keys`，effect 会在每次 build 后执行（可能导致性能问题）
- 返回的清理函数可以是 `null`，表示不需要清理
