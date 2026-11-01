# usePageController

## 签名

```dart
PageController usePageController({
  int initialPage = 0,
  double viewportFraction = 1.0,
  bool keepPage = true,
})
```

## 用途

创建并自动管理 `PageController` 的生命周期，widget dispose 时自动销毁。

## 说明

- 返回一个 `PageController` 实例
- 用于 `PageView` 的控制器
- Widget dispose 时自动调用 `controller.dispose()`
- 可以控制页面滚动、获取当前页面等

## 示例

### 基本用法

```dart
final pageController = usePageController();

return PageView(
  controller: pageController,
  children: [
    Container(color: Colors.red, child: Center(child: Text('Page 1'))),
    Container(color: Colors.green, child: Center(child: Text('Page 2'))),
    Container(color: Colors.blue, child: Center(child: Text('Page 3'))),
  ],
);
```

### 监听页面变化

```dart
final pageController = usePageController();
final currentPage = useState(0);

useEffect(() {
  void listener() {
    currentPage.value = pageController.page?.round() ?? 0;
  }
  pageController.addListener(listener);
  return () => pageController.removeListener(listener);
}, [pageController]);

return Column(
  children: [
    Text('Current page: ${currentPage.value}'),
    Expanded(
      child: PageView(
        controller: pageController,
        children: [Page1(), Page2(), Page3()],
      ),
    ),
  ],
);
```

### 程序控制页面切换

```dart
final pageController = usePageController(initialPage: 0);

return Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () {
            pageController.previousPage(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          child: Text('Previous'),
        ),
        SizedBox(width: 16),
        ElevatedButton(
          onPressed: () {
            pageController.nextPage(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          child: Text('Next'),
        ),
      ],
    ),
    Expanded(
      child: PageView(
        controller: pageController,
        children: [Page1(), Page2(), Page3()],
      ),
    ),
  ],
);
```

### 带页面指示器

```dart
final pageController = usePageController();
final currentPage = useState(0);

useEffect(() {
  void listener() {
    currentPage.value = pageController.page?.round() ?? 0;
  }
  pageController.addListener(listener);
  return () => pageController.removeListener(listener);
}, [pageController]);

return Stack(
  children: [
    PageView(
      controller: pageController,
      children: [Page1(), Page2(), Page3()],
    ),
    Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          return Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: currentPage.value == index
                  ? Colors.blue
                  : Colors.grey,
            ),
          );
        }),
      ),
    ),
  ],
);
```
