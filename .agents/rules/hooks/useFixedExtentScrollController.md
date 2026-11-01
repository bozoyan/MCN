# useFixedExtentScrollController

## 签名

```dart
FixedExtentScrollController useFixedExtentScrollController({
  int initialItem = 0,
  ScrollControllerCallback? onAttach,
  ScrollControllerCallback? onDetach,
})
```

## 用途

创建并自动管理 `FixedExtentScrollController` 的生命周期，用于 `ListWheelScrollView`。

## 说明

- 返回一个 `FixedExtentScrollController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于 `ListWheelScrollView`（iOS 风格的滚轮选择器）
- 可以通过 `selectedItem` 获取当前选中项

## 示例

### 基本用法 - 配合 ListWheelScrollView

```dart
final controller = useFixedExtentScrollController(initialItem: 2);

return ListWheelScrollView(
  controller: controller,
  itemExtent: 50,
  children: List.generate(10, (index) => Center(child: Text('Item $index'))),
);
```

### 获取选中项

```dart
final controller = useFixedExtentScrollController();
final selectedIndex = useState(0);

useEffect(() {
  void listener() {
    selectedIndex.value = controller.selectedItem;
  }
  controller.addListener(listener);
  return () => controller.removeListener(listener);
}, [controller]);

return Column(
  children: [
    Text('Selected: ${selectedIndex.value}'),
    SizedBox(
      height: 200,
      child: ListWheelScrollView(
        controller: controller,
        itemExtent: 50,
        children: List.generate(10, (index) => Center(child: Text('Item $index'))),
      ),
    ),
  ],
);
```

### 程序控制滚动

```dart
final controller = useFixedExtentScrollController();

return Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const RevericIcon(RevericIcons.arrow_upward_rounded),
          onPressed: () {
            if (controller.selectedItem > 0) {
              controller.animateToItem(
                controller.selectedItem - 1,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          },
        ),
        IconButton(
          icon: const RevericIcon(RevericIcons.arrow_downward_rounded),
          onPressed: () {
            if (controller.selectedItem < 9) {
              controller.animateToItem(
                controller.selectedItem + 1,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          },
        ),
      ],
    ),
    Expanded(
      child: ListWheelScrollView(
        controller: controller,
        itemExtent: 50,
        children: List.generate(10, (index) => Center(child: Text('Item $index'))),
      ),
    ),
  ],
);
```

## 注意事项

- 专门用于 `ListWheelScrollView`，不是普通的 `ListView`
- 使用 `controller.selectedItem` 获取当前选中索引
- 使用 `controller.animateToItem()` 或 `controller.jumpToItem()` 控制滚动
