# usePlatformBrightness

## 签名

```dart
Brightness usePlatformBrightness()
```

## 用途

返回当前的平台亮度模式（深色/浅色），并在变化时重建 widget。

## 说明

- 返回 `Brightness`（`light` 或 `dark`）
- 当系统亮度模式变化时，自动触发 widget 重建
- 适合根据系统主题调整 UI

## 示例

### 基本用法 - 响应系统主题

```dart
final brightness = usePlatformBrightness();

return Container(
  color: brightness == Brightness.dark ? Colors.black : Colors.white,
  child: Text(
    'Current mode: ${brightness.name}',
    style: TextStyle(
      color: brightness == Brightness.dark ? Colors.white : Colors.black,
    ),
  ),
);
```

### 配合 RevericTheme

```dart
final brightness = usePlatformBrightness();
final isDark = brightness == Brightness.dark;

return MaterialApp(
  theme: RevericTheme.light(),
  darkTheme: RevericTheme.dark(),
  themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
  home: MyHomePage(),
);
```

### 与 useOnPlatformBrightnessChange 对比

```dart
// usePlatformBrightness - 返回值 + 触发重建
final brightness = usePlatformBrightness();
return Container(color: brightness == Brightness.dark ? Colors.black : Colors.white);

// useOnPlatformBrightnessChange - 只执行回调（不重建）
useOnPlatformBrightnessChange((prev, curr) {
  print('Brightness changed to $curr');
});
```

## 注意事项

- 返回当前的系统亮度模式
- 系统切换深色/浅色模式时会重建 widget
- 如果需要执行副作用而不重建，使用 `useOnPlatformBrightnessChange`
