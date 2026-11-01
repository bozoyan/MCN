// 职责: 编排本次修订的逐帧输出、规格校验、取消与运行内暂停。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/services/director/renderer.dart
//   lib/shared/services/director/storage.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../models/director/sampling.dart';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/renderer.dart';
import 'package:reveric/shared/services/director/storage.dart';

enum OutputState {
  idle,
  preparing,
  rendering,
  packaging,
  completed,
  cancelling,
  cancelled,
  failed,
  paused,
}

class ExportTaskOrchestrator extends ChangeNotifier {
  OutputState state = OutputState.idle;
  String? errorCode, operationId;
  Json? diagnostic;
  Directory? result;
  int written = 0, total = 0;
  bool _cancel = false, _pause = false;
  bool get cancelled => _cancel;
  bool registersAssets = false;
  Future<void> Function()? cancelEncoding;
  Completer<void>? _resume;
  bool get active => [
    OutputState.preparing,
    OutputState.rendering,
    OutputState.packaging,
    OutputState.cancelling,
    OutputState.paused,
  ].contains(state);
  void cancel() {
    if (active) {
      _cancel = true;
      unawaited(cancelEncoding?.call());
      state = OutputState.cancelling;
      _resume?.complete();
      _resume = null;
      notifyListeners();
    }
  }

  void pause() {
    if (active) {
      _pause = true;
    }
  }

  void resume() {
    _pause = false;
    _resume?.complete();
    _resume = null;
  }

  Future<void> _checkpoint() async {
    if (_cancel) {
      throw const _Cancelled();
    }
    if (_pause) {
      final previous = state;
      final waiting = Completer<void>();
      _resume = waiting;
      state = OutputState.paused;
      notifyListeners();
      if (!_pause || _cancel) {
        if (!waiting.isCompleted) {
          waiting.complete();
        }
      }
      await waiting.future;
      if (_cancel) {
        throw const _Cancelled();
      }
      state = previous;
      notifyListeners();
    }
  }

