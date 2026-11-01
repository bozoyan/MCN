// 职责: 验证全景节点工具的显式视角、授权、来源冻结与逐方向部分完成和取消。
// 关联文件:
//   lib/shared/services/ai/media/panorama_nodes.dart
//   lib/shared/services/production/panorama_service.dart
//   lib/shared/services/production/node_source.dart
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reveric/shared/agent/tool_approval.dart';
import 'package:reveric/shared/database/app_database.dart' as app;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:reveric/shared/models/tool_permission.dart';
import 'package:reveric/shared/models/production/panorama.dart';
import 'package:reveric/shared/services/ai/media/production.dart';
import 'package:reveric/shared/services/ai/tool_operations.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/production/audio_service.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/image_service.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/production/panorama_service.dart';
import 'package:reveric/shared/services/production/result_service.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import 'package:reveric/shared/services/tool_permission_gate.dart';
import 'package:reveric/shared/services/tool_permissions.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:reveric/shared/widgets/production/panorama/texture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NovelContentDatabase db;
  late app.AppDatabase appDb;
  late Directory root;
  late _Canvas canvas;
  late CanvasNode node;
  late String episode, sourceAsset;
  late ToolOperationManager operations;
  late ToolOperationRegistry registry;
  late ToolPermissionService permissions;
  late AiToolApprovalController approvals;
  late AiToolManager tools;
  late PanoramaRender render;
  late List<PanoramaView> seen;
  late Uint8List png;
  final context = ToolExecutionContext(
    sessionId: 'owner',
    sourceTurnId: 'turn',
  );
  Map<String, dynamic> view(
    num yaw, {
    num pitch = 0,
    num fov = 75,
    String title = 'Same',
  }) => {'yaw': yaw, 'pitch': pitch, 'fov': fov, 'title': title};

  /// 全景取景固定后台执行；默认等待同一 run 结束，[wait] 为 false 时返回提交回执。
  Future<Map<String, dynamic>> run(
    List<Map<String, dynamic>> views, {
    bool wait = true,
    Map<String, dynamic> extra = const {},
  }) async {
    final response = await tools.executeTool(
      name: 'Run',
      callId: 'panorama',
      context: context,
      input: {
        'command': 'production',
        'subcommand': 'capture-panorama',
        'options': {'node_id': node.id, 'views': views, ...extra},
      },
    );
    final runId = response['run_id'];
    if (!wait || runId is! String) {
      return response;
    }
    return operations.wait(runId, context);
  }

  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDb = app.AppDatabase.forTest(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('panorama-node-tools-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    await RevericPaths.initialize();
    episode = (await ScreenplayService(db).createInitialStructure()).episodeId;
    canvas = _Canvas(
      StoryboardService(db),
      MediaLibraryService(appDb, MediaService(FfmpegRunner()), root),
      'work',
    );
    png = Uint8List.fromList(img.encodePng(img.Image(width: 64, height: 32)));
    final file = await File('${root.path}/source.png').writeAsBytes(png);
    sourceAsset = (await canvas.library.importFile(
      file,
      name: 'Source.png',
      novelId: 'work',
      purpose: AssetPurpose.production_upload,
      cancellation: MediaCancellation(),
    )).id;
    node = await canvas.addMedia(
      (await canvas.ensureCanvas(episode)).id,
      sourceAsset,
    );
    await canvas.setPanoramaView(
      node.id,
      const PanoramaView(yaw: 33, pitch: 20, fov: 50),
    );
    await appDb
        .into(appDb.novels)
        .insert(
          app.NovelsCompanion.insert(
            id: 'work',
            title: 'Work',
            description: '',
          ),
        );
    await appDb
        .into(appDb.aiChatSessions)
        .insert(
          app.AiChatSessionsCompanion.insert(id: 'owner', novelId: 'work'),
        );
    permissions = ToolPermissionService(
      appDb,
      episodeExists: (work, id) async =>
          work == 'work' && await db.screenplayDao.getEpisode(id) != null,
    );
    await permissions.setRule(
      'files.read',
      const ToolPermissionScope.global(),
      ToolPermissionDecision.allow,
    );
    approvals = AiToolApprovalController();
    registry = ToolOperationRegistry();
    operations = ToolOperationManager(
      ownerSessionId: 'owner',
      registry: registry,
      gate: () => ToolPermissionGate(permissions, approvals, enabled: true),
      onChanged: (_) {},
      onRecord: (_) {},
    );
    seen = [];
    render = (_, _, _) async => png;
    final content = NovelContentService(db);
    tools = AiToolManager(
      content,
      workingOverlayService: WorkingOverlayService(
        db,
        content,
        novelActionsService: NovelActionsService(appDb),
      ),
      contentKind: 'screenplay',
      sessionId: 'owner',
      workId: 'work',
      operationHost: ToolOperationHost(
        operations,
        production: () async => ProductionToolHost(
          canvas: canvas,
          images: _Images(),
          audio: _Audio(),
          video: () => throw StateError('No generation'),
          results: ProductionResultService(appDb, (_) async => canvas),
          panorama: PanoramaService(
            canvas,
            render: (image, view, size) {
              seen.add(view);
              return render(image, view, size);
            },
          ),
        ),
      ),
    );
    tools.registerAllTools();
  });
  tearDown(() async {
    tools.dispose();
    operations.dispose();
    registry.dispose();
    approvals.dispose();
    expect(PanoramaTextures.activePaths, 0);
    await db.close();
    await appDb.close();
    await root.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test(
    'explicit views normalize yaw, retain duplicate titles and create real derived outputs',
    () async {
      final response = await run([
        view(450, pitch: 85, fov: 100),
        view(-450, pitch: -85, fov: 30),
      ]);
      expect(response['ok'], true, reason: '$response');
      expect(seen, [
        const PanoramaView(yaw: 90, pitch: 85, fov: 100),
        const PanoramaView(yaw: -90, pitch: -85, fov: 30),
      ]);
      final outputs = response['result']['outputs'] as List;
      expect(outputs.map((o) => o['view_index']), [0, 1]);
      expect(
        (response['result']['views'] as List).map((v) => v['node_id']),
        outputs.map((o) => o['node_id']),
      );
      for (final output in outputs) {
        expect(
          await File('${root.path}/${output['file_path']}').exists(),
          true,
        );
        expect((output['width'], output['height']), (64, 32));
        expect(
          output['node_path'],
          '/episodes/$episode/production/canvas/nodes/${output['node_id']}',
        );
      }
      final edges = await db.select(db.canvasEdges).get();
      expect(
        edges.where(
          (e) => e.type == 'derived_output' && e.sourceNodeId == node.id,
        ),
        hasLength(2),
      );
      expect((await canvas.requireNode(node.id)).mediaAssetId, sourceAsset);
      expect(
        PanoramaView.fromStyle((await canvas.requireNode(node.id)).style),
        const PanoramaView(yaw: 33, pitch: 20, fov: 50),
      );
      expect(await appDb.select(appDb.generationTasks).get(), isEmpty);
      final read = await tools.executeTool(
        name: 'Read',
        input: {
          'path': '/episodes/$episode/production/canvas/nodes/${node.id}',
        },
      );
      expect(read['panorama'], {'yaw': 33.0, 'pitch': 20.0, 'fov': 50.0});
    },
  );

  test(
    'invalid view shapes and four-direction constraints fail before decoding',
    () async {
      for (final views in <List<Map<String, dynamic>>>[
        [],
        [for (var i = 0; i < 5; i++) view(i * 90)],
        [view(0, pitch: 86)],
        [view(0, fov: 29)],
        [view(double.infinity)],
        [
          {'yaw': 0, 'pitch': 0},
        ],
        [view(0), view(90), view(180), view(270, pitch: 10)],
        [view(0), view(90), view(180), view(180)],
        [
          {'yaw': 0, 'pitch': 0, 'fov': 75, 'roll': 0},
        ],
      ]) {
        expect((await run(views))['error_code'], 'invalid_argument');
      }
      expect(
        (await run([view(0)], extra: {'clip_id': 'fake'}))['error_code'],
        'invalid_argument',
      );
      expect(seen, isEmpty);
      expect(PanoramaTextures.activePaths, 0);
    },
  );

  test(
    'four explicit directions preserve per-index failures despite duplicate titles',
    () async {
      render = (_, _, _) async {
        if (seen.length == 2 || seen.length == 3) {
          throw StateError('render failure ${seen.length - 1}');
        }
        return png;
      };
      final response = await run([view(0), view(90), view(180), view(270)]);
      expect(response['ok'], false);
      expect(
        (response['result']['outputs'] as List).map((v) => v['view_index']),
        [0, 3],
      );
      expect(
        (response['result']['failures'] as List).map((v) => v['view_index']),
        [1, 2],
      );
      expect(
        response['result']['failures'][0]['error'],
        contains('render failure 1'),
      );
      expect(
        (response['result']['views'] as List)
            .map((v) => v['node_id'])
            .whereType<String>(),
        hasLength(2),
      );
      expect(seen.map((v) => v.yaw), [0, 90, -180, -90]);
    },
  );

  test(
    'ordinary image is rejected while declared panorama image remains eligible after viewer closes',
    () async {
      await canvas.setPanoramaView(node.id, null);
      expect((await run([view(0)]))['error_code'], 'failed_precondition');
      node = await canvas.addImage(node.canvasId);
      await canvas.adopt(node.id, sourceAsset);
      await db.canvasDao.updateActiveNodeFields(
        node.id,
        const CanvasNodesCompanion(
          style: Value({
            'imageGeneration': {'method': 'panorama'},
          }),
        ),
      );
      expect((await run([view(0)]))['ok'], true);
    },
  );

  test('panorama capture needs no external file permission', () async {
    await permissions.setRule(
      'files.read',
      const ToolPermissionScope.global(),
      ToolPermissionDecision.deny,
    );
    final response = await run([view(0)]);
    expect(response['ok'], true, reason: '$response');
    expect(seen, hasLength(1));
    expect(approvals.pending, isEmpty);
  });

  test(
    'closing panorama mode during capture does not discard the loaded image',
    () async {
      render = (_, _, _) async {
        if (seen.length == 2) {
          await canvas.setPanoramaView(node.id, null);
        }
        return png;
      };
      final response = await run([view(0), view(90), view(180)]);
      expect(response['ok'], true, reason: '$response');
      expect(response['result']['outputs'], hasLength(3));
      expect(seen, hasLength(3));
    },
  );

  test(
    'registered assets survive a placement failure with indexed diagnostics',
    () async {
      canvas.failPlacement = 1;
      final response = await run([view(0), view(90)]);
      expect(response['ok'], false);
      expect(response['result']['outputs'], hasLength(1));
      final saved = (response['result']['registered_assets'] as List).single;
      expect(saved['view_index'], 0);
      expect(await File('${root.path}/${saved['file_path']}').exists(), true);
      expect(
        await appDb.assetDao.getAsset(saved['asset_id'] as String),
        isNotNull,
      );
      expect(response['result']['failures'][0]['stage'], 'placement');
      expect(
        response['result']['failures'][0]['error'],
        contains('simulated placement failure'),
      );
    },
  );

  test(
    'late cancellation retains a committed screenshot without rendering the next view',
    () async {
      canvas.onPlaced = () =>
          operations.cancel(operations.state.runs.single.runId, context);
      final response = await run([view(0), view(90)]);
      expect(response['status'], 'cancelled');
      expect(response['result']['outputs'], hasLength(1));
      expect(seen, hasLength(1));
      final output = response['result']['outputs'][0];
      expect(
        (await canvas.requireNode(output['node_id'] as String)).mediaAssetId,
        output['asset_id'],
      );
    },
  );

  test(
    'panorama capture uses the current adopted source without approval',
    () async {
      await permissions.setRule(
        'files.read',
        const ToolPermissionScope.global(),
        ToolPermissionDecision.ask,
      );
      final file = await File('${root.path}/replacement.png').writeAsBytes(
        img.encodePng(
          img.Image(width: 64, height: 32)..setPixelRgb(0, 0, 255, 0, 0),
        ),
      );
      final replacement = await canvas.library.importFile(
        file,
        name: 'Replacement.png',
        novelId: 'work',
        purpose: AssetPurpose.production_upload,
        cancellation: MediaCancellation(),
      );
      await db.canvasDao.updateActiveNodeFields(
        node.id,
        CanvasNodesCompanion(refId: Value(replacement.id)),
      );
      final response = await run([view(0)]).timeout(const Duration(seconds: 5));
      expect(response['ok'], true, reason: '$response');
      expect(response['result']['source_asset_id'], replacement.id);
      expect(seen, hasLength(1));
      expect(approvals.pending, isEmpty);
    },
  );

  test(
    'cancel waits for current render and retains completed views without starting remaining views',
    () async {
      final started = Completer<void>();
      final native = Completer<Uint8List>();
      render = (_, _, _) async {
        if (seen.length == 2) {
          started.complete();
          return native.future;
        }
        return png;
      };
      final response = await run([view(0), view(90), view(180)], wait: false);
      final id = response['run_id'] as String;
      await Future.any([
        started.future,
        operations
            .wait(id, context)
            .then<void>(
              (done) => throw StateError('Ended before second render: $done'),
            ),
      ]);
      operations.cancel(id, context);
      expect(operations.read(id, context)['status'], 'cancelling');
      native.complete(png);
      final done = await operations.wait(id, context);
      expect(done['status'], 'cancelled');
      expect(done['result']['outputs'], hasLength(1));
      expect(done['result']['failures'], hasLength(2));
      expect(seen, hasLength(2));
    },
  );
}

class _Images implements ImageTaskService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements AudioTaskService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Canvas extends ProductionCanvasService {
  _Canvas(super.shots, super.library, super.novelId);
  int placements = 0;
  int? failPlacement;
  void Function()? onPlaced;
  @override
  Future<CanvasNode> addDerivedOutput(
    String sourceNodeId,
    String assetId, {
    ProductionNodePlacement? placement,
    String? title,
  }) async {
    if (++placements == failPlacement) {
      throw StateError('simulated placement failure');
    }
    final node = await super.addDerivedOutput(
      sourceNodeId,
      assetId,
      placement: placement,
      title: title,
    );
    onPlaced?.call();
    return node;
  }
}
