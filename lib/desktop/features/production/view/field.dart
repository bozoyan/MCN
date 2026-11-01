// 职责: 将派生面板的离散字段连接到通用分段或下拉控件。
// 关联文件:
//   lib/desktop/features/production/view/form.dart
//   lib/shared/components/reveric_segmented_control.dart
import 'package:flutter/material.dart';
import '../../../../shared/components/reveric_segmented_control.dart';
import '../../../../shared/components/reveric_select.dart';
import '../../../../shared/form/form.dart';
import '../../../../shared/theme/theme.dart';
import 'form.dart';

class ViewChoice<T> extends StatelessWidget {
  const ViewChoice({
    super.key,
    required this.field,
    required this.label,
    required this.options,
  });
  final ViewField field;
  final String label;
  final Map<T, String> options;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: RevericSpacing.lg),
    child: HookedFormField<ViewField, T>(
      fieldHook: field,
      notifyOnChange: true,
      builder: (value, onChanged, error) => LayoutBuilder(
        builder: (context, constraints) {
          if (options.length > 5 || constraints.maxWidth < 340) {
            return RevericSelect<T>(
              value: value,
              label: label,
              items: [
                for (final entry in options.entries)
                  RevericSelectItem(value: entry.key, label: entry.value),
              ],
              onChanged: (next) => onChanged?.call(next),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: RevericTheme.typographyOf(context).uiSmallSemibold,
              ),
              const SizedBox(height: RevericSpacing.xs),
              RevericSegmentedControl<T>(
                segments: [
                  for (final entry in options.entries)
                    RevericSegment(value: entry.key, label: entry.value),
                ],
                selected: value as T,
                onChanged: (next) => onChanged?.call(next),
              ),
            ],
          );
        },
      ),
    ),
  );
}
