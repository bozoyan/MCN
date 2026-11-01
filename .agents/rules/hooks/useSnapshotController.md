# useSnapshotController

## 签名

```dart
SnapshotController useSnapshotController({
  bool allowSnapshotting = false,
})
```

## 用途

创建并自动管理 `SnapshotController` 的生命周期，用于 `SnapshotWidget`。

## 说明

- 返回一个 `SnapshotController` 实例
- `allowSnapshotting`：是否允许快照功能
- Widget dispose 时自动调用 `controller.dispose()`
- 用于 Flutter 的 `SnapshotWidget`（创建 widget 快照）

## 示例

### 基本用法

```dart
final controller = useSnapshotController(allowSnapshotting: true);

return SnapshotWidget(
  controller: controller,
  child: Container(
    width: 100,
    height: 100,
    color: Colors.blue,
  ),
);
```

### 控制快照

```dart
final controller = useSnapshotController();

return Column(
  children: [
    SnapshotWidget(
      controller: controller,
      child: SomeComplexWidget(),
    ),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () {
            controller.allowSnapshotting = true;
          },
          child: Text('Enable Snapshot'),
        ),
        SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            controller.allowSnapshotting = false;
          },
          child: Text('Disable Snapshot'),
        ),
      ],
    ),
  ],
);
```

## 注意事项

- 用于 Flutter 的 `SnapshotWidget`
- `controller.allowSnapshotting` 控制是否允许快照
- 这是一个较新的 Flutter 功能
