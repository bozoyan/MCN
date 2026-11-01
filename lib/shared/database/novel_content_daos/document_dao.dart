// 职责: 文档数据访问对象 — 封装所有文档相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';

part 'document_dao.drift.dart';

@DriftAccessor(tables: [Documents])
class DocumentDao extends DatabaseAccessor<NovelContentDatabase>
    with _$DocumentDaoMixin {
  DocumentDao(super.db);

  Future<List<Document>> getByType(String type) {
    return (select(documents)
          ..where(
            (table) =>
                table.type.equals(type) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Future<Document?> getById(String id) {
    return (select(documents)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Stream<List<Document>> watchByType(String type) {
    return (select(documents)
          ..where(
            (table) =>
                table.type.equals(type) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .watch();
  }

  Future<void> upsert(Document document) async {
    await into(documents).insertOnConflictUpdate(document);
  }

  Future<int> softDelete(String id) {
    return (update(documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> restore(String id) {
    return (update(documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(deletedAt: Value(notDeletedSentinel)),
    );
  }

  Future<int> hardDelete(String id) {
    return (delete(documents)..where((t) => t.id.equals(id))).go();
  }
}
