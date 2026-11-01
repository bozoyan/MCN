// 职责: 伏笔位置受控选择器 — 按章节或季、集、场次展示候选，改动经 onChanged 交给页面随其保存流程落库，保留不可用目标信息。
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/widgets/screenplay/labels.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_select.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/chapter.dart';
import '../../database/novel_content_database.dart'
    show ScreenplaySeasonRow, ScreenplayEpisodeRow;
import '../../models/foreshadowing.dart';
import '../../models/screenplay.dart';
import '../../providers/novel_providers.dart';
import '../../providers/screenplay_providers.dart';
import '../../theme/theme.dart';
import '../screenplay/labels.dart';

class ForeshadowingPositionTarget {
  const ForeshadowingPositionTarget({
    required this.id,
    required this.label,
    required this.shortLabel,
    this.seasonId,
    this.scene,
  });
  final String id;

  /// 选择器用的完整定位，剧本含季 / 集 / 场次与梗概。
  final String label;

  /// 列表 chip 用的短标签。
  final String shortLabel;
  final String? seasonId;
  final ScreenplaySceneSummary? scene;
}

/// 解析当前作品可选的伏笔位置：有剧本根按季 / 集 / 场次展开，否则按章节展开。
///
/// `ready` 为 false 表示仍有 provider 在加载，调用方应保留上一次结果而不是清空。
({bool ready, bool isScreenplay, List<ForeshadowingPositionTarget> options})
watchForeshadowingPositionTargets(
  BuildContext context,
  WidgetRef ref,
  String databasePath,
) {
  final root = ref.watch(screenplayRootProvider(databasePath));
  final screenplay = root.value;
  var ready = root.hasValue;
  final options = <ForeshadowingPositionTarget>[];
  if (screenplay != null) {
    final seasons = ref.watch(
      screenplaySeasonsProvider(databasePath, screenplay.id),
    );
    final episodes = ref.watch(
      screenplayEpisodesOfScreenplayProvider(databasePath, screenplay.id),
    );
    final scenes = ref.watch(
      screenplayScenesOfScreenplayProvider(databasePath, screenplay.id),
    );
    ready = ready && seasons.hasValue && episodes.hasValue && scenes.hasValue;
    final episodesBySeason = <String, List<ScreenplayEpisodeRow>>{};
    for (final episode in episodes.value ?? const <ScreenplayEpisodeRow>[]) {
      episodesBySeason.putIfAbsent(episode.seasonId, () => []).add(episode);
    }
    final scenesByEpisode =
        scenes.value ?? const <String, List<ScreenplaySceneSummary>>{};
    for (final season in seasons.value ?? const <ScreenplaySeasonRow>[]) {
      final seasonEpisodes =
          episodesBySeason[season.id] ?? const <ScreenplayEpisodeRow>[];
      for (final episode in seasonEpisodes) {
        final episodeNumber = screenplayEpisodeNumberLabel(context, episode);
        final episodeTitle = episode.title.trim();
        final episodeScenes =
            scenesByEpisode[episode.id] ?? const <ScreenplaySceneSummary>[];
        for (final scene in episodeScenes) {
          final sceneLabel = screenplaySceneLabel(context, scene);
          options.add(
            ForeshadowingPositionTarget(
              id: scene.id,
              seasonId: season.id,
              scene: scene,
              label:
                  '${screenplaySeasonLabel(context, season)} / $episodeNumber${episodeTitle.isEmpty ? "" : " · $episodeTitle"} / $sceneLabel · ${scene.synopsis}',
              shortLabel: '$episodeNumber · $sceneLabel',
            ),
          );
        }
      }
    }
  } else if (root.hasValue) {
    final chapters = ref.watch(chaptersProvider(databasePath));
    ready = ready && chapters.hasValue;
    for (final chapter in chapters.value ?? const <Chapter>[]) {
      if (chapter.type != nodeTypeVolume) {
        options.add(
          ForeshadowingPositionTarget(
            id: chapter.id,
            label: chapter.displayTitle,
            shortLabel: chapter.displayTitle,
          ),
        );
      }
    }
  }
  return (ready: ready, isScreenplay: screenplay != null, options: options);
}

/// 取伏笔某一端当前关联的位置 ID，剧本场次优先。
String? foreshadowingPositionId(Foreshadowing entry, {required bool setup}) =>
    setup
    ? entry.setupSceneId ?? entry.setupChapterId
    : entry.payoffSceneId ?? entry.payoffChapterId;

/// 伏笔两端的位置关联（章节 / 场次二选一），由页面持有并随自身保存流程落库。
typedef ForeshadowingPositionIds = ({
  String? setupChapterId,
  String? payoffChapterId,
  String? setupSceneId,
  String? payoffSceneId,
});

const ForeshadowingPositionIds emptyForeshadowingPositionIds = (
  setupChapterId: null,
  payoffChapterId: null,
  setupSceneId: null,
  payoffSceneId: null,
);

ForeshadowingPositionIds foreshadowingPositionIdsOf(Foreshadowing entry) => (
  setupChapterId: entry.setupChapterId,
  payoffChapterId: entry.payoffChapterId,
  setupSceneId: entry.setupSceneId,
  payoffSceneId: entry.payoffSceneId,
);

/// 按列名展开，供 overlay 暂存（列名与 `updateForeshadowingPositions` 一致）。
Map<String, String?> foreshadowingPositionFields(
  ForeshadowingPositionIds ids,
) => {
  'setup_chapter_id': ids.setupChapterId,
  'payoff_chapter_id': ids.payoffChapterId,
  'setup_scene_id': ids.setupSceneId,
  'payoff_scene_id': ids.payoffSceneId,
};

