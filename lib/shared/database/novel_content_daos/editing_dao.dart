// 职责: 创建、读取和按修订原子保存独立剪辑工程，保留软删除工程的素材引用。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/editing/document.dart
//   lib/shared/services/production/editing_orchestrator.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'package:drift/drift.dart';
import '../../logger/app_logger.dart';
import '../../models/editing/document.dart';
import '../novel_content_database.dart';
part 'editing_dao.drift.dart';

final _log = AppLogger.forModule('EditingDao');

class EditingConflict implements Exception {
  const EditingConflict();
}

@DriftAccessor(tables: [VideoEditings])
class EditingDao extends DatabaseAccessor<NovelContentDatabase>
    with _$EditingDaoMixin {
  EditingDao(super.db);

  Future<VideoEditingRow?> get(String id) =>
      (select(videoEditings)..where(
            (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
          ))
          .getSingleOrNull();

  Future<List<VideoEditingRow>> list() =>
      (select(videoEditings)
            ..where((t) => t.deletedAt.equals(notDeletedSentinel))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<void> create(String id, String title, EditingDocument document) async {
    document.validate();
    try {
      await into(videoEditings).insert(
        VideoEditingsCompanion.insert(id: id, title: title, document: document),
      );
    } catch (error, stack) {
      _log.error(
        '[DB] table=video_editings op=INSERT id=$id',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<int> save(
    String id, {
    required int expectedRevision,
    EditingDocument? document,
    String? title,
  }) async {
    document?.validate();
    try {
      final count =
          await (update(videoEditings)..where(
                (t) =>
                    t.id.equals(id) &
                    t.revision.equals(expectedRevision) &
                    t.deletedAt.equals(notDeletedSentinel),
              ))
              .write(
                VideoEditingsCompanion(
                  document: document == null
                      ? const Value.absent()
                      : Value(document),
                  title: title == null ? const Value.absent() : Value(title),
                  revision: Value(expectedRevision + 1),
                  updatedAt: Value(DateTime.now()),
                ),
              );
      if (count != 1) {
        throw const EditingConflict();
      }
      return expectedRevision + 1;
    } catch (error, stack) {
      _log.error(
        '[DB] table=video_editings op=UPDATE id=$id',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> softDelete(String id) async {
    try {
      final now = DateTime.now();
      await (update(videoEditings)..where(
            (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
          ))
          .write(
            VideoEditingsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } catch (error, stack) {
      _log.error(
        '[DB] table=video_editings op=UPDATE id=$id',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
