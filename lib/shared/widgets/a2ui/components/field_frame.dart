// 职责: 为 A2UI 输入组件提供与 RevericTextField 一致的标签和错误文案排版，并本地化未写 message 的校验提示。
// 关联文件:
//   lib/shared/widgets/a2ui/components/choice_picker.dart
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/a2ui.json
//   assets/translations/zh-CN/a2ui.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../theme/theme.dart';

/// a2ui_core 在 check 规则未写 message 时使用的固定英文提示。
const _defaultCheckMessage = 'Validation failed';

/// 组件显示的校验提示：规则未写 message 时换成本地化的通用提示。
String? a2uiCheckMessage(BuildContext context, String? error) =>
    error == _defaultCheckMessage
    ? context.t(LocaleKeys.a2uiValidationFailed)
    : error;

class A2uiFieldFrame extends StatelessWidget {
  const A2uiFieldFrame({
    super.key,
    required this.label,
    required this.error,
    required this.child,
  });

  final String? label;
  final String? error;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final label = this.label;
    final error = this.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null && label.isNotEmpty) ...[
          Text(
            label,
            style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.xs),
        ],
        child,
        if (error != null) ...[
          const SizedBox(height: RevericSpacing.xs),
          Text(error, style: typo.uiSmall.copyWith(color: colors.error)),
        ],
      ],
    );
  }
}
