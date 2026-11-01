// 职责: 统一剧本集数的展示与按季统计口径。
// 关联文件:
//   lib/shared/widgets/screenplay/season_manager.dart
//   lib/desktop/features/screenplay/context_panel.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json

import 'package:flutter/material.dart';
import '../../database/novel_content_database.dart' show ScreenplayEpisodeRow;
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

/// 把整剧的集按季数出来。调用方统一 watch 一条
/// `screenplayEpisodesOfScreenplayProvider`，不要按季各开一条 stream ——
/// N 季就是 N 条 query，而这里要的只是一个计数。
Map<String, int> screenplaySeasonEpisodeCounts(
  List<ScreenplayEpisodeRow> episodes,
) {
  final counts = <String, int>{};
  for (final episode in episodes) {
    counts.update(episode.seasonId, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// 集数的三种态共用这一枚：`3 集` / `2/8 集` / `5/4 集` + 已超出规划。
/// 超出规划是有效状态，不是错误 —— 用 warning 底色提示，不拦任何操作。
class ScreenplayEpisodeCount extends StatelessWidget {
  const ScreenplayEpisodeCount({
    super.key,
    required this.episodeCount,
    required this.planned,
    this.showOverPlanned = true,
  });

  final int episodeCount;
  final int? planned;
  final bool showOverPlanned;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final over = planned != null && episodeCount > planned!;
    final text = planned == null
        ? context.t(
            LocaleKeys.screenplayEpisodeCount,
            namedArgs: {'count': '$episodeCount'},
          )
        : context.t(
            LocaleKeys.screenplayEpisodeCount,
            namedArgs: {'count': '$episodeCount/$planned'},
          );
    return Wrap(
      spacing: RevericSpacing.xxs,
      runSpacing: RevericSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          text,
          style: typo.mono.copyWith(
            height: 1.2,
            fontWeight: over ? FontWeight.w500 : FontWeight.w400,
            color: over ? colors.warningText : colors.textSubtle,
          ),
        ),
        if (over && showOverPlanned)
          Container(
            height: RevericSizes.badgeHeightSm,
            padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.warningBg,
              borderRadius: BorderRadius.circular(RevericRadius.small),
            ),
            child: Text(
              context.t(LocaleKeys.screenplayOverPlanned),
              style: typo.uiTiny.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.warningText,
              ),
            ),
          ),
      ],
    );
  }
}
