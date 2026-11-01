// 职责: 验证场次投影响应源数据变化且保留画布引用、连线与坐标。
// 关联文件:
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/services/canvas_service.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/models/screenplay_document.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/state-management.md

import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/canvas_scene_reference.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/models/screenplay_document.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/providers/canvas_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/services/screenplay_service.dart';

void main() {
  const path = 'memory:canvas-scenes';
  late NovelContentDatabase db;
  late ProviderContainer container;
  late ScreenplayService screenplay;
  late CanvasService canvas;
  late CreatedSeason initial;
  late String rootId;
  late String canvasId;
  final projection = canvasSceneReferencesProvider(path);

  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    screenplay = ScreenplayService(db);
    canvas = CanvasService(db);
    initial = await screenplay.createInitialStructure();
    rootId = (await db.screenplayDao.getRoot())!.id;
    canvasId = await canvas.createCanvas(name: 'Story');
    container = ProviderContainer(
      overrides: [novelContentDatabaseProvider(path).overrideWithValue(db)],
    );
    container.listen(projection, (_, _) {});
    await container.read(projection.future);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<Map<String, CanvasSceneReference>> waitForScenes(
    bool Function(Map<String, CanvasSceneReference>) predicate,
  ) async {
    final done = Completer<Map<String, CanvasSceneReference>>();
    final subscription = container.listen(projection, (_, value) {
      if (value.hasError && !done.isCompleted) {
        done.completeError(value.error!, value.stackTrace);
      } else if (!value.isLoading &&
          value.value != null &&
          predicate(value.value!) &&
          !done.isCompleted) {
        done.complete(value.value);
      }
    }, fireImmediately: true);
    try {
      return await done.future.timeout(const Duration(seconds: 5));
    } finally {
      subscription.close();
    }
  }

  Future<Set<String>> waitForInvalid(Set<String> expected) async {
    final provider = canvasInvalidNodeIdsProvider((
      canvasId: canvasId,
      databasePath: path,
    ));
    final done = Completer<Set<String>>();
    final subscription = container.listen(provider, (_, value) {
      if (value.hasError && !done.isCompleted) {
        done.completeError(value.error!, value.stackTrace);
      } else if (!value.isLoading &&
          value.value != null &&
          value.value!.length == expected.length &&
          value.value!.containsAll(expected) &&
          !done.isCompleted) {
        done.complete(value.value);
      }
    }, fireImmediately: true);
    try {
      return await done.future.timeout(const Duration(seconds: 5));
    } finally {
      subscription.close();
    }
  }

  Future<String> addReference(String sceneId) => canvas.addNode(
    canvasId: canvasId,
    type: canvasNodeTypeReference,
    refType: canvasNodeRefTypeScreenplayScene,
    refId: sceneId,
    x: 123,
    y: 456,
  );

  test(
    'rename, reorder, cross-season move and deletion refresh every duplicate without canvas writes',
    () async {
      final sceneId = await screenplay.createScene(
        screenplayId: rootId,
        episodeId: initial.episodeId,
        title: 'Before',
      );
      final first = await addReference(sceneId);
      final duplicate = await addReference(sceneId);
      await canvas.addEdge(
        canvasId: canvasId,
        sourceNodeId: first,
        targetNodeId: duplicate,
        type: canvasEdgeTypeTimeline,
        label: 'Choice',
      );
      final beforeNodes = await db.canvasDao.getNodesByCanvas(canvasId);
      final beforeEdges = await db.canvasDao.getEdgesByCanvas(canvasId);
      container.listen(
        canvasInvalidNodeIdsProvider((canvasId: canvasId, databasePath: path)),
        (_, _) {},
      );
      await waitForInvalid({});
      await screenplay.updateScene(
        sceneId: sceneId,
        title: 'After',
        synopsis: 'Detailed synopsis',
      );
      var references = await waitForScenes(
        (items) => items[sceneId]?.scene.title == 'After',
      );
      expect(references[sceneId]!.scene.synopsis, 'Detailed synopsis');
      final target = await screenplay.createSeason(screenplayId: rootId);
      final anchor = await screenplay.createScene(
        screenplayId: rootId,
        episodeId: target.episodeId,
      );
      await screenplay.moveSceneToEpisodeEnd(sceneId, target.episodeId);
      references = await waitForScenes(
        (items) => items[sceneId]?.episode.id == target.episodeId,
      );
      expect(references[sceneId]!.season.id, target.seasonId);
      expect(references[sceneId]!.scene.sceneNumber, 2);
      await screenplay.moveSceneBefore(sceneId, anchor);
      await waitForScenes((items) => items[sceneId]?.scene.sceneNumber == 1);
      expect(
        await canvas.referenceExists(canvasNodeRefTypeScreenplayScene, sceneId),
        isTrue,
      );
      await screenplay.deleteScene(sceneId);
      await waitForScenes((items) => !items.containsKey(sceneId));
      expect(await waitForInvalid({first, duplicate}), {first, duplicate});
      expect(
        await canvas.referenceExists(canvasNodeRefTypeScreenplayScene, sceneId),
        isFalse,
      );
      await expectLater(
        addReference(sceneId),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'code',
            'invalid_reference',
          ),
        ),
      );
      expect(await db.canvasDao.getNodesByCanvas(canvasId), beforeNodes);
      expect(await db.canvasDao.getEdgesByCanvas(canvasId), beforeEdges);
    },
  );

  test(
    'missing season or episode invalidates references even if child rows remain active',
    () async {
      final sceneId = await screenplay.createScene(
        screenplayId: rootId,
        episodeId: initial.episodeId,
      );
      final nodeId = await addReference(sceneId);
      container.listen(
        canvasInvalidNodeIdsProvider((canvasId: canvasId, databasePath: path)),
        (_, _) {},
      );
      await waitForScenes((items) => items.containsKey(sceneId));
      await waitForInvalid({});
      await (db.update(db.screenplayEpisodes)
            ..where((t) => t.id.equals(initial.episodeId)))
          .write(ScreenplayEpisodesCompanion(deletedAt: Value(DateTime.now())));
      await waitForScenes((items) => items.isEmpty);
      await waitForInvalid({nodeId});
      expect(
        await canvas.referenceExists(canvasNodeRefTypeScreenplayScene, sceneId),
        isFalse,
      );
      await (db.update(
        db.screenplayEpisodes,
      )..where((t) => t.id.equals(initial.episodeId))).write(
        ScreenplayEpisodesCompanion(deletedAt: Value(notDeletedSentinel)),
      );
      await waitForScenes((items) => items.containsKey(sceneId));
      await waitForInvalid({});
      await (db.update(db.screenplaySeasons)
            ..where((t) => t.id.equals(initial.seasonId)))
          .write(ScreenplaySeasonsCompanion(deletedAt: Value(DateTime.now())));
      await waitForScenes((items) => items.isEmpty);
      await waitForInvalid({nodeId});
      expect(
        await canvas.referenceExists(canvasNodeRefTypeScreenplayScene, sceneId),
        isFalse,
      );
      expect((await db.canvasDao.getNodeById(nodeId))!.refId, sceneId);
    },
  );

  test(
    'split retains original node; merge leaves absorbed reference invalid and edges intact',
    () async {
      final sceneId = await screenplay.createScene(
        screenplayId: rootId,
        episodeId: initial.episodeId,
      );
      await screenplay.writeElements(
        sceneId: sceneId,
        elements: const [
          ScreenplayElement(type: ScreenplayElementType.action, text: '前段后段'),
        ],
      );
      final originalNode = await addReference(sceneId);
      final baseline = await screenplay.readDocument(initial.episodeId);
      final body = baseline.elements.firstWhere((e) => !e.isHeading);
      final split = baseline.split(ScreenplayPosition(body.id!, 2));
      final saved = await screenplay.applyDocument(baseline, split, {
        ...baseline.scenes.keys,
        ...split.scenes.keys,
      });
      final splitId = saved.document.sceneOrder.last;
      await waitForScenes((items) => items.length == 2);
      expect(await db.canvasDao.getNodesByCanvas(canvasId), hasLength(1));
      expect((await db.canvasDao.getNodeById(originalNode))!.refId, sceneId);
      final absorbedNode = await addReference(splitId);
      await canvas.addEdge(
        canvasId: canvasId,
        sourceNodeId: originalNode,
        targetNodeId: absorbedNode,
        type: canvasEdgeTypeTimeline,
      );
      final nodes = await db.canvasDao.getNodesByCanvas(canvasId);
      final edges = await db.canvasDao.getEdgesByCanvas(canvasId);
      final merged = saved.document.merge(splitId);
      await screenplay.applyDocument(saved.document, merged, {
        sceneId,
        splitId,
      });
      await waitForScenes(
        (items) => items.length == 1 && items.containsKey(sceneId),
      );
      await waitForInvalid({absorbedNode});
      expect(await db.canvasDao.getNodesByCanvas(canvasId), nodes);
      expect(await db.canvasDao.getEdgesByCanvas(canvasId), edges);
    },
  );
}
