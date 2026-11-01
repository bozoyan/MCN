# useValueNotifier

## 签名

```dart
ValueNotifier<T> useValueNotifier<T>(T initialValue)
```

## 用途

创建并自动管理 `ValueNotifier<T>` 的生命周期，widget dispose 时自动销毁。

## 说明

- 返回一个 `ValueNotifier<T>` 实例
- 类似 `useState`，但更明确地创建 `ValueNotifier`
- Widget dispose 时自动调用 `valueNotifier.dispose()`
- `ValueNotifier` 继承自 `ChangeNotifier`，也实现了 `ValueListenable<T>`

## 示例

### 基本用法 - 替代 useState

```dart
final counter = useValueNotifier(0);

return Column(
  children: [
    ValueListenableBuilder(
      valueListenable: counter,
      builder: (context, value, _) => Text('Count: $value'),
    ),
    ElevatedButton(
      onPressed: () => counter.value++,
      child: Text('Increment'),
    ),
  ],
);
```

### 配合 useValueListenable

```dart
final notifier = useValueNotifier('Hello');

// 使用 useValueListenable 订阅
final value = useValueListenable(notifier);

return Column(
  children: [
    Text('Value: $value'),
    ElevatedButton(
      onPressed: () => notifier.value = 'World',
      child: Text('Change'),
    ),
  ],
);
```

### 与使用 useState 对比

```dart
// useState - 返回 ValueNotifier，但语义上更偏向状态
final state1 = useState(0); // state1 is ValueNotifier<int>

// useValueNotifier - 更明确地创建 ValueNotifier
final state2 = useValueNotifier(0); // state2 is ValueNotifier<int>

// 两者在功能上是等价的
```

## 注意事项

- 与 `useState` 功能类似，都返回 `ValueNotifier<T>`
- `useValueNotifier` 语义更明确，表示创建一个 `ValueNotifier`
- dispose 时自动调用 `dispose()`
- 可以作为 `ValueListenable` 传递给其他 widget
