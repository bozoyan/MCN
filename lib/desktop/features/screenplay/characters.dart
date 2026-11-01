// 职责: 剧本角色出场视图 — 角色名单、当前集出场矩阵与角色关系，挂在场次区域第三个视图下。
// 关联文件:
//   lib/desktop/features/screenplay/scenes.dart
//   lib/desktop/features/screenplay/chrome.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/horizontal_wheel_scroll.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/database/novel_content_database.dart'
    show
        RelationSummary,
        ScreenplayEpisodeRow,
        ScreenplaySeasonRow,
        entityTypeCharacter;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/character_profile.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/models/screenplay_workspace_state.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/providers/workspace_navigation_provider.dart';
import '../../../shared/theme/theme.dart';
import 'chips.dart';
import 'chrome.dart';
import 'support.dart';
import '../../../shared/providers/maps_providers.dart';

/// 角色出场视图 —— 场次区域的第三个视图，没有自己的区域标题栏：
/// 标题栏和视图切换器由 [ScreenplayScenesRegion] 统一提供。
class ScreenplayAppearanceView extends ConsumerWidget {
  const ScreenplayAppearanceView({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final stateProvider = screenplayWorkspaceStateControllerProvider(
      novel.id,
      path,
    );
    final workspace = ref.watch(stateProvider);
    final episodeId = workspace.episodeId;
    final profiles =
        ref.watch(characterProfilesProvider(path)).value ??
        const <CharacterProfile>[];
    final matrix = episodeId == null
        ? const <ScreenplayAppearanceMatrixRow>[]
        : ref
                  .watch(screenplayAppearanceMatrixProvider(path, episodeId))
                  .value ??
              const <ScreenplayAppearanceMatrixRow>[];
    final appearingIds = matrix.expand((row) => row.characterIds).toSet();
    // 人物跨季共享 —— 左栏名单不按季裁，只把这一集真的出过场的排在前面。
    final appearing = profiles
        .where((profile) => appearingIds.contains(profile.id))
        .toList();

    if (appearing.isEmpty) {
      return ScreenplayEmptyState(
        title: context.t(LocaleKeys.screenplayNoCharacters),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x5l,
        RevericSpacing.x4l,
        RevericSpacing.x5l,
        64,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: RevericSizes.screenplayCharacterColumnWidth,
            child: _CharacterListCard(
              path: path,
              profiles: appearing,
              matrix: matrix,
            ),
          ),
          const SizedBox(width: RevericSpacing.x4l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AppearanceMatrixCard(
                  novel: novel,
                  profiles: appearing,
                  matrix: matrix,
                  // 选中场次写进剧本工作区状态，再请宿主页把 Main 切到剧本。
                  onOpenScene: (sceneId) {
                    ref
                        .read(stateProvider.notifier)
                        .update(workspace.copyWith(sceneId: sceneId));
                    ref
                        .read(workspaceNavigationProvider.notifier)
                        .request(
                          WorkspaceNavigationRequest(
                            section: NovelWorkspaceSection.screenplay_script,
                            itemId: sceneId,
                          ),
                        );
                  },
                ),
                const SizedBox(height: RevericSpacing.x3l),
                _RelationsCard(path: path, profiles: appearing),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterListCard extends StatelessWidget {
  const _CharacterListCard({
    required this.path,
    required this.profiles,
    required this.matrix,
  });

  final String path;
  final List<CharacterProfile> profiles;
  final List<ScreenplayAppearanceMatrixRow> matrix;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return ScreenplayCard(
      icon: RevericIcons.group,
      title: context.t(LocaleKeys.screenplayCharacterList),
      hint: Text(
        '${profiles.length}',
        style: typo.uiTiny.copyWith(color: colors.textSubtle),
      ),
      child: Column(
        children: [
          for (final profile in profiles)
            _CharacterRow(
              profile: profile,
              sceneCount: matrix
                  .where((row) => row.characterIds.contains(profile.id))
                  .length,
              isLast: profile.id == profiles.last.id,
            ),
        ],
      ),
    );
  }
}

class _CharacterRow extends StatelessWidget {
  const _CharacterRow({
    required this.profile,
    required this.sceneCount,
    required this.isLast,
  });

  final CharacterProfile profile;
  final int sceneCount;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final note = profile.description.trim().isNotEmpty
        ? profile.description.trim()
        : profile.identity.trim();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.selected,
              shape: BoxShape.circle,
            ),
            child: Text(
              profile.name.trim().isEmpty ? '?' : profile.name.characters.first,
              style: typo.uiSemibold.copyWith(color: colors.accent),
            ),
          ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                if (note.isNotEmpty)
                  Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typo.bodySmall.copyWith(
                      fontSize: 12,
                      height: 1.5,
                      color: colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          ScreenplayChip(
            tone: ScreenplayChipTone.plain,
            label: context.t(
              LocaleKeys.screenplaySceneCount,
              namedArgs: {'count': '$sceneCount'},
            ),
          ),
        ],
      ),
    );
  }
}

