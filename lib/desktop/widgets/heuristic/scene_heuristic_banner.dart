// 职责: 场景启发式横幅 — 编辑器顶部单行提示，显示上下文相关功能推荐
// 关联文件:
//   lib/shared/heuristic/scene_registry.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/heuristic.json
//   assets/translations/zh-CN/heuristic.json
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

class SceneHeuristicBanner extends StatelessWidget {
  const SceneHeuristicBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: RevericSpacing.md),
          RevericIcon(
            RevericIcons.lightbulb_outline,
            size: 18,
            color: colors.accent,
          ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Text(
              context.t(LocaleKeys.heuristicGoThere),
              style: typo.uiSmall.copyWith(color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
        ],
      ),
    );
  }
}
