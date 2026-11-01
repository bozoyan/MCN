# useReassemble

## 签名

```dart
void useReassemble(VoidCallback callback)
```

## 用途

在每次 hot reload 时执行回调，类似 `State.reassemble`。

## 说明

- 仅在 debug 模式下有效（release 模式不执行）
- `callback` 在 hot reload 时被调用
- 适合热重载时重新加载数据、重置状态等开发调试场景

## 示例

### 热重载时重新加载数据

```dart
final data = useState<Data?>(null);

useReassemble(() {
  // hot reload 时重新加载数据
  loadData().then((d) => data.value = d);
});

useEffect(() {
  loadData().then((d) => data.value = d);
  return null;
}, []);
```

### 热重载时重置状态

```dart
final counter = useState(0);

useReassemble(() {
  counter.value = 0; // hot reload 时重置计数器
});
```

## 注意事项

- 仅在 debug 模式生效，release 模式无任何效果
- 保持回调轻量，避免在 hot reload 时执行耗时操作
