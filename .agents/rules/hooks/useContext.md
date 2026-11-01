# useContext

## 签名

```dart
BuildContext useContext()
```

## 用途

获取当前 `HookWidget` 的 `BuildContext`，用于在 hook 函数内部访问 context。

## 说明

- 返回当前 widget 的 `BuildContext`
- 允许在 hook 函数内部（而非 `build` 方法中）访问 context
- 通常用于自定义 hook 中，或在需要在 effect 等地方使用 context 的场景
- **注意**：不能在 `useEffect` 初始化阶段或 hook 初始化时调用 `context.t(...)`、`Theme.of(context)` 等 inherited widget 读取方法

## 示例

### 在自定义 hook 中使用

```dart
// 自定义 hook，读取主题颜色
Color useThemeColor() {
  final context = useContext();
  return Theme.of(context).primaryColor;
}

class MyWidget extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final color = useThemeColor();
    return Container(color: color);
  }
}
```

### 与在 build 中直接使用的对比

```dart
// ✅ 在 build 顶层读取
Widget build(BuildContext context) {
  final colors = RevericTheme.colorsOf(context); // 安全

  useEffect(() {
    // 使用已经读取的值
    someService.configure(colors.accent);
    return null;
  }, [colors]);

  return Container();
}

// ❌ 在 hook 中使用 context 读取 inherited widget（可能触发断言）
Widget build(BuildContext context) {
  useEffect(() {
    // 危险！可能在 hook init 阶段触发断言
    final colors = RevericTheme.colorsOf(context);
    return null;
  }, []);

  return Container();
}
```

## 注意事项

- `useContext()` 本身可以安全调用
- 但使用 context 读取 inherited widget（如 `Theme.of`、`MediaQuery.of`、`context.t`）时，必须在 `build` 顶层进行，不能在 `useEffect`、初始化闭包中使用
- 如果需要在副作用中使用这些值，先在 build 顶层读取成局部变量，再传入
