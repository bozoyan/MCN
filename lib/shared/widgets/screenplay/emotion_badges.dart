// 职责: 在场次标题旁展示有限数量的情绪标签与完整情绪提示。
// 关联文件:
//   lib/shared/widgets/screenplay/document_heading.dart
//   lib/shared/widgets/screenplay/scene_properties_form.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json

import 'package:flutter/material.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

class SceneEmotionBadges extends StatelessWidget {
  const SceneEmotionBadges({
    super.key,
    required this.emotion,
    this.max = 2,
    this.stale = false,
  });
  final List<String> emotion;
  final int max;
  final bool stale;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    if (emotion.isEmpty && !stale) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: emotion.join(' · '),
      child: Wrap(
        spacing: RevericSpacing.xxs,
        runSpacing: RevericSpacing.xxs,
        children: [
          for (final label in [
            ...emotion.take(max),
            if (emotion.length > max) '+${emotion.length - max}',
            if (stale) context.t(LocaleKeys.screenplaySceneAnalysisStale),
          ])
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.sm,
                vertical: RevericSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.selected,
                borderRadius: BorderRadius.circular(RevericRadius.small),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiTiny.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