  Future<void> run({
    required DirectorStorage workspace,
    required DirectorDocument document,
    required FrameRenderer renderer,
    required String cameraMode,
    String? cameraId,
    int? singleFrame,
    int startFrame = 0,
    int? endFrame,
    Future<int> Function(String)? spaceProbe,
    String? savedRevisionId,
    Future<void> Function(Directory, Json)? onRendered,
  }) async {
    if (active) {
      throw StateError('output_busy');
    }
    _cancel = false;
    registersAssets = onRendered != null;
    _pause = false;
    written = 0;
    errorCode = null;
    diagnostic = null;
    result = null;
    operationId = const Uuid().v4();
    state = OutputState.preparing;
    notifyListeners();
    final id = operationId!,
        temp = Directory('${workspace.temporary.path}/$id');
    final start = singleFrame ?? startFrame,
        end = singleFrame == null
            ? (endFrame ?? document.durationFrames)
            : singleFrame + 1;
    total = end - start;
    final frames = <Json>[];
    try {
      choice(cameraMode, 'camera_mode', ['sequence', 'fixed']);
      if (cameraMode == 'fixed'
          ? cameraId == null || document.camera(cameraId) == null
          : cameraId != null) {
        invalid(
          'camera_id',
          cameraMode == 'fixed' ? 'camera_required' : 'fixed_only',
        );
      }
      if (start < 0 ||
          start > document.durationFrames ||
          end <= start ||
          (singleFrame == null
              ? end > document.durationFrames
              : end > document.durationFrames + 1)) {
        invalid('frames', 'invalid_interval');
      }
      await temp.create(recursive: true);
      final required =
          (document.width * document.height * 4 * total * 3 * 1.2).ceil() +
          64 * 1024 * 1024;
      final probe = spaceProbe ?? workspace.availableBytes;
      for (final path in [temp.path, workspace.root.path]) {
        int available;
        try {
          available = await probe(path);
        } catch (_) {
          throw StateError('storage_probe_failed');
        }
        if (available < required) {
          throw StateError('storage_full');
        }
      }
      animationPlan(document).audit();
      state = OutputState.rendering;
      notifyListeners();
      for (var index = written; index < total; index++) {
        await _checkpoint();
        final actualCamera = cameraMode == 'sequence'
            ? document.cameraAt(start + index)
            : cameraId!;
        final bytes = await renderer.capture(
          document,
          start + index,
          actualCamera,
        );
        final name = 'frame_${index.toString().padLeft(6, '0')}.png';
        await File('${temp.path}/$name').writeAsBytes(bytes, flush: true);
        frames.add({
          'index': index,
          'sourceFrame': start + index,
          'cameraId': actualCamera,
          'timeNumerator': start + index,
          'timeDenominator': document.fps,
          'file': name,
        });
        written = index + 1;
        notifyListeners();
      }
      await _checkpoint();
      state = OutputState.packaging;
      notifyListeners();
      final manifest = {
        'format': 'reveric.director.frames',
        'version': 1,
        'operationId': id,
        'documentId': document.id,
        'documentRevision': document.revision,
        'savedRevisionId': savedRevisionId,
        'cameraMode': cameraMode,
        'cameraId': cameraId,
        'kind': singleFrame == null ? 'motion' : 'still',
        'width': document.width,
        'height': document.height,
        'fps': document.fps,
        'startFrame': start,
        'endFrameExclusive': end,
        'frameCount': total,
        'frames': frames,
      };
      await File(
        '${temp.path}/manifest.json',
      ).writeAsString(jsonEncode(manifest), flush: true);
      final zip = ZipFileEncoder();
      zip.create('${temp.path}/frames.zip');
      try {
        for (final file in [
          'manifest.json',
          ...frames.map((f) => f['file'] as String),
        ]) {
          await _checkpoint();
          await zip.addFile(File('${temp.path}/$file'), file);
        }
      } finally {
        zip.close();
      }
      final completed = Directory('${workspace.root.path}/completed');
      await completed.create(recursive: true);
      final staging = Directory('${completed.path}/$id.staging');
      await staging.create(recursive: true);
      for (final entity in temp.listSync().whereType<File>()) {
        await _checkpoint();
        final name = entity.uri.pathSegments.last;
        await entity.copy('${staging.path}/$name');
      }
      result = await staging.rename('${completed.path}/$id');
      if (onRendered != null) {
        await onRendered(result!, manifest);
      }
      state = OutputState.completed;
    } on _Cancelled {
      state = OutputState.cancelled;
    } catch (error, stack) {
      state = _cancel ? OutputState.cancelled : OutputState.failed;
      final message = error is StateError ? error.message.toString() : '';
      if (error is DocumentError) {
        diagnostic = {
          'frameTargetProperty': error.path,
          'reason': error.reason,
        };
      }
      errorCode = error is DocumentError
          ? 'validation_failed'
          : ['storage_full', 'storage_probe_failed'].contains(message)
          ? message
          : error is FileSystemException
          ? (error.osError?.errorCode == 28
                ? 'storage_full'
                : [1, 13].contains(error.osError?.errorCode)
                ? 'access_denied'
                : 'file_write_failed')
          : 'capture_failed';
      debugPrint(
        'director output $id frame=$written code=$errorCode type=${error.runtimeType}\n$stack',
      );
    } finally {
      renderer.dispose();
      if ([
        OutputState.completed,
        OutputState.cancelled,
        OutputState.failed,
      ].contains(state)) {
        try {
          if (await temp.exists()) {
            await temp.delete(recursive: true);
          }
        } catch (cleanupError) {
          debugPrint(
            'director temporary cleanup failed: ${cleanupError.runtimeType}',
          );
        }
      }
      notifyListeners();
    }
  }

  /// 某个机位已完成的输出版本，按完成时间升序；版本号即列表序号 + 1，
  /// 预演与静帧分别计数。
  static Future<List<Json>> completedFor(
    DirectorStorage workspace,
    String documentId,
    String? cameraId,
  ) async {
    final dir = Directory('${workspace.root.path}/completed');
    if (!await dir.exists()) {
      return [];
    }
    final found = <(DateTime, Json)>[];
    await for (final entry in dir.list()) {
      final file = File('${entry.path}/manifest.json');
      if (entry is! Directory ||
          entry.path.endsWith('.staging') ||
          !await file.exists()) {
        continue;
      }
      final j = jsonDecode(await file.readAsString()) as Json;
      if (j['documentId'] == documentId &&
          j['cameraMode'] == (cameraId == null ? 'sequence' : 'fixed') &&
          j['cameraId'] == cameraId) {
        found.add((await file.lastModified(), j));
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    final counts = <String, int>{};
    return [
      for (final (at, j) in found)
        {
          'cameraMode': j['cameraMode'],
          'cameraId': j['cameraId'],
          'operationId': j['operationId'],
          'kind': j['kind'],
          'version': counts[j['kind']] = (counts[j['kind']] ?? 0) + 1,
          'at': at.toIso8601String(),
        },
    ];
  }
}

class _Cancelled {
  const _Cancelled();
}
