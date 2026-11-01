// 职责: 编辑作品分类，并按起点男女频目录选择候选，保留任意旧值及自定义文本。
// 关联文件:
//   lib/shared/models/novel_form_fields.dart
//   lib/shared/models/novel_categories.dart
//   lib/shared/form/hooked_text_form_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_filter_chip.dart';
import '../../components/reveric_segmented_control.dart';
import '../../form/form.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/novel_categories.dart';
import '../../theme/theme.dart';

class NovelCategoryField extends HookWidget {
  const NovelCategoryField({super.key, required this.fieldHook});

  final FieldSchema fieldHook;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final expanded = useState(false);
    final audience = useState('male');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标签自绘，把平台目录入口放在同一行，避免按钮悬在输入框下方另占一行。
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(LocaleKeys.libraryCategory),
                style: typo.uiSmallSemibold.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                expanded.value = !expanded.value;
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: typo.uiSmall,
              ),
              child: Text(
                context.t(
                  expanded.value
                      ? LocaleKeys.libraryCategoryHide
                      : LocaleKeys.libraryCategoryBrowse,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.xs),
        HookedTextFormField<FieldSchema>(
          fieldHook: fieldHook,
          hintText: context.t(LocaleKeys.libraryCategoryCustomHint),
          notifyOnChange: true,
        ),
        if (expanded.value) ...[
          const SizedBox(height: RevericSpacing.md),
          Wrap(
            spacing: RevericSpacing.md,
            runSpacing: RevericSpacing.sm,
            children: [
              _CompactSegments(
                selected: audience.value,
                segments: [
                  RevericSegment(
                    value: 'male',
                    label: context.t(LocaleKeys.libraryCategoryMale),
                  ),
                  RevericSegment(
                    value: 'female',
                    label: context.t(LocaleKeys.libraryCategoryFemale),
                  ),
                ],
                onChanged: (value) => audience.value = value,
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.md),
          _CategoryChoices(
            fieldHook: fieldHook,
            categories: qidianNovelCategories[audience.value]!,
          ),
        ],
      ],
    );
  }
}

/// 定宽小号分段：筛选器只是辅助，不该像主控件那样撑满整行。
class _CompactSegments extends StatelessWidget {
  const _CompactSegments({
    required this.selected,
    required this.segments,
    required this.onChanged,
  });

  final String selected;
  final List<RevericSegment<String>> segments;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64.0 * segments.length,
      child: RevericSegmentedControl<String>(
        selected: selected,
        segments: segments,
        height: 26,
        onChanged: onChanged,
      ),
    );
  }
}

class _CategoryChoices extends StatelessWidget {
  const _CategoryChoices({required this.fieldHook, required this.categories});

  final FieldSchema fieldHook;

  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    final form = useFormContext<FieldSchema>(context);
    final current = form.getValue<String>(fieldHook);
    return Wrap(
      spacing: RevericSpacing.xs,
      runSpacing: RevericSpacing.xs,
      children: [
        for (final category in categories.toSet())
          RevericFilterChip(
            label: category,
            selected: current == category,
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              form.updateValue(fieldHook, category);
            },
          ),
      ],
    );
  }
}
