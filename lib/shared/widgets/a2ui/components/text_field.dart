// 职责: A2UI TextField 的 builder — 双向绑定页面数据，IME 组词期间不写回，校验提示在用户编辑后显示。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/components/write_back.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/utils/text_input_composing.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../components/reveric_text_field.dart';
import '../../../utils/text_input_composing.dart';
import '../component.dart';
import 'field_frame.dart';
import 'write_back.dart';

Widget buildTextField(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  return _A2uiTextField(
    label: props.string('label'),
    placeholder: props.string('placeholder'),
    value: props.string('value') ?? '',
    variant: props.string('variant'),
    error: a2uiCheckMessage(context, props.validationErrors.firstOrNull),
    write: a2uiWriterFor(context, props, 'value'),
  );
}

final _partialNumber = RegExp(r'^-?\d*\.?\d*$');

final _numberFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) =>
      _partialNumber.hasMatch(newValue.text) ? newValue : oldValue,
);

class _A2uiTextField extends HookWidget {
  const _A2uiTextField({
    required this.label,
    required this.placeholder,
    required this.value,
    required this.variant,
    required this.error,
    required this.write,
  });

  final String? label;
  final String? placeholder;
  final String value;
  final String? variant;
  final String? error;

  /// 未绑定数据路径时为 null，输入只保留在本地。
  final bool Function(Object? value)? write;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: value);
    final touched = useState(false);
    final latestValue = useRef(value);
    final latestWrite = useRef(write);
    latestValue.value = value;
    latestWrite.value = write;

    // 页面数据被 action 或其他组件改写时同步到输入框；组词中不覆盖，避免丢掉拼音。
    useEffect(() {
      if (controller.text != value && !isTextInputComposing(controller)) {
        controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
      return null;
    }, [value]);

    // 组词结束（上屏）后才写回页面数据。
    useOnListenableChange(controller, () {
      if (isTextInputComposing(controller) ||
          controller.text == latestValue.value) {
        return;
      }
      final writer = latestWrite.value;
      if (writer == null) {
        return;
      }
      if (!touched.value) {
        touched.value = true;
      }
      writer(controller.text);
    });

    final obscured = variant == 'obscured';
    final number = variant == 'number';
    final multiline = variant == 'longText';
    return RevericTextField(
      controller: controller,
      label: label == null || label!.isEmpty ? null : label,
      hintText: placeholder == null || placeholder!.isEmpty
          ? null
          : placeholder,
      errorText: touched.value ? error : null,
      obscureText: obscured,
      multiline: multiline,
      minLines: 3,
      maxLines: 8,
      autocorrect: !obscured && !number,
      enableSuggestions: !obscured && !number,
      keyboardType: number
          ? const TextInputType.numberWithOptions(signed: true, decimal: true)
          : multiline
          ? TextInputType.multiline
          : TextInputType.text,
      inputFormatters: number ? [_numberFormatter] : null,
    );
  }
}
