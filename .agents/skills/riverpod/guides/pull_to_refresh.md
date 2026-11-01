# Pull-to-refresh

## 做法

```dart
RefreshIndicator(
  onRefresh: () => ref.refresh(activityProvider.future),
  child: ListView(children: [...]),
)
```

## AsyncValue 模式匹配

```dart
final activity = ref.watch(activityProvider);
switch (activity) {
  AsyncValue<Activity>(:final value?) => Text(value.activity),
  AsyncValue(:final error?) => Text('Error: $error'),
  _ => const CircularProgressIndicator(),
}
```

- **初始加载**: 无数据 → 全屏 spinner。
- **刷新**: RefreshIndicator 显示 + 保留旧数据直到新结果到达。
