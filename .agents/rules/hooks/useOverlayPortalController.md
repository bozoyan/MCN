# useOverlayPortalController

## 签名

```dart
OverlayPortalController useOverlayPortalController()
```

## 用途

创建并自动管理 `OverlayPortalController` 的生命周期，用于控制 `OverlayPortal` 的显示/隐藏。

## 说明

- 返回一个 `OverlayPortalController` 实例
- Widget dispose 时自动调用 `controller.dispose()`
- 用于 Flutter 的 `OverlayPortal` widget
- 控制 overlay 内容的显示和隐藏

## 示例

### 基本用法 - 配合 OverlayPortal

```dart
final controller = useOverlayPortalController();

return OverlayPortal(
  controller: controller,
  overlayChildBuilder: (context) {
    return Container(
      color: Colors.black54,
      child: Center(child: Text('Overlay Content')),
    );
  },
  child: ElevatedButton(
    onPressed: () {
      controller.show();
    },
    child: Text('Show Overlay'),
  ),
);
```

### 切换显示/隐藏

```dart
final controller = useOverlayPortalController();

return Column(
  children: [
    ElevatedButton(
      onPressed: () {
        if (controller.isShowing) {
          controller.hide();
        } else {
          controller.show();
        }
      },
      child: Text(controller.isShowing ? 'Hide' : 'Show'),
    ),
    Expanded(
      child: OverlayPortal(
        controller: controller,
        overlayChildBuilder: (context) => /* overlay content */,
        child: /* main content */,
      ),
    ),
  ],
);
```

## 注意事项

- 用于 Flutter 的 `OverlayPortal` widget（较新）
- `controller.show()` 显示 overlay
- `controller.hide()` 隐藏 overlay
- `controller.isShowing` 获取当前显示状态
