// 职责: 验证剧本正文 working overlay 的整场快照、会话冲突与人工保存提交语义。
// 关联文件:
//   lib/shared/services/working_overlay.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/models/screenplay_element_render.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/screenplay.dart'
    show ScreenplayServiceException;
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/models/screenplay_element_render.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/screenplay_outline_save.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  late AppDatabase appDatabase;
  late NovelContentDatabase contentDatabase;
  late ScreenplayService screenplayService;
  late WorkingOverlayService overlayService;
  late String sceneId;
  late String elementsPath;
  late String episodeId;
  late String outlinePath;

  setUp(() async {
    appDatabase = AppDatabase.forTest(NativeDatabase.memory());
    contentDatabase = NovelContentDatabase.forTest(NativeDatabase.memory());
    final contentService = NovelContentService(contentDatabase);
    screenplayService = ScreenplayService(contentDatabase);
    overlayService = WorkingOverlayService(
      contentDatabase,
      contentService,
      novelActionsService: NovelActionsService(appDatabase),
    );

    final initial = await screenplayService.createInitialStructure();
    final root = (await contentDatabase.screenplayDao.getRoot())!;
    sceneId = await screenplayService.createScene(
      screenplayId: root.id,
      episodeId: initial.episodeId,
    );
    elementsPath = '/scenes/$sceneId/elements';
    episodeId = initial.episodeId;
    outlinePath = '/episodes/$episodeId/outline';
  });

  tearDown(() async {
    await contentDatabase.close();
    await appDatabase.close();
  });

  Future<String> currentOutline() async {
    return (await contentDatabase.screenplayDao.getEpisode(episodeId))!.outline;
  }

  Future<String> currentElementsJson() async {
    final rows = await contentDatabase.screenplayDao.getElementRows(sceneId);
    return serializeScreenplayElements(
      rows.map(
        (row) => ScreenplayElement(
          id: row.id,
          type: screenplayElementTypeFromName(row.type),
          text: row.textContent,
          characterId: row.characterId,
          extension: row.extension,
        ),
      ),
    );
  }

  for (final committed in [false, true]) {
    test(
      'restores missing character references only during rollback committed=$committed',
      () async {
        final content = NovelContentService(contentDatabase);
        final character = await content.createCharacterProfile(name: '角色');
        await screenplayService.writeElements(
          sceneId: sceneId,
          elements: [
            ScreenplayElement(
              type: ScreenplayElementType.character,
              characterId: character,
            ),
            const ScreenplayElement(
              type: ScreenplayElementType.dialogue,
              text: '原台词',
            ),
          ],
        );
        final oldText = await currentElementsJson();
        final change = await overlayService.stageTextChange(
          resourcePath: elementsPath,
          resourceType: workingChangeResourceTypeScreenplayScenes,
          resourceId: sceneId,
          field: 'elements',
          oldText: oldText,
          newText: '[]',
          source: workingChangeSourceAi,
        );
        if (committed) {
          await overlayService.commitWorkingChanges(
            [change.id],
            source: workingChangeSourceAi,
            message: 'accept',
          );
        }
        await content.deleteCharacterProfile(character, restoreHistory: true);
        await expectLater(
          screenplayService.writeElements(
            sceneId: sceneId,
            elements: [
              ScreenplayElement(
                type: ScreenplayElementType.character,
                characterId: character,
              ),
            ],
          ),
          throwsA(isA<ScreenplayServiceException>()),
        );
        expect(
          await overlayService.rollbackChange(change.id),
          RollbackChangeResult.rolledBack,
        );
        final restored = await contentDatabase.screenplayDao.getElementRows(
          sceneId,
        );
        expect(restored.first.characterId, character);
        expect(restored.last.textContent, '原台词');
        expect(
          (await contentDatabase.screenplayDao.getScene(
            sceneId,
          ))!.dialogueLineCount,
          1,
        );
      },
    );
  }

  test(
    'created location rollback bypasses scene references but ordinary delete does not',
    () async {
      final content = NovelContentService(contentDatabase);
      final location = await content.locationsService.createLocation(
        name: '地点',
      );
      final change = await overlayService.stageCreateChange(
        resourcePath: '/locations/$location',
        resourceType: 'locations',
        resourceId: location,
        previewText: '地点',
        source: workingChangeSourceAi,
      );
      await screenplayService.updateScene(
        sceneId: sceneId,
        locationId: Value(location),
      );
      await expectLater(
        content.locationsService.deleteLocation(location),
        throwsA(isA<ScreenplayServiceException>()),
      );
      expect(
        await overlayService.rollbackChange(change.id),
        RollbackChangeResult.rolledBack,
      );
      expect(await content.locationsService.getLocationById(location), isNull);
      expect(
        (await contentDatabase.screenplayDao.getScene(sceneId))!.locationId,
        location,
      );
    },
  );

  test(
    'scene property rollback ignores an unrelated missing location',
    () async {
      final content = NovelContentService(contentDatabase);
      final location = await content.locationsService.createLocation(
        name: '地点',
      );
      await screenplayService.updateScene(
        sceneId: sceneId,
        locationId: Value(location),
      );
      final change = await overlayService.stageTextChange(
        resourcePath: '/scenes/$sceneId/synopsis',
        resourceType: workingChangeResourceTypeScreenplayScenes,
        resourceId: sceneId,
        field: 'synopsis',
        oldText: '',
        newText: 'AI',
        source: workingChangeSourceAi,
      );
      await content.locationsService.deleteLocation(
        location,
        restoreHistory: true,
      );
      await screenplayService.updateScene(sceneId: sceneId, synopsis: 'normal');
      expect(
        await overlayService.rollbackChange(change.id),
        RollbackChangeResult.rolledBack,
      );
      expect(
        (await contentDatabase.screenplayDao.getScene(sceneId))!.synopsis,
        '',
      );
    },
  );

  test(
    'rolls back character creation while a scene still references it',
    () async {
      final contentService = NovelContentService(contentDatabase);
      final characterId = await contentService.createCharacterProfile(
        name: '角色',
      );
      final change = await overlayService.stageCreateChange(
        resourcePath: '/characters/$characterId',
        resourceType: 'characters',
        resourceId: characterId,
        previewText: '角色',
        source: workingChangeSourceAi,
      );
      await screenplayService.writeElements(
        sceneId: sceneId,
        elements: [
          ScreenplayElement(
            type: ScreenplayElementType.character,
            characterId: characterId,
          ),
        ],
      );
      final reviews = await overlayService.resolveFieldReviews([change]);

      expect((await overlayService.rollbackFields(reviews)).rolledBack, 1);
      expect(await contentService.getCharacterProfileById(characterId), isNull);
      expect(
        (await contentDatabase.workingChangeDao.getById(change.id))!.status,
        workingChangeStatusRejected,
      );
      expect(
        (await contentDatabase.screenplayDao.getElementRows(
          sceneId,
        )).single.characterId,
        characterId,
      );
    },
  );

  test('structured field rollback restores the whole snapshot', () async {
    final change = await overlayService.stageTextChange(
      resourcePath: elementsPath,
      resourceType: workingChangeResourceTypeScreenplayScenes,
      resourceId: sceneId,
      field: 'elements',
      oldText: '[]',
      newText: serializeScreenplayElements(const [
        ScreenplayElement(type: ScreenplayElementType.action, text: 'body'),
      ]),
      source: workingChangeSourceAi,
      sourceSessionId: 'session',
    );
    final review = (await overlayService.resolveFieldReviews([change])).single;
    expect(
      await overlayService.rollbackFieldLines(review, {'d:1', 'i:1'}),
      RollbackChangeResult.rolledBack,
    );
    expect(await currentElementsJson(), '[]');
    expect(
      (await contentDatabase.workingChangeDao.getById(change.id))!.status,
      workingChangeStatusRejected,
    );
  });

  test(
    'new body snapshot records final short IDs and rollback keeps that history',
    () async {
      final change = await overlayService.stageTextChange(
        resourcePath: elementsPath,
        resourceType: workingChangeResourceTypeScreenplayScenes,
        resourceId: sceneId,
        field: 'elements',
        oldText: '[]',
        newText: serializeScreenplayElements(const [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: 'new body',
          ),
        ]),
        source: workingChangeSourceAi,
        sourceSessionId: 'session',
      );
      final entries = jsonDecode(change.newText!) as List;
      expect(entries.single['id'], matches(RegExp(r'^elm_[A-Z0-9]{6}$')));
      expect(change.newText, await currentElementsJson());
      await overlayService.rollbackChange(change.id);
      expect(await currentElementsJson(), '[]');
      final history = await contentDatabase.workingChangeDao.getById(change.id);
      expect(history!.newText, change.newText);
      final restored = await screenplayService.writeElements(
        sceneId: sceneId,
        elements: [
          ScreenplayElement(
            id: entries.single['id'] as String,
            type: ScreenplayElementType.action,
            text: 'new body',
          ),
        ],
      );
      expect(restored.elements.single.id, entries.single['id']);
    },
  );

  for (final target in ['outline', 'elements', 'emotion', 'events']) {
    for (final mode in [
      'single',
      'turn',
      'commit',
      if (target == 'outline') 'lines',
    ]) {
      test(
        'review P2 $target $mode supersedes only selected active field and preserves normal guards',
        () async {
          final resourceType = target == 'outline'
              ? workingChangeResourceTypeScreenplayEpisodes
              : workingChangeResourceTypeScreenplayScenes;
          final resourceId = target == 'outline' ? episodeId : sceneId;
          final path = target == 'outline'
              ? outlinePath
              : '/scenes/$sceneId/$target';
          String? elementId;
          String text(String version) => switch (target) {
            'outline' => switch (version) {
              'old' => 'a\nb\nc',
              'AI' => 'a\nB\nc\nd',
              _ => version,
            },
            'elements' => serializeScreenplayElements([
              ScreenplayElement(
                id: elementId,
                type: ScreenplayElementType.action,
                text: version,
              ),
            ]),
            'emotion' => jsonEncode([version]),
            _ => jsonEncode([
              {'title': version, 'summary': version},
            ]),
          };
          Future<String> read() async => switch (target) {
            'outline' => await currentOutline(),
            'elements' => await currentElementsJson(),
            'emotion' => jsonEncode(
              (await contentDatabase.screenplayDao.getScene(sceneId))!.emotion,
            ),
            _ => jsonEncode(
              (await contentDatabase.screenplayDao.getScene(sceneId))!.events,
            ),
          };
          if (target == 'outline') {
            await screenplayService.updateEpisodeOutline(
              episodeId: episodeId,
              outline: text('old'),
            );
          } else if (target == 'elements') {
            await screenplayService.writeElements(
              sceneId: sceneId,
              elements: const [
                ScreenplayElement(
                  type: ScreenplayElementType.action,
                  text: 'old',
                ),
              ],
            );
            elementId = (await contentDatabase.screenplayDao.getElementRows(
              sceneId,
            )).single.id;
          } else if (target == 'emotion') {
            await screenplayService.updateScene(
              sceneId: sceneId,
              emotion: const Value(['old']),
            );
          } else {
            await screenplayService.updateScene(
              sceneId: sceneId,
              events: const Value([
                {'title': 'old', 'summary': 'old'},
              ]),
            );
          }
          final selected = await overlayService.stageTextChange(
            resourcePath: path,
            resourceType: resourceType,
            resourceId: resourceId,
            field: target,
            oldText: text('old'),
            newText: text('AI'),
            source: workingChangeSourceAi,
            sourceSessionId: 'session_a',
            sourceTurnId: 'turn_a',
            expectedCurrentText: await read(),
          );
          final commit = await overlayService.commitWorkingChanges(
            [selected.id],
            source: workingChangeSourceAi,
            message: 'selected',
          );
          final later = await overlayService.stageTextChange(
            resourcePath: path,
            resourceType: resourceType,
            resourceId: resourceId,
            field: target,
            oldText: await read(),
            newText: text('later'),
            source: workingChangeSourceAi,
            sourceSessionId: 'session_b',
            sourceTurnId: 'turn_b',
            expectedCurrentText: await read(),
          );
          final outside = await overlayService.stageTextChange(
            resourcePath: '/scenes/$sceneId/synopsis',
            resourceType: workingChangeResourceTypeScreenplayScenes,
            resourceId: sceneId,
            field: 'synopsis',
            oldText: '',
            newText: 'outside pending',
            source: workingChangeSourceAi,
            sourceSessionId: 'outside_session',
          );
          final outsideBefore = (await contentDatabase.workingChangeDao.getById(
            outside.id,
          ))!.toJson();
          final historyBeforeGuard = (await overlayService.getWorkingChanges())
              .map((r) => r.toJson())
              .toList();
          for (final sameSession in [false, true]) {
            await expectLater(
              overlayService.stageTextChange(
                resourcePath: path,
                resourceType: resourceType,
                resourceId: resourceId,
                field: target,
                oldText: text('later'),
                newText: text('forbidden'),
                source: workingChangeSourceAi,
                sourceSessionId: sameSession ? 'session_b' : 'session_c',
                expectedCurrentText: sameSession
                    ? 'stale expected text'
                    : await read(),
              ),
              throwsA(isA<WorkingOverlayConflictException>()),
            );
          }
          expect(
            (await overlayService.getWorkingChanges())
                .map((r) => r.toJson())
                .toList(),
            historyBeforeGuard,
          );
          Future<void> rollback() async {
            switch (mode) {
              case 'single':
                await overlayService.rollbackChange(selected.id);
              case 'turn':
                await overlayService.rollbackTurn(turnId: 'turn_a');
              case 'lines':
                await overlayService.rollbackChangeLines(selected.id, {'i:4'});
              default:
                await overlayService.rollbackCommit(commitId: commit!);
            }
          }

          await rollback();
          expect(await read(), mode == 'lines' ? 'a\nB\nc' : text('old'));
          expect(
            (await contentDatabase.workingChangeDao.getById(later.id))!.status,
            workingChangeStatusRejected,
          );
          expect(
            (await contentDatabase.workingChangeDao.getById(
              outside.id,
            ))!.toJson(),
            outsideBefore,
          );
          expect(
            (await contentDatabase.screenplayDao.getScene(sceneId))!.synopsis,
            'outside pending',
          );
          final items = await contentDatabase
              .select(contentDatabase.changeCommitItems)
              .get();
          expect(
            items.where(
              (r) =>
                  r.workingChangeId == outside.id ||
                  r.workingChangeId == later.id,
            ),
            isEmpty,
          );
          final rows = (await overlayService.getWorkingChanges())
              .map((r) => r.toJson())
              .toList();
          final commits = (await overlayService.getChangeCommits())
              .map((r) => r.toJson())
              .toList();
          await rollback();
          expect(
            (await overlayService.getWorkingChanges())
                .map((r) => r.toJson())
                .toList(),
            rows,
          );
          expect(
            (await overlayService.getChangeCommits())
                .map((r) => r.toJson())
                .toList(),
            commits,
          );
        },
      );
    }
  }

  test(
    'review P2 failed historical restore rolls back selected active supersession',
    () async {
      await screenplayService.writeElements(
        sceneId: sceneId,
        elements: const [
          ScreenplayElement(type: ScreenplayElementType.action, text: 'before'),
        ],
      );
      final original = await currentElementsJson();
      final selected = await overlayService.stageTextChange(
        resourcePath: elementsPath,
        resourceType: workingChangeResourceTypeScreenplayScenes,
        resourceId: sceneId,
        field: 'elements',
        oldText: original,
        newText: original.replaceAll('before', 'AI'),
        source: workingChangeSourceAi,
        sourceSessionId: 'session_a',
      );
      await overlayService.commitWorkingChanges(
        [selected.id],
        source: workingChangeSourceAi,
        message: 'selected',
      );
      await overlayService.stageTextChange(
        resourcePath: elementsPath,
        resourceType: workingChangeResourceTypeScreenplayScenes,
        resourceId: sceneId,
        field: 'elements',
        oldText: await currentElementsJson(),
        newText: original.replaceAll('before', 'later'),
        source: workingChangeSourceAi,
        sourceSessionId: 'session_b',
      );
      await (contentDatabase.update(
        contentDatabase.changeCommitItems,
      )..where((row) => row.workingChangeId.equals(selected.id))).write(
        ChangeCommitItemsCompanion(
          oldText: Value(
            serializeScreenplayElements(const [
              ScreenplayElement(
                id: 'foreign_element',
                type: ScreenplayElementType.action,
                text: 'invalid historical identity',
              ),
            ]),
          ),
        ),
      );
      Future<List<Object>> snapshot() async => [
        await currentElementsJson(),
        (await contentDatabase.select(contentDatabase.workingChanges).get())
            .map((row) => row.toJson())
            .toList(),
        (await contentDatabase.select(contentDatabase.changeCommits).get())
            .map((row) => row.toJson())
            .toList(),
        (await contentDatabase.select(contentDatabase.changeCommitItems).get())
            .map((row) => row.toJson())
            .toList(),
      ];
      final before = await snapshot();
      await expectLater(
        overlayService.rollbackChange(selected.id),
        throwsA(isA<ScreenplayServiceException>()),
      );
      expect(await snapshot(), before);
    },
  );

  test('canonical paths share changes, locks, history and rollback', () async {
    final localPath = outlinePath.substring(1);
    final first = await overlayService.stageTextChange(
      resourcePath: localPath,
      resourceType: 'screenplay_episodes',
      resourceId: episodeId,
      field: 'outline',
      oldText: '',
      newText: 'first',
      source: workingChangeSourceAi,
      sourceSessionId: 'old_session',
    );
    final second = await overlayService.stageTextChange(
      resourcePath: localPath,
      resourceType: 'screenplay_episodes',
      resourceId: episodeId,
      field: 'outline',
      oldText: 'first',
      newText: 'second',
      source: workingChangeSourceAi,
      sourceSessionId: 'old_session',
    );
    expect(second.id, first.id);
    expect(second.oldText, '');
    await expectLater(
      overlayService.stageTextChange(
        resourcePath: localPath,
        resourceType: 'screenplay_episodes',
        resourceId: episodeId,
        field: 'outline',
        oldText: 'second',
        newText: 'conflict',
        source: workingChangeSourceAi,
        sourceSessionId: 'new_session',
      ),
      throwsA(isA<WorkingOverlayConflictException>()),
    );
    expect(await currentOutline(), 'second');
    expect(
      await contentDatabase.workingChangeDao.getByResource(localPath),
      hasLength(1),
    );
    await commitEpisodeOutlineManualSave(
      overlayService,
      contentDatabase,
      episodeId: episodeId,
      newOutline: 'manual',
    );
    final oldLookup = await contentDatabase.changeCommitDao.getItemsByResource(
      outlinePath,
    );
    final newLookup = await contentDatabase.changeCommitDao.getItemsByResource(
      localPath,
    );
    expect(newLookup.map((e) => e.id), oldLookup.map((e) => e.id));
    expect(newLookup, hasLength(2));
    expect(await currentOutline(), 'manual');
    final manualItem = newLookup.singleWhere(
      (item) => item.newText == 'manual',
    );
    await overlayService.rollbackChange(manualItem.workingChangeId);
    expect(await currentOutline(), 'second');
    await overlayService.rollbackChange(first.id);
    expect(await currentOutline(), '');
  });

  test('stages a canonical scene snapshot and reject restores it', () async {
    await screenplayService.writeElements(
      sceneId: sceneId,
      elements: const [
        ScreenplayElement(type: ScreenplayElementType.action, text: '夜雨落在窗上。'),
      ],
    );
    final original = await currentElementsJson();
    final replacement = serializeScreenplayElements(const [
      ScreenplayElement(type: ScreenplayElementType.action, text: '林默推门而入。'),
      ScreenplayElement(type: ScreenplayElementType.transition, text: '切至：'),
    ]);

    final change = await overlayService.stageTextChange(
      resourcePath: elementsPath,
      resourceType: 'screenplay_scenes',
      resourceId: sceneId,
      field: 'elements',
      oldText: original,
      newText: replacement,
      source: workingChangeSourceAi,
      sourceSessionId: 'session_1',
      expectedCurrentText: original,
    );

    expect(await currentElementsJson(), isNot(original));
    expect(change.oldText, original);
    expect(change.newText, await currentElementsJson());
    expect((jsonDecode(change.newText!) as List).map((e) => e['text']), [
      '林默推门而入。',
      '切至：',
    ]);
    expect(change.newText, isNot(contains('sort_order')));
    expect(change.newText, isNot(contains('updated_at')));
    expect(change.newText, isNot(contains('name')));

    await overlayService.rejectWorkingChange(change.id);

    expect(await currentElementsJson(), original);
    expect(
      (await contentDatabase.workingChangeDao.getById(change.id))?.status,
      workingChangeStatusRejected,
    );
  });

  test(
    'same session merges while another session cannot stack a snapshot',
    () async {
      final original = await currentElementsJson();
      final firstValue = serializeScreenplayElements(const [
        ScreenplayElement(type: ScreenplayElementType.action, text: '第一版'),
      ]);
      final first = await overlayService.stageTextChange(
        resourcePath: elementsPath,
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        field: 'elements',
        oldText: original,
        newText: firstValue,
        source: workingChangeSourceAi,
        sourceSessionId: 'session_1',
        expectedCurrentText: original,
      );
      final currentAfterFirst = await currentElementsJson();
      final secondValue = serializeScreenplayElements(const [
        ScreenplayElement(type: ScreenplayElementType.action, text: '第二版'),
      ]);

      final merged = await overlayService.stageTextChange(
        resourcePath: elementsPath,
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        field: 'elements',
        oldText: currentAfterFirst,
        newText: secondValue,
        source: workingChangeSourceAi,
        sourceSessionId: 'session_1',
        expectedCurrentText: currentAfterFirst,
      );

      expect(merged.id, first.id);
      expect(merged.oldText, original);
      expect(
        (await contentDatabase.workingChangeDao.getByResource(
          elementsPath,
        )).where((change) => change.status == workingChangeStatusActive),
        hasLength(1),
      );

      await expectLater(
        overlayService.stageTextChange(
          resourcePath: elementsPath,
          resourceType: 'screenplay_scenes',
          resourceId: sceneId,
          field: 'elements',
          oldText: await currentElementsJson(),
          newText: firstValue,
          source: workingChangeSourceAi,
          sourceSessionId: 'session_2',
          expectedCurrentText: await currentElementsJson(),
        ),
        throwsA(isA<WorkingOverlayConflictException>()),
      );
      expect(await currentElementsJson(), isNot(original));
    },
  );

  test('stages an episode outline and reject restores it', () async {
    await screenplayService.updateEpisodeOutline(
      episodeId: episodeId,
      outline: '原大纲',
    );
    final change = await overlayService.stageTextChange(
      resourcePath: outlinePath,
      resourceType: workingChangeResourceTypeScreenplayEpisodes,
      resourceId: episodeId,
      field: 'outline',
      oldText: '原大纲',
      newText: 'AI 大纲',
      source: workingChangeSourceAi,
      sourceSessionId: 'session_1',
      expectedCurrentText: '原大纲',
    );

    // apply-on-stage：真表当场就改了。
    expect(await currentOutline(), 'AI 大纲');

    await overlayService.rejectWorkingChange(change.id);

    expect(await currentOutline(), '原大纲');
    expect(
      (await contentDatabase.workingChangeDao.getById(change.id))?.status,
      workingChangeStatusRejected,
    );
  });

  test(
    'episode outline mismatch raises a conflict rather than an ArgumentError',
    () async {
      await screenplayService.updateEpisodeOutline(
        episodeId: episodeId,
        outline: '真实大纲',
      );
      // _verifyExpectedCurrentText 的分支若插在 throw 之后就是死代码，
      // 这里会变成 ArgumentError 而不是冲突。
      await expectLater(
        overlayService.stageTextChange(
          resourcePath: outlinePath,
          resourceType: workingChangeResourceTypeScreenplayEpisodes,
          resourceId: episodeId,
          field: 'outline',
          oldText: '过期快照',
          newText: '新大纲',
          source: workingChangeSourceAi,
          sourceSessionId: 'session_1',
          expectedCurrentText: '过期快照',
        ),
        throwsA(isA<WorkingOverlayConflictException>()),
      );
      expect(await currentOutline(), '真实大纲');
    },
  );

  test('episode outline merges per session and blocks another', () async {
    final first = await overlayService.stageTextChange(
      resourcePath: outlinePath,
      resourceType: workingChangeResourceTypeScreenplayEpisodes,
      resourceId: episodeId,
      field: 'outline',
      oldText: '',
      newText: '会话一',
      source: workingChangeSourceAi,
      sourceSessionId: 'session_1',
      expectedCurrentText: '',
    );
    await overlayService.stageTextChange(
      resourcePath: outlinePath,
      resourceType: workingChangeResourceTypeScreenplayEpisodes,
      resourceId: episodeId,
      field: 'outline',
      oldText: '会话一',
      newText: '会话一第二版',
      source: workingChangeSourceAi,
      sourceSessionId: 'session_1',
      expectedCurrentText: '会话一',
    );
    expect(
      await overlayService.getWorkingChangesForResource(outlinePath),
      hasLength(1),
    );
    await expectLater(
      overlayService.stageTextChange(
        resourcePath: outlinePath,
        resourceType: workingChangeResourceTypeScreenplayEpisodes,
        resourceId: episodeId,
        field: 'outline',
        oldText: '会话一第二版',
        newText: '会话二',
        source: workingChangeSourceAi,
        sourceSessionId: 'session_2',
        expectedCurrentText: '会话一第二版',
      ),
      throwsA(isA<WorkingOverlayConflictException>()),
    );
    // 驳回会话一应回到空，而不是回到某个被叠加过的中间值。
    await overlayService.rejectWorkingChange(first.id);
    expect(await currentOutline(), '');
  });

  test('committed episode outline rolls back to the previous text', () async {
    await screenplayService.updateEpisodeOutline(
      episodeId: episodeId,
      outline: '提交前',
    );
    final change = await overlayService.stageTextChange(
      resourcePath: outlinePath,
      resourceType: workingChangeResourceTypeScreenplayEpisodes,
      resourceId: episodeId,
      field: 'outline',
      oldText: '提交前',
      newText: '提交后',
      source: workingChangeSourceAi,
      sourceSessionId: 'session_1',
      expectedCurrentText: '提交前',
    );
    await overlayService.autoSaveCommit(
      [change.id],
      source: workingChangeSourceAi,
      message: 'history.commit_message.auto_commit_ai_changes',
    );
    expect(
      (await contentDatabase.workingChangeDao.getById(change.id))?.status,
      workingChangeStatusCommitted,
    );

    await screenplayService.updateEpisodeOutline(
      episodeId: episodeId,
      outline: '提交后的手工编辑',
    );
    // 主动回退恢复历史目标，正常 expectedCurrentText 保护由上方独立用例覆盖。
    final result = await overlayService.rollbackChange(change.id);
    expect(result, RollbackChangeResult.rolledBack);
    expect(await currentOutline(), '提交前');
  });

  // 反向守卫：synopsis 是短字段，故意不上会话锁，重构会话锁时不要把它扫进去。
  test('scene synopsis still allows two sessions to stage', () async {
    await overlayService.stageTextChange(
      resourcePath: '/scenes/$sceneId/synopsis',
      resourceType: workingChangeResourceTypeScreenplayScenes,
      resourceId: sceneId,
      field: 'synopsis',
      oldText: '',
      newText: '会话一梗概',
      source: workingChangeSourceAi,
      sourceSessionId: 'session_1',
      expectedCurrentText: '',
    );
    await overlayService.stageTextChange(
      resourcePath: '/scenes/$sceneId/synopsis',
      resourceType: workingChangeResourceTypeScreenplayScenes,
      resourceId: sceneId,
      field: 'synopsis',
      oldText: '会话一梗概',
      newText: '会话二梗概',
      source: workingChangeSourceAi,
      sourceSessionId: 'session_2',
      expectedCurrentText: '会话一梗概',
    );
    expect(
      (await contentDatabase.screenplayDao.getScene(sceneId))?.synopsis,
      '会话二梗概',
    );
  });

  test(
    'manual save commits every active AI change in the scene scope',
    () async {
      final sceneScope = '/scenes/$sceneId';
      final createChange = await overlayService.stageCreateChange(
        resourcePath: sceneScope,
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        previewText: '新场次',
        source: workingChangeSourceAi,
        sourceSessionId: 'session_1',
      );
      final elementsChange = await overlayService.stageTextChange(
        resourcePath: elementsPath,
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        field: 'elements',
        oldText: await currentElementsJson(),
        newText: serializeScreenplayElements(const [
          ScreenplayElement(type: ScreenplayElementType.action, text: '新正文'),
        ]),
        source: workingChangeSourceAi,
        sourceSessionId: 'session_1',
        expectedCurrentText: await currentElementsJson(),
      );
      final synopsisChange = await overlayService.stageTextChange(
        resourcePath: '$sceneScope/synopsis',
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        field: 'synopsis',
        oldText: '',
        newText: '新梗概',
        source: workingChangeSourceAi,
        sourceSessionId: 'session_1',
        expectedCurrentText: '',
      );
      final manualChange = await overlayService.stageTextChange(
        resourcePath: '$sceneScope/synopsis',
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        field: 'synopsis',
        oldText: '新梗概',
        newText: '人工修订梗概',
        source: workingChangeSourceManual,
        expectedCurrentText: '新梗概',
      );

      await overlayService.commitManualSave(
        manualChangeIds: [manualChange.id],
        resourceScopes: [sceneScope],
        manualMessage: 'history.commit_message.manual_screenplay_save',
      );

      for (final change in [createChange, elementsChange, synopsisChange]) {
        expect(
          (await contentDatabase.workingChangeDao.getById(change.id))?.status,
          workingChangeStatusCommitted,
        );
      }
      expect(
        (await contentDatabase.workingChangeDao.getById(
          manualChange.id,
        ))?.status,
        workingChangeStatusCommitted,
      );
      expect(
        (await contentDatabase.screenplayDao.getScene(sceneId))?.synopsis,
        '人工修订梗概',
      );
    },
  );

  test(
    'explicit takeover needs no manual change and stays within dirty scenes',
    () async {
      final scene = (await contentDatabase.screenplayDao.getScene(sceneId))!;
      final otherId = await screenplayService.createScene(
        screenplayId: scene.screenplayId,
        episodeId: scene.episodeId,
      );
      final changes = <String>[];
      for (final id in [sceneId, otherId]) {
        final created = await overlayService.stageCreateChange(
          resourcePath: '/scenes/$id',
          resourceType: 'screenplay_scenes',
          resourceId: id,
          previewText: 'AI scene',
          source: workingChangeSourceAi,
        );
        changes.add(created.id);
      }
      final synopsis = await overlayService.stageTextChange(
        resourcePath: '/scenes/$sceneId/synopsis',
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        field: 'synopsis',
        oldText: '',
        newText: 'AI synopsis',
        source: workingChangeSourceAi,
        expectedCurrentText: '',
      );
      final body = await overlayService.stageTextChange(
        resourcePath: elementsPath,
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        field: 'elements',
        oldText: await currentElementsJson(),
        newText: serializeScreenplayElements(const [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: 'AI body',
          ),
        ]),
        source: workingChangeSourceAi,
        expectedCurrentText: await currentElementsJson(),
      );
      await overlayService.commitManualSave(
        manualChangeIds: const [],
        resourceScopes: ['/scenes/$sceneId'],
        manualMessage: 'Unused',
      );
      await overlayService.takeOverScreenplayScenes({});
      expect(
        (await contentDatabase.workingChangeDao.getById(changes.first))!.status,
        workingChangeStatusActive,
      );
      await overlayService.takeOverScreenplayScenes({sceneId});
      for (final id in [changes.first, synopsis.id, body.id]) {
        expect(
          (await contentDatabase.workingChangeDao.getById(id))!.status,
          workingChangeStatusCommitted,
        );
      }
      expect(
        (await contentDatabase.workingChangeDao.getById(changes.last))!.status,
        workingChangeStatusActive,
      );
      expect(
        (await overlayService.getWorkingChanges()).where(
          (change) => change.source == workingChangeSourceManual,
        ),
        isEmpty,
      );
    },
  );

  test(
    'failed outer document transaction rolls back AI takeover and content',
    () async {
      final created = await overlayService.stageCreateChange(
        resourcePath: '/scenes/$sceneId',
        resourceType: 'screenplay_scenes',
        resourceId: sceneId,
        previewText: 'AI scene',
        source: workingChangeSourceAi,
      );
      await expectLater(
        contentDatabase.transaction(() async {
          await overlayService.takeOverScreenplayScenes({sceneId});
          await screenplayService.writeElements(
            sceneId: sceneId,
            elements: const [
              ScreenplayElement(
                type: ScreenplayElementType.action,
                text: 'Draft',
              ),
            ],
          );
          throw StateError('injected document failure');
        }),
        throwsStateError,
      );
      expect(
        (await contentDatabase.workingChangeDao.getById(created.id))!.status,
        workingChangeStatusActive,
      );
      expect(
        await contentDatabase.screenplayDao.getElementRows(sceneId),
        isEmpty,
      );
      expect(await contentDatabase.changeCommitDao.getLatestCommit(), isNull);
    },
  );
}
