// 职责: 按作品恢复、修复并串行持久化剧本工作区选择。
// 关联文件:
//   lib/shared/models/screenplay_workspace_state.dart
//   lib/shared/database/daos/app_state_dao.dart
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/json.md

import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../logger/app_logger.dart';
import '../models/screenplay.dart';
import '../models/screenplay_workspace_state.dart';
import 'novel_providers.dart';

part 'screenplay_workspace_state_provider.g.dart';

const String screenplayWorkspaceAppStateKeyPrefix = 'screenplay_workspace:';

String screenplayWorkspaceAppStateKey(String workId) {
  return '$screenplayWorkspaceAppStateKeyPrefix$workId';
}

final _log = AppLogger.forModule('ScreenplayWorkspaceState');

@riverpod
class ScreenplayWorkspaceStateController
    extends _$ScreenplayWorkspaceStateController {
  late Future<void> _restoreFuture;
  Future<void> _writeChain = Future<void>.value();
  ScreenplayWorkspaceState? _pendingState;

  @override
  ScreenplayWorkspaceState build(String workId, String databasePath) {
    _writeChain = Future<void>.value();
    _pendingState = null;
    final lease = ref.keepAlive();
    _restoreFuture = Future<void>(() async {
      try {
        await _restore();
      } finally {
        lease.close();
      }
    });
    return ScreenplayWorkspaceState.initial();
  }

  Future<void> get ready => _restoreFuture;

  Future<void> flush() => _writeChain;

  /// 按稳定场次 ID 重新读取父级，跨集移动后仍打开当前正文。
  Future<void> openSceneScript(String sceneId) async {
    final lease = ref.keepAlive();
    try {
      await ready;
      final database = ref.read(novelContentDatabaseProvider(databasePath));
      final target = await database.transaction(() async {
        final dao = database.screenplayDao;
        final scene = await dao.getScene(sceneId);
        final episode = scene == null
            ? null
            : await dao.getEpisode(scene.episodeId);
        final season = episode == null
            ? null
            : await dao.getSeason(episode.seasonId);
        final root = await dao.getRoot();
        if (scene == null ||
            episode == null ||
            season == null ||
            root == null ||
            scene.screenplayId != root.id ||
            episode.screenplayId != root.id ||
            season.screenplayId != root.id) {
          throw const ScreenplayServiceException(
            'scene_not_found',
            'Scene or its parent is no longer available.',
          );
        }
        return (sceneId: scene.id, episodeId: episode.id, seasonId: season.id);
      });
      update(
        state.copyWith(
          section: ScreenplayWorkspaceSection.script,
          seasonId: target.seasonId,
          episodeId: target.episodeId,
          sceneId: target.sceneId,
        ),
      );
    } finally {
      lease.close();
    }
  }

  /// 从改动记录按集 ID 打开大纲，同时切换所属季并清除上一集的场次选择。
  Future<void> openEpisodeOutline(String episodeId) async {
    final lease = ref.keepAlive();
    try {
      // 等恢复完成再导航，避免启动时的旧快照把显式选择覆盖回去。
      await ready;
      final episode = await ref
          .read(novelContentDatabaseProvider(databasePath))
          .screenplayDao
          .getEpisode(episodeId);
      if (episode == null) {
        throw StateError('Episode $episodeId was not found.');
      }
      update(
        state.copyWith(
          section: ScreenplayWorkspaceSection.outline,
          seasonId: episode.seasonId,
          episodeId: episode.id,
          clearSceneId: true,
        ),
      );
    } finally {
      lease.close();
    }
  }

  void update(ScreenplayWorkspaceState next) {
    if (!state.isHydrated) {
      _pendingState = next;
      state = next;
      return;
    }
    if (state == next) {
      return;
    }
    state = next.copyWith(isHydrated: true);
    _enqueuePersist();
  }

  Future<void> reconcile({int? preferredSeasonIndex}) async {
    final repaired = await _reconcileState(
      state,
      preferredSeasonIndex: preferredSeasonIndex,
    );
    if (!ref.mounted) {
      return;
    }
    if (!_sameSelection(state, repaired) || !state.isHydrated) {
      state = repaired;
      _enqueuePersist();
    }
  }

  Future<void> _restore() async {
    final key = screenplayWorkspaceAppStateKey(workId);
    ScreenplayWorkspaceState restored;
    try {
      final raw = await ref.read(appDatabaseProvider).appStateDao.get(key);
      restored = raw == null || raw.trim().isEmpty
          ? ScreenplayWorkspaceState.initial()
          : ScreenplayWorkspaceState.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
      restored = await _reconcileState(_pendingState ?? restored);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=app_states operation=SELECT id=$key failed',
        error: error,
        stackTrace: stackTrace,
      );
      restored = await _reconcileState(ScreenplayWorkspaceState.initial());
    }
    if (!ref.mounted) {
      return;
    }
    _pendingState = null;
    state = restored;
    _enqueuePersist();
  }

  Future<ScreenplayWorkspaceState> _reconcileState(
    ScreenplayWorkspaceState candidate, {
    int? preferredSeasonIndex,
  }) async {
    final dao = ref
        .read(novelContentDatabaseProvider(databasePath))
        .screenplayDao;
    final root = await dao.getRoot();
    if (root == null) {
      return candidate.copyWith(
        clearSeasonId: true,
        clearEpisodeId: true,
        clearSceneId: true,
        isHydrated: true,
      );
    }
    final seasons = await dao.getSeasons(root.id);
    final episodeIdsBySeason = <String, List<String>>{};
    final sceneIdsByEpisode = <String, List<String>>{};
    for (final season in seasons) {
      final episodes = await dao.getEpisodes(season.id);
      episodeIdsBySeason[season.id] = episodes.map((row) => row.id).toList();
      for (final episode in episodes) {
        sceneIdsByEpisode[episode.id] = (await dao.getSceneRows(
          episode.id,
        )).map((row) => row.id).toList();
      }
    }
    return reconcileScreenplayWorkspaceState(
      state: candidate,
      seasonIds: seasons.map((row) => row.id).toList(),
      episodeIdsBySeason: episodeIdsBySeason,
      sceneIdsByEpisode: sceneIdsByEpisode,
      preferredSeasonIndex: preferredSeasonIndex,
    );
  }

  void _enqueuePersist() {
    final snapshot = state;
    final key = screenplayWorkspaceAppStateKey(workId);
    final lease = ref.keepAlive();
    _writeChain = _writeChain.then((_) async {
      try {
        await ref
            .read(appDatabaseProvider)
            .appStateDao
            .set(key: key, value: jsonEncode(snapshot.toJson()));
      } catch (error, stackTrace) {
        _log.error(
          '[DB] table=app_states operation=UPSERT id=$key failed',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        lease.close();
      }
    });
    unawaited(_writeChain);
  }
}

bool _sameSelection(
  ScreenplayWorkspaceState left,
  ScreenplayWorkspaceState right,
) {
  return left.section == right.section &&
      left.seasonId == right.seasonId &&
      left.episodeId == right.episodeId &&
      left.sceneId == right.sceneId;
}
