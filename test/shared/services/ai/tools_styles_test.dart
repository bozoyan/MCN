// 职责: 验证风格查询、剧本与节点写入、继承、隔离和撤销形成完整工具流程。
// 关联文件:
//   lib/shared/services/ai/styles_run_command_handler.dart
//   lib/shared/services/ai/tools_production.dart
//   lib/shared/services/working_overlay.dart
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/media/production.dart';
import 'package:reveric/shared/services/ai/tool_operations.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import 'package:reveric/shared/services/working_overlay.dart';

class _StyleHost implements ProductionToolHost {
  _StyleHost(this.canvas);
  @override
  final ProductionCanvasService canvas;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedOperations implements ToolOperationManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase app;
  late NovelContentDatabase db;
  late ProductionCanvasService canvas;
  late WorkingOverlayService overlay;
  late AiToolManager tools;
  late String episode;
  late Directory root;
  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    app = AppDatabase.forTest(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('styles-tools-');
    episode = (await ScreenplayService(db).createInitialStructure()).episodeId;
    canvas = ProductionCanvasService(
      StoryboardService(db),
      MediaLibraryService(app, MediaService(FfmpegRunner()), root),
      'work',
    );
    final content = NovelContentService(db);
    overlay = WorkingOverlayService(
      db,
      content,
      novelActionsService: NovelActionsService(app),
    );
    tools = AiToolManager(
      content,
      workingOverlayService: overlay,
      contentKind: 'screenplay',
      sessionId: 'session',
      workId: 'work',
      productionStyleServiceBuilder: () async => canvas,
    )..registerAllTools();
    tools.operationHost = ToolOperationHost(
      _UnusedOperations(),
      production: () async => _StyleHost(canvas),
    );
  });
  tearDown(() async {
    await db.close();
    await app.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, dynamic>> run(
    String action, [
    Map<String, dynamic> options = const {},
  ]) => tools.executeTool(
    name: 'Run',
    input: {'command': 'styles', 'subcommand': action, 'options': options},
  );
  Future<Map<String, dynamic>> write(String path, Object? value) =>
      tools.executeTool(name: 'Write', input: {'path': path, 'value': value});
  Future<void> style(String id, {bool deleted = false}) => app
      .into(app.productionStyles)
      .insert(
        ProductionStylesCompanion.insert(
          id: id,
          name: const Value('同名风格'),
          before: Value('Before $id'),
          after: const Value('After'),
          deletedAt: Value(deleted ? DateTime(2026) : notDeletedSentinel),
        ),
      );

  test('catalog discovery returns selectable IDs and scoped details', () async {
    await style('first');
    await style('second');
    await style('deleted', deleted: true);
    final help = await tools.executeTool(
      name: 'Run',
      input: {'command': 'help'},
    );
    expect(help['output'], contains('\n  styles '));
    final detailHelp = await tools.executeTool(
      name: 'Run',
      input: {'command': 'help', 'subcommand': 'styles'},
    );
    expect(detailHelp['output'], contains('剧本工具使用规范'));
    expect(detailHelp['output'], isNot(contains('styles list:')));
    final result = await run('list');
    final entries = (result['entries'] as List).cast<Map>();
    expect(entries.any((row) => row['id'] == 'preset:pixel-art'), isTrue);
    expect(entries.map((row) => row['id']), containsAll(['first', 'second']));
    expect(entries.map((row) => row['id']), isNot(contains('deleted')));
    expect(entries.every((row) => !row.containsKey('before')), isTrue);
    expect(
      (await run('read', {'style_id': 'preset:premium-costume-drama'}))['name'],
      '古装偶像剧',
    );
    for (final id in [
      'preset:costume-romance-dreamy',
      'preset:3d-glossy-latex',
    ]) {
      expect(entries.map((row) => row['id']), isNot(contains(id)));
      expect((await run('read', {'style_id': id}))['error_code'], 'not_found');
    }
    final filtered = await run('list', {'search': '同名', 'category': 'custom'});
    expect(filtered['entries'], hasLength(2));
    expect(
      (await run('read', {'style_id': 'second'}))['before'],
      'Before second',
    );
    expect(
      (await run('read', {'style_id': 'deleted'}))['error_code'],
      'not_found',
    );
    expect(
      (await run('list', {'category': 'invalid'}))['error_code'],
      'invalid_argument',
    );
  });

  test('custom styles are created, merged on update and bindable', () async {
    final created = await run('create', {
      'name': '同名风格',
      'before': '写实CG',
      'after': '避免水墨',
    });
    expect(created['ok'], isTrue, reason: '$created');
    expect(created['source'], 'custom');
    final id = created['id'] as String;
    final duplicate = await run('create', {'name': '同名风格', 'before': 'x'});
    expect(duplicate['name'], '同名风格 (2)');
    final updated = await run('update', {'style_id': id, 'after': '无卡通'});
    expect(updated['ok'], isTrue, reason: '$updated');
    expect(
      await run('read', {'style_id': id}),
      allOf(
        containsPair('name', '同名风格'),
        containsPair('before', '写实CG'),
        containsPair('after', '无卡通'),
      ),
    );
    expect((await write('/screenplay/style_id', id))['ok'], isTrue);
    for (final (action, options, code) in [
      ('create', {'name': ' ', 'before': 'x'}, 'invalid_argument'),
      ('create', {'name': '空', 'before': ' ', 'after': ''}, 'invalid_argument'),
      ('create', {'name': 'x', 'style_id': id}, 'invalid_argument'),
      ('update', {'style_id': id}, 'invalid_argument'),
      (
        'update',
        {'style_id': 'preset:pixel-art', 'before': 'x'},
        'invalid_argument',
      ),
      ('update', {'style_id': 'missing', 'before': 'x'}, 'not_found'),
    ]) {
      expect(
        (await run(action, options))['error_code'],
        code,
        reason: '$options',
      );
    }
    expect(
      (await app.select(app.productionStyles).get()).map((row) => row.name),
      unorderedEquals(['同名风格', '同名风格 (2)']),
    );
  });

  test('screenplay style persists, streams, reads and rolls back', () async {
    final before = (await db.screenplayDao.getRoot())!.styleId;
    final changed = db.screenplayDao.watchRoot().firstWhere(
      (root) => root?.styleId == 'preset:pixel-art',
    );
    final saved = await write('/screenplay/style_id', 'preset:pixel-art');
    expect(saved['ok'], isTrue, reason: '$saved');
    expect(
      (await changed.timeout(const Duration(seconds: 3)))!.styleId,
      'preset:pixel-art',
    );
    final read = await tools.executeTool(
      name: 'Read',
      input: {'path': '/screenplay'},
    );
    expect(read['style_id'], 'preset:pixel-art');
    expect(read, isNot(contains('style_asset_id')));
    final changes = await overlay.getWorkingChanges();
    expect(changes, hasLength(1));
    await overlay.rejectWorkingChange(changes.single.id);
    expect((await db.screenplayDao.getRoot())!.styleId, before);
    final created = await tools.executeTool(
      name: 'Create',
      input: {
        'path': '/screenplay',
        'fields': {'style_id': 'preset:pixel-art'},
      },
    );
    expect(created['ok'], isTrue, reason: '$created');
    final edited = await tools.executeTool(
      name: 'Edit',
      input: {
        'path': '/screenplay/style_id',
        'old_text': 'preset:pixel-art',
        'new_text': 'preset:eastern-ink-decorative',
      },
    );
    expect(edited['ok'], isTrue, reason: '$edited');
    expect((await write('/screenplay/style_id', null))['ok'], isTrue);
    expect((await db.screenplayDao.getRoot())!.styleId, isNull);
  });

  test(
    'clip overrides survive global changes and can resume inheritance',
    () async {
      await style('custom');
      final clip = await canvas.shots.createImage(episode);
      final path = '/clips/${clip.id}/style_selection';
      expect(
        (await write('/screenplay/style_id', 'preset:pixel-art'))['ok'],
        isTrue,
      );
      expect((await write(path, 'custom'))['ok'], isTrue);
      expect((await write('/screenplay/style_id', null))['ok'], isTrue);
      expect(
        (await canvas.effectiveStyle(
          (await canvas.shots.getShot(clip.id))!,
        ))!.before,
        'Before custom',
      );
      expect((await write(path, 'none'))['ok'], isTrue);
      expect(
        (await write('/screenplay/style_id', 'preset:pixel-art'))['ok'],
        isTrue,
      );
      expect(
        await canvas.effectiveStyle((await canvas.shots.getShot(clip.id))!),
        isNull,
      );
      expect((await write(path, null))['ok'], isTrue);
      expect(
        await canvas.effectiveStyle((await canvas.shots.getShot(clip.id))!),
        isNotNull,
      );
      expect((await write(path, 'custom'))['ok'], isTrue);
      final styleChange = (await overlay.getWorkingChanges()).lastWhere(
        (row) => row.resourceType == 'production_clips',
      );
      await overlay.rejectWorkingChange(styleChange.id);
      expect((await canvas.shots.getShot(clip.id))!.styleSelection, isNull);
    },
  );

  test('invalid styles never change records or history', () async {
    await style('deleted', deleted: true);
    final clip = await canvas.shots.createImage(episode);
    final before = (await db.screenplayDao.getRoot())!.styleId;
    for (final id in [
      'preset:missing',
      'preset:costume-romance-dreamy',
      'preset:3d-glossy-latex',
      'deleted',
      'missing',
      '',
    ]) {
      expect((await write('/screenplay/style_id', id))['ok'], isFalse);
      expect(
        (await write('/clips/${clip.id}/style_selection', id))['ok'],
        isFalse,
      );
    }
    expect((await db.screenplayDao.getRoot())!.styleId, before);
    expect((await canvas.shots.getShot(clip.id))!.styleSelection, isNull);
    expect(await overlay.getWorkingChanges(), isEmpty);
    final audio = await canvas.shots.createAudio(episode);
    expect(
      (await write('/clips/${audio.id}/style_selection', 'none'))['ok'],
      isFalse,
    );
  });

  test(
    'Create validates style before inserting the clip and canvas node',
    () async {
      final invalid = await tools.executeTool(
        name: 'Create',
        input: {
          'path': '/clips',
          'fields': {
            'kind': 'image',
            'episode_id': episode,
            'style_selection': 'preset:missing',
          },
        },
      );
      expect(invalid['ok'], isFalse);
      expect(await db.select(db.productionClips).get(), isEmpty);
      expect(await db.select(db.canvasNodes).get(), isEmpty);
      final valid = await tools.executeTool(
        name: 'Create',
        input: {
          'path': '/clips',
          'fields': {
            'kind': 'image',
            'episode_id': episode,
            'style_selection': 'preset:pixel-art',
          },
        },
      );
      expect(valid['ok'], isTrue, reason: '$valid');
      expect(
        (await db.select(db.productionClips).get()).single.styleSelection,
        'preset:pixel-art',
      );
    },
  );

  test(
    'repeated global writes are idempotent and none clears the default',
    () async {
      expect(
        (await write('/screenplay/style_id', 'preset:pixel-art'))['updated'],
        isTrue,
      );
      expect(
        (await write('/screenplay/style_id', 'preset:pixel-art'))['updated'],
        isFalse,
      );
      expect(await overlay.getWorkingChanges(), hasLength(1));
      expect((await write('/screenplay/style_id', 'none'))['style_id'], isNull);
      expect((await db.screenplayDao.getRoot())!.styleId, isNull);
    },
  );

  test(
    'broad search works without media capability and removed assets paths fail',
    () async {
      final mediaHost = tools.operationHost;
      tools.operationHost = null;
      final broad = await tools.executeTool(
        name: 'Glob',
        input: {'pattern': '**', 'path': '/'},
      );
      expect(broad['ok'], isTrue, reason: '$broad');
      final explicit = await tools.executeTool(
        name: 'Glob',
        input: {'pattern': '**', 'path': '/assets'},
      );
      expect(explicit['error_code'], 'invalid_argument', reason: '$explicit');
      expect((await run('list'))['error_code'], 'invalid_argument');
      expect(
        (await write('/screenplay/style_id', 'preset:pixel-art'))['ok'],
        isTrue,
      );
      tools.operationHost = mediaHost;
      tools.productionStyleServiceBuilder = null;
      expect((await run('list'))['error_code'], 'unavailable');
    },
  );
}
