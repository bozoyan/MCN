# useValueChanged

## 签名

```dart
R? useValueChanged<T, R>(T value, R? Function(T oldValue, R? oldResult) valueChange)
```

## 用途

监听一个值的变化，当值改变时触发回调，并返回回调的结果。

## 说明

- 第一次调用时**不会**触发 `valueChange` 回调
- 从第二次开始，只有 `value` 与之前不同时才触发回调
- 返回值是最近一次 `valueChange` 回调的返回值（首次为 `null`）
- 适合在值变化时执行副作用或计算派生状态

## 示例

### 监听值变化执行操作

```dart
final animationController = useAnimationController();
final color = useState(Colors.blue);

// 当 color.value 变化时，执行回调
useValueChanged(color.value, (oldColor, _) {
  print('Color changed from $oldColor to ${color.value}');
  animationController.forward();
  return null;
});
```

### 派生状态

```dart
final items = useState<List<Item>>([]);

// 返回过滤后的列表，当 items 变化时重新计算
final activeItems = useValueChanged(items.value, (oldItems, oldResult) {
  return items.value.where((item) => item.isActive).toList();
}) ?? []; // 首次返回 null，使用默认值
```

### 与 useEffect 对比

```dart
// useValueChanged - 专注于值变化
useValueChanged(value, (old, _) {
  doSomething(value);
  return null;
});

// useEffect - 更通用的副作用
useEffect(() {
  doSomething(value);
  return null;
}, [value]);
```

## 注意事项

- 第一次调用不会触发回调（`oldValue` 不存在）
- 回调返回值会被缓存，可通过 `useValueChanged` 的返回值获取
- 如果只需要触发重建，考虑使用 `useValueListenable` 或 `useListenable`
