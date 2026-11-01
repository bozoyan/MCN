# Consumers

Consumers 是连接 Widget 树和 Provider 树的桥梁，为 UI 提供 `WidgetRef`。

## Consumer (builder)

```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final value = ref.watch(myProvider);
        return Text(value.toString());
      },
    );
  }
}
```

`ref` 是 WidgetRef 类型。`child` 参数可传入不依赖 Provider 的子 widget 避免多余重建。

## ConsumerWidget

```dart
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(myProvider);
    return Text(value.toString());
  }
}
```

## ConsumerStatefulWidget + ConsumerState

```dart
class MyWidget extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends ConsumerState<MyWidget> {
  @override
  Widget build(BuildContext context) {
    final value = ref.watch(myProvider);
    return Text(value.toString());
  }
}
```

## 选型

- **Consumer**: 不改变 widget 基类，略啰嗦。
- **ConsumerWidget**: 不需要 State 时的首选。
- **ConsumerStatefulWidget**: 需要 State（TabController、动画等）。
