# useTreeSliverController

## 签名

```dart
TreeSliverController useTreeSliverController()
```

## 用途

创建并自动管理 `TreeSliverController` 的生命周期，用于 `TreeSliver`。

## 说明

- 返回一个 `TreeSliverController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于控制 `TreeSliver` 树的展开/收起状态
- Flutter 较新的 widget（需要较新版本）

## 示例

### 基本用法 - 配合 TreeSliver

```dart
final controller = useTreeSliverController();

return TreeSliver(
  controller: controller,
  tree: treeData,
  builder: (context, node) => ListTile(title: Text(node.name)),
);
```

### 程序控制节点

```dart
final controller = useTreeSliverController();

return Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () {
            // 展开所有节点
            controller.expandAll();
          },
          child: Text('Expand All'),
        ),
        SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            // 收起所有节点
            controller.collapseAll();
          },
          child: Text('Collapse All'),
        ),
      ],
    ),
    Expanded(
      child: TreeSliver(
        controller: controller,
        tree: treeData,
        builder: (context, node) => ListTile(title: Text(node.name)),
      ),
    ),
  ],
);
```

## 注意事项

- 用于 Flutter 的 `TreeSliver` widget（较新）
- 具体 API 可能需要查阅最新 Flutter 文档
- `controller.expandAll()` 和 `controller.collapseAll()` 可能支持
