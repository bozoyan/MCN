# useWidgetStatesController

## 签名

```dart
WidgetStatesController useWidgetStatesController({
  Set<WidgetState>? values,
})
```

## 用途

创建并自动管理 `WidgetStatesController` 的生命周期，用于跟踪 widget 状态（hovered、pressed 等）。

## 说明

- 返回一个 `WidgetStatesController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于跟踪 Material widget 的交互状态
- 状态包括：`hovered`、`focused`、`pressed`、`dragged`、`selected`、`scrolledUnder`、`disabled`、`error`

## 示例

### 基本用法

```dart
final controller = useWidgetStatesController();

return TextButton(
  statesController: controller,
  onPressed: () {},
  child: Text('Button'),
);
```

### 监听状态变化

```dart
final controller = useWidgetStatesController();
useListenable(controller);

return Column(
  children: [
    ElevatedButton(
      statesController: controller,
      onPressed: () {},
      child: Text('Hover me'),
    ),
    Text(
      'Hovered: ${controller.value.contains(WidgetState.hovered)}',
    ),
  ],
);
```

### 程序控制状态

```dart
final controller = useWidgetStatesController();

return Row(
  children: [
    ElevatedButton(
      statesController: controller,
      onPressed: () {},
      child: Text('Button'),
    ),
    IconButton(
      icon: const RevericIcon(RevericIcons.edit),
      onPressed: () {
        // 手动更新状态
        controller.update(WidgetState.selected, true);
      },
    ),
  ],
);
```

## WidgetState 值

| 状态 | 说明 |
|---|---|
| `hovered` | 鼠标悬停 |
| `focused` | 获得焦点 |
| `pressed` | 被按下 |
| `dragged` | 被拖拽 |
| `selected` | 被选中 |
| `scrolledUnder` | 滚动到其他内容下方 |
| `disabled` | 禁用 |
| `error` | 错误状态 |

## 注意事项

- 用于需要精确控制或监听 widget 状态的场景
- `controller.value` 是一个 `Set<WidgetState>`
- 使用 `controller.update(state, true/false)` 更新状态
