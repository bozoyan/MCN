# useTabController

## 签名

```dart
TabController useTabController({
  required int length,
  int initialIndex = 0,
  Duration? animationDuration,
})
```

## 用途

创建并自动管理 `TabController` 的生命周期，widget dispose 时自动销毁。

## 说明

- 返回一个 `TabController` 实例
- `length`：Tab 数量
- `initialIndex`：初始选中的 Tab 索引
- Widget dispose 时自动调用 `controller.dispose()`
- 通常与 `TabBar` 和 `TabBarView` 配合使用

## 示例

### 基本用法

```dart
final tabController = useTabController(length: 3);

return Column(
  children: [
    TabBar(
      controller: tabController,
      tabs: [
        Tab(text: 'Tab 1'),
        Tab(text: 'Tab 2'),
        Tab(text: 'Tab 3'),
      ],
    ),
    Expanded(
      child: TabBarView(
        controller: tabController,
        children: [
          Center(child: Text('Content 1')),
          Center(child: Text('Content 2')),
          Center(child: Text('Content 3')),
        ],
      ),
    ),
  ],
);
```

### 监听 Tab 变化

```dart
final tabController = useTabController(length: 2);
final currentIndex = useState(0);

useEffect(() {
  void listener() {
    currentIndex.value = tabController.index;
  }
  tabController.addListener(listener);
  return () => tabController.removeListener(listener);
}, [tabController]);

return Column(
  children: [
    Text('Current tab: ${currentIndex.value}'),
    TabBar(
      controller: tabController,
      tabs: [Tab(text: 'A'), Tab(text: 'B')],
    ),
    Expanded(
      child: TabBarView(
        controller: tabController,
        children: [PageA(), PageB()],
      ),
    ),
  ],
);
```

### 程序控制 Tab 切换

```dart
final tabController = useTabController(length: 3);

return Column(
  children: [
    Row(
      children: [
        IconButton(
          icon: const RevericIcon(RevericIcons.caret_left),
          onPressed: () {
            if (tabController.index > 0) {
              tabController.animateTo(tabController.index - 1);
            }
          },
        ),
        IconButton(
          icon: const RevericIcon(RevericIcons.caret_right),
          onPressed: () {
            if (tabController.index < 2) {
              tabController.animateTo(tabController.index + 1);
            }
          },
        ),
      ],
    ),
    Expanded(
      child: TabBarView(
        controller: tabController,
        children: [Page1(), Page2(), Page3()],
      ),
    ),
  ],
);
```
