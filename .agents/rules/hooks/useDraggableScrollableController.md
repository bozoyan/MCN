# useDraggableScrollableController

## 签名

```dart
DraggableScrollableController useDraggableScrollableController()
```

## 用途

创建并自动管理 `DraggableScrollableController` 的生命周期，用于 `DraggableScrollableSheet`。

## 说明

- 返回一个 `DraggableScrollableController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于控制 `DraggableScrollableSheet` 的拖拽状态
- 可以获取当前子组件大小比例

## 示例

### 基本用法 - 配合 DraggableScrollableSheet

```dart
final controller = useDraggableScrollableController();

return DraggableScrollableSheet(
  controller: controller,
  builder: (context, scrollController) {
    return Container(
      color: Colors.blue,
      child: ListView.builder(
        controller: scrollController,
        itemCount: 100,
        itemBuilder: (context, index) => ListTile(
          title: Text('Item $index'),
        ),
      ),
    );
  },
);
```

### 监听拖拽变化

```dart
final controller = useDraggableScrollableController();
final currentSize = useState(0.0);

useEffect(() {
  void listener() {
    currentSize.value = controller.size; // 当前大小比例 (0.0 - 1.0)
  }
  controller.addListener(listener);
  return () => controller.removeListener(listener);
}, [controller]);

return Column(
  children: [
    Text('Current size: ${currentSize.value.toStringAsFixed(2)}'),
    Expanded(
      child: DraggableScrollableSheet(
        controller: controller,
        builder: (context, scrollController) => Container(color: Colors.blue),
      ),
    ),
  ],
);
```

### 程序控制

```dart
final controller = useDraggableScrollableController();

return Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => controller.jumpTo(0.5), // 跳到一半
          child: Text('Half'),
        ),
        ElevatedButton(
          onPressed: () => controller.jumpTo(1.0), // 完全展开
          child: Text('Expand'),
        ),
      ],
    ),
    Expanded(
      child: DraggableScrollableSheet(
        controller: controller,
        builder: (context, scrollController) => Container(color: Colors.green),
      ),
    ),
  ],
);
```

## 注意事项

- 专门用于 `DraggableScrollableSheet`
- `controller.size` 获取当前大小比例（0.0 - 1.0）
- `controller.jumpTo()` 或 `controller.animateTo()` 控制位置
