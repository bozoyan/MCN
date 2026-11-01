# useSingleTickerProvider

## 签名

```dart
TickerProvider useSingleTickerProvider()
```

## 用途

创建一个单次使用的 `TickerProvider`，通常内部被 `useAnimationController` 使用。

## 说明

- 返回一个 `TickerProvider`
- 通常不需要直接使用，因为 `useAnimationController` 会自动调用
- 如果你需要手动创建 `AnimationController` 并需要 `vsync`，可以使用
- 注意：一个 widget 只能使用一次（因为是 SingleTickerProvider）

## 示例

### 配合手动创建的 AnimationController

```dart
final tickerProvider = useSingleTickerProvider();
final controller = AnimationController(
  vsync: tickerProvider,
  duration: Duration(seconds: 1),
);
```

### 通常不需要直接使用

```dart
// 通常直接用 useAnimationController，它会自动处理 vsync
final controller = useAnimationController(
  duration: Duration(seconds: 1),
);
// useAnimationController 内部已经调用了 useSingleTickerProvider
```

## 注意事项

- 一个 HookWidget 只能调用一次 `useSingleTickerProvider`
- 通常不需要直接使用，除非有特殊需求
- `useAnimationController` 已经内部使用了这个 hook
