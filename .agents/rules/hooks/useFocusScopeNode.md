# useFocusScopeNode

## 签名

```dart
FocusScopeNode useFocusScopeNode({
  String? debugLabel,
  FocusOnKeyEventCallback? onKeyEvent,
  bool skipTraversal = false,
  bool canRequestFocus = true,
})
```

## 用途

创建并自动管理 `FocusScopeNode` 的生命周期，widget dispose 时自动销毁。

## 说明

- 返回一个 `FocusScopeNode` 实例
- Widget dispose 时自动调用 `node.dispose()`
- `FocusScopeNode` 用于管理焦点范围（focus scope），例如在多个 TextField 之间按 Tab 切换
- 与 `FocusNode` 的区别：`FocusScope` 管理一组焦点节点，通常用于表单级焦点控制

## 示例

### 基本用法

```dart
final scopeNode = useFocusScopeNode();

return Focus(
  focusScopeNode: scopeNode,
  child: Column(
    children: [
      TextField(
        focusNode: FocusNode(),
        decoration: InputDecoration(labelText: 'Name'),
      ),
      TextField(
        focusNode: FocusNode(),
        decoration: InputDecoration(labelText: 'Email'),
      ),
    ],
  ),
);
```

### 程序化控制焦点

```dart
final scopeNode = useFocusScopeNode();

return Column(
  children: [
    Focus(
      focusScopeNode: scopeNode,
      child: Column(
        children: [
          TextField(decoration: InputDecoration(labelText: 'Field 1')),
          TextField(decoration: InputDecoration(labelText: 'Field 2')),
        ],
      ),
    ),
    ElevatedButton(
      onPressed: () => scopeNode.requestFocus(),
      child: Text('Focus first field'),
    ),
  ],
);
```

## 与 useFocusNode 对比

| | useFocusNode | useFocusScopeNode |
|---|---|---|
| 用途 | 单个可聚焦控件 | 一组焦点的范围管理 |
| 适用场景 | TextField、按钮等单个控件 | 表单、对话框等焦点组 |

## 注意事项

- 参数（`debugLabel`、`onKeyEvent`、`skipTraversal`、`canRequestFocus`）在 rebuild 时会同步到已有的 FocusScopeNode
- 通常用在 `Focus` widget 的 `focusScopeNode` 参数上
