# useExpansionTileController

> ⚠️ **已废弃**：请使用 `useExpansibleController` 替代。

## 签名

```dart
@Deprecated('Use `useExpansibleController` instead.')
ExpansionTileController useExpansionTileController({List<Object?>? keys})
```

## 替代方案

改用 `useExpansibleController`，用法完全相同，但返回 `ExpansibleController`。

```dart
// 旧（已废弃）
final controller = useExpansionTileController();

// 新
final controller = useExpansibleController();
```

详见 [useExpansibleController.md](useExpansibleController.md)。
