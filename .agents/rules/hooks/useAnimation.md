# useAnimation

## 签名

```dart
T useAnimation<T>(Animation<T> animation)
```

## 用途

订阅 `Animation` 并返回其当前值，值变化时触发 widget 重建。

## 说明

- 返回 `animation.value` 的当前值
- 当动画值变化时，自动触发 widget 重建
- 通常与 `useAnimationController` 配合使用
- 类似 `useValueListenable`，但专门针对 `Animation`

## 示例

### 基本用法 - 淡入动画

```dart
final controller = useAnimationController(
  duration: Duration(milliseconds: 300),
);
final opacity = useAnimation(controller);

useEffect(() {
  controller.forward();
  return null;
}, []);

return Opacity(
  opacity: opacity, // 使用动画值
  child: Container(width: 100, height: 100, color: Colors.blue),
);
```

### 缩放动画

```dart
final controller = useAnimationController(
  duration: Duration(seconds: 1),
);
final scale = useAnimation(controller);

useEffect(() {
  controller.repeat(reverse: true);
  return controller.dispose;
}, []);

return Transform.scale(
  scale: scale, // 0.0 -> 1.0 -> 0.0 ...
  child: Container(width: 100, height: 100, color: Colors.red),
);
```

### 与 CurvedAnimation 配合

```dart
final controller = useAnimationController(
  duration: Duration(milliseconds: 500),
);
final curve = CurvedAnimation(
  parent: controller,
  curve: Curves.easeInOut,
);
final value = useAnimation(curve); // 使用 CurvedAnimation

useEffect(() {
  controller.forward();
  return null;
}, []);

return Transform.translate(
  offset: Offset(0, 50 * (1 - value)), // 从下往上移动
  child: Container(width: 100, height: 100, color: Colors.green),
);
```

## 与 useValueListenable 对比

```dart
final controller = useAnimationController();

// useAnimation - 专门针对 Animation
final value1 = useAnimation(controller);

// useValueListenable - 通用 Listenable
final value2 = useValueListenable(controller); // 返回 AnimationValue

// 对于 AnimationController，两者效果类似，但 useAnimation 更语义化
```

## 注意事项

- 通常配合 `useAnimationController` 使用
- 返回的 `animation.value` 类型由 `Animation<T>` 决定
- 动画完成后，值会保持在结束状态
