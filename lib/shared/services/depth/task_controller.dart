// 职责: 持有应用级串行深度任务，记录中断状态并将结果入库与挂接画布。
// 关联文件:
//   lib/shared/services/depth/orchestrator.dart
//   lib/shared/services/depth/model_service.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/providers/depth.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../logger/app_logger.dart';
import '../../models/asset_purpose.dart';
import '../../models/production/media.dart';
import '../production/canvas_service.dart';
import '../production/ffmpeg_runner.dart';
import 'model.dart';
import 'model_service.dart';
import 'native_runner.dart';
import 'orchestrator.dart';

final _log = AppLogger.forModule('Depth');

class DepthTask {
  const DepthTask({
    required this.id,
    required this.novelId,
    required this.nodeId,
    required this.stage,
    this.progress,
    this.failure,
    this.assetId,
    this.outputNodeId,
  });
  final String id, novelId, nodeId;
  final DepthStage stage;
  final double? progress;
  final DepthFailure? failure;
  final String? assetId, outputNodeId;
  bool get active => stage.index <= DepthStage.saving.index;
  Map<String, dynamic> toJson() => {
    'id': id,
    'novelId': novelId,
    'nodeId': nodeId,
    'stage': stage.name,
    'failure': failure?.name,
    'assetId': assetId,
    'outputNodeId': outputNodeId,
  };
  factory DepthTask.fromJson(Map<String, dynamic> json) => DepthTask(
    id: json['id'] as String,
    novelId: json['novelId'] as String,
    nodeId: json['nodeId'] as String,
    stage: DepthStage.values.byName(json['stage'] as String),
    failure: json['failure'] == null
        ? null
        : DepthFailure.values.byName(json['failure'] as String),
    assetId: json['assetId'] as String?,
    outputNodeId: json['outputNodeId'] as String?,
  );
}

class DepthTaskController {
  DepthTaskController({
    required this.root,
    required this.models,
    required this.native,
    required this.resolve,
    required this.release,
    required this.ffmpeg,
  });
  final Directory root;
  final DepthModelService models;
  final DepthNativeRunner native;
  final FfmpegRunner ffmpeg;
  final Future<ProductionCanvasService?> Function(String novelId) resolve;
  final Future<void> Function(ProductionCanvasService service) release;
  final state = ValueNotifier<DepthTask?>(null);
  MediaCancellation? _token;
  Future<void>? _initialization;
  Future<void> _writes = Future.value();
  Future<void>? _running;
  bool _disposed = false;
  bool _interrupted = false;
  File get _journal => File(p.join(root.path, 'last-task.json'));

