// 职责: 在移动书架的作品网格里渲染剧本的季 / 集 / 场统计文字。
// 关联文件:
//   lib/mobile/pages/library_page.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/theme/theme.dart';

/// 剧本没有字数，网格卡把小说的「万字」那一行换成季 / 集 / 场。
/// 统计数存在作品自己的 content DB 里，所以要顺着 root → season → episode 取。
class MobileScreenplayMetaLabel extends ConsumerWidget {
  const MobileScreenplayMetaLabel({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final path = novel.contentDatabasePath;
    final root = path == null || path.isEmpty
        ? null
        : ref.watch(screenplayRootProvider(path));
    final screenplay = root?.value;
    var meta = '';
    if (screenplay != null && path != null) {
      final seasons = ref
          .watch(screenplaySeasonsProvider(path, screenplay.id))
          .value;
      final overview = ref
          .watch(screenplayOverviewProvider(path, screenplay.id))
          .value;
      final episodes = [
        for (final season in seasons ?? [])
          ref.watch(screenplayEpisodesProvider(path, season.id)).value,
      ];
      if (seasons != null &&
          overview != null &&
          episodes.every((rows) => rows != null)) {
        meta = [
          if (seasons.length > 1)
            context.t(
              LocaleKeys.screenplaySeasonCount,
              namedArgs: {'count': '${seasons.length}'},
            ),
          context.t(
            LocaleKeys.screenplayEpisodeCount,
            namedArgs: {
              'count':
                  '${episodes.fold<int>(0, (sum, rows) => sum + rows!.length)}',
            },
          ),
          context.t(
            LocaleKeys.screenplaySceneCount,
            namedArgs: {'count': '${overview.sceneCount}'},
          ),
        ].join(' · ');
      }
    }
    if (path == null || path.isEmpty || root?.hasError == true) {
      meta = context.t(LocaleKeys.libraryWorkspaceLoadFailed);
    }
    // 加载中保持空串：网格格子高度是算出来的，这一行必须占位不塌。
    return Text(
      meta,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: typo.uiTiny.copyWith(color: colors.textMuted),
    );
  }
}
