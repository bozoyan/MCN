# useCupertinoTabController

## 签名

```dart
CupertinoTabController useCupertinoTabController({
  int initialIndex = 0,
})
```

## 用途

创建并自动管理 `CupertinoTabController` 的生命周期，用于 `CupertinoTabScaffold`。

## 说明

- 返回一个 `CupertinoTabController` 实例
- `initialIndex`：初始选中的 tab 索引
- Widget dispose 时自动调用 `controller.dispose()`
- 用于 iOS 风格的底部 tab 导航

## 示例

### 基本用法 - 配合 CupertinoTabScaffold

```dart
final controller = useCupertinoTabController(initialIndex: 0);

return CupertinoTabScaffold(
  controller: controller,
  tabBuilder: (context, index) {
    switch (index) {
      case 0:
        return CupertinoTabView(builder: (context) => Page1());
      case 1:
        return CupertinoTabView(builder: (context) => Page2());
      default:
        return Container();
    }
  },
);
```

### 程序控制 Tab 切换

```dart
final controller = useCupertinoTabController();

return Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => controller.index = 0,
          child: Text('Tab 1'),
        ),
        ElevatedButton(
          onPressed: () => controller.index = 1,
          child: Text('Tab 2'),
        ),
      ],
    ),
    Expanded(
      child: CupertinoTabScaffold(
        controller: controller,
        tabBuilder: (context, index) => /* ... */,
      ),
    ),
  ],
);
```

### 监听 Tab 变化

```dart
final controller = useCupertinoTabController();
final currentIndex = useState(0);

useEffect(() {
  void listener() {
    currentIndex.value = controller.index;
  }
  controller.addListener(listener);
  return () => controller.removeListener(listener);
}, [controller]);

return Text('Current tab: ${currentIndex.value}');
```

## 注意事项

- 专门用于 iOS 风格的 `CupertinoTabScaffold`
- 使用 `controller.index` 获取或设置当前 tab
