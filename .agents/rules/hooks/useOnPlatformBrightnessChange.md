# useOnPlatformBrightnessChange

## 签名

```dart
void useOnPlatformBrightnessChange(BrightnessCallback onBrightnessChange)
```

其中 `BrightnessCallback` 定义为：

```dart
typedef BrightnessCallback = FutureOr<void> Function(
  Brightness previous,
  Brightness current,
);
```

## 用途

监听平台亮度（深色/浅色模式）变化并执行回调，**不触发** widget 重建。

## 说明

- 当系统亮度模式变化时，执行 `onBrightnessChange` 回调
- **不会**触发 widget 重建
- 回调接收前一个亮度和当前亮度
- 适合执行副作用（如重新加载主题、更新配置等）

## 示例

### 基本用法 - 监听深色模式切换

```dart
useOnPlatformBrightnessChange((previous, current) {
  print('Brightness changed: $previous -> $current');

  if (current == Brightness.dark) {
    print('Switched to dark mode');
  } else {
    print('Switched to light mode');
  }
});
```

### 重新加载主题

```dart
final themeNotifier = useContext().read(themeProvider);

useOnPlatformBrightnessChange((previous, current) async {
  // 根据系统亮度自动切换主题
  if (current == Brightness.dark) {
    await themeNotifier.setTheme(ThemeMode.dark);
  } else {
    await themeNotifier.setTheme(ThemeMode.light);
  }
});
```

### 与 usePlatformBrightness 对比

```dart
// usePlatformBrightness - 返回值 + 触发重建
final brightness = usePlatformBrightness();
// brightness 变化时会重建 widget
return Container(color: brightness == Brightness.dark ? Colors.black : Colors.white);

// useOnPlatformBrightnessChange - 只执行回调（不重建）
useOnPlatformBrightnessChange((prev, curr) {
  print('Brightness changed to $curr');
});
```

## 注意事项

- 不会触发 widget 重建，只执行回调
- 回调可以是异步的（`FutureOr<void>`）
- 如果需要更新 UI，使用 `usePlatformBrightness`
- 通常在应用启动时注册，用于响应系统主题切换
