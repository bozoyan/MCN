// 职责: 组合继续写作卡、故事简介与按季分组的分集入口。
// 关联文件:
//   lib/mobile/features/screenplay/editor_page.dart
//   lib/mobile/features/screenplay/overview_cards.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/common.json
//   assets/translations/en/common.json
//   lib/shared/models/novel_type.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/database/novel_content_database.dart'
    show ScreenplayEpisodeRow, ScreenplaySeasonRow;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/screenplay_workspace_state.dart';
import '../../../shared/models/novel_type.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import 'episode_card.dart';
import 'overview_cards.dart';
import 'support.dart';

class MobileScreenplayOverview extends ConsumerWidget {
  const MobileScreenplayOverview({
    super.key,
    required this.novel,
    required this.screenplayId,
  });
  final Novel novel;
  final String screenplayId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final source = novel.sourceNovelId == null
        ? null
        : ref.watch(novelProvider(novel.sourceNovelId!)).value;
    final overview = ref.watch(screenplayOverviewProvider(path, screenplayId));
    final seasons =
        ref.watch(screenplaySeasonsProvider(path, screenplayId)).value ??
        const <ScreenplaySeasonRow>[];
    final episodesBySeason = <String, List<ScreenplayEpisodeRow>>{
      for (final season in seasons)
        season.id:
            ref.watch(screenplayEpisodesProvider(path, season.id)).value ??
            const <ScreenplayEpisodeRow>[],
    };
    final provider = screenplayWorkspaceStateControllerProvider(novel.id, path);
    final workspace = ref.watch(provider);
    final service = ref.read(
      screenplayServiceProvider(path, novelId: novel.id),
    );
    final episodes = episodesBySeason.values.expand((rows) => rows).toList();
    final current =
        episodes.where((row) => row.id == workspace.episodeId).firstOrNull ??
        episodes.firstOrNull;
    void open(ScreenplayEpisodeRow episode) {
      ref
          .read(provider.notifier)
          .update(
            ref
                .read(provider)
                .copyWith(
                  section: ScreenplayWorkspaceSection.script,
                  seasonId: episode.seasonId,
                  episodeId: episode.id,
                  clearSceneId: episode.id != workspace.episodeId,
                ),
          );
    }

    Future<void> deleteEpisode(ScreenplayEpisodeRow episode) async {
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.commonDelete),
        message: context.t(LocaleKeys.screenplayConfirmDelete),
        variant: ConfirmDialogVariant.warning,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      await service.deleteEpisode(episode.id);
      if (!context.mounted) {
        return;
      }
      await ref.read(provider.notifier).reconcile();
    }

    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          Center(child: Text(context.t(LocaleKeys.libraryWorkspaceLoadFailed))),
      data: (value) => ListView(
        key: const PageStorageKey('screenplay-overview'),
        padding: const EdgeInsets.all(RevericSpacing.x2l),
        children: [
          if (current != null) ...[
            MobileScreenplayContinueCard(
              novelId: novel.id,
              path: path,
              episode: current,
            ),
            const SizedBox(height: RevericSpacing.md),
          ],
          MobileScreenplayIntroCard(
            novel: novel,
            overview: value,
            chips: [
              _sourceRelationshipLabel(context, novel: novel, source: source),
              if (seasons.length > 1)
                context.t(
                  LocaleKeys.screenplaySeasonCount,
                  namedArgs: {'count': '${seasons.length}'},
                ),
              context.t(
                LocaleKeys.screenplayEpisodeCount,
                namedArgs: {'count': '${episodes.length}'},
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.x2l),
          if (seasons.length <= 1)
            Padding(
              padding: const EdgeInsets.only(bottom: RevericSpacing.md),
              child: Text(
                context.t(LocaleKeys.screenplayEpisodes),
                style: typo.uiSemibold,
              ),
            ),
          for (final season in seasons) ...[
            if (seasons.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: RevericSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        mobileSeasonLabel(context, season),
                        style: typo.uiSemibold,
                      ),
                    ),
                    Text(
                      '${episodesBySeason[season.id]!.length}${season.plannedEpisodeCount == null ? '' : '/${season.plannedEpisodeCount}'}',
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            for (final episode in episodesBySeason[season.id]!)
              Padding(
                padding: const EdgeInsets.only(bottom: RevericSpacing.md),
                child: MobileScreenplayEpisodeCard(
                  path: path,
                  episode: episode,
                  isCurrent: episode.id == current?.id,
                  onTap: () => open(episode),
                  onDelete: episodesBySeason[season.id]!.length > 1
                      ? () => unawaited(deleteEpisode(episode))
                      : null,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _sourceRelationshipLabel(
  BuildContext context, {
  required Novel novel,
  required Novel? source,
}) {
  if (novel.sourceNovelId == null) {
    return switch (novel.type) {
      novelTypeAdaptation => context.t(LocaleKeys.libraryNovelTypeAdaptation),
      novelTypeSequel => context.t(LocaleKeys.libraryNovelTypeSequel),
      novelTypeFanfic => context.t(LocaleKeys.libraryNovelTypeFanfic),
      novelTypeDerivative => context.t(LocaleKeys.libraryNovelTypeDerivative),
      _ => context.t(LocaleKeys.screenplayOriginal),
    };
  }
  if (source == null) {
    return context.t(LocaleKeys.screenplaySourceUnavailable);
  }
  final args = {'title': source.title};
  return switch (novel.type) {
    novelTypeAdaptation => context.t(
      LocaleKeys.screenplayAdaptedFrom,
      namedArgs: args,
    ),
    novelTypeSequel => context.t(
      LocaleKeys.screenplaySequelTo,
      namedArgs: args,
    ),
    novelTypeFanfic => context.t(
      LocaleKeys.screenplayFanficOf,
      namedArgs: args,
    ),
    novelTypeDerivative => context.t(
      LocaleKeys.screenplayDerivedFrom,
      namedArgs: args,
    ),
    _ => context.t(LocaleKeys.screenplaySourceFrom, namedArgs: args),
  };
}
