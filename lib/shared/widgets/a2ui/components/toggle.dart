// 职责: A2UI 布尔输入组件 CheckBox、Switch 的 builder 与整行可点的勾选行。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/components/write_back.dart
//   lib/shared/components/reveric_checkbox.dart
//   lib/shared/components/reveric_switch.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../components/reveric_checkbox.dart';
import '../../../components/reveric_switch.dart';
import '../../../theme/theme.dart';
import '../component.dart';
import 'field_frame.dart';
import 'write_back.dart';

Widget buildCheckBox(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) => _A2uiToggle(
  label: props.string('label') ?? '',
  value: props.boolean('value') ?? false,
  error: a2uiCheckMessage(context, props.validationErrors.firstOrNull),
  write: a2uiWriterFor(context, props, 'value'),
  asSwitch: false,
);

Widget buildSwitch(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) => _A2uiToggle(
  label: props.string('label') ?? '',
  value: props.boolean('value') ?? false,
  error: a2uiCheckMessage(context, props.validationErrors.firstOrNull),
  write: a2uiWriterFor(context, props, 'value'),
  asSwitch: true,
);

class _A2uiToggle extends HookWidget {
  const _A2uiToggle({
    required this.label,
    required this.value,
    required this.error,
    required this.write,
    required this.asSwitch,
  });

  final String label;
  final bool value;
  final String? error;
  final bool Function(Object? value)? write;
  final bool asSwitch;

  @override
  Widget build(BuildContext context) {
    final touched = useState(false);
    final write = this.write;
    final ValueChanged<bool>? onChanged = write == null
        ? null
        : (next) {
            touched.value = true;
            write(next);
          };
    return A2uiFieldFrame(
      label: null,
      error: touched.value ? error : null,
      child: asSwitch
          ? _SwitchRow(label: label, value: value, onChanged: onChanged)
          : A2uiCheckRow(label: label, value: value, onChanged: onChanged),
    );
  }
}

/// 复选框加文字的整行；整行点击即切换，读屏只读一次文字。
class A2uiCheckRow extends StatelessWidget {
  const A2uiCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        onTap: onChanged == null ? null : () => onChanged(!value),
        child: Row(
          children: [
            RevericCheckbox(value: value, onChanged: onChanged),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: typo.ui.copyWith(
                  color: onChanged == null
                      ? colors.textMuted
                      : colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: typo.ui.copyWith(
                color: onChanged == null
                    ? colors.textMuted
                    : colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.lg),
          RevericSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
