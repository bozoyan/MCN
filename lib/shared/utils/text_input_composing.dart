// 职责: 外部 TextEditingController 编辑 — IME 检测、组词安全写入、save 前 form 同步、dirty 通知与焦点保持
// 关联文件:
//   lib/third/form/flutter_hook_form.dart
// 遵循的 Rules:
//   .agents/rules/text-input-ime.md
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../third/form/flutter_hook_form.dart';

/// 当前 [TextEditingController] 是否处于 IME 合成输入（如中文拼音组词）中。
bool isTextInputComposing(TextEditingController controller) {
  final composing = controller.value.composing;
  return composing.isValid && !composing.isCollapsed;
}

/// 组词期间延后写入 controller 文本，避免打断 IME。
///
/// 裸赋值 `controller.value = TextEditingValue(text: ..., selection: ...)` 会把
/// `composing` 重置成默认的 [TextRange.empty]，等于通知平台「组词已结束」。macOS
/// embedder 收到 collapsed composing 且此前正在组词时会调用 `discardMarkedText`，
/// 用户正在输入的拼音被直接丢弃。
///
/// 因此后台事件（草稿消费、handoff、建议填充、resend 等）写入 composer 时必须走本
/// 函数：未组词立即写入；正在组词则挂一次性 listener，等 `composing` 变空后再套用。
///
/// [buildText] 接收写入时刻的最新文本，从而延后执行时基于用户组词完成后的内容计算
/// （append 语义不会丢掉刚上屏的字）。光标统一落到文末，与改造前各调用点行为一致。
void writeControllerTextAfterComposing(
  TextEditingController controller,
  String Function(String currentText) buildText,
) {
  void apply() {
    final next = buildText(controller.text);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  if (!isTextInputComposing(controller)) {
    apply();
    return;
  }

  // controller 先被 dispose 时 ChangeNotifier 会清空监听，回调不会再触发，无需额外
  // 兜底；listener 只可能由 notify 唤醒，此时 controller 必然存活。
  void awaitComposingEnd() {
    if (isTextInputComposing(controller)) {
      return;
    }
    controller.removeListener(awaitComposingEnd);
    apply();
  }

  controller.addListener(awaitComposingEnd);
}

/// 校验/提交前将 controller 最新文本写入 form（typing 期间不写 form）。
void syncFormFieldsFromControllersBeforeValidate<F extends FieldSchema>({
  required FormFieldsController<F> form,
  required Map<F, TextEditingController> fields,
}) {
  for (final entry in fields.entries) {
    form.updateValue(entry.key, entry.value.text, notify: false);
  }
}

/// 外部 controller 编辑后 postFrame 上报 dirty；可选在父级 rebuild 后恢复焦点。
void notifyDirtyAfterExternalControllerEdit({
  FocusNode? focusToPreserve,
  required bool suppress,
  TextEditingController? composingController,
  required bool Function() computeHasEdits,
  required bool Function() readHasEdits,
  required void Function(bool value) writeHasEdits,
  ValueChanged<bool>? onHasChangesChanged,
}) {
  if (suppress) {
    return;
  }
  if (composingController != null &&
      isTextInputComposing(composingController)) {
    return;
  }

  void apply() {
    final next = computeHasEdits();
    if (next == readHasEdits()) {
      return;
    }
    writeHasEdits(next);
    onHasChangesChanged?.call(next);
  }

  if (focusToPreserve != null) {
    preserveFocusAfterTextEdit(focusToPreserve, apply);
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
  }
}

/// 在文本编辑副作用后恢复焦点；副作用与父级通知均延后到 postFrame，避免 build 中 setState。
void preserveFocusAfterTextEdit(FocusNode focusNode, VoidCallback action) {
  final preserve = focusNode.hasFocus;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    action();
    if (!preserve) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!focusNode.hasFocus && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
    });
  });
}
