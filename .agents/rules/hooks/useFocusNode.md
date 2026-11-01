# useFocusNode

## 签名

```dart
FocusNode useFocusNode({
  String? debugLabel,
  FocusOnKeyEventCallback? onKeyEvent,
  bool skipTraversal = false,
  bool canRequestFocus = true,
  bool descendantsAreFocusable = true,
  bool descendantsAreTraversable = true,
})
```

## 用途

创建并自动管理 `FocusNode` 的生命周期，widget dispose 时自动销毁。

## 说明

- 返回一个 `FocusNode` 实例
- Widget dispose 时自动调用 `focusNode.dispose()`
- 用于管理 TextField、TextFormField 等组件的焦点状态
- 可以检测焦点变化、请求焦点、失去焦点等
- 参数在首次创建后仍可通过 `didUpdateHook` 保持同步

## 示例

### 基本用法

```dart
final focusNode = useFocusNode();

return TextField(
  focusNode: focusNode,
  decoration: InputDecoration(
    labelText: 'Name',
  ),
);
```

### 监听焦点变化

```dart
final focusNode = useFocusNode();
final isFocused = useState(false);

useEffect(() {
  void listener() {
    isFocused.value = focusNode.hasFocus;
  }
  focusNode.addListener(listener);
  return () => focusNode.removeListener(listener);
}, [focusNode]);

return Column(
  children: [
    TextField(focusNode: focusNode),
    Text(isFocused.value ? 'Focused' : 'Not focused'),
  ],
);
```

### 切换焦点

```dart
final nameFocus = useFocusNode();
final emailFocus = useFocusNode();

return Column(
  children: [
    TextField(
      focusNode: nameFocus,
      onSubmitted: (_) => emailFocus.requestFocus(), // 切换焦点
      decoration: InputDecoration(labelText: 'Name'),
    ),
    TextField(
      focusNode: emailFocus,
      decoration: InputDecoration(labelText: 'Email'),
    ),
  ],
);
```

### 配合 useListenable 监听焦点

```dart
final focusNode = useFocusNode();
useListenable(focusNode); // 焦点变化时触发重建

return Container(
  decoration: BoxDecoration(
    border: Border.all(
      color: focusNode.hasFocus ? Colors.blue : Colors.grey,
    ),
  ),
  child: TextField(focusNode: focusNode),
);
```

## 注意事项

- 参数（`debugLabel`、`onKeyEvent`、`skipTraversal`、`canRequestFocus` 等）在 rebuild 时会同步到已有的 FocusNode
- 如果需要 FocusScopeNode，使用 `useFocusScopeNode`
