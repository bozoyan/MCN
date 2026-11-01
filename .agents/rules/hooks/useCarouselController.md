# useCarouselController

## 签名

```dart
CarouselController useCarouselController({
  int initialItem = 0,
})
```

## 用途

创建并自动管理 `CarouselController` 的生命周期，用于 `CarouselView`。

## 说明

- 返回一个 `CarouselController` 实例
- `initialItem`：初始选中的项目索引
- Widget dispose 时自动调用 `controller.dispose()`
- 用于控制 `CarouselView` 的滚动

## 示例

### 基本用法 - 配合 CarouselView

```dart
final controller = useCarouselController();

return CarouselView(
  controller: controller,
  children: List.generate(10, (index) {
    return Container(
      color: Colors.primaries[index % Colors.primaries.length],
      child: Center(child: Text('Item $index')),
    );
  }),
);
```

### 程序控制滚动

```dart
final controller = useCarouselController(initialItem: 0);

return Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const RevericIcon(RevericIcons.caret_left),
          onPressed: () {
            final current = controller.jumpTo(
              controller.initialItem - 1,
            );
          },
        ),
        IconButton(
          icon: const RevericIcon(RevericIcons.caret_right),
          onPressed: () {
            controller.jumpTo(controller.initialItem + 1);
          },
        ),
      ],
    ),
    Expanded(
      child: CarouselView(
        controller: controller,
        children: List.generate(10, (index) => Container()),
      ),
    ),
  ],
);
```

### 监听当前项

```dart
final controller = useCarouselController();
useListenable(controller);

return Stack(
  children: [
    CarouselView(
      controller: controller,
      children: List.generate(10, (index) => Container()),
    ),
    Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Text(
        'Current: ${controller.initialItem}',
        textAlign: TextAlign.center,
      ),
    ),
  ],
);
```

## 注意事项

- 专门用于 Flutter 的 `CarouselView`（较新的 widget）
- 使用 `controller.jumpTo(index)` 跳转到指定项
- 可能需要查阅最新 Flutter 文档了解 API 细节
