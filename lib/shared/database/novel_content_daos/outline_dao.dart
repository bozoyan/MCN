// 职责: Timeline 大纲数据访问对象 — 读取、监听、写入结构化大纲记录。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/outline_service.dart
import 'package:drift/drift.dart';

import '../novel_content_database.dart';
import '../../models/outline_draft.dart';
import '../../logger/app_logger.dart';

part 'outline_dao.drift.dart';

final _log = AppLogger.forModule('OutlineDao');

@DriftAccessor(tables: [Outlines, OutlineBeats])
class OutlineDao extends DatabaseAccessor<NovelContentDatabase>
    with _$OutlineDaoMixin {
  OutlineDao(super.db);

  Stream<List<OutlineDraft>> watchAll() {
    return _joinedOutlineBeatQuery().watch().map(_mapJoinedRows);
  }

  Future<List<OutlineDraft>> getAll() async {
    final rows = await _joinedOutlineBeatQuery().get();
    return _mapJoinedRows(rows);
  }

  Future<List<Outline>> getOutlineRows() {
    return (select(outlines)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Stream<OutlineDraft?> watchByDocumentId(String documentId) {
    return (_joinedOutlineBeatQuery(
      documentId: documentId,
    )).watch().map(_mapJoinedRows).map((items) => items.firstOrNull);
  }

  Future<OutlineDraft?> getByDocumentId(String documentId) async {
    final rows = await _joinedOutlineBeatQuery(documentId: documentId).get();
    return _mapJoinedRows(rows).firstOrNull;
  }

  Future<Outline?> getOutlineRowByDocumentId(
    String documentId, {
    bool includeDeleted = false,
  }) {
    final query = select(outlines)
      ..where((table) => table.documentId.equals(documentId));
    if (!includeDeleted) {
      query.where((table) => table.deletedAt.equals(notDeletedSentinel));
    }
    return query.getSingleOrNull();
  }

  Future<Outline?> getOutlineRowByTitle(String title) {
    return (select(outlines)..where(
          (table) =>
              table.title.equals(title) &
              table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Future<int> updateTitle({required String documentId, required String title}) {
    return (update(
      outlines,
    )..where((table) => table.documentId.equals(documentId))).write(
      OutlinesCompanion(title: Value(title), updatedAt: Value(DateTime.now())),
    );
  }

  Future<bool> outlineIdExists(String documentId) async {
    final row =
        await (selectOnly(outlines)
              ..addColumns([outlines.documentId])
              ..where(outlines.documentId.equals(documentId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> insertOutline(Outline outline) {
    return into(outlines).insert(outline);
  }

  Future<void> updateActiveOutline(Outline outline) async {
    final count =
        await (update(outlines)..where(
              (table) =>
                  table.documentId.equals(outline.documentId) &
                  table.deletedAt.equals(notDeletedSentinel),
            ))
            .write(
              OutlinesCompanion(
                title: Value(outline.title),
                content: Value(outline.content),
                status: Value(outline.status),
                startChapterNum: Value(outline.startChapterNum),
                sortOrder: Value(outline.sortOrder),
                updatedAt: Value(outline.updatedAt),
              ),
            );
    if (count != 1) {
      throw ArgumentError('Outline is no longer available.');
    }
  }

  Future<List<OutlineBeat>> getBeatRows(String outlineDocumentId) {
    return (select(outlineBeats)
          ..where((table) => table.outlineDocumentId.equals(outlineDocumentId)))
        .get();
  }

  Future<bool> beatIdExists(String id) async {
    final row =
        await (selectOnly(outlineBeats)
              ..addColumns([outlineBeats.id])
              ..where(outlineBeats.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> insertBeat(OutlineBeat beat) {
    return into(outlineBeats).insert(beat);
  }

  Future<void> updateBeat(
    OutlineBeat beat, {
    bool restoreDeleted = false,
  }) async {
    final count =
        await (update(outlineBeats)..where(
              (table) =>
                  table.id.equals(beat.id) &
                  table.outlineDocumentId.equals(beat.outlineDocumentId) &
                  (restoreDeleted
                      ? const Constant(true)
                      : table.deletedAt.equals(notDeletedSentinel)),
            ))
            .write(
              OutlineBeatsCompanion(
                title: Value(beat.title),
                content: Value(beat.content),
                status: Value(beat.status),
                chapterCount: Value(beat.chapterCount),
                sortOrder: Value(beat.sortOrder),
                updatedAt: Value(beat.updatedAt),
                deletedAt: Value(beat.deletedAt),
              ),
            );
    if (count != 1) {
      throw ArgumentError('Outline beat ${beat.id} is no longer available.');
    }
  }

  Future<void> softDeleteActiveBeatsExcept(
    String outlineDocumentId,
    Set<String> retainedIds,
    DateTime now,
  ) async {
    final query = update(outlineBeats)
      ..where(
        (table) =>
            table.outlineDocumentId.equals(outlineDocumentId) &
            table.deletedAt.equals(notDeletedSentinel),
      );
    if (retainedIds.isNotEmpty) {
      query.where((table) => table.id.isNotIn(retainedIds));
    }
    await query.write(
      OutlineBeatsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Ordinary edits never insert or restore a deleted beat or parent.
  Future<void> updateActiveBeatField({
    required String beatId,
    required String field,
    required String value,
  }) async {
    try {
      await transaction(() async {
        final updateValue = switch (field) {
          'title' => OutlineBeatsCompanion(title: Value(value)),
          'content' => OutlineBeatsCompanion(content: Value(value)),
          'status' when outlineStatuses.contains(value) =>
            OutlineBeatsCompanion(status: Value(value)),
          _ => throw ArgumentError('Unsupported outline beat field or value.'),
        };
        final row =
            await (select(outlineBeats)..where(
                  (table) =>
                      table.id.equals(beatId) &
                      table.deletedAt.equals(notDeletedSentinel),
                ))
                .getSingleOrNull();
        if (row == null ||
            await getOutlineRowByDocumentId(row.outlineDocumentId) == null) {
          throw ArgumentError('Outline beat or parent is no longer available.');
        }
        final count =
            await (update(outlineBeats)..where(
                  (table) =>
                      table.id.equals(beatId) &
                      table.deletedAt.equals(notDeletedSentinel),
                ))
                .write(updateValue.copyWith(updatedAt: Value(DateTime.now())));
        if (count != 1) {
          throw StateError('Outline beat update did not match an active row.');
        }
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=outline_beats op=UPDATE id=$beatId failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<int> softDelete(String documentId) {
    final now = DateTime.now();
    return transaction(() async {
      await (update(
        outlineBeats,
      )..where((table) => table.outlineDocumentId.equals(documentId))).write(
        OutlineBeatsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      return (update(
        outlines,
      )..where((table) => table.documentId.equals(documentId))).write(
        OutlinesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  JoinedSelectStatement<HasResultSet, dynamic> _joinedOutlineBeatQuery({
    String? documentId,
  }) {
    final query =
        select(outlines).join([
            leftOuterJoin(
              outlineBeats,
              outlineBeats.outlineDocumentId.equalsExp(outlines.documentId) &
                  outlineBeats.deletedAt.equals(notDeletedSentinel),
            ),
          ])
          ..where(outlines.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            OrderingTerm(expression: outlines.createdAt),
            OrderingTerm(expression: outlines.documentId),
            OrderingTerm(expression: outlineBeats.sortOrder),
          ]);
    if (documentId != null) {
      query.where(outlines.documentId.equals(documentId));
    }
    return query;
  }

  List<OutlineDraft> _mapJoinedRows(List<TypedResult> rows) {
    final outlineMap = <String, OutlineDraft>{};
    for (final row in rows) {
      final outline = row.readTable(outlines);
      final current = outlineMap.putIfAbsent(
        outline.documentId,
        () => OutlineDraft(
          documentId: outline.documentId,
          title: outline.title,
          content: outline.content,
          status: outline.status,
          startChapterNum: outline.startChapterNum,
          sortOrder: outline.sortOrder,
          createdAt: outline.createdAt,
          updatedAt: outline.updatedAt,
          deletedAt: outline.deletedAt,
        ),
      );
      final beat = row.readTableOrNull(outlineBeats);
      if (beat != null) {
        outlineMap[outline.documentId] = current.copyWith(
          beats: [
            ...current.beats,
            OutlineBeatDraft(
              id: beat.id,
              title: beat.title,
              content: beat.content,
              status: beat.status,
              chapterCount: beat.chapterCount,
              sortOrder: beat.sortOrder,
              createdAt: beat.createdAt,
              updatedAt: beat.updatedAt,
              deletedAt: beat.deletedAt,
            ),
          ],
        );
      }
    }
    return outlineMap.values.toList(growable: false);
  }
}