/// 出场矩阵按当前这一集算 —— 跨集拼在一起场号会从 1 重来，读不出谁在哪一场。
class _AppearanceMatrixCard extends ConsumerWidget {
  const _AppearanceMatrixCard({
    required this.novel,
    required this.profiles,
    required this.matrix,
    required this.onOpenScene,
  });

  final Novel novel;
  final List<CharacterProfile> profiles;
  final List<ScreenplayAppearanceMatrixRow> matrix;
  final ValueChanged<String> onOpenScene;

  static const double _rowHeadWidth = 78;
  static const double _cellWidth = 120;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final workspace = ref.watch(
      screenplayWorkspaceStateControllerProvider(novel.id, path),
    );
    final scenes = workspace.episodeId == null
        ? <ScreenplaySceneSummary>[]
        : ref
                  .watch(screenplayScenesProvider(path, workspace.episodeId!))
                  .value ??
              [];
    final byId = {for (final scene in scenes) scene.id: scene};
    final names = <String, String>{
      for (final location in ref.watch(locationsProvider(path)).value ?? [])
        location.id: location.name,
    };
    return ScreenplayCard(
      icon: RevericIcons.space_dashboard_outlined,
      title: context.t(LocaleKeys.screenplayAppearanceMatrix),
      hint: Text(
        context.t(
          LocaleKeys.screenplayMatrixHint,
          namedArgs: {'scope': _scopeLabel(context, ref, path, workspace)},
        ),
        style: typo.uiTiny.copyWith(height: 1.3, color: colors.textSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _rowHeadWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 26),
                for (final profile in profiles)
                  SizedBox(
                    height: 26,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSmallSemibold.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: HorizontalWheelScroll(
              builder: (context, controller) => SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 26,
                      child: Row(
                        children: [
                          for (final row in matrix)
                            SizedBox(
                              width: _cellWidth,
                              child: Center(
                                child: Text(
                                  '${row.sceneNumber}、${byId[row.sceneId] == null ? '' : screenplaySceneTitle(context, byId[row.sceneId]!, locationNames: names)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: typo.mono.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: colors.textSubtle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final profile in profiles)
                      SizedBox(
                        height: 26,
                        child: Row(
                          children: [
                            for (final row in matrix)
                              SizedBox(
                                width: _cellWidth,
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: _MatrixBox(
                                    present: row.characterIds.contains(
                                      profile.id,
                                    ),
                                    onTap: () => onOpenScene(row.sceneId),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 多季时集号会重复，列头说明要带上季才说得清是哪一集的场号。
  String _scopeLabel(
    BuildContext context,
    WidgetRef ref,
    String path,
    ScreenplayWorkspaceState workspace,
  ) {
    final screenplayId = ref.watch(screenplayRootProvider(path)).value?.id;
    if (screenplayId == null) return '';
    final seasons =
        ref.watch(screenplaySeasonsProvider(path, screenplayId)).value ??
        const <ScreenplaySeasonRow>[];
    final seasonId = workspace.seasonId;
    final episodes = seasonId == null
        ? const <ScreenplayEpisodeRow>[]
        : ref.watch(screenplayEpisodesProvider(path, seasonId)).value ??
              const <ScreenplayEpisodeRow>[];
    final parts = <String>[
      if (seasons.length > 1)
        for (final season in seasons)
          if (season.id == seasonId) screenplaySeasonLabel(context, season),
      for (final episode in episodes)
        if (episode.id == workspace.episodeId)
          screenplayEpisodeNumberLabel(context, episode),
    ];
    return parts.isEmpty ? '' : '${parts.join(' · ')} ';
  }
}

/// 在场 = 淡一档的 accent，两者必须一眼分得开。
class _MatrixBox extends StatelessWidget {
  const _MatrixBox({required this.present, required this.onTap});

  final bool present;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 22,
        decoration: BoxDecoration(
          color: present
              ? Color.alphaBlend(
                  colors.accent.withValues(alpha: 0.34),
                  colors.surface,
                )
              : colors.surfaceDim,
          borderRadius: BorderRadius.circular(RevericRadius.small),
          border: Border.all(
            color: present
                ? Color.alphaBlend(
                    colors.accent.withValues(alpha: 0.46),
                    colors.surface,
                  )
                : colors.borderSubtle,
          ),
        ),
      ),
    );
  }
}

class _RelationsCard extends ConsumerWidget {
  const _RelationsCard({required this.path, required this.profiles});

  final String path;
  final List<CharacterProfile> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final names = {for (final profile in profiles) profile.id: profile.name};
    final relations = <RelationSummary>[];
    final seen = <String>{};
    for (final profile in profiles) {
      final rows =
          ref
              .watch(
                entityRelationsProvider(
                  path: path,
                  entityType: entityTypeCharacter,
                  entityId: profile.id,
                ),
              )
              .value ??
          const <RelationSummary>[];
      for (final relation in rows) {
        if (relation.status == 'active' && seen.add(relation.id)) {
          relations.add(relation);
        }
      }
    }
    return ScreenplayCard(
      icon: RevericIcons.account_tree,
      title: context.t(LocaleKeys.screenplayRelations),
      hint: Text(
        '${relations.length}',
        style: typo.uiTiny.copyWith(color: colors.textSubtle),
      ),
      child: relations.isEmpty
          ? Text(
              context.t(LocaleKeys.commonNone),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            )
          : Column(
              children: [
                for (final relation in relations)
                  _RelationRow(
                    source:
                        names[relation.sourceId] ??
                        context.t(LocaleKeys.screenplayUnknownCharacter),
                    target:
                        names[relation.targetId] ??
                        context.t(LocaleKeys.screenplayUnknownCharacter),
                    type: relation.relationType,
                    note: relation.proof,
                    isLast: relation.id == relations.last.id,
                  ),
              ],
            ),
    );
  }
}

class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.source,
    required this.target,
    required this.type,
    required this.note,
    required this.isLast,
  });

  final String source;
  final String target;
  final String type;
  final String note;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final who = typo.ui.copyWith(
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );
    final arrow = typo.ui.copyWith(color: colors.textSubtle);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.md),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          // 三字名在窄栏里会被折成两行，关系行就读不成一句话了。
          Text(source, softWrap: false, style: who),
          const SizedBox(width: RevericSpacing.sm),
          Text('—', style: arrow),
          const SizedBox(width: RevericSpacing.sm),
          ScreenplayChip(label: type),
          const SizedBox(width: RevericSpacing.sm),
          Text('—', style: arrow),
          const SizedBox(width: RevericSpacing.sm),
          Text(target, softWrap: false, style: who),
          const Spacer(),
          Flexible(
            child: Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
