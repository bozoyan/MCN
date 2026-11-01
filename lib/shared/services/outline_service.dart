// 职责: Timeline 大纲服务 — 负责结构化大纲的创建、读取、保存与删除。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/outline.dart
//   lib/shared/utils/unique_display_name.dart
//   lib/shared/logger/app_logger.dart
import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../models/outline.dart';
import '../utils/ai_path_name_check.dart';
import '../utils/short_entity_id.dart';
import '../utils/short_entity_id_allocator.dart';
import '../utils/unique_display_name.dart';

final _log = AppLogger.forModule('OutlineService');

class OutlineService {
  OutlineService(
    this._database, {
    ShortEntityIdBuilder idBuilder = buildShortEntityId,
  }) : _buildEntityId = idBuilder;

  final NovelContentDatabase _database;
  final ShortEntityIdBuilder _buildEntityId;

  Stream<List<OutlineDraft>> watchAll() {
    return _database.outlineDao.watchAll();
  }

  Future<List<OutlineDraft>> getAll() {
    return _database.outlineDao.getAll();
  }

  Future<OutlineDraft?> getByDocumentId(String documentId) {
    return _database.outlineDao.getByDocumentId(documentId);
  }

  Future<OutlineDraft?> getByTitle(String title) async {
    final outline = await _database.outlineDao.getOutlineRowByTitle(title);
    if (outline == null) {
      return null;
    }
    return _database.outlineDao.getByDocumentId(outline.documentId);
  }

  Stream<OutlineDraft?> watchByDocumentId(String documentId) {
    return _database.outlineDao.watchByDocumentId(documentId);
  }

  /// 大纲标题是 AI 路径 `/outlines/{title}` 的键；结构字符会让路径截断或错位。
  void _assertTitlePathSafe(String title) {
    if (nameHasAiPathStructuralChars(title)) {
      throw ArgumentError.value(
        title,
        'title',
        'Outline title must not contain "?" or "/" (AI path separators)',
      );
    }
  }

