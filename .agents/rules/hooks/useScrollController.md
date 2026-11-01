# useScrollController

## 签名

```dart
ScrollController useScrollController({
  double initialScrollOffset = 0.0,
  bool keepScrollOffset = true,
  String? debugLabel,
  ScrollControllerCallback? onAttach,
  ScrollControllerCallback? onDetach,
  List<Object?>? keys,
})
```

## 用途

创建并自动管理 `ScrollController` 的生命周期，widget dispose 时自动销毁。

## 说明

- 返回一个 `ScrollController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于监听滚动位置、控制滚动行为
- 可配合 `SingleChildScrollView`、`ListView`、`GridView` 等使用

## 示例

### 基本用法 - 监听滚动

```dart
final scrollController = useScrollController();
final scrollOffset = useState(0.0);

useEffect(() {
  void listener() {
    scrollOffset.value = scrollController.offset;
  }
  scrollController.addListener(listener);
  return () => scrollController.removeListener(listener);
}, [scrollController]);

return Column(
  children: [
    Text('Scroll offset: ${scrollOffset.value}'),
    Expanded(
      child: ListView.builder(
        controller: scrollController,
        itemCount: 100,
        itemBuilder: (context, index) => ListTile(
          title: Text('Item $index'),
        ),
      ),
    ),
  ],
);
```

### 滚动到顶部

```dart
final scrollController = useScrollController();

return Column(
  children: [
    IconButton(
      icon: const RevericIcon(RevericIcons.arrow_upward_rounded),
      onPressed: () {
        scrollController.animateTo(
          0,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
    ),
    Expanded(
      child: ListView.builder(
        controller: scrollController,
        itemCount: 100,
        itemBuilder: (context, index) => ListTile(
          title: Text('Item $index'),
        ),
      ),
    ),
  ],
);
```

### 配合 useListenable 监听

```dart
final controller = useScrollController();
useListenable(controller); // 滚动时触发重建

final showBackToTop = controller.offset > 200;

return Stack(
  children: [
    ListView.builder(
      controller: controller,
      itemCount: 100,
      itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
    ),
    if (showBackToTop)
      Positioned(
        bottom: 16,
        right: 16,
        child: FloatingActionButton(
          onPressed: () => controller.animateTo(0, duration: Duration(milliseconds: 300)),
          child: const RevericIcon(RevericIcons.arrow_upward_rounded),
        ),
      ),
  ],
);
```
