# useAnimationController

## 签名

```dart
AnimationController useAnimationController({
  Duration? duration,
  Duration? reverseDuration,
  String? debugLabel,
  double initialValue = 0.0,
  double lowerBound = 0.0,
  double upperBound = 1.0,
  TickerProvider? vsync, // 可选，缺省时自动使用 useSingleTickerProvider
  AnimationBehavior animationBehavior = AnimationBehavior.normal,
  List<Object?>? keys,
})
```

## 用途

创建并自动管理 `AnimationController` 的生命周期，widget dispose 时自动销毁。

## 说明

- 返回一个 `AnimationController` 实例
- 自动处理 `vsync`（HookWidget 自动提供）
- Widget dispose 时自动 dispose controller
- 适合创建动画，配合 `useAnimation` 使用

## 示例

### 基本用法 - 淡入动画

```dart
class FadeIn extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: Duration(milliseconds: 300),
    );
    final animation = useAnimation(controller);

    useEffect(() {
      controller.forward(); // 启动动画
      return null;
    }, []);

    return Opacity(
      opacity: animation,
      child: Container(width: 100, height: 100, color: Colors.blue),
    );
  }
}
```

### 循环动画

```dart
final controller = useAnimationController(
  duration: Duration(seconds: 1),
);

useEffect(() {
  controller.repeat(reverse: true); // 往复循环
  return controller.dispose; // 清理
}, []);

final animation = useAnimation(controller);

return Transform.scale(
  scale: 1 + animation * 0.5,
  child: Container(width: 100, height: 100, color: Colors.red),
);
```

### 根据状态控制动画

```dart
final isExpanded = useState(false);
final controller = useAnimationController(
  duration: Duration(milliseconds: 300),
);

useEffect(() {
  if (isExpanded.value) {
    controller.forward();
  } else {
    controller.reverse();
  }
  return null;
}, [isExpanded.value]);

final animation = useAnimation(controller);

return Column(
  children: [
    IconButton(
      icon: const RevericIcon(RevericIcons.keyboard_arrow_down_rounded),
      onPressed: () => isExpanded.value = !isExpanded.value,
    ),
    Container(
      height: 100 * animation, // 根据动画值改变高度
      color: Colors.blue,
    ),
  ],
);
```

## 注意事项

- `vsync` 参数通常由 HookWidget 自动提供，无需手动传递
- 配合 `useAnimation` 获取动画当前值
- 可以使用 `controller.forward()`、`controller.reverse()`、`controller.repeat()` 等控制动画
- 与 `SingleTickerProviderMixin` 的 StatefulWidget 代码等效，但更简洁
