// 职责: 保存当前故事状态及历史版本，并提供快照查询。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/ai/tools_create.dart
//   lib/shared/services/ai/tools_read.dart

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../novel_content_database.dart';
import '../../logger/app_logger.dart';

part 'novel_state_snapshot_dao.drift.dart';

final _log = AppLogger.forModule('NovelStateSnapshotDao');

@DriftAccessor(tables: [NovelStateSnapshots])
class NovelStateSnapshotDao extends DatabaseAccessor<NovelContentDatabase>
    with _$NovelStateSnapshotDaoMixin {
  NovelStateSnapshotDao(super.db);

  static const _uuid = Uuid();

  /// 创建新 active snapshot，同事务内把旧 active 标为 superseded。
  Future<NovelStateSnapshot> createSnapshot({
    required String content,
    String createdBy = novelStateSnapshotCreatedByChronicler,
  }) async {
    final id = _uuid.v4();
    try {
      return await transaction(() async {
        await (update(
          novelStateSnapshots,
        )..where((t) => t.status.equals(novelStateSnapshotStatusActive))).write(
          const NovelStateSnapshotsCompanion(
            status: Value(novelStateSnapshotStatusSuperseded),
          ),
        );
        await into(novelStateSnapshots).insert(
          NovelStateSnapshotsCompanion(
            id: Value(id),
            content: Value(content),
            status: const Value(novelStateSnapshotStatusActive),
            createdBy: Value(createdBy),
          ),
        );
        return (select(
          novelStateSnapshots,
        )..where((t) => t.id.equals(id))).getSingle();
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=novel_state_snapshots op=INSERT id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 读取最新 active snapshot。
  Future<NovelStateSnapshot?> getLatestActive() {
    return (select(novelStateSnapshots)
          ..where((t) => t.status.equals(novelStateSnapshotStatusActive))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 按 ID 读取历史 snapshot。
  Future<NovelStateSnapshot?> getById(String id) {
    return (select(
      novelStateSnapshots,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 监听当前故事状态快照。
  Stream<NovelStateSnapshot?> watchLatestActive() {
    return (select(novelStateSnapshots)
          ..where((t) => t.status.equals(novelStateSnapshotStatusActive))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .watchSingleOrNull();
  }

  /// 删除 createdAt 早于 [cutoff] 的 superseded 快照；永不删除当前快照。
  Future<int> deleteSupersededOlderThan(DateTime cutoff) {
    return (delete(novelStateSnapshots)..where(
          (t) =>
              t.status.equals(novelStateSnapshotStatusSuperseded) &
              ColumnFilters<DateTime>(t.createdAt).isBefore(cutoff),
        ))
        .go();
  }
}
