# Text Input & IME Rules

## 适用范围

- 使用 **外部 `TextEditingController`** 绑定 `TextField` / `RevericTextField` / Markdown 编辑器，同时又用 `lib/third/form` 做校验与提交的编辑面板。
- 中文、日文、韩文等 **IME 组词输入** 场景。
- 编辑面板通过 `onHasChangesChanged` 向父级（如 `NovelEditorPage`）上报 dirty 状态。

共享工具：`lib/shared/utils/text_input_composing.dart`

参考实现：`lib/desktop/widgets/agent_management/agent_rule_edit_panel.dart`

## 本质原因

**失焦不是 FocusNode 用错，而是输入过程中的副作用触发了整棵子树 rebuild，输入框在 rebuild 中被拆掉/重建，IME 连接断开。**

中文 IME 会放大问题：组词与上屏都会多次改动 controller；若每次改动都走「同步 form → notify → 父级 dirty → rebuild」，第一个字上屏时 dirty 从 false 变 true，父级也会 rebuild，最容易失焦。

典型触发链：

```
用户输入 / IME 上屏
  → Controller listener
  → form.updateValue(notify: true) 或 onHasChangesChanged(true)
  → useForm(listen: true) 整页 rebuild + 父级 rebuild
  → TextField 重建 → 失焦
```

隐蔽路径：`useEffect` 里 `controller.text = baseline` 在 **build 阶段同步** 触发 listener，若再同步调用父级回调，会触发 `setState() during build`。

## 必须遵守

### 1. typing 期间不写 form

外部 controller 是输入期的唯一真相源。**不要在 controller listener 里调用 `form.updateValue`**。仅在校验/保存前一次性写入：

```dart
syncFormFieldsFromControllersBeforeValidate(
  form: form,
  fields: {MyFields.name: nameController, ...},
);
if (!form.validate()) return;
```

`form.hasChanged` 读的是 `FormFieldState.value`（由 `didChange` 更新），typing 期间不 sync 时它不会反映 controller 文本；不要用 `form.hasChanged` 驱动 Save 或 `onHasChangesChanged`。

### 2. 需要避免输入期 rebuild 时用 `useForm(listen: false)`

父级 dirty 上报会触发 rebuild 的面板（如 Agent Rule）：

```dart
final form = useForm<MyFields>(..., listen: false);
```

其它面板可保持默认 `listen: true`，只要 typing 不写 form、不在 listener 里 `notify: true` 即可。

### 3. dirty 用 baseline 本地比较

```dart
bool computeHasEdits() =>
    nameController.text != effectiveEntity.name ||
    contentController.text != effectiveEntity.content ||
    enabledValue != effectiveEntity.enabled;
```

Header 保存按钮、离开确认、`canDrag` 等 UI 用 `computeHasEdits()`，不要用 `form.hasChanged`。

### 4. 通知父级必须 postFrame

`onHasChangesChanged` 会触发父级 `useState` → 父级 rebuild → 失焦高危。**禁止**在 controller listener 或 `useEffect` 内同步调用：

```dart
// ❌
onHasChangesChanged?.call(true);

// ✅
WidgetsBinding.instance.addPostFrameCallback((_) {
  onHasChangesChanged?.call(next);
});
```

推荐用 `notifyDirtyAfterExternalControllerEdit` 或 `useEffect` 依赖 `computeHasEdits()` 结果。若 dirty 翻转后仍失焦，用 `preserveFocusAfterTextEdit`。

### 5. 程序化改 controller 要 suppress listener

rule 切换、保存后 reset 等场景：

```dart
syncingControllersRef.value = true;
nameController.text = baseline.name;
contentController.text = baseline.content;
syncingControllersRef.value = false;

WidgetsBinding.instance.addPostFrameCallback((_) {
  hasEdits.value = false;
  onHasChangesChanged?.call(false);
});
```

listener 开头应检查 `syncingControllersRef.value` 并直接 return。

### 6. IME 合成期跳过 dirty / 父级通知

```dart
if (isTextInputComposing(controller)) return;
```

组词阶段不要 flip dirty、不要通知父级；**上屏后再处理**。

## 禁止组合（高风险）

| 模式 | 原因 |
|------|------|
| `useValueListenable(textController)` 绑定输入 UI | 每键 rebuild |
| `HookedFormField(notifyOnChange: true)` + 外部 controller | 双重 rebuild |
| controller listener 里 `form.updateValue(..., notify: true)` | 整页 rebuild |
| typing 期间 sync form + `useForm(listen: true)` | 无必要且易误触 notify |
| `useEffect` 依赖 `form.hasChanged` 同步 `onHasChangesChanged` | build 阶段改父级 state |
| header/layout 随 dirty 增删 widget | 结构性 rebuild 更易丢 focus |

## 监听 controller 的推荐写法

```dart
useEffect(() {
  void onNameChanged() {
    if (syncingControllersRef.value) return;
    if (isTextInputComposing(nameController)) return;
    notifyDirtyAfterExternalControllerEdit(
      focusToPreserve: nameFocusNode,
      suppress: syncingControllersRef.value,
      composingController: nameController,
      computeHasEdits: computeHasEdits,
      readHasEdits: () => hasEdits.value,
      writeHasEdits: (v) => hasEdits.value = v,
      onHasChangesChanged: onHasChangesChanged,
    );
  }
  nameController.addListener(onNameChanged);
  return () => nameController.removeListener(onNameChanged);
}, [nameController, nameFocusNode]);
```

## 测试要求

涉及外部 controller 编辑面板时，至少覆盖：

1. IME 组词（composing range 存在）时 focus 不变。
2. IME 上屏（commit）后 focus 不变，且 dirty 变 true。
3. 带 `onHasChangesChanged` 的父级 harness（模拟 `NovelEditorPage` rebuild）。
4. baseline 重置（save / 切换实体）不抛 `setState during build`。

参考：`test/desktop/widgets/agent_management/agent_rule_edit_panel_focus_test.dart`

## 与 form.md 的关系

- 纯 `HookedTextFormField`、无外部 controller 的表单：仍优先 `form.hasChanged`、默认 `notifyOnChange: false`。
- **一旦引入外部 `TextEditingController`**（Markdown 编辑器、tag editor、复杂控件）：按本文档执行，不再适用 form.md 中「优先 form.hasChanged」的默认约定。
