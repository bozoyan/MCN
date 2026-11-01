// 职责: 完成后发现推荐横幅 — 首页小说列表上方的单行提示，推荐用户尚未使用的功能
// 关联文件:
//   lib/shared/heuristic/feature_metadata.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/heuristic.json
//   assets/translations/zh-CN/heuristic.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';

import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/heuristic/feature_metadata.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/feature_id.dart';
import '../../../shared/theme/theme.dart';

class DiscoveryBanner extends StatelessWidget {
  const DiscoveryBanner({
    super.key,
    required this.feature,
    this.onGoThere,
    this.onNotToday,
    this.onStopSuggestions,
    this.onDismissSession,
  });

  final FeatureId feature;
  final VoidCallback? onGoThere;
  final VoidCallback? onNotToday;
  final VoidCallback? onStopSuggestions;
  final VoidCallback? onDismissSession;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final meta = featureMetadata[feature];
    final featureName = meta != null
        ? context.t(meta.nameKey)
        : feature.storageKey;
    final featureDesc = meta != null ? context.t(meta.descriptionKey) : '';

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
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
                children: [
                  TextSpan(
                    text: featureName,
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                  if (featureDesc.isNotEmpty) ...[
                    const TextSpan(text: ' — '),
                    TextSpan(text: featureDesc),
                  ],
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: onGoThere,
            child: Text(context.t(LocaleKeys.heuristicGoThere)),
          ),
          TextButton(
            onPressed: onNotToday,
            child: Text(context.t(LocaleKeys.heuristicNotToday)),
          ),
          Builder(
            builder: (buttonContext) => RevericIconButton(
              icon: RevericIcons.more_horiz,
              tooltip: context.t(LocaleKeys.commonMoreActions),
              onPressed: () {
                final box = buttonContext.findRenderObject()! as RenderBox;
                showRevericContextMenu(
                  context: context,
                  position: box.localToGlobal(Offset(0, box.size.height)),
                  entries: [
                    RevericMenuItem(
                      label: context.t(LocaleKeys.heuristicStopSuggestions),
                      onTap: onStopSuggestions,
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            icon: RevericIcon(
              RevericIcons.close_rounded,
              size: 16,
              color: colors.textSecondary,
            ),
            onPressed: onDismissSession,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 16,
          ),
          const SizedBox(width: RevericSpacing.sm),
        ],
      ),
    );
  }
}
