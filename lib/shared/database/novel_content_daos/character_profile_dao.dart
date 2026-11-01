// 职责: 角色档案数据访问对象 — 封装所有角色档案相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';

part 'character_profile_dao.drift.dart';

@DriftAccessor(tables: [CharacterProfiles])
class CharacterProfileDao extends DatabaseAccessor<NovelContentDatabase>
    with _$CharacterProfileDaoMixin {
  CharacterProfileDao(super.db);

  Future<List<CharacterProfile>> getAll() {
    return (select(characterProfiles)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Future<CharacterProfile?> getById(String id) {
    return (select(characterProfiles)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Stream<List<CharacterProfile>> watchAll() {
    return (select(characterProfiles)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .watch();
  }

  Future<void> upsert(CharacterProfile profile) async {
    await into(characterProfiles).insertOnConflictUpdate(profile);
  }

  Future<int> softDelete(String id) {
    return (update(characterProfiles)..where((t) => t.id.equals(id))).write(
      CharacterProfilesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> restore(String id) {
    return (update(characterProfiles)..where((t) => t.id.equals(id))).write(
      CharacterProfilesCompanion(deletedAt: Value(notDeletedSentinel)),
    );
  }

  Future<int> hardDelete(String id) {
    return (delete(characterProfiles)..where((t) => t.id.equals(id))).go();
  }
}
