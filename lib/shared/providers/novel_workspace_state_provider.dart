// 职责: 小说工作区状态控制器 — 按小说从 app_states 恢复并串行持久化单-key 快照。
// 关联文件:
//   lib/shared/database/daos/app_state_dao.dart
//   lib/shared/models/novel_workspace_state.dart
//   lib/shared/providers/novel_providers.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/json.md

import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../logger/app_logger.dart';
import '../models/novel_workspace.dart';
import '../models/novel_workspace_state.dart';
import 'novel_providers.dart';

part 'novel_workspace_state_provider.g.dart';

const String novelWorkspaceAppStateKeyPrefix = 'novel_workspace:';

String novelWorkspaceAppStateKey(String novelId) {
  return '$novelWorkspaceAppStateKeyPrefix$novelId';
}

final _log = AppLogger.forModule('NovelWorkspaceState');

@riverpod
class NovelWorkspaceStateController extends _$NovelWorkspaceStateController {
  late Future<void> _restoreFuture;
  Future<void> _writeChain = Future<void>.value();
  WorkspaceSelection? _pendingStableSelection;
  WorkspaceSelection _lastStableSelection = const WorkspaceSelection.overview();

  @override
  NovelWorkspaceStateData build(String novelId) {
    _writeChain = Future<void>.value();
    _pendingStableSelection = null;
    _lastStableSelection = const WorkspaceSelection.overview();
    final lease = ref.keepAlive();
    _restoreFuture = Future<void>(() async {
      try {
        await _restore();
      } finally {
        lease.close();
      }
    });
    return NovelWorkspaceStateData.initial();
  }

  WorkspaceSelection get value => state.selection;

  set value(WorkspaceSelection next) => updateSelection(next);

  Future<void> get ready => _restoreFuture;

  Future<void> flush() => _writeChain;

  void updateSelection(WorkspaceSelection next) {
    if (state.selection == next && state.isHydrated) {
      return;
    }
    if (state.selection != next) {
      state = state.copyWith(selection: next);
    }
    if (next.isCreating) {
      return;
    }
    if (!state.isHydrated) {
      _pendingStableSelection = next;
      return;
    }
    _lastStableSelection = next;
    _pendingStableSelection = null;
    _enqueuePersist();
  }

  void toggleExpandedNode(NovelWorkspaceSection section, String nodeId) {
    final normalizedId = nodeId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    final nextIds = <String>{...state.expandedNodeIdsFor(section)};
    if (!nextIds.remove(normalizedId)) {
      nextIds.add(normalizedId);
    }
    state = state.copyWithExpandedNodeIds(section, nextIds);
    if (state.isHydrated) {
      _enqueuePersist();
    }
  }

  void ensureExpandedNode(NovelWorkspaceSection section, String nodeId) {
    final normalizedId = nodeId.trim();
    if (normalizedId.isEmpty ||
        state.expandedNodeIdsFor(section).contains(normalizedId)) {
      return;
    }
    state = state.copyWithExpandedNodeIds(section, <String>{
      ...state.expandedNodeIdsFor(section),
      normalizedId,
    });
    if (state.isHydrated) {
      _enqueuePersist();
    }
  }

  Future<void> _restore() async {
    final key = novelWorkspaceAppStateKey(novelId);
    NovelWorkspaceStateData restored;
    try {
      final database = ref.read(appDatabaseProvider);
      final raw = await database.appStateDao.get(key);
      restored = raw == null || raw.trim().isEmpty
          ? NovelWorkspaceStateData(
              selection: const WorkspaceSelection.overview(),
              isHydrated: true,
            )
          : _decode(raw, key);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=app_states operation=SELECT id=$key failed',
        error: error,
        stackTrace: stackTrace,
      );
      restored = NovelWorkspaceStateData(
        selection: const WorkspaceSelection.overview(),
        isHydrated: true,
      );
    }
    if (!ref.mounted) {
      return;
    }
    final pendingSelection = _pendingStableSelection;
    final restoredSelection = pendingSelection ?? restored.selection;
    _lastStableSelection = restoredSelection;
    _pendingStableSelection = null;
    state = restored.copyWith(selection: restoredSelection, isHydrated: true);
    if (pendingSelection != null) {
      _enqueuePersist();
    }
  }

  NovelWorkspaceStateData _decode(String raw, String key) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('workspace state must be an object');
      }
      return NovelWorkspaceStateData.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (error) {
      _log.warning(
        '[DB] table=app_states operation=DECODE id=$key failed; '
        'using defaults error=$error',
      );
      return NovelWorkspaceStateData(
        selection: const WorkspaceSelection.overview(),
        isHydrated: true,
      );
    }
  }

  void _enqueuePersist() {
    final key = novelWorkspaceAppStateKey(novelId);
    final snapshot = state.copyWith(selection: _lastStableSelection);
    final lease = ref.keepAlive();
    _writeChain = _writeChain.then((_) async {
      try {
        final encoded = jsonEncode(snapshot.toJson());
        final database = ref.read(appDatabaseProvider);
        await database.appStateDao.set(key: key, value: encoded);
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
