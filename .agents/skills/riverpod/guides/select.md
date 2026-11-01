# 减少重建 — select

`ref.watch(provider)` 在 Provider 值变化时重建。如果 widget 只用了某个字段，用 **select** 减少重建。

## 语法

```dart
// 仅在 firstName 变化时重建
final name = ref.watch(provider.select((it) => it.firstName));
return Text('Hello $name');
```

## Async 场景

```dart
// ref.watch(provider.future) 配合 selectAsync (版本内 API 不同)
```

## 何时使用

仅在"其他属性"频繁变化且你测量到重建是瓶颈时才用。select 有额外开销，先默认 watch。
