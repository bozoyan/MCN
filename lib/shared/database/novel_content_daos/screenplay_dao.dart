// 职责: 访问剧本正文和导演台调度，提供聚合投影、正文 reconcile 与原子版本保存。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/screenplay.dart
//   lib/shared/models/screenplay_element.dart
//   lib/shared/services/screenplay_service.dart
// 遵循的 Rules:
//   .agents/rules/db-query-aggregation.md
//   .agents/rules/error-handling.md

import 'package:drift/drift.dart';

import '../../logger/app_logger.dart';
import '../../models/screenplay.dart';
import '../../models/screenplay_element.dart';
import '../../utils/short_entity_id.dart';
import '../../utils/short_entity_id_allocator.dart';
import '../../models/screenplay_document.dart';
import '../novel_content_database.dart';
import '../type_converters.dart';

part 'screenplay_dao.drift.dart';

final _log = AppLogger.forModule('ScreenplayDao');

@DriftAccessor(
  tables: [
    Screenplays,
    ScreenplaySeasons,
    ScreenplayEpisodes,
    ScreenplayScenes,
    VideoStagings,
    Revisions,
    ScreenplayBeats,
    ScreenplaySceneCharacters,
    ScreenplaySceneElements,
  ],
)
class ScreenplayDao extends DatabaseAccessor<NovelContentDatabase>
    with _$ScreenplayDaoMixin {
  ScreenplayDao(super.db);

  Future<VideoStagingRow?> getStaging(String id) {
    return (select(videoStagings)..where(
          (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Future<void> createStaging(String id, String title) async {
    try {
      await into(
        videoStagings,
      ).insert(VideoStagingsCompanion.insert(id: id, title: Value(title)));
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=video_stagings op=INSERT id=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static const _stagingEntityType = 'video_staging';

  /// 只列历史版本身份与时间，不加载每版完整布景；当前版本在调度表里。
  Future<List<({int version, DateTime savedAt})>> getStagingHistory(String id) {
    final query = selectOnly(revisions)
      ..addColumns([revisions.version, revisions.createdAt])
      ..where(
        revisions.entityType.equals(_stagingEntityType) &
            revisions.entityId.equals(id) &
            revisions.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([OrderingTerm.desc(revisions.version)]);
    return query
        .map(
          (row) => (
            version: row.read(revisions.version)!,
            savedAt: row.read(revisions.createdAt)!,
          ),
        )
        .get();
  }

  Future<RevisionRow?> getStagingRevision(String id, int version) {
    return (select(revisions)..where(
          (row) =>
              row.entityType.equals(_stagingEntityType) &
              row.entityId.equals(id) &
              row.version.equals(version) &
              row.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  final _stagingWrites = <String, Future<void>>{};

  /// 所有编辑在同一队列内读取并修改最新文档。
  Future<T> serializeStaging<T>(String id, Future<T> Function() action) {
    final operation = (_stagingWrites[id] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _stagingWrites[id] = settled;
    settled.then((_) {
      if (identical(_stagingWrites[id], settled)) {
        _stagingWrites.remove(id);
      }
    });
    return operation;
  }

  /// 编辑开始时保存一次修改前快照，后续写入只更新当前内容。
  Future<int> saveStaging(
    String id,
    Map<String, dynamic> document, {
    required String title,
    required DateTime savedAt,
    String? checkpointId,
    Map<String, dynamic>? initialDocument,
  }) async {
    try {
      return await transaction(() async {
        final current = await getStaging(id);
        if (current == null) {
          throw const ScreenplayServiceException(
            'staging_not_found',
            'Staging does not exist',
          );
        }
        final snapshot = current.document ?? initialDocument;
        final checkpoint = checkpointId == null
            ? null
            : await (select(
                revisions,
              )..where((t) => t.id.equals(checkpointId))).getSingleOrNull();
        if (checkpointId != null && checkpoint == null && snapshot != null) {
          await into(revisions).insert(
            RevisionsCompanion.insert(
              id: checkpointId,
              entityType: _stagingEntityType,
              entityId: id,
              version: current.version,
              value: snapshot,
              createdAt: Value(current.updatedAt),
              updatedAt: Value(current.updatedAt),
            ),
          );
        }
        final version = current.version + 1;
        await (update(videoStagings)..where((t) => t.id.equals(id))).write(
          VideoStagingsCompanion(
            title: Value(title),
            document: Value(document),
            version: Value(version),
            updatedAt: Value(savedAt),
          ),
        );
        return version;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=revisions,video_stagings op=INSERT,UPDATE '
        'id=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Stream<ScreenplayRow?> watchRoot() {
    return (select(screenplays)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel)))
        .watchSingleOrNull();
  }

  Future<ScreenplayRow?> getRoot() {
    return (select(screenplays)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel)))
        .getSingleOrNull();
  }

  Future<ScreenplaySeasonRow?> getSeason(String id) {
    return (select(screenplaySeasons)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Stream<List<ScreenplaySeasonRow>> watchSeasons(String screenplayId) {
    return _seasonsQuery(screenplayId).watch();
  }

  Future<List<ScreenplaySeasonRow>> getSeasons(String screenplayId) {
    return _seasonsQuery(screenplayId).get();
  }

  SimpleSelectStatement<$ScreenplaySeasonsTable, ScreenplaySeasonRow>
  _seasonsQuery(String screenplayId) {
    return select(screenplaySeasons)
      ..where(
        (table) =>
            table.screenplayId.equals(screenplayId) &
            table.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([(table) => OrderingTerm(expression: table.seasonNumber)]);
  }

  Future<ScreenplayEpisodeRow?> getEpisode(String id) {
    return (select(screenplayEpisodes)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Stream<ScreenplayEpisodeRow?> watchEpisode(String id) {
    return (select(screenplayEpisodes)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .watchSingleOrNull();
  }

  Stream<List<ScreenplayEpisodeRow>> watchEpisodes(String seasonId) {
    return _episodesQuery(seasonId).watch();
  }

  Future<List<ScreenplayEpisodeRow>> getEpisodes(String seasonId) {
    return _episodesQuery(seasonId).get();
  }

  /// 整剧的集，按集号排序；调用方自行按 [ScreenplayEpisodeRow.seasonId] 分组。
  Stream<List<ScreenplayEpisodeRow>> watchEpisodesOfScreenplay(
    String screenplayId,
  ) {
    return (select(screenplayEpisodes)
          ..where(
            (table) =>
                table.screenplayId.equals(screenplayId) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.episodeNumber)]))
        .watch();
  }

  SimpleSelectStatement<$ScreenplayEpisodesTable, ScreenplayEpisodeRow>
  _episodesQuery(String seasonId) {
    return select(screenplayEpisodes)
      ..where(
        (table) =>
            table.seasonId.equals(seasonId) &
            table.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([(table) => OrderingTerm(expression: table.episodeNumber)]);
  }

  Future<ScreenplaySceneRecord?> getScene(String id) async {
    final rows =
        await (_sceneRowsQuery()..where(screenplayScenes.id.equals(id))).get();
    return rows.isEmpty ? null : _sceneRecord(rows.single);
  }

  /// 按场头顺序聚合当前场号，避免为单个标题加载整集场次资料。
  Future<int> getSceneNumber(ScreenplaySceneRecord scene) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS number FROM screenplay_scenes s '
      'JOIN screenplay_scene_elements h ON h.scene_id = s.id '
      "AND h.type = 'scene_heading' AND h.deleted_at = 0 "
      'WHERE s.episode_id = ? AND s.deleted_at = 0 AND h.sort_order <= ?',
      variables: [
        Variable.withString(scene.episodeId),
        Variable.withInt(scene.heading.sortOrder),
      ],
      readsFrom: {screenplayScenes, screenplaySceneElements},
    ).getSingle();
    return row.read<int>('number');
  }

  Future<List<ScreenplaySceneRecord>> getSceneRows(String episodeId) async =>
      (await (_sceneRowsQuery()
                ..where(screenplayScenes.episodeId.equals(episodeId)))
              .get())
          .map(_sceneRecord)
          .toList();

  Stream<List<ScreenplaySceneSummary>> watchScenes(String episodeId) =>
      _sceneSummariesQuery('s.episode_id', episodeId).watch().map(
        (rows) => [
          for (final (index, row) in rows.indexed)
            _sceneSummaryFromCustomRow(row, index + 1),
        ],
      );

  Stream<Map<String, List<ScreenplaySceneSummary>>> watchScenesOfScreenplay(
    String screenplayId,
  ) =>
      _sceneSummariesQuery('s.screenplay_id', screenplayId).watch().map((rows) {
        final result = <String, List<ScreenplaySceneSummary>>{};
        for (final row in rows) {
          final scenes = result.putIfAbsent(
            row.read<String>('episode_id'),
            () => [],
          );
          scenes.add(_sceneSummaryFromCustomRow(row, scenes.length + 1));
        }
        return result;
      });

  Selectable<QueryRow> _sceneSummariesQuery(
    String scope,
    String id,
  ) => customSelect(
    'SELECT s.id AS scene_id, s.episode_id, s.beat_id, s.title, '
    's.emotion, s.synopsis, s.stage, '
    's.page_eighths, s.dialogue_line_count, '
    's.word_count, h.location_id, h.interior_exterior, h.time_label '
    'FROM screenplay_scenes s JOIN screenplay_scene_elements h '
    "ON h.scene_id = s.id AND h.type = 'scene_heading' AND h.deleted_at = 0 "
    'WHERE s.deleted_at = 0 AND $scope = ? ORDER BY h.sort_order',
    variables: [Variable.withString(id)],
    readsFrom: {screenplayScenes, screenplaySceneElements},
  );

  JoinedSelectStatement<HasResultSet, dynamic> _sceneRowsQuery() =>
      select(screenplayScenes).join([
          leftOuterJoin(
            screenplaySceneElements,
            screenplaySceneElements.sceneId.equalsExp(screenplayScenes.id) &
                screenplaySceneElements.type.equals('scene_heading') &
                screenplaySceneElements.deletedAt.equals(notDeletedSentinel),
          ),
        ])
        ..where(screenplayScenes.deletedAt.equals(notDeletedSentinel))
        ..orderBy([
          OrderingTerm(expression: screenplaySceneElements.sortOrder),
        ]);

  ScreenplaySceneRecord _sceneRecord(TypedResult result) {
    final scene = result.readTable(screenplayScenes);
    final heading = result.readTableOrNull(screenplaySceneElements);
    if (heading == null || heading.episodeId != scene.episodeId) {
      throw const ScreenplayServiceException(
        'invalid_screenplay_document',
        'Scene heading is missing or belongs to another episode.',
      );
    }
    return ScreenplaySceneRecord(scene, heading);
  }

  Future<ScreenplayBeatRow?> getBeat(String id) {
    return (select(screenplayBeats)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Future<List<ScreenplayBeatRow>> getBeatRows(String episodeId) {
    return _beatRowsQuery(episodeId).get();
  }

  Stream<List<ScreenplayBeatSummary>> watchBeats(String episodeId) {
    final query = customSelect(
      'SELECT b.id, b.episode_id, b.act_number, b.title, b.description, '
      'COUNT(s.id) AS scene_count, COALESCE(SUM(s.page_eighths), 0) AS page_eighths '
      'FROM screenplay_beats b '
      'LEFT JOIN screenplay_scenes s ON s.beat_id = b.id AND s.deleted_at = 0 '
      'WHERE b.episode_id = ? AND b.deleted_at = 0 '
      'GROUP BY b.id '
      'ORDER BY b.act_number, b.sort_order',
      variables: [Variable.withString(episodeId)],
      readsFrom: {screenplayBeats, screenplayScenes},
    );
    return query.watch().map((rows) {
      final actPositions = <int, int>{};
      return rows
          .map((row) {
            final actNumber = row.read<int>('act_number');
            final beatNumber = (actPositions[actNumber] ?? 0) + 1;
            actPositions[actNumber] = beatNumber;
            return ScreenplayBeatSummary(
              id: row.read<String>('id'),
              episodeId: row.read<String>('episode_id'),
              actNumber: actNumber,
              beatNumber: beatNumber,
              title: row.read<String>('title'),
              description: row.read<String>('description'),
              sceneCount: row.read<int>('scene_count'),
              pageEighths: row.read<int>('page_eighths'),
            );
          })
          .toList(growable: false);
    });
  }

  SimpleSelectStatement<$ScreenplayBeatsTable, ScreenplayBeatRow>
  _beatRowsQuery(String episodeId) {
    return select(screenplayBeats)
      ..where(
        (table) =>
            table.episodeId.equals(episodeId) &
            table.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([
        (table) => OrderingTerm(expression: table.actNumber),
        (table) => OrderingTerm(expression: table.sortOrder),
      ]);
  }

  Future<List<ScreenplaySceneElementRow>> getElementRows(String sceneId) {
    return _elementRowsQuery(sceneId).get();
  }

  Stream<List<ScreenplayElement>> watchElements(String sceneId) {
    return _elementRowsQuery(
      sceneId,
    ).watch().map((rows) => rows.map(_elementFromRow).toList(growable: false));
  }

  SimpleSelectStatement<
    $ScreenplaySceneElementsTable,
    ScreenplaySceneElementRow
  >
  _elementRowsQuery(String sceneId) {
    return select(screenplaySceneElements)
      ..where(
        (table) =>
            table.sceneId.equals(sceneId) &
            table.type.equals('scene_heading').not() &
            table.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]);
  }

  ScreenplayElement _elementFromRow(ScreenplaySceneElementRow row) {
    return ScreenplayElement(
      id: row.id,
      episodeId: row.episodeId,
      sceneId: row.sceneId,
      interiorExterior: row.interiorExterior,
      locationId: row.locationId,
      timeLabel: row.timeLabel,
      type: screenplayElementTypeFromName(row.type),
      text: row.textContent,
      characterId: row.characterId,
      extension: row.extension,
    );
  }

  Future<List<ScreenplayElement>> getDocumentElements(String episodeId) async =>
      (await _documentQuery(episodeId).get()).map(_elementFromRow).toList();

  Stream<List<ScreenplayElement>> watchDocumentElements(String episodeId) =>
      _documentQuery(
        episodeId,
      ).watch().map((rows) => rows.map(_elementFromRow).toList());

  SimpleSelectStatement<
    $ScreenplaySceneElementsTable,
    ScreenplaySceneElementRow
  >
  _documentQuery(String episodeId) => select(screenplaySceneElements)
    ..where(
      (table) =>
          table.episodeId.equals(episodeId) &
          table.deletedAt.equals(notDeletedSentinel),
    )
    ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]);

  Future<List<ScreenplayElement>> reconcileElements({
    required String sceneId,
    required List<ScreenplayElement> elements,
    ShortEntityIdBuilder idBuilder = buildShortEntityId,
  }) async {
    return transaction(() async {
      final scene = await getScene(sceneId);
      if (scene == null) {
        throw const ScreenplayServiceException(
          'scene_not_found',
          'Scene was not found.',
        );
      }
      final rows =
          await (select(screenplaySceneElements)..where(
                (table) =>
                    table.sceneId.equals(sceneId) &
                    table.type.equals('scene_heading').not(),
              ))
              .get();
      final ids = rows.map((row) => row.id).toSet();
      final supplied = <String>{};
      final body = <ScreenplayElement>[];
      final newIds = <String>{};
      final reserved = {
        ...(await (selectOnly(
          screenplaySceneElements,
        )..addColumns([screenplaySceneElements.id])).get()).map(
          (row) => row.read(screenplaySceneElements.id)!,
        ),
        ...elements.map((e) => e.id).whereType<String>(),
      };
      for (final element in elements) {
        element.validateShape();
        if (element.isHeading ||
            (element.sceneId != null && element.sceneId != sceneId) ||
            (element.episodeId != null &&
                element.episodeId != scene.episodeId) ||
            (element.id != null && !ids.contains(element.id))) {
          throw const ScreenplayServiceException(
            'invalid_element_ref',
            'Body element must belong to the scene.',
          );
        }
        if (element.id != null && !supplied.add(element.id!)) {
          throw const ScreenplayServiceException(
            'duplicate_element_id',
            'Element IDs must be unique.',
          );
        }
        final id =
            element.id ??
            allocateScreenplayDraftId(
              ShortEntityIdType.screenplayElement,
              reserved,
              buildId: idBuilder,
            );
        if (element.id == null) {
          newIds.add(id);
        }
        body.add(
          element.normalized().copyWith(
            id: id,
            sceneId: sceneId,
            episodeId: scene.episodeId,
          ),
        );
      }
      final document = await getDocumentElements(scene.episodeId);
      final headingIndex = document.indexWhere(
        (element) => element.id == scene.heading.id,
      );
      final next = [
        ...document.take(headingIndex + 1),
        ...body,
        ...document
            .skip(headingIndex + 1)
            .where((element) => element.sceneId != sceneId),
      ];
      final mapped = await reconcileDocuments(
        {scene.episodeId: next},
        newElementIds: newIds,
        idBuilder: idBuilder,
      );
      return [for (final e in body) e.copyWith(id: mapped[e.id] ?? e.id)];
    });
  }

  /// 调用方先验证编辑范围和新 ID；跨集移动的所有文档须同批提交。
  Future<Map<String, String>> reconcileDocuments(
    Map<String, List<ScreenplayElement>> documents, {
    Set<String> newElementIds = const {},
    ShortEntityIdBuilder idBuilder = buildShortEntityId,
  }) async {
    try {
      return await transaction(() async {
        final rows = await (select(
          screenplaySceneElements,
        )..where((table) => table.episodeId.isIn(documents.keys))).get();
        final existing = {for (final row in rows) row.id: row};
        final targetIds = <String>{};
        final activeScenes =
            await (select(screenplayScenes)..where(
                  (table) =>
                      table.episodeId.isIn(documents.keys) &
                      table.deletedAt.equals(notDeletedSentinel),
                ))
                .get();
        final scenes = {for (final row in activeScenes) row.id: row};
        for (final entry in documents.entries) {
          final headings = <String>{};
          String? currentScene;
          for (final element in entry.value) {
            element.validateShape();
            if (element.id == null || !targetIds.add(element.id!)) {
              throw const ScreenplayServiceException(
                'duplicate_element_id',
                'Document requires unique element IDs.',
              );
            }
            if (element.episodeId != entry.key ||
                scenes[element.sceneId]?.episodeId != entry.key) {
              throw const ScreenplayServiceException(
                'invalid_screenplay_document',
                'Element ownership is inconsistent.',
              );
            }
            if (element.isHeading) {
              if (!headings.add(element.sceneId!)) {
                throw const ScreenplayServiceException(
                  'invalid_screenplay_document',
                  'Scene headings must be unique.',
                );
              }
              currentScene = element.sceneId;
            } else if (currentScene == null ||
                currentScene != element.sceneId) {
              throw const ScreenplayServiceException(
                'invalid_screenplay_document',
                'Scene blocks must be contiguous.',
              );
            }
          }
          if (headings.length !=
              scenes.values
                  .where((scene) => scene.episodeId == entry.key)
                  .length) {
            throw const ScreenplayServiceException(
              'invalid_screenplay_document',
              'Every scene must have one heading.',
            );
          }
        }
        final now = DateTime.now();
        var temporary =
            rows.fold<int>(
              0,
              (minimum, row) =>
                  row.sortOrder < minimum ? row.sortOrder : minimum,
            ) -
            1;
        final mapped = <String, String>{};
        final reserved = {...targetIds};
        for (final entry in documents.entries) {
          for (final raw in entry.value.where(
            (e) => newElementIds.contains(e.id),
          )) {
            final element = raw.normalized();
            var first = true;
            reserved.remove(element.id);
            final id = await insertWithShortEntityId(
              type: ShortEntityIdType.screenplayElement,
              tableName: 'screenplay_scene_elements',
              reservedIds: reserved,
              buildId: (type) {
                if (first) {
                  first = false;
                  return element.id!;
                }
                return idBuilder(type);
              },
              idExists: (id) async =>
                  (await (selectOnly(screenplaySceneElements)
                            ..addColumns([screenplaySceneElements.id])
                            ..where(screenplaySceneElements.id.equals(id))
                            ..limit(1))
                          .get())
                      .isNotEmpty,
              insert: (id) async {
                await into(screenplaySceneElements).insert(
                  ScreenplaySceneElementsCompanion.insert(
                    id: id,
                    episodeId: entry.key,
                    sceneId: element.sceneId!,
                    sortOrder: temporary,
                    type: element.type.name,
                    textContent: Value(element.text),
                    characterId: Value(element.characterId),
                    extension: Value(element.extension),
                    interiorExterior: Value(element.interiorExterior),
                    locationId: Value(element.locationId),
                    timeLabel: Value(element.timeLabel),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                  ),
                );
              },
            );
            temporary--;
            mapped[element.id!] = id;
            existing[id] = await (select(
              screenplaySceneElements,
            )..where((t) => t.id.equals(id))).getSingle();
          }
        }
        documents = {
          for (final entry in documents.entries)
            entry.key: [
              for (final e in entry.value) e.copyWith(id: mapped[e.id] ?? e.id),
            ],
        };
        final targetPositions = <String, (String, int)>{
          for (final entry in documents.entries)
            for (final (index, element) in entry.value.indexed)
              element.id!: (entry.key, index),
        };
        // 仅释放需要移动或删除的位置，普通打字不会改排序。
        for (final row in rows.where(
          (row) => row.deletedAt == notDeletedSentinel,
        )) {
          final position = targetPositions[row.id];
          if (position == null) {
            await (update(
              screenplaySceneElements,
            )..where((table) => table.id.equals(row.id))).write(
              ScreenplaySceneElementsCompanion(
                deletedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
          } else if (position.$1 != row.episodeId ||
              position.$2 != row.sortOrder) {
            await (update(
              screenplaySceneElements,
            )..where((table) => table.id.equals(row.id))).write(
              ScreenplaySceneElementsCompanion(sortOrder: Value(temporary--)),
            );
          }
        }
        for (final entry in documents.entries) {
          for (final (index, raw) in entry.value.indexed) {
            final element = raw.normalized();
            final old = existing[element.id];
            if (old != null &&
                old.deletedAt == notDeletedSentinel &&
                old.sortOrder == index &&
                old.episodeId == element.episodeId &&
                old.sceneId == element.sceneId &&
                old.type == element.type.name &&
                old.textContent == element.text &&
                old.characterId == element.characterId &&
                old.extension == element.extension &&
                old.interiorExterior == element.interiorExterior &&
                old.locationId == element.locationId &&
                old.timeLabel == element.timeLabel) {
              continue;
            }
            final companion = ScreenplaySceneElementsCompanion.insert(
              id: element.id!,
              episodeId: entry.key,
              sceneId: element.sceneId!,
              sortOrder: index,
              type: element.type.name,
              textContent: Value(element.text),
              characterId: Value(element.characterId),
              extension: Value(element.extension),
              interiorExterior: Value(element.interiorExterior),
              locationId: Value(element.locationId),
              timeLabel: Value(element.timeLabel),
              createdAt: Value(old?.createdAt ?? now),
              updatedAt: Value(now),
              deletedAt: Value(notDeletedSentinel),
            );
            if (old == null) {
              throw const ScreenplayServiceException(
                'invalid_element_ref',
                'Retained element was not found.',
              );
            }
            await (update(
              screenplaySceneElements,
            )..where((table) => table.id.equals(element.id!))).write(companion);
          }
        }
        return mapped;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=screenplay_scene_elements operation=RECONCILE_DOCUMENT id=${documents.keys.join(',')}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<ScreenplaySceneCharacterRow>> getSceneCharacters(String sceneId) {
    return (select(screenplaySceneCharacters)
          ..where(
            (table) =>
                table.sceneId.equals(sceneId) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Stream<List<ScreenplayOutlineEntry>> watchOutline(String episodeId) {
    final query = customSelect(
      'SELECT s.id AS scene_id, s.episode_id, s.beat_id, h.location_id, '
      'h.interior_exterior, h.time_label, s.synopsis, s.stage, '
      's.title, s.emotion, '
      's.page_eighths, s.dialogue_line_count, '
      's.word_count, h.sort_order AS scene_order, b.title AS beat_title, '
      'sc.character_id, sc.sort_order AS character_order '
      'FROM screenplay_scenes s '
      "JOIN screenplay_scene_elements h ON h.scene_id = s.id AND h.type = 'scene_heading' AND h.deleted_at = 0 "
      'LEFT JOIN screenplay_beats b '
      'ON b.id = s.beat_id AND b.deleted_at = 0 '
      'LEFT JOIN screenplay_scene_characters sc '
      'ON sc.scene_id = s.id AND sc.deleted_at = 0 '
      'WHERE s.episode_id = ? AND s.deleted_at = 0 '
      'ORDER BY h.sort_order, sc.sort_order',
      variables: [Variable.withString(episodeId)],
      readsFrom: {
        screenplayScenes,
        screenplaySceneElements,
        screenplayBeats,
        screenplaySceneCharacters,
      },
    );
    return query.watch().map((rows) {
      final scenes = <String, ScreenplaySceneSummary>{};
      final beatTitles = <String, String?>{};
      final characterIdsByScene = <String, List<String>>{};
      for (final row in rows) {
        final sceneId = row.read<String>('scene_id');
        scenes.putIfAbsent(
          sceneId,
          () => _sceneSummaryFromCustomRow(row, scenes.length + 1),
        );
        beatTitles.putIfAbsent(
          sceneId,
          () => row.readNullable<String>('beat_title'),
        );
        final characterIds = characterIdsByScene.putIfAbsent(
          sceneId,
          () => <String>[],
        );
        final characterId = row.readNullable<String>('character_id');
        if (characterId != null) {
          characterIds.add(characterId);
        }
      }
      return <ScreenplayOutlineEntry>[
        for (final entry in scenes.entries)
          ScreenplayOutlineEntry(
            scene: entry.value,
            beatTitle: beatTitles[entry.key],
            characterIds: characterIdsByScene[entry.key]!,
          ),
      ];
    });
  }

  /// 仍在出场名单或对白中引用该人物的未删除场次。
  Future<List<ScreenplaySceneReference>> getCharacterSceneReferences(
    String characterId,
  ) => _getSceneReferences(
    "SELECT scene_id, 'cast' AS source "
    'FROM screenplay_scene_characters '
    'WHERE character_id = ? AND deleted_at = 0 '
    'UNION '
    "SELECT scene_id, 'dialogue' AS source "
    'FROM screenplay_scene_elements '
    'WHERE character_id = ? AND deleted_at = 0',
    [Variable.withString(characterId), Variable.withString(characterId)],
    logTarget: 'character=$characterId',
  );

  /// 场次标题仍指向该地点的未删除场次。
  Future<List<ScreenplaySceneReference>> getLocationSceneReferences(
    String locationId,
  ) => _getSceneReferences(
    "SELECT scene_id, 'heading' AS source "
    'FROM screenplay_scene_elements '
    "WHERE type = 'scene_heading' AND location_id = ? AND deleted_at = 0",
    [Variable.withString(locationId)],
    logTarget: 'location=$locationId',
  );

  /// [referencesSql] 产出 `(scene_id, source)`；结果按季、集、场次顺序合并为每场一条。
  ///
  /// 季 / 集缺失时编号为 null，场次仍会列出 —— 删除拦截不能因为上级数据异常而放行。
  Future<List<ScreenplaySceneReference>> _getSceneReferences(
    String referencesSql,
    List<Variable<Object>> variables, {
    required String logTarget,
  }) async {
    try {
      final rows = await customSelect(
        'SELECT r.scene_id, r.source, s.title, '
        'se.season_number, e.episode_number, '
        '(SELECT COUNT(*) FROM screenplay_scenes s2 '
        'JOIN screenplay_scene_elements h2 ON h2.scene_id = s2.id '
        "AND h2.type = 'scene_heading' AND h2.deleted_at = 0 "
        'WHERE s2.episode_id = s.episode_id AND s2.deleted_at = 0 '
        'AND h2.sort_order <= h.sort_order) AS scene_number '
        'FROM ($referencesSql) r '
        'JOIN screenplay_scenes s ON s.id = r.scene_id AND s.deleted_at = 0 '
        'LEFT JOIN screenplay_scene_elements h ON h.scene_id = s.id '
        "AND h.type = 'scene_heading' AND h.deleted_at = 0 "
        'LEFT JOIN screenplay_episodes e ON e.id = s.episode_id '
        'LEFT JOIN screenplay_seasons se ON se.id = e.season_id '
        'ORDER BY se.season_number, e.episode_number, h.sort_order, '
        'r.scene_id, r.source',
        variables: variables,
        readsFrom: {
          screenplaySceneCharacters,
          screenplaySceneElements,
          screenplayScenes,
          screenplayEpisodes,
          screenplaySeasons,
        },
      ).get();
      final scenes = <String, ScreenplaySceneReference>{};
      for (final row in rows) {
        final sceneId = row.read<String>('scene_id');
        scenes[sceneId] = ScreenplaySceneReference(
          sceneId: sceneId,
          seasonNumber: row.readNullable<int>('season_number'),
          episodeNumber: row.readNullable<int>('episode_number'),
          sceneNumber: row.read<int>('scene_number'),
          title: row.read<String>('title'),
          sources: [...?scenes[sceneId]?.sources, row.read<String>('source')],
        );
      }
      return scenes.values.toList();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] SELECT scene references $logTarget failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Stream<List<ScreenplayAppearanceMatrixRow>> watchAppearanceMatrix(
    String episodeId,
  ) {
    final query = customSelect(
      'SELECT s.id AS scene_id, h.sort_order AS scene_order, '
      'sc.character_id, sc.sort_order AS character_order '
      'FROM screenplay_scenes s '
      "JOIN screenplay_scene_elements h ON h.scene_id = s.id AND h.type = 'scene_heading' AND h.deleted_at = 0 "
      'LEFT JOIN screenplay_scene_characters sc '
      'ON sc.scene_id = s.id AND sc.deleted_at = 0 '
      'WHERE s.episode_id = ? AND s.deleted_at = 0 '
      'ORDER BY h.sort_order, sc.sort_order',
      variables: [Variable.withString(episodeId)],
      readsFrom: {
        screenplayScenes,
        screenplaySceneElements,
        screenplaySceneCharacters,
      },
    );
    return query.watch().map((rows) {
      final characterIdsByScene = <String, List<String>>{};
      for (final row in rows) {
        final sceneId = row.read<String>('scene_id');
        final characterIds = characterIdsByScene.putIfAbsent(
          sceneId,
          () => <String>[],
        );
        final characterId = row.readNullable<String>('character_id');
        if (characterId != null) {
          characterIds.add(characterId);
        }
      }
      return <ScreenplayAppearanceMatrixRow>[
        for (final (index, entry) in characterIdsByScene.entries.indexed)
          ScreenplayAppearanceMatrixRow(
            sceneId: entry.key,
            sceneNumber: index + 1,
            characterIds: entry.value,
          ),
      ];
    });
  }

  /// 聚合整部剧集的统计；给了 [seasonId] 就只统计那一季。
  ///
  /// 季级范围靠「集属于这一季」过滤，而不是给 scenes / beats 加冗余的 season_id 列。
  Stream<ScreenplayOverview> watchOverview(
    String screenplayId, {
    String? seasonId,
  }) {
    const seasonFilter =
        ' AND episode_id IN (SELECT id FROM screenplay_episodes '
        'WHERE season_id = ? AND deleted_at = 0)';
    const joinedSeasonFilter =
        ' AND s.episode_id IN (SELECT id FROM screenplay_episodes '
        'WHERE season_id = ? AND deleted_at = 0)';
    final scoped = seasonId != null;
    final scene = scoped ? seasonFilter : '';
    final joined = scoped ? joinedSeasonFilter : '';
    final variables = <Variable<String>>[
      for (var index = 0; index < 7; index += 1) ...[
        Variable.withString(screenplayId),
        if (scoped) Variable.withString(seasonId),
      ],
    ];
    final query = customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM screenplay_scenes '
      ' WHERE screenplay_id = ? AND deleted_at = 0$scene) AS scene_count, '
      '(SELECT COALESCE(SUM(page_eighths), 0) FROM screenplay_scenes '
      ' WHERE screenplay_id = ? AND deleted_at = 0$scene) AS page_eighths, '
      '(SELECT COALESCE(SUM(dialogue_line_count), 0) FROM screenplay_scenes '
      ' WHERE screenplay_id = ? AND deleted_at = 0$scene) AS dialogue_line_count, '
      '(SELECT COALESCE(SUM(word_count), 0) FROM screenplay_scenes '
      ' WHERE screenplay_id = ? AND deleted_at = 0$scene) AS word_count, '
      '(SELECT COUNT(DISTINCT sc.character_id) '
      ' FROM screenplay_scene_characters sc '
      ' JOIN screenplay_scenes s ON s.id = sc.scene_id '
      ' WHERE s.screenplay_id = ? AND s.deleted_at = 0 AND sc.deleted_at = 0$joined) '
      ' AS character_count, '
      '(SELECT COUNT(DISTINCT h.location_id) FROM screenplay_scenes s '
      "JOIN screenplay_scene_elements h ON h.scene_id = s.id AND h.type = 'scene_heading' AND h.deleted_at = 0 "
      ' WHERE s.screenplay_id = ? AND s.deleted_at = 0 AND h.location_id IS NOT NULL$joined) '
      ' AS location_count, '
      '(SELECT COUNT(*) FROM screenplay_beats '
      ' WHERE screenplay_id = ? AND deleted_at = 0$scene) AS beat_count',
      variables: variables,
      readsFrom: {
        screenplayScenes,
        screenplaySceneElements,
        screenplaySceneCharacters,
        screenplayBeats,
        screenplayEpisodes,
      },
    );
    return query.watchSingle().map(
      (row) => ScreenplayOverview(
        sceneCount: row.read<int>('scene_count'),
        pageEighths: row.read<int>('page_eighths'),
        dialogueLineCount: row.read<int>('dialogue_line_count'),
        wordCount: row.read<int>('word_count'),
        characterCount: row.read<int>('character_count'),
        locationCount: row.read<int>('location_count'),
        beatCount: row.read<int>('beat_count'),
      ),
    );
  }

  Stream<List<EpisodeScriptScenePreview>> watchEpisodeScriptPreview(
    String episodeId,
  ) {
    final query = customSelect(
      'SELECT s.id AS scene_id, s.episode_id, s.beat_id, h.location_id, '
      'h.interior_exterior, h.time_label, s.synopsis, s.stage, '
      's.title, s.emotion, '
      's.page_eighths, s.dialogue_line_count, '
      's.word_count, h.sort_order AS scene_order, e.id AS element_id, '
      'e.type AS element_type, e.text AS element_text, e.character_id, '
      'e.extension, e.sort_order AS element_order '
      'FROM screenplay_scenes s '
      "JOIN screenplay_scene_elements h ON h.scene_id = s.id AND h.type = 'scene_heading' AND h.deleted_at = 0 "
      "LEFT JOIN screenplay_scene_elements e ON e.scene_id = s.id AND e.deleted_at = 0 AND e.type != 'scene_heading' "
      'WHERE s.episode_id = ? AND s.deleted_at = 0 '
      'ORDER BY h.sort_order, e.sort_order',
      variables: [Variable.withString(episodeId)],
      readsFrom: {screenplayScenes, screenplaySceneElements},
    );
    return query.watch().map((rows) {
      final scenes = <String, EpisodeScriptScenePreview>{};
      for (final row in rows) {
        final sceneId = row.read<String>('scene_id');
        final preview = scenes.putIfAbsent(sceneId, () {
          return EpisodeScriptScenePreview(
            scene: ScreenplaySceneSummary(
              id: sceneId,
              episodeId: row.read<String>('episode_id'),
              sceneNumber: scenes.length + 1,
              beatId: row.readNullable<String>('beat_id'),
              locationId: row.readNullable<String>('location_id'),
              interiorExterior: row.readNullable<String>('interior_exterior'),
              timeLabel: row.read<String>('time_label'),
              synopsis: row.read<String>('synopsis'),
              title: row.read<String>('title'),
              emotion: row.readNullable<String>('emotion') == null
                  ? const []
                  : const StringListConverter().fromSql(
                      row.read<String>('emotion'),
                    ),
              stage: row.read<String>('stage'),
              pageEighths: row.read<int>('page_eighths'),
              dialogueLineCount: row.read<int>('dialogue_line_count'),
              wordCount: row.read<int>('word_count'),
            ),
            elements: <ScreenplayElement>[],
          );
        });
        final elementId = row.readNullable<String>('element_id');
        if (elementId != null) {
          preview.elements.add(
            ScreenplayElement(
              id: elementId,
              episodeId: row.read<String>('episode_id'),
              sceneId: sceneId,
              type: screenplayElementTypeFromName(
                row.read<String>('element_type'),
              ),
              text: row.read<String>('element_text'),
              characterId: row.readNullable<String>('character_id'),
              extension: row.read<String>('extension'),
            ),
          );
        }
      }
      return scenes.values
          .map(
            (preview) => EpisodeScriptScenePreview(
              scene: preview.scene,
              elements: List<ScreenplayElement>.unmodifiable(preview.elements),
            ),
          )
          .toList(growable: false);
    });
  }

  ScreenplaySceneSummary _sceneSummaryFromCustomRow(QueryRow row, int number) {
    return ScreenplaySceneSummary(
      id: row.read<String>('scene_id'),
      episodeId: row.read<String>('episode_id'),
      sceneNumber: number,
      beatId: row.readNullable<String>('beat_id'),
      locationId: row.readNullable<String>('location_id'),
      interiorExterior: row.readNullable<String>('interior_exterior'),
      timeLabel: row.read<String>('time_label'),
      synopsis: row.read<String>('synopsis'),
      title: row.read<String>('title'),
      emotion: row.readNullable<String>('emotion') == null
          ? const []
          : const StringListConverter().fromSql(row.read<String>('emotion')),
      stage: row.read<String>('stage'),
      pageEighths: row.read<int>('page_eighths'),
      dialogueLineCount: row.read<int>('dialogue_line_count'),
      wordCount: row.read<int>('word_count'),
    );
  }
}
