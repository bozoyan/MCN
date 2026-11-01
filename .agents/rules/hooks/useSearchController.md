# useSearchController

## 签名

```dart
SearchController useSearchController()
```

## 用途

创建并自动管理 `SearchController` 的生命周期，用于 `SearchAnchor`。

## 说明

- 返回一个 `SearchController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于 Flutter 的搜索功能（SearchAnchor/SearchView）
- 控制搜索视图的打开/关闭和查询文本

## 示例

### 基本用法 - 配合 SearchAnchor

```dart
final searchController = useSearchController();

return SearchAnchor(
  searchController: searchController,
  builder: (context, controller) {
    return IconButton(
      icon: const RevericIcon(RevericIcons.search),
      onPressed: () {
        controller.openView();
      },
    );
  },
  suggestionsBuilder: (context, controller) {
    return [
      ListTile(title: Text('Suggestion 1')),
      ListTile(title: Text('Suggestion 2')),
    ];
  },
);
```

### 监听搜索文本

```dart
final searchController = useSearchController();
useListenable(searchController);

return Column(
  children: [
    SearchAnchor(
      searchController: searchController,
      builder: (context, controller) => SearchBar(),
      suggestionsBuilder: (context, controller) => [],
    ),
    Text('Current query: ${searchController.text}'),
  ],
);
```

### 程序控制搜索

```dart
final searchController = useSearchController();

return Row(
  children: [
    IconButton(
      icon: const RevericIcon(RevericIcons.search),
      onPressed: () => searchController.openView(),
    ),
    IconButton(
      icon: const RevericIcon(RevericIcons.close),
      onPressed: () {
        searchController.clear();
        searchController.closeView();
      },
    ),
  ],
);
```

## 注意事项

- 专门用于 Flutter 的 `SearchAnchor` widget
- `controller.text` 获取当前搜索文本
- `controller.openView()` 打开搜索视图
- `controller.closeView()` 关闭搜索视图