  Future<String> createOutline({
    String? defaultTitle,
    String content = '',
    String status = outlineStatusPending,
    int startChapterNum = 1,
    List<OutlineBeatDraft> beats = const [],
  }) async {
    final now = DateTime.now();
    final existingItems = await _database.outlineDao.getOutlineRows();
    final title = defaultTitle == null
        ? existingItems.isEmpty
              ? '主线'
              : ''
        : buildUniqueDisplayName(
            baseName: defaultTitle,
            existingNames: existingItems.map((item) {
              return item.title;
            }),
          );
    _assertTitlePathSafe(title);
    final nextSortOrder = existingItems.isEmpty
        ? 0
        : existingItems
                  .map((item) => item.sortOrder)
                  .reduce(
                    (value, element) => value > element ? value : element,
                  ) +
              1;
    try {
      return await _database.transaction(() async {
        final documentId = await insertWithShortEntityId(
          type: ShortEntityIdType.outline,
          tableName: 'outlines',
          primaryKeyColumn: 'document_id',
          idExists: _database.outlineDao.outlineIdExists,
          buildId: _buildEntityId,
          insert: (id) => _database.outlineDao.insertOutline(
            Outline(
              documentId: id,
              title: title,
              content: content.trimRight(),
              status: status,
              startChapterNum: startChapterNum < 1 ? 1 : startChapterNum,
              sortOrder: nextSortOrder,
              createdAt: now,
              updatedAt: now,
              deletedAt: notDeletedSentinel,
            ),
          ),
        );
        await _replaceBeats(
          documentId,
          beats.map((beat) => beat.copyWith(isNew: true)).toList(),
          creatingOutline: true,
        );
        return documentId;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=outlines op=INSERT failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<String> resolveUniqueTitle(
    String title, {
    String? excludingDocumentId,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '';
    }
    final existingItems = await _database.outlineDao.getOutlineRows();
    return buildUniqueDisplayName(
      baseName: normalizedTitle,
      existingNames: existingItems
          .where((item) => item.documentId != excludingDocumentId)
          .map((item) => item.title),
    );
  }

  /// 将外部文本作为一个独立的大纲导入，沿用创建大纲时的标题去重与排序规则。
  Future<String> importOutline({
    required String title,
    required String content,
  }) async {
    return createOutline(defaultTitle: title, content: content);
  }

  Future<void> saveOutline(OutlineDraft draft) => _saveOutline(draft);

  /// Only trusted historical snapshots may restore same-outline tombstones.
  Future<void> restoreOutline(OutlineDraft draft) =>
      _saveOutline(draft, restoreDeleted: true);

  Future<void> updateActiveBeatField({
    required String beatId,
    required String field,
    required String value,
  }) => _database.outlineDao.updateActiveBeatField(
    beatId: beatId,
    field: field,
    value: value,
  );

  Future<void> _saveOutline(
    OutlineDraft draft, {
    bool restoreDeleted = false,
  }) async {
    late List<OutlineBeatDraft> persistedBeats;
    try {
      await _database.transaction(() async {
        final now = DateTime.now();
        if (!restoreDeleted) {
          _assertTitlePathSafe(draft.title);
        }
        final existingTimeline = await _database.outlineDao
            .getOutlineRowByDocumentId(draft.documentId);
        if (existingTimeline == null) {
          throw ArgumentError('Outline is no longer available.');
        }
        final documentTitle = restoreDeleted
            ? draft.title
            : await resolveUniqueTitle(
                draft.title,
                excludingDocumentId: draft.documentId,
              );
        await _database.outlineDao.updateActiveOutline(
          Outline(
            documentId: draft.documentId,
            title: documentTitle,
            content: draft.content.trimRight(),
            status: draft.status,
            startChapterNum: !restoreDeleted && draft.startChapterNum < 1
                ? 1
                : draft.startChapterNum,
            sortOrder: existingTimeline.sortOrder,
            createdAt: existingTimeline.createdAt,
            updatedAt: now,
            deletedAt: notDeletedSentinel,
          ),
        );
        persistedBeats = await _replaceBeats(
          draft.documentId,
          draft.beats,
          restoreDeleted: restoreDeleted,
        );
      });
      for (var index = 0; index < draft.beats.length; index++) {
        draft.beats[index].acceptPersistedIdentity(persistedBeats[index].id);
      }
      if (_log.isDebugEnabled) {
        _log.debug('[DB] table=outlines op=UPDATE id=${draft.documentId}');
      }
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=outlines op=UPDATE id=${draft.documentId} failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  OutlineBeatDraft createBeatDraft({
    String title = '',
    String content = '',
    String status = outlineStatusPending,
    int chapterCount = 1,
    int sortOrder = 0,
  }) {
    return OutlineBeatDraft(
      id: _buildEntityId(ShortEntityIdType.outlineBeat),
      isNew: true,
      title: title,
      content: content,
      status: status,
      chapterCount: chapterCount,
      sortOrder: sortOrder,
    );
  }

  Future<List<OutlineBeatDraft>> _replaceBeats(
    String outlineDocumentId,
    List<OutlineBeatDraft> beats, {
    bool restoreDeleted = false,
    bool creatingOutline = false,
  }) async {
    final retainedIdsSeen = <String>{};
    for (final beat in beats) {
      if (beat.id.trim().isEmpty) {
        throw ArgumentError('Beat IDs must be nonempty.');
      }
      if (!creatingOutline && !beat.isNew && !retainedIdsSeen.add(beat.id)) {
        throw ArgumentError('Existing beat IDs must be unique.');
      }
      if (!restoreDeleted &&
          (!outlineStatuses.contains(beat.status) || beat.chapterCount < 1)) {
        throw ArgumentError('Invalid outline beat status or chapter count.');
      }
    }

    final currentRows = creatingOutline
        ? const <OutlineBeat>[]
        : await _database.outlineDao.getBeatRows(outlineDocumentId);
    final currentById = {for (final row in currentRows) row.id: row};
    for (final beat in beats) {
      if (creatingOutline || beat.isNew) {
        continue;
      }
      final current = currentById[beat.id];
      if (current == null) {
        throw ArgumentError('Beat ${beat.id} is not part of this outline.');
      }
      if (!restoreDeleted && current.deletedAt != notDeletedSentinel) {
        throw ArgumentError('Beat ${beat.id} has been deleted.');
      }
    }

    final now = DateTime.now();
    final retainedIds = {
      for (final beat in beats)
        if (!creatingOutline && !beat.isNew) beat.id,
    };
    if (!creatingOutline) {
      await _database.outlineDao.softDeleteActiveBeatsExcept(
        outlineDocumentId,
        retainedIds,
        now,
      );
    }

    final persisted = <OutlineBeatDraft>[];
    final reservedIds = <String>{};
    for (var index = 0; index < beats.length; index++) {
      final beat = beats[index];
      if (creatingOutline || beat.isNew) {
        var useCandidate = beat.id.isNotEmpty;
        final id = await insertWithShortEntityId(
          type: ShortEntityIdType.outlineBeat,
          tableName: 'outline_beats',
          idExists: _database.outlineDao.beatIdExists,
          reservedIds: reservedIds,
          buildId: (type) {
            if (useCandidate) {
              useCandidate = false;
              return beat.id;
            }
            return _buildEntityId(type);
          },
          insert: (id) => _database.outlineDao.insertBeat(
            OutlineBeat(
              id: id,
              outlineDocumentId: outlineDocumentId,
              title: beat.title.trim(),
              content: beat.content.trimRight(),
              status: beat.status,
              chapterCount: beat.chapterCount,
              sortOrder: index,
              createdAt: now,
              updatedAt: now,
              deletedAt: notDeletedSentinel,
            ),
          ),
        );
        persisted.add(
          beat.copyWith(
            id: id,
            isNew: false,
            sortOrder: index,
            createdAt: now,
            updatedAt: now,
            deletedAt: notDeletedSentinel,
          ),
        );
        continue;
      }

      final previous = currentById[beat.id]!;
      final row = OutlineBeat(
        id: beat.id,
        outlineDocumentId: outlineDocumentId,
        title: beat.title.trim(),
        content: beat.content.trimRight(),
        status: beat.status,
        chapterCount: beat.chapterCount,
        sortOrder: index,
        createdAt: previous.createdAt,
        updatedAt: previous.updatedAt,
        deletedAt: notDeletedSentinel,
      );
      // 只改大纲字段时整组 beat 会原样回写；没变的 beat 保留原修改时间。
      await _database.outlineDao.updateBeat(
        row == previous ? row : row.copyWith(updatedAt: now),
        restoreDeleted: restoreDeleted,
      );
      persisted.add(beat.copyWith(isNew: false, sortOrder: index));
    }
    return persisted;
  }

  Future<void> deleteOutline(String documentId) async {
    await _database.outlineDao.softDelete(documentId);
  }
}
