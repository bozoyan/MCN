# Automatic Disposal

开启 auto-dispose 后，Provider 在无监听者一帧后销毁状态，释放资源和内存。

## 启用 / 禁用

```dart
// Codegen: 默认启用，用 @Riverpod(keepAlive: true) 关闭
@Riverpod(keepAlive: true)
String helloWorld(Ref ref) => 'Hello world!';

// Manual: 加 .autoDispose 后缀
final provider = Provider.autoDispose<int>((ref) => 0);
```

**Family 必须配合 autoDispose**，否则每种参数组合会永久缓存，造成内存泄漏。

## 生命周期

监听者计数归零 → 等一帧 → `onCancel` → 状态销毁 → `onDispose`

## ref.keepAlive

在 auto-dispose 开启时，调用 `ref.keepAlive()` 阻止销毁：

```dart
final link = ref.keepAlive();
// 某时恢复自动销毁:
link.close();
```

Provider 重算后 auto-dispose 自动重新生效。

## ref.invalidate

`ref.invalidate(provider)` 强制销毁状态。如果还有监听者，会重建；否则保持销毁直到再次被读取。

## 缓存时长

Riverpod 没有内置 "缓存 X 秒" 机制。可结合 `Timer` + `ref.keepAlive` 或 `onCancel`/`onResume` 实现。
