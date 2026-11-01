// 职责: 验证制作画布分组的成员校验、布局变更、互转、整组移动、解组、清空与删除规则。
// 关联文件:
//   lib/shared/services/production/group_service.dart
//   lib/shared/models/production/group_layout.dart
//   lib/shared/services/production/canvas_service.dart
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' as app;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/production/asset_content.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/models/video/request.dart';
import 'package:reveric/shared/models/production/image_request.dart';

void main() {
  late NovelContentDatabase db;
  late app.AppDatabase appDb;
  late Directory root;
  late ProductionCanvasService service;
  late ProductionGroupService groups;
  late String canvasId;

  Future<CanvasNode> media(String id, {String type = 'image'}) async {
    final relative =
        'file_workspaces/work/$id.${type == 'image' ? 'png' : 'mp4'}';
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    await appDb.assetDao.insertAsset(
      app.AssetsCompanion.insert(
        id: id,
        type: type,
        name: Value(id),
        path: Value(relative),
        content: Value(
          type == 'image'
              ? const ImageAssetContent(mimeType: 'image/png')
              : const VideoAssetContent(mimeType: 'video/mp4'),
        ),
        purpose: 'upload',
        source: const Value('upload'),
      ),
    );
    return service.addMedia(canvasId, id);
  }

  Future<CanvasNode> node(String id) async =>
      (await db.canvasDao.getNodeById(id))!;

  Future<CanvasNode> storyboard(
    List<CanvasNode> cells, {
    int cols = 2,
    int rows = 2,
    Offset origin = const Offset(100, 50),
  }) => service.createStoryboardGroup(
    canvasId,
    layout: StoryboardGroupLayout(cols: cols, rows: rows),
    origin: origin,
    memberIds: [for (final cell in cells) cell.id],
  );

  Matcher rejected(String code) =>
      throwsA(isA<StoryboardException>().having((e) => e.code, 'code', code));

  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDb = app.AppDatabase.forTest(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('production-group-test-');
    final episode = (await ScreenplayService(
      db,
    ).createInitialStructure()).episodeId;
    final shots = StoryboardService(db);
    service = ProductionCanvasService(
      shots,
      MediaLibraryService(appDb, MediaService(FfmpegRunner()), root),
      'work',
    );
    groups = service.groups;
    canvasId = (await service.ensureCanvas(episode)).id;
  });
  tearDown(() async {
    await db.close();
    await appDb.close();
    await root.delete(recursive: true);
  });

  test('storyboard cells tile compactly from the group origin', () async {
    final cells = [for (var i = 0; i < 3; i++) await media('cell-$i')];
    final group = await storyboard(cells);
    final layout =
        ProductionGroupLayout.fromStyle(group.style) as StoryboardGroupLayout;
    expect((layout.cols, layout.rows, layout.ratio), (2, 2, '16:9'));
    final cell = layout.cellSize;
    expect(
      (group.width, group.height),
      (
        cell.width * 2 + StoryboardGroupLayout.gap,
        cell.height * 2 + StoryboardGroupLayout.gap,
      ),
    );
    final stored = await groups.members(group.id);
    expect(stored.map((m) => m.id), cells.map((c) => c.id));
    expect(stored.map((m) => m.parentId).toSet(), {group.id});
    expect(stored.map((m) => (m.sortOrder, m.x, m.y)), [
      (0, 100.0, 50.0),
      (1, 100 + cell.width + 2, 50.0),
      (2, 100.0, 50 + cell.height + 2),
    ]);
  });

  test(
    'membership rules reject nesting, foreign canvases, non-images and taken slots',
    () async {
      final cell = await media('cell');
      final video = await media('clip', type: 'video');
      final group = await storyboard([cell]);
      await expectLater(storyboard([video]), rejected('invalid_asset'));
      await expectLater(
        groups.createStoryboard(
          canvasId,
          layout: const StoryboardGroupLayout(cols: 2, rows: 2),
          origin: Offset.zero,
          memberIds: [group.id],
        ),
        rejected('invalid_config'),
      );
      // 已在分镜组里的成员不能再挂到另一个分组。
      await expectLater(storyboard([cell]), rejected('invalid_config'));
      final other = await db
          .into(db.canvases)
          .insert(CanvasesCompanion.insert(id: 'other', name: 'Other'));
      expect(other, isNonZero);
      await expectLater(
        groups.createStoryboard(
          'other',
          layout: const StoryboardGroupLayout(cols: 2, rows: 2),
          origin: Offset.zero,
          memberIds: [(await media('elsewhere')).id],
        ),
        rejected('invalid_config'),
      );
      final extra = await media('extra');
      await expectLater(
        groups.attachToSlot(group.id, extra.id, 0),
        rejected('invalid_config'),
      );
      await expectLater(
        groups.attachToSlot(group.id, extra.id, 4),
        rejected('invalid_config'),
      );
      await groups.attachToSlot(group.id, extra.id, 3);
      expect((await node(extra.id)).sortOrder, 3);
      await expectLater(
        storyboard([for (var i = 0; i < 5; i++) await media('overflow-$i')]),
        rejected('invalid_config'),
      );
    },
  );

  test(
    'moving the frame moves every cell; a single cell cannot move',
    () async {
      final cells = [await media('a'), await media('b')];
      final group = await storyboard(cells);
      final cell = await node(cells[1].id);
      await expectLater(
        service.move(cell.id, cell.x + 10, cell.y),
        rejected('invalid_config'),
      );
      // 框选里只带格子的原位坐标不算移动。
      await service.moveNodes(canvasId, {cell.id: (x: cell.x, y: cell.y)});
      await service.moveNodes(canvasId, {
        group.id: (x: 300, y: 400),
        cell.id: (x: -999, y: -999),
      });
      final moved = await groups.members(group.id);
      final size =
          (ProductionGroupLayout.fromStyle(group.style)
                  as StoryboardGroupLayout)
              .cellSize;
      expect(moved.map((m) => (m.x, m.y)), [
        (300.0, 400.0),
        (300 + size.width + 2, 400.0),
      ]);
      expect(
        ((await node(group.id)).x, (await node(group.id)).y),
        (300.0, 400.0),
      );
    },
  );

  test(
    'converting to free and back keeps id, members, order and edges',
    () async {
      final source = await media('source');
      final cells = [for (var i = 0; i < 3; i++) await media('cell-$i')];
      final group = await storyboard(cells, cols: 3, rows: 1);
      await db
          .into(db.canvasEdges)
          .insert(
            CanvasEdgesCompanion.insert(
              id: 'lineage',
              canvasId: canvasId,
              sourceNodeId: source.id,
              targetNodeId: group.id,
              type: const Value(canvasEdgeTypeDerivedOutput),
            ),
          );
      const sizes = {'wide': Size(260, 146.25), 'square': Size(220, 220)};
      await groups.toFree(group.id, {
        cells[0].id: sizes['wide']!,
        cells[1].id: sizes['square']!,
        cells[2].id: sizes['wide']!,
      });
      final free = await node(group.id);
      expect(
        ProductionGroupLayout.fromStyle(free.style),
        const FreeGroupLayout(),
      );
      final spread = await groups.members(group.id);
      expect(spread.map((m) => m.id), cells.map((c) => c.id));
      // 同一行从左到右、互不重叠，外框包住成员和标题。
      final rects = [
        for (var i = 0; i < 3; i++)
          Offset(spread[i].x, spread[i].y) &
              (i == 1 ? sizes['square']! : sizes['wide']!),
      ];
      expect(rects[0].right < rects[1].left, isTrue);
      expect(rects[1].right < rects[2].left, isTrue);
      final frame = Rect.fromLTWH(free.x, free.y, free.width!, free.height!);
      for (final rect in rects) {
        expect(frame.contains(rect.topLeft), isTrue);
        expect(frame.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
      }

      await groups.toStoryboard(group.id, {
        for (var i = 0; i < 3; i++) spread[i].id: rects[i],
      });
      final back = await node(group.id);
      final layout =
          ProductionGroupLayout.fromStyle(back.style) as StoryboardGroupLayout;
      expect((layout.cols, layout.rows, layout.ratio), (2, 2, '16:9'));
      expect(back.id, group.id);
      expect((await groups.members(group.id)).map((m) => (m.id, m.sortOrder)), [
        for (var i = 0; i < 3; i++) (cells[i].id, i),
      ]);
      expect(
        (await db.canvasDao.getEdgesByCanvas(canvasId)).single.id,
        'lineage',
      );
    },
  );

  test(
    'changing the grid re-packs members and refuses too small grids',
    () async {
      final cells = [for (var i = 0; i < 3; i++) await media('cell-$i')];
      final group = await storyboard(cells, cols: 3, rows: 3);
      final extra = await media('extra');
      await groups.attachToSlot(group.id, extra.id, 8);
      await expectLater(
        groups.setStoryboardLayout(
          group.id,
          const StoryboardGroupLayout(cols: 1, rows: 3),
        ),
        rejected('invalid_config'),
      );
      await groups.setStoryboardLayout(
        group.id,
        const StoryboardGroupLayout(cols: 2, rows: 2, ratio: '9:16'),
      );
      expect((await groups.members(group.id)).map((m) => (m.id, m.sortOrder)), [
        for (var i = 0; i < 3; i++) (cells[i].id, i),
        (extra.id, 3),
      ]);
      // 只改比例和序号时格位不动，空格位留在原处。
      await service.removeNode(cells[1].id);
      await groups.setStoryboardLayout(
        group.id,
        const StoryboardGroupLayout(
          cols: 2,
          rows: 2,
          ratio: '1:1',
          numbered: true,
        ),
      );
      expect((await groups.members(group.id)).map((m) => (m.sortOrder, m.x)), [
        (0, 100.0),
        (2, 100.0),
        (3, 100 + 220 + 2.0),
      ]);
    },
  );

  test(
    'ungroup, clear, and delete keep data soft-deleted as specified',
    () async {
      final cells = [await media('a'), await media('b'), await media('c')];
      final group = await storyboard(cells);
      await service.removeNode(cells[1].id);
      expect((await groups.members(group.id)).map((m) => m.sortOrder), [0, 2]);
      expect(await node(group.id), isNotNull);

      await groups.clear(group.id);
      expect(await groups.members(group.id), isEmpty);
      expect(await db.canvasDao.getNodeById(group.id), isNotNull);

      final kept = [await media('d'), await media('e')];
      for (var i = 0; i < kept.length; i++) {
        await groups.attachToSlot(group.id, kept[i].id, i);
      }
      await groups.ungroup(
        group.id,
        sizes: {for (final k in kept) k.id: const Size(260, 146.25)},
      );
      expect(await db.canvasDao.getNodeById(group.id), isNull);
      for (final k in kept) {
        expect((await node(k.id)).parentId, isNull);
      }
      // 解组前已按普通组重排，原尺寸的卡片不再重叠。
      final a = await node(kept[0].id), b = await node(kept[1].id);
      expect(a.x + 260 < b.x, isTrue);

      final image = await service.addImage(canvasId);
      final second = await storyboard([await media('f'), image]);
      await service.removeNode(second.id);
      expect(await db.canvasDao.getNodeById(second.id), isNull);
      expect(await db.canvasDao.getNodeById(image.id), isNull);
      expect(await service.shots.getShot(image.clipId!), isNull);
    },
  );

  test('a parent_id pointing at a deleted group reads as ungrouped', () async {
    final cell = await media('cell');
    final group = await storyboard([cell]);
    await db.canvasDao.softDeleteNode(group.id);
    final orphan = await node(cell.id);
    expect(orphan.parentId, group.id);
    expect(await groups.groupOf(orphan), isNull);
    await service.move(orphan.id, 10, 20);
    expect(((await node(cell.id)).x, (await node(cell.id)).y), (10.0, 20.0));
    final regrouped = await storyboard([orphan]);
    expect((await node(cell.id)).parentId, regrouped.id);
  });

  test(
    'swapping occupied and empty slots preserves members and reference identities',
    () async {
      final first = await media('first');
      final second = await media('second');
      final group = await storyboard([first, second]);
      final overlay = WorkingOverlayService(
        db,
        NovelContentService(db),
        novelActionsService: NovelActionsService(appDb),
      );
      final target = await service.addStoryboardReference(
        group.id,
        video: false,
        overlay: overlay,
        placement: (at: (x: 900.0, y: 50.0), moves: const {}),
      );
      final before = await service.inputs(target.id);
      expect(before.map((i) => i.refId), [first.id, second.id]);
      final edgesBefore = (await service.content(
        canvasId,
      )).edges.map((e) => e.id).toSet();
      await groups.swapSlot(group.id, first.id, 1);
      expect((await groups.members(group.id)).map((n) => n.id), [
        second.id,
        first.id,
      ]);
      expect((await node(first.id)).sortOrder, 1);
      expect((await node(second.id)).sortOrder, 0);
      expect(
        (await service.content(canvasId)).edges.map((e) => e.id).toSet(),
        edgesBefore,
      );
      final layout =
          ProductionGroupLayout.fromStyle(group.style) as StoryboardGroupLayout;
      expect(
        Offset((await node(first.id)).x, (await node(first.id)).y),
        Offset(group.x, group.y) + layout.cellOffset(1),
      );
      await groups.swapSlot(group.id, first.id, 3);
      expect((await node(first.id)).sortOrder, 3);
      expect((await groups.members(group.id)).map((n) => n.sortOrder), [0, 3]);
      await service.attachStoryboardGroup(
        group.id,
        target.id,
        overlay: overlay,
      );
      final after = await service.inputs(target.id);
      expect(after.map((i) => i.refId), [second.id, first.id]);
      expect(after.map((i) => i.id).toSet(), before.map((i) => i.id).toSet());
      await expectLater(
        groups.swapSlot(group.id, first.id, 4),
        rejected('invalid_config'),
      );
      final stranger = await media('stranger');
      await expectLater(
        groups.swapSlot(group.id, stranger.id, 0),
        rejected('invalid_config'),
      );
      expect((await node(first.id)).sortOrder, 3);
      final video = await service.addStoryboardReference(
        group.id,
        video: true,
        overlay: overlay,
        placement: (at: (x: 900.0, y: 400.0), moves: const {}),
      );
      expect(
        (await service.shots.getShot(video.clipId!))!.referenceMode,
        'reference',
      );
      expect((await service.inputs(video.id)).map((i) => i.refId), [
        second.id,
        first.id,
      ]);
      await expectLater(
        service.attachStoryboardGroup(group.id, first.id, overlay: overlay),
        rejected('invalid_reference'),
      );
    },
  );

  test('group nodes cannot feed generation inputs', () async {
    final group = await storyboard([await media('cell')]);
    final image = await service.addImage(canvasId);
    final overlay = WorkingOverlayService(
      db,
      NovelContentService(db),
      novelActionsService: NovelActionsService(appDb),
    );
    await expectLater(
      service.saveImage(
        nodeId: image.id,
        overlay: overlay,
        inputs: [
          ProductionInput.node(group.id, VideoInputRole.reference_image),
        ],
        draft: const ProductionImageDraft(
          prompt: '',
          modelId: '',
          ratio: '1:1',
          resolution: '1K',
        ),
      ),
      rejected('invalid_reference'),
    );
  });

  test('layout math packs, orders and validates', () {
    expect(
      [1, 3, 4, 7, 25].map((n) {
        final l = StoryboardGroupLayout.fitting(n, ratio: '1:1');
        return (l.cols, l.rows);
      }),
      [(1, 1), (2, 2), (2, 2), (3, 3), (5, 5)],
    );
    expect(
      readingOrder({
        'c': const Rect.fromLTWH(0, 300, 100, 100),
        'b': const Rect.fromLTWH(200, 10, 100, 100),
        'a': const Rect.fromLTWH(0, 0, 100, 100),
      }),
      ['a', 'b', 'c'],
    );
    expect(productionNearestRatio(256 / 144), '16:9');
    expect(productionNearestRatio(1), '1:1');
    expect(
      () => ProductionGroupLayout.fromStyle({
        'group': {'layout': 'storyboard', 'cols': 6, 'rows': 1, 'ratio': '1:1'},
      }),
      throwsFormatException,
    );
    expect(
      const StoryboardGroupLayout(cols: 2, rows: 2).writeTo({'color': 'blue'}),
      {
        'color': 'blue',
        'group': {
          'layout': 'storyboard',
          'cols': 2,
          'rows': 2,
          'ratio': '16:9',
          'numbered': false,
        },
      },
    );
  });
}
