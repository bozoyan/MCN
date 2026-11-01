// 职责: 读取可选择的人物、地点或图鉴主体，并监听单个主体的资料与照片。
// 关联文件:
//   lib/shared/models/subject.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/widgets/subject_picker.dart
//   lib/shared/utils/chapter_entity_recognition.dart
import 'package:drift/drift.dart';

import '../database/novel_content_database.dart';
import '../models/subject.dart';
import '../utils/chapter_entity_recognition.dart';

Future<List<Subject>> loadSubjects(
  NovelContentDatabase db,
  SubjectKind kind,
) async {
  return switch (kind) {
    SubjectKind.character => [
      for (final row in await db.characterProfileDao.getAll())
        Subject(
          id: row.id,
          name: row.name,
          photos: row.photos ?? const [],
          aliases: row.aliases,
          avatarAssetId: row.avatarAssetId,
        ),
    ],
    SubjectKind.location => [
      for (final row in await db.locationDao.getAll())
        Subject(id: row.id, name: row.name, photos: row.photos ?? const []),
    ],
    SubjectKind.compendium => [
      for (final row
          in await (db.select(db.items)
                ..where(
                  (t) =>
                      t.type.isIn(compendiumEntityTypes) &
                      t.deletedAt.equals(notDeletedSentinel),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
              .get())
        Subject(
          id: row.id,
          name: row.title,
          photos: row.photos ?? const [],
          category: row.type,
        ),
    ],
  };
}

/// 监听主体资料；主体不存在或已删除时流报错。
Stream<SubjectProfile> watchSubjectProfile(
  NovelContentDatabase db,
  SubjectKind kind,
  String id,
) {
  List<(SubjectField, String)> nonEmpty(List<(SubjectField, String)> fields) =>
      [
        for (final (field, text) in fields)
          if (text.trim().isNotEmpty) (field, text.trim()),
      ];
  return switch (kind) {
    SubjectKind.character =>
      (db.select(db.characterProfiles)..where(
            (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
          ))
          .watchSingle()
          .map(
            (row) => SubjectProfile(
              entity: characterEntityMention(row),
              fields: nonEmpty([
                (SubjectField.identity, row.identity),
                // 年龄列默认「未知」，等同未填写。
                if (row.age != '未知') (SubjectField.age, row.age),
                (SubjectField.appearance, row.appearance),
                (SubjectField.description, row.description),
                (SubjectField.personality, row.personality),
                (SubjectField.motivation, row.motivation),
                (SubjectField.arc, row.arc),
                (SubjectField.biography, row.biography),
                (SubjectField.currentState, row.currentState),
              ]),
              photos: row.photos ?? const [],
            ),
          ),
    SubjectKind.location =>
      (db.select(db.locations)..where(
            (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
          ))
          .watchSingle()
          .map(
            (row) => SubjectProfile(
              entity: locationEntityMention(row),
              fields: nonEmpty([(SubjectField.description, row.description)]),
              photos: row.photos ?? const [],
            ),
          ),
    SubjectKind.compendium =>
      (db.select(db.items)..where(
            (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
          ))
          .watchSingle()
          .map(
            (row) => SubjectProfile(
              entity: itemEntityMention(row),
              fields: nonEmpty([
                (SubjectField.category, row.category),
                (SubjectField.content, row.content),
              ]),
              photos: row.photos ?? const [],
            ),
          ),
  };
}