String? _positionIdOf(ForeshadowingPositionIds ids, {required bool setup}) =>
    setup
    ? ids.setupSceneId ?? ids.setupChapterId
    : ids.payoffSceneId ?? ids.payoffChapterId;

/// 改写某一端：剧本作品写场次、清章节，小说反之。
ForeshadowingPositionIds _withPosition(
  ForeshadowingPositionIds ids, {
  required bool setup,
  required String? id,
  required bool isScreenplay,
}) {
  final chapterId = isScreenplay ? null : id;
  final sceneId = isScreenplay ? id : null;
  return setup
      ? (
          setupChapterId: chapterId,
          payoffChapterId: ids.payoffChapterId,
          setupSceneId: sceneId,
          payoffSceneId: ids.payoffSceneId,
        )
      : (
          setupChapterId: ids.setupChapterId,
          payoffChapterId: chapterId,
          setupSceneId: ids.setupSceneId,
          payoffSceneId: sceneId,
        );
}

class ForeshadowingPositionLinks extends HookConsumerWidget {
  const ForeshadowingPositionLinks({
    super.key,
    required this.databasePath,
    required this.value,
    required this.onChanged,
    this.mobile = false,
    this.onNavigate,
    this.positions = const ['setup', 'payoff'],
    this.rowBuilder,
  });
  final String databasePath;
  final ForeshadowingPositionIds value;
  final ValueChanged<ForeshadowingPositionIds> onChanged;
  final bool mobile;
  final ValueChanged<ForeshadowingPositionTarget>? onNavigate;

  /// 要渲染的端：'setup' / 'payoff'。移动端拆成两次调用，让每端各占一行字段行。
  final List<String> positions;

  /// 自定义「标签 + 值」的行布局；为空时标签在上、值在下。
  final Widget Function(String label, Widget value)? rowBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retainedOptions =
        useRef<({String path, List<ForeshadowingPositionTarget> options})?>(
          null,
        );
    final resolved = watchForeshadowingPositionTargets(
      context,
      ref,
      databasePath,
    );
    final ready = resolved.ready;
    if (ready) {
      retainedOptions.value = (path: databasePath, options: resolved.options);
    }
    final visibleOptions = ready || retainedOptions.value?.path != databasePath
        ? resolved.options
        : retainedOptions.value!.options;
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    // 铺垫与回收共用同一份候选，只构建一次。
    final items = [
      RevericSelectItem(value: '', label: context.t(LocaleKeys.commonNone)),
      for (final option in visibleOptions)
        RevericSelectItem(value: option.id, label: option.label),
    ];

    void change(String position, String? id) => onChanged(
      _withPosition(
        value,
        setup: position == 'setup',
        id: id,
        isScreenplay: resolved.isScreenplay,
      ),
    );

    Future<void> pickOnMobile(String position, String? id) async {
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .75,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: RevericSpacing.x5l),
              children: [
                for (final item in items)
                  ListTile(
                    title: Text(item.label),
                    selected: item.value == (id ?? ''),
                    onTap: () => Navigator.pop(context, item.value),
                  ),
              ],
            ),
          ),
        ),
      );
      if (picked != null && context.mounted) {
        change(position, picked.isEmpty ? null : picked);
      }
    }

    // 跳转图标收紧到 32，不撑高字段行，也不在双列布局里抢宽度；清空走候选里的「无」。
    final iconButtonStyle = IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(32),
      fixedSize: const Size.square(32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: colors.textMuted,
    );
    const double iconSize = 16;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final position in positions)
          Builder(
            builder: (context) {
              final id = _positionIdOf(value, setup: position == 'setup');
              final target = visibleOptions
                  .where((option) => option.id == id)
                  .firstOrNull;
              final label = context.t(
                position == 'setup'
                    ? LocaleKeys.workspaceForeshadowSetupPosition
                    : LocaleKeys.workspaceForeshadowPayoffPosition,
              );
              final selectedLabel =
                  target?.label ??
                  context.t(
                    id == null
                        ? LocaleKeys.commonNone
                        : LocaleKeys.workspaceForeshadowPositionUnavailable,
                  );
              final enabled = ready;
              final field = Row(
                children: [
                  Expanded(
                    child: mobile
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: enabled
                                ? () => pickOnMobile(position, id)
                                : null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    selectedLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: typo.uiSmallSemibold.copyWith(
                                      color: target == null
                                          ? colors.textSubtle
                                          : colors.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: RevericSpacing.xxs),
                                RevericIcon(
                                  RevericIcons.expand_more,
                                  size: 11,
                                  color: colors.textSubtle,
                                ),
                              ],
                            ),
                          )
                        : RevericSelect<String>(
                            value: target?.id ?? (id == null ? '' : null),
                            placeholder: selectedLabel,
                            items: items,
                            enabled: enabled,
                            onChanged: (next) =>
                                change(position, next.isEmpty ? null : next),
                          ),
                  ),
                  if (onNavigate != null)
                    IconButton(
                      tooltip: context.t(
                        LocaleKeys.workspaceForeshadowOpenPosition,
                      ),
                      style: iconButtonStyle,
                      iconSize: iconSize,
                      onPressed: target == null || !ready
                          ? null
                          : () => onNavigate!(target),
                      icon: const RevericIcon(RevericIcons.arrow_forward),
                    ),
                ],
              );
              if (rowBuilder != null) {
                return rowBuilder!(label, field);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: RevericSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: RevericSpacing.xs),
                    field,
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
