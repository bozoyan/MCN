# useTransformationController

## 签名

```dart
TransformationController useTransformationController({
  Matrix4? initialValue,
})
```

## 用途

创建并自动管理 `TransformationController` 的生命周期，用于 `InteractiveViewer`。

## 说明

- 返回一个 `TransformationController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于控制 `InteractiveViewer` 的变换矩阵（缩放、平移、旋转）
- `controller.value` 是一个 `Matrix4`，表示当前变换

## 示例

### 基本用法 - 配合 InteractiveViewer

```dart
final controller = useTransformationController();

return InteractiveViewer(
  controller: controller,
  child: Image.asset('assets/large_image.jpg'),
);
```

### 获取和重置变换

```dart
final controller = useTransformationController();

return Column(
  children: [
    Expanded(
      child: InteractiveViewer(
        controller: controller,
        child: Image.asset('assets/image.jpg'),
      ),
    ),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () {
            // 重置变换
            controller.value = Matrix4.identity();
          },
          child: Text('Reset'),
        ),
        SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            // 获取当前变换矩阵
            final matrix = controller.value;
            print('Current transform: $matrix');
          },
          child: Text('Get Transform'),
        ),
      ],
    ),
  ],
);
```

### 监听变换变化

```dart
final controller = useTransformationController();
useListenable(controller); // 变换时重建

return Stack(
  children: [
    InteractiveViewer(
      controller: controller,
      child: Image.asset('assets/image.jpg'),
    ),
    Positioned(
      bottom: 16,
      right: 16,
      child: Text(
        'Scale: ${controller.value.getMaxScaleOnAxis().toStringAsFixed(2)}',
      ),
    ),
  ],
);
```

## 注意事项

- 专门用于 `InteractiveViewer`
- `controller.value` 是 `Matrix4`，包含缩放、平移、旋转信息
- 使用 `matrix.getMaxScaleOnAxis()` 获取当前缩放级别
- 可以用来保存和恢复视图状态
