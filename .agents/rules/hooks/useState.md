# useState

## 签名

```dart
ValueNotifier<T> useState<T>(T initialData)
```

## 用途

创建一个局部响应式变量，当值改变时自动触发 widget 重建。

## 说明

- 返回一个 `ValueNotifier<T>`，通过其 `.value` 属性读写状态
- 第一次调用时初始化为 `initialData`，后续 rebuild 会保持同一个实例
- 修改 `.value` 会自动触发 widget 重建
- widget dispose 时自动销毁 `ValueNotifier`

## 示例

### 基本用法 - 计数器

```dart
class Counter extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final counter = useState(0);

    return GestureDetector(
      onTap: () => counter.value++,
      child: Text(counter.value.toString()),
    );
  }
}
```

### 复杂对象状态

```dart
class FormPage extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final formData = useState<Map<String, dynamic>>({
      'name': '',
      'email': '',
    });

    return Column(
      children: [
        TextField(
          onChanged: (value) {
            formData.value = {...formData.value, 'name': value};
          },
        ),
        ElevatedButton(
          onPressed: () {
            print('Submit: ${formData.value}');
          },
          child: Text('Submit'),
        ),
      ],
    );
  }
}
```

### 与 useValueListenable 配合

```dart
final counter = useState(0);
final value = useValueListenable(counter); // 获取当前值并订阅变化

// counter.value++ 会触发重建，value 会自动更新
```
