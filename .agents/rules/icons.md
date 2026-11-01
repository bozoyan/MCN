# 图标规则

## 原则

- 所有 UI 图标使用 `RevericIcon` + `RevericIcons`（Phosphor SVG），禁止使用 `Icon(Icons.*)`（Material 图标）。项目覆盖了 Material Icons 字体，使用 `Icons.*` 会渲染成 tofu，因此不存在 Material fallback。

## 新增图标流程

1. 先在 `lib/shared/theme/reveric_icons.dart` 和 `assets/icons/phosphor/` 中查找是否已有需要的图标。
2. 如果没有，从 `${PHOSPHOR_ICONS_DIR}` 指向的 SVG 源查找 `regular` 权重图标；未配置时再检查 `$HOME/Pictures/phosphor-icons/SVGs/regular`。本地没有图库时，可从官方仓库 [phosphor-icons/core](https://github.com/phosphor-icons/core) 的 `assets/regular/` 获取，并将 `PHOSPHOR_ICONS_DIR` 指向该目录。
3. 两处来源都不可用时明确报告阻塞，不得回退 Material 图标。找到后将 `.svg` 复制到 `assets/icons/phosphor/`。
4. 在 `RevericIcons` 类中注册新常量，格式：
   ```dart
   static const icon_name = '$_base/filename.svg';
   ```
5. 在 `pubspec.yaml` 的 `flutter > assets` 中确认 SVG 已被包含（通常自动匹配 `assets/icons/phosphor/` 目录）。

## 命名约定

- 使用 `snake_case`，与 `RevericIcons` 已有命名风格一致。
- 使用 phosphor 官方名称或描述性名称，例如 `account_tree`、`chat_bubble_outline`。
- 避免与已有常量重名。

## 渲染

`RevericIcon` 自动继承 `IconTheme` 的 `color` 和 `size`，也支持显式传参：

```dart
RevericIcon(RevericIcons.check_circle, size: 16, color: colors.accent)
```
