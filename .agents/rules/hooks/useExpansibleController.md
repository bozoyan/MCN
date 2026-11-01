# useExpansibleController

> 替代已废弃的 `useExpansionTileController`。

## 签名

```dart
ExpansibleController useExpansibleController({List<Object?>? keys})
```

## 用途

创建并自动管理 `ExpansibleController` 的生命周期，用于控制 `ExpansionTile` 或 `Expansible` 的展开/收起。

## 说明

- 返回一个 `ExpansibleController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于控制 `ExpansionTile`、`Expansible` 的展开状态
- 可以程序化地展开/收起

## 示例

### 基本用法 - 配合 ExpansionTile

```dart
final controller = useExpansibleController();

return ExpansionTile(
  controller: controller,
  title: Text('Expand me'),
  children: [
    ListTile(title: Text('Child 1')),
    ListTile(title: Text('Child 2')),
  ],
);
```

### 程序控制展开/收起

```dart
final controller = useExpansibleController();

return Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => controller.expand(),
          child: Text('Expand'),
        ),
        SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => controller.collapse(),
          child: Text('Collapse'),
        ),
        SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => controller.toggle(),
          child: Text('Toggle'),
        ),
      ],
    ),
    ExpansionTile(
      controller: controller,
      title: Text('Controlled Tile'),
      children: [ListTile(title: Text('Content'))],
    ),
  ],
);
```

### 监听状态

```dart
final controller = useExpansibleController();
useListenable(controller);

return Column(
  children: [
    Text('Is expanded: ${controller.isExpanded}'),
    ExpansionTile(
      controller: controller,
      title: Text('Tile'),
      children: [ListTile(title: Text('Child'))],
    ),
  ],
);
```

## 方法说明

| 方法 | 说明 |
|---|---|
| `expand()` | 展开 |
| `collapse()` | 收起 |
| `toggle()` | 切换状态 |
| `isExpanded` | 当前是否展开 |

## 注意事项

- 旧版 `useExpansionTileController` 已废弃，请改用此 hook
- 可用于 `ExpansionTile` 或 `Expansible` widget
- `controller.isExpanded` 获取当前状态
