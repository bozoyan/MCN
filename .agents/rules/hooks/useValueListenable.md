# useValueListenable

## 签名

```dart
T useValueListenable<T>(ValueListenable<T> listenable)
```

## 用途

订阅 `ValueListenable` 并返回其当前值，值变化时触发 widget 重建。

## 说明

- 返回 `listenable.value` 的当前值
- 当 `listenable.value` 变化时，自动触发 widget 重建
- 适合直接消费 `ValueListenable` 的值（如 `TextEditingController`、`ValueNotifier` 等）
- `TextEditingController` 本身是 `ValueListenable<TextEditingValue>`

## 示例

### 监听 TextEditingController

```dart
final controller = useTextEditingController();

// 返回 controller.value (TextEditingValue)，输入时自动重建
final textValue = useValueListenable(controller);

return Column(
  children: [
    TextField(controller: controller),
    Text('You typed: ${textValue.text}'), // 实时更新
  ],
);
```

### 监听 useState 创建的 ValueNotifier

```dart
final counter = useState(0);

// 获取当前值并订阅变化
final count = useValueListenable(counter);

return Column(
  children: [
    Text('Count: $count'),
    ElevatedButton(
      onPressed: () => counter.value++,
      child: Text('Increment'),
    ),
  ],
);
```

### 与 useListenable 对比

```dart
final controller = useTextEditingController();

// useValueListenable - 返回值，适合消费数据
final value = useValueListenable(controller);
print(value.text); // 可以直接使用 TextEditingValue

// useListenable - 只触发重建，不返回值
useListenable(controller);
// 需要手动读取 controller.value
```

## 注意事项

- 返回的是 `listenable.value` 的当前值，类型由 `ValueListenable<T>` 决定
- 如果只需要重建通知而不需要值，考虑使用 `useListenable`
- 如果不需要重建，只需要副作用，考虑使用 `useOnListenableChange`