  Future<void> initialize() => _initialization ??= _recover();
  Future<void> _recover() async {
    await root.create(recursive: true);
    if (!await _journal.exists()) {
      return;
    }
    final task = DepthTask.fromJson(
      jsonDecode(await _journal.readAsString()) as Map<String, dynamic>,
    );
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(task.id)) {
      throw const DepthException(DepthFailure.storage_failed);
    }
    state.value = task.active
        ? DepthTask(
            id: task.id,
            novelId: task.novelId,
            nodeId: task.nodeId,
            stage: task.assetId == null
                ? DepthStage.interrupted
                : DepthStage.complete,
            assetId: task.assetId,
            outputNodeId: task.outputNodeId,
          )
        : task;
    // A crashed host has closed the native process's stdin. Only the workspace
    // explicitly recorded by this task is eligible for cleanup.
    final work = Directory(p.join(root.path, 'work-${task.id}'));
    if (await work.exists()) {
      await work.delete(recursive: true);
    }
    await _persist();
  }

  Future<void> _persist() {
    final value = state.value!.toJson();
    final write = _writes.then((_) async {
      final part = File('${_journal.path}.part');
      await part.writeAsString(jsonEncode(value), flush: true);
      await part.rename(_journal.path);
    });
    _writes = write.catchError((Object error, StackTrace stack) {
      _log.error('task journal write failed', error: error, stackTrace: stack);
    });
    return write;
  }

  Future<void> start(String novelId, String nodeId) async {
    await initialize();
    if (_disposed) {
      throw StateError('Depth controller is disposed');
    }
    if (_running != null || state.value?.active == true) {
      throw const MediaException(MediaFailure.busy);
    }
    final token = MediaCancellation();
    _interrupted = false;
    _token = token;
    state.value = DepthTask(
      id: const Uuid().v4(),
      novelId: novelId,
      nodeId: nodeId,
      stage: DepthStage.preparing,
    );
    final run = _run(token);
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
      _token = null;
    }
  }

  Future<void> _run(MediaCancellation token) async {
    final task = state.value!;
    ProductionCanvasService? canvas;
    Directory? workspace;
    String? resultAsset, resultNode;
    void report(DepthStage stage, double? progress) {
      if (_disposed) {
        return;
      }
      state.value = DepthTask(
        id: task.id,
        novelId: task.novelId,
        nodeId: task.nodeId,
        stage: stage,
        progress: progress,
        assetId: resultAsset,
        outputNodeId: resultNode,
      );
    }

    try {
      await _persist();
      if (!await File(native.executable).exists()) {
        throw const DepthException(DepthFailure.unavailable);
      }
      canvas = await resolve(task.novelId);
      if (canvas == null) {
        throw const DepthException(DepthFailure.invalid_video);
      }
      final source = await canvas.videoSource(task.nodeId);
      final input = canvas.library.resolve(source);
      final model = await models.prepare(token, report);
      checkDepthCancellation(token);
      workspace = await Directory(
        p.join(root.path, 'work-${task.id}'),
      ).create();
      final media = await DepthOrchestrator().run(
        input: input,
        model: model,
        workspace: workspace,
        ffmpeg: ffmpeg,
        native: native,
        token: token,
        progress: report,
      );
      checkDepthCancellation(token);
      report(DepthStage.saving, null);
      final asset = await canvas.library.importFile(
        media.file,
        name: '${p.basenameWithoutExtension(source.name)}_depth.mp4',
        novelId: task.novelId,
        purpose: AssetPurpose.production_video_tool,
        addToLibrary: true,
        cancellation: token,
      );
      resultAsset = asset.id;
      report(DepthStage.saving, null);
      await _persist();
      // Validate the source and attach in the same transaction. If it changed,
      // the imported result remains available in the library.
      try {
        await canvas.db.transaction(() async {
          if ((await canvas!.videoSource(task.nodeId)).id == source.id) {
            resultNode = (await canvas!.addDerivedOutput(
              task.nodeId,
              asset.id,
            )).id;
          }
        });
      } catch (error, stack) {
        _log.error(
          'result kept in library; source attachment failed',
          error: error,
          stackTrace: stack,
        );
      }
      report(DepthStage.complete, 1);
    } catch (error, stack) {
      _log.error(
        'task failed stage=${state.value?.stage.name} type=${error.runtimeType}',
        error: error is FileSystemException ? error.osError : error,
        stackTrace: stack,
      );
      if (resultAsset != null) {
        report(DepthStage.complete, 1);
      } else if (token.cancelled ||
          error is MediaException && error.reason == MediaFailure.cancelled) {
        report(
          _interrupted ? DepthStage.interrupted : DepthStage.cancelled,
          null,
        );
      } else {
        state.value = DepthTask(
          id: task.id,
          novelId: task.novelId,
          nodeId: task.nodeId,
          stage: DepthStage.failed,
          failure: error is DepthException
              ? error.reason
              : error is FileSystemException
              ? DepthFailure.storage_failed
              : DepthFailure.native_failed,
        );
      }
    } finally {
      token.onProgress = null;
      if (workspace != null && await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
      if (canvas != null) {
        await release(canvas);
      }
      await _persist();
    }
  }

  Future<void> cancel() async {
    await _token?.cancel();
  }

  Future<void> stop() async {
    _interrupted = true;
    await cancel();
    await _running;
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancel();
    await _running;
    await _writes;
    await _initialization;
    state.dispose();
  }
}
