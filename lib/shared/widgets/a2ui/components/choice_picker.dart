// 职责: A2UI ChoicePicker 的 builder — 单选用下拉，多选用复选框列表，chips 样式用筛选项。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/components/write_back.dart
//   lib/shared/widgets/a2ui/components/toggle.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/components/reveric_filter_chip.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../components/reveric_filter_chip.dart';
import '../../../components/reveric_select.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../theme/theme.dart';
import '../component.dart';
import 'field_frame.dart';
import 'toggle.dart';
import 'write_back.dart';

typedef _Option = ({String value, String label});

Widget buildChoicePicker(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  return _A2uiChoicePicker(
    label: props.string('label'),
    options: [
      for (final item in props.list('options'))
        if (item case final Map<Object?, Object?> option)
          if (option['value'] case final String value)
            (value: value, label: A2uiProps.asString(option['label']) ?? value),
    ],
    selected: switch (props.value('value')) {
      final List<Object?> values => values.whereType<String>().toList(),
      final String value => [value],
      _ => const [],
    },
    multiple: props.string('variant') == 'multipleSelection',
    chips: props.string('displayStyle') == 'chips',
    error: a2uiCheckMessage(context, props.validationErrors.firstOrNull),
    write: a2uiWriterFor(context, props, 'value'),
  );
}

class _A2uiChoicePicker extends HookWidget {
  const _A2uiChoicePicker({
    required this.label,
    required this.options,
    required this.selected,
    required this.multiple,
    required this.chips,
    required this.error,
    required this.write,
  });

  final String? label;
  final List<_Option> options;
  final List<String> selected;
  final bool multiple;
  final bool chips;
  final String? error;
  final bool Function(Object? value)? write;

  @override
  Widget build(BuildContext context) {
    final touched = useState(false);
    final write = this.write;

    void select(String value) {
      if (write == null) {
        return;
      }
      touched.value = true;
      if (!multiple) {
        write([value]);
        return;
      }
      write(
        selected.contains(value)
            ? [
                for (final item in selected)
                  if (item != value) item,
              ]
            : [...selected, value],
      );
    }

    final enabled = write != null;
    final shownError = touched.value ? error : null;

    if (!multiple && !chips) {
      // RevericSelect 自带标签，错误文案单独放在下方。
      return A2uiFieldFrame(
        label: null,
        error: shownError,
        child: RevericSelect<String>(
          label: label == null || label!.isEmpty ? null : label,
          value: selected.firstOrNull,
          placeholder: context.t(LocaleKeys.commonChoose),
          enabled: enabled,
          items: [
            for (final option in options)
              RevericSelectItem(value: option.value, label: option.label),
          ],
          onChanged: select,
        ),
      );
    }

    final Widget content;
    if (chips) {
      content = Wrap(
        spacing: RevericSpacing.sm,
        runSpacing: RevericSpacing.sm,
        children: [
          for (final option in options)
            RevericFilterChip(
              label: option.label,
              selected: selected.contains(option.value),
              onTap: enabled ? () => select(option.value) : null,
            ),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            A2uiCheckRow(
              label: option.label,
              value: selected.contains(option.value),
              onChanged: enabled ? (_) => select(option.value) : null,
            ),
        ],
      );
    }
    return A2uiFieldFrame(label: label, error: shownError, child: content);
  }
}
