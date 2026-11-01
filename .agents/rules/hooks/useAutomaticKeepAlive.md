# useAutomaticKeepAlive

## 签名

```dart
void useAutomaticKeepAlive({
  bool wantKeepAlive = true,
})
```

## 用途

等效于 `AutomaticKeepAlive` widget，让 widget 在滑出屏幕后仍然保持 alive 状态。

## 说明

- 调用后，当前 widget 会被标记为需要保持 alive
- 通常用于 `PageView`、`TabBarView`、`ListView` 等可滚动组件中的子 widget
- 避免 widget 滑出屏幕后被 dispose，再次进入时重新构建
- 不需要返回值，只需要调用即可

## 示例

### 在 PageView 中保持页面状态

```dart
class MyPage extends HookWidget {
  @override
  Widget build(BuildContext context) {
    useAutomaticKeepAlive(); // 保持页面状态

    final counter = useState(0);

    // 即使滑出屏幕，counter 的值也会保留
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Count: ${counter.value}'),
            ElevatedButton(
              onPressed: () => counter.value++,
              child: Text('Increment'),
            ),
          ],
        ),
      ),
    );
  }
}

// 在 PageView 中使用
final pageController = usePageController();

return PageView(
  controller: pageController,
  children: [
    MyPage(), // 滑出后状态保留
    AnotherPage(),
  ],
);
```

### 在 TabBarView 中保持 Tab 状态

```dart
class TabContent extends HookWidget {
  final int tabIndex;

  const TabContent({required this.tabIndex});

  @override
  Widget build(BuildContext context) {
    useAutomaticKeepAlive(); // 保持 Tab 状态

    final scrollController = useScrollController();

    // 切换 Tab 后，滚动位置仍然保留
    return ListView.builder(
      controller: scrollController,
      itemCount: 100,
      itemBuilder: (context, index) => ListTile(
        title: Text('Item $index in Tab $tabIndex'),
      ),
    );
  }
}
```

### 与 AutomaticKeepAlive widget 对比

```dart
// 使用 AutomaticKeepAlive widget
class MyPage extends StatefulWidget {
  @override
  _MyPageState createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 需要保持 alive

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用
    return Content();
  }
}

// 使用 useAutomaticKeepAlive hook（更简洁）
class MyPage extends HookWidget {
  @override
  Widget build(BuildContext context) {
    useAutomaticKeepAlive(); // 一行搞定
    return Content();
  }
}
```

## 注意事项

- 只需要在 `build` 方法中调用一次即可
- 适合需要在滚动组件中保持状态的页面或 widget
- 过多使用可能会影响内存，只在需要时使
