# useOnListenableChange

## 签名

```dart
void useOnListenableChange(Listenable listenable, VoidCallback callback)
```

## 用途

监听 `Listenable` 的变化并执行回调，**不触发** widget 重建。适合执行副作用。

## 说明

- 当 `listenable` 触发通知时，执行 `callback`
- **不会**触发 widget 重建
- 适合执行副作用（如日志、API 调用、状态同步等）
- `callback` 会在 listenable 变化时被调用

## 示例

### 监听变化执行副作用

```dart
final controller = useTextEditingController();

// 文本变化时执行回调，不触发重建
useOnListenableChange(controller, () {
  print('Text changed: ${controller.text}');
});
```

### 同步状态到外部

```dart
final controller = useTextEditingController();
final store = useContext().read(dataStoreProvider);

// 当文本变化时，同步到 store（不触发重建）
useOnListenableChange(controller, () {
  store.updateName(controller.text);
});
```

### 三种 Listenable hook 对比

```dart
final notifier = useState(0);

// 1. useListenable - 触发重建（不返回值）
useListenable(notifier);

// 2. useValueListenable - 返回值 + 触发重建
final value = useValueListenable(notifier); // value 是 int

// 3. useOnListenableChange - 只执行回调（不重建、不返回值）
useOnListenableChange(notifier, () {
  print('Value changed'); // 副作用
});
```

## 注意事项

- 不会触发 widget 重建，只执行回调
- 如果需要重建 UI，使用 `useListenable` 或 `useValueListenable`
- `callback` 中不要直接调用 `setState` 或类似的重置状态方法（会引起循环）
