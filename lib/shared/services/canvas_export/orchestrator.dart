// 职责: 在单个只读事务中采集画布快照，校验图结构后交给 isolate 编码。
// 关联文件:
//   lib/shared/models/canvas_export.dart
//   lib/shared/services/canvas_export/resources.dart
//   lib/shared/services/canvas_export/format.dart
//   lib/shared/services/canvas_export/validate.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md

import 'dart:isolate';
import '../../database/novel_content_database.dart';
import '../../logger/app_logger.dart';
import '../../models/canvas_export.dart';
import '../../models/canvas_export_preview.dart';
import 'format.dart';
import 'resources.dart';
import 'validate.dart';

final _log = AppLogger.forModule('CanvasExport');

class CanvasExportOrchestrator {
  Future<CanvasExportSnapshot> snapshot({
    required NovelContentDatabase database,
    required String canvasId,
    required String workId,
    required String contentKind,
    DateTime? exportedAt,
  }) async {
    _log.info('export stage=snapshot');
    try {
      final result = await database.transaction(() async {
        final time = (exportedAt ?? DateTime.now()).toUtc();
        final canvas = await database.canvasDao.getCanvasById(canvasId);
        if (canvas == null || canvas.kind == canvasKindProduction) {
          throw const CanvasExportException('canvas_not_found');
        }
        final nodes = await database.canvasDao.getNodesByCanvas(canvasId);
        final edges = await database.canvasDao.getEdgesByCanvas(canvasId);
        if (nodes.isEmpty) {
          throw const CanvasExportException('empty_canvas');
        }
        final resources = await collectCanvasResources(database, nodes);
        return buildCanvasExportSnapshot(
          canvas: canvas,
          nodes: nodes,
          edges: edges,
          resources: resources,
          workId: workId,
          contentKind: contentKind,
          exportedAt: time,
        );
      });
      _log.info(
        'export stage=snapshot result=success nodes=${result.nodes.length} edges=${result.edges.length} resources=${result.resources.length} issues=${result.issues.length}',
      );
      return result;
    } catch (error) {
      _log.warning(
        'export stage=snapshot result=failed errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }

  Future<CanvasExportArtifact> encode(
    CanvasExportSnapshot snapshot,
    CanvasExportFormat format, {
    CanvasExportPreview? preview,
  }) async {
    if (snapshot.hasErrors) {
      throw const CanvasExportException('invalid_snapshot');
    }
    _log.info('export stage=encode format=${format.name}');
    try {
      final result = await _encodeInIsolate(snapshot, format, preview);
      _log.info(
        'export stage=encode result=success bytes=${result.bytes.length}',
      );
      return result;
    } catch (error) {
      _log.warning(
        'export stage=encode result=failed errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }
}

// 此闭包只持有不可变导出值，不捕获数据库、Widget 或 Orchestrator 的调用栈。
Future<CanvasExportArtifact> _encodeInIsolate(
  CanvasExportSnapshot snapshot,
  CanvasExportFormat format,
  CanvasExportPreview? preview,
) => Isolate.run(() => encodeCanvasExport(snapshot, format, preview: preview));
