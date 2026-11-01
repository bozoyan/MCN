# useTextEditingController

## 签名

```dart
// 带初始文本
TextEditingController useTextEditingController({String? text, List<Object?>? keys})

// 带初始 TextEditingValue（更精细控制）
TextEditingController useTextEditingController.fromValue(
  TextEditingValue value, [
  List<Object?>? keys,
])
```

## 用途

创建并自动管理 `TextEditingController` 的生命周期，widget dispose 时自动销毁。

## 说明

- `useTextEditingController` 是一个 callable class，支持 `.fromValue(...)` 变体
- 提供了可选的初始文本 `text`（只在首次创建时使用）
- `fromValue(...)` 可用于指定初始 `TextEditingValue`（如设置选区、组合文字等）
- Widget dispose 时自动调用 `controller.dispose()`
- `TextEditingController` 本身是 `ValueListenable<TextEditingValue>`，可用于 `useValueListenable`
- `keys` 参数控制何时重建 controller（默认只在首次创建）
- **HookedForm + 外部 controller 编辑面板**（Markdown 编辑器、向父级上报 dirty、CJK IME）：见 `.agents/rules/text-input-ime.md`；不要对该场景使用 `useValueListenable(controller)` 驱动 rebuild

## 示例

### 基本用法

```dart
final controller = useTextEditingController();

return TextField(
  controller: controller,
  onChanged: (value) {
    print('Current text: $value');
  },
);
```

### 设置初始文本

```dart
final controller = useTextEditingController(text: 'Initial text');

return TextField(controller: controller);
```

### 配合 useValueListenable 获取实时文本

> ⚠️ 编辑面板 + form + IME 场景不要用此模式（见 `.agents/rules/text-input-ime.md`）。以下仅适用于简单 UI（如字符计数、搜索框即时预览）。

```dart
final controller = useTextEditingController();
final value = useValueListenable(controller); // 监听变化

// value 是 TextEditingValue，value.text 是实际文本
return Column(
  children: [
    TextField(controller: controller),
    Text('You typed: ${value.text}'), // 实时更新
  ],
);
```

### 配合 useDebounced 实现搜索防抖

```dart
final controller = useTextEditingController();
final value = useValueListenable(controller);
final debouncedText = useDebounced(value.text, Duration(milliseconds: 300));

useEffect(() {
  if (debouncedText == null) return null;
  print('Searching for: $debouncedText');
  // 执行搜索
  return null;
}, [debouncedText]);

return TextField(controller: controller);
```

### 重置/清空文本

```dart
final controller = useTextEditingController();

return Row(
  children: [
    Expanded(child: TextField(controller: controller)),
    IconButton(
      icon: const RevericIcon(RevericIcons.close),
      onPressed: () {
        controller.clear(); // 或 controller.text = '';
      },
    ),
  ],
);
```
