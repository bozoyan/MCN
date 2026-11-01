// 职责: 移动端剧本区域共享展示组件与标签格式化。
// 关联文件:
//   lib/mobile/features/screenplay/editor_page.dart
//   lib/shared/models/screenplay.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json

import 'package:flutter/material.dart';

import '../../../shared/database/novel_content_database.dart'
    show ScreenplayEpisodeRow, ScreenplaySeasonRow;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/theme/theme.dart';

String mobileSeasonLabel(BuildContext context, ScreenplaySeasonRow season) {
  final number = context.t(
    LocaleKeys.screenplaySeason,
    namedArgs: {'number': '${season.seasonNumber}'},
  );
  return season.title.trim().isEmpty
      ? number
      : '$number · ${season.title.trim()}';
}

String mobileEpisodeLabel(BuildContext context, ScreenplayEpisodeRow episode) {
  final number = context.t(
    LocaleKeys.screenplayEpisode,
    namedArgs: {'number': '${episode.episodeNumber}'},
  );
  return episode.title.trim().isEmpty
      ? number
      : '$number · ${episode.title.trim()}';
}

String mobileSceneLabel(BuildContext context, ScreenplaySceneSummary scene) {
  return context.t(
    LocaleKeys.screenplayScene,
    namedArgs: {'number': '${scene.sceneNumber}'},
  );
}

String mobileSceneHeading(BuildContext context, ScreenplaySceneSummary scene) {
  final parts = <String>[
    if (scene.interiorExterior == screenplayInterior)
      context.t(LocaleKeys.screenplayInterior),
    if (scene.interiorExterior == screenplayInteriorExterior)
      context.t(LocaleKeys.screenplayInteriorAndExterior),
    if (scene.interiorExterior == screenplayExterior)
      context.t(LocaleKeys.screenplayExterior),
    if (scene.timeLabel.trim().isNotEmpty) scene.timeLabel.trim(),
  ];
  return parts.isEmpty
      ? context.t(LocaleKeys.screenplayUntitledScene)
      : parts.join(' · ');
}

class MobileScreenplaySectionHeader extends StatelessWidget {
  const MobileScreenplaySectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.lg,
        RevericSpacing.x2l,
        RevericSpacing.lg,
        RevericSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: typo.heading2.copyWith(color: colors.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
          // ignore: use_null_aware_elements
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class MobileScreenplayEmpty extends StatelessWidget {
  const MobileScreenplayEmpty({
    super.key,
    required this.icon,
    required this.label,
  });

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RevericIcon(icon, size: 36, color: colors.textSubtle),
          const SizedBox(height: RevericSpacing.md),
          Text(label, style: typo.ui.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}

class MobileScreenplayCard extends StatelessWidget {
  const MobileScreenplayCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Container(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderSubtle),
            borderRadius: BorderRadius.circular(RevericRadius.large),
          ),
          child: child,
        ),
      ),
    );
  }
}
