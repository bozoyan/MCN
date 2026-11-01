// 职责: 在剧本首次打开时展示单一进度反馈。
// 关联文件:
//   lib/shared/widgets/screenplay/document_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'package:flutter/material.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

class ScreenplayLoading extends StatelessWidget {
  const ScreenplayLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final label = context.t(LocaleKeys.screenplayOpening);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x3l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: RevericSpacing.x3l,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.textMuted,
                semanticsLabel: label,
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(label, style: typo.uiSmall.copyWith(color: colors.textMuted)),
          ],
        ),
      ),
    );
  }
}
