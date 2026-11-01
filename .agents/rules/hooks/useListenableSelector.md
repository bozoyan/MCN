# useListenableSelector

## 签名

```dart
R useListenableSelector<R>(Listenable? listenable, R Function() selector)
```

## 用途

订阅 `Listenable`，但只在 `selector` 返回的结果变化时才触发重建，减少不必要的重建。

## 说明

- 类似 `useListenable`，但增加了过滤功能
- `selector` 函数从 listenable 中选择需要的部分
- 只有当 `selector()` 返回的值变化时，才触发重建
- 适合优化性能，避免 listenable 变化但关心的数据未变化时重建

## 示例

### 基本用法 - 过滤重建条件

```dart
final controller = useTextEditingController();

// 只有当 text 是否为空的状态变化时才重建
final bool textIsEmpty = useListenableSelector(
  controller,
  () => controller.text.isEmpty,
);

return Column(
  children: [
    TextField(controller: controller),
    ElevatedButton(
      // 只有 text 为空时按钮才不可用
      onPressed: textIsEmpty ? null : () => print("Button pressed!"),
      child: Text("Button"),
    ),
  ],
);
```

### 优化性能 - 避免无关更新

```dart
final notifier = useState(MyComplexObject());

// 只关心 name 字段，其他字段变化不重建
final name = useListenableSelector(
  notifier,
  () => notifier.value.name,
);

// notifier.value 的其他字段变化不会触发重建，只有 name 变化才会
return Text('Name: $name');
```

### 与 useListenable 对比

```dart
final controller = useTextEditingController();

// useListenable - 任何变化都重建
useListenable(controller);
// controller 的任何变化都会重建

// useListenableSelector - 只有 selector 结果变化才重建
final isEmpty = useListenableSelector(
  controller,
  () => controller.text.isEmpty,
);
// 只有 text 的空/非空状态变化时才重建
```

## 注意事项

- `selector` 在每次 listenable 通知时调用
- 只有当 `selector()` 返回的值与之前不同时才重建
- 适合优化性能，特别是当 listenable 包含多个字段但只关心部分时
- `selector` 应该是一个纯函数，只读取并可能转换数据
