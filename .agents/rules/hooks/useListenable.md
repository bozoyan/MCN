# useListenable

## 签名

```dart
T useListenable<T extends Listenable?>(T listenable)
```

## 用途

订阅 `Listenable` 并在其触发通知时重建 widget，同时返回 listenable 自身。

## 说明

- 订阅 `Listenable`（如 `ChangeNotifier`、`Animation`、`ValueNotifier` 等）
- 当 listenable 触发通知时，标记 widget 需要重建
- **返回** listenable 自身（可用于链式调用）
- 适合只需要重建通知，不需要直接消费值的场景

## 示例

### 监听 ChangeNotifier

```dart
final model = useMemoized(() => MyChangeNotifier());

// 当 model 通知时重建
useListenable(model);

return Column(
  children: [
    Text('Data: ${model.data}'), // 手动读取 model.data
    ElevatedButton(
      onPressed: () => model.fetchData(),
      child: Text('Fetch'),
    ),
  ],
);
```

### 监听 Animation

```dart
final controller = useAnimationController(
  duration: Duration(seconds: 1),
);

// 动画值变化时重建
useListenable(controller);

return Container(
  width: 100 * controller.value, // 手动读取 controller.value
  height: 100,
  color: Colors.blue,
);
```

### 与 useValueListenable 对比

```dart
final controller = useTextEditingController();

// useListenable - 只触发重建，需要手动读值
useListenable(controller);
Text(controller.text); // 手动读取

// useValueListenable - 返回值并触发重建
final value = useValueListenable(controller);
Text(value.text); // 直接使用返回的值
```

## 注意事项

- 只触发重建，不返回值
- 如果需要获取 listenable 的当前值，使用 `useValueListenable`
- 如果不需要重建，只需要执行副作用，使用 `useOnListenableChange`
