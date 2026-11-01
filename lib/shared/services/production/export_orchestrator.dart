// 职责: 冻结成片顺序及采用资产，流式导出视频和逐段对应提示词表并报告部分完成。
// 关联文件:
//   lib/shared/services/storyboard/export.dart
//   lib/shared/services/production/canvas_service.dart
// 遵循的 Rules:
//   .agents/rules/file-access.md
//   .agents/rules/service-naming.md
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../logger/app_logger.dart';
import '../storyboard/export.dart';
import 'canvas_service.dart';
import 'ffmpeg_runner.dart';

final _log = AppLogger.forModule('ProductionExport');

class ProductionExportReport {
  const ProductionExportReport(
    this.directory,
    this.completed,
    this.remaining, {
    this.error,
    this.cancelled = false,
    this.unreadable = const [],
  });
  final String? directory;
  final List<String> completed;
  final List<String> remaining;
  final Object? error;
  final bool cancelled;
  final List<String> unreadable;
  bool get complete => remaining.isEmpty && error == null && !cancelled;
}

class ProductionExportOrchestrator {
  Future<ProductionExportReport> run({
    required ProductionCanvasService service,
    required List<StoryboardExportRow> rows,
    required Directory destination,
    required List<String> headings,
    required String Function(String) statusLabel,
    required MediaCancellation cancellation,
  }) async {
    final sources = <String, File>{};
    final names = <String, String>{};
    final missing = <String>[];
    final completed = <String>[];
    Directory? folder;
    try {
      if (rows.isEmpty) {
        throw ArgumentError('Select at least one segment');
      }
      final episodeId = rows.first.shot.episodeId;
      if (rows.any(
            (r) =>
                r.shot.sceneId == null ||
                r.shot.kind != 'video' ||
                r.shot.episodeId != episodeId,
          ) ||
          rows.map((r) => r.shot.id).toSet().length != rows.length) {
        throw ArgumentError(
          'Export requires distinct segments from one episode',
        );
      }
      final ordered = await service.shots.episodeShots(episodeId);
      final order = {for (var i = 0; i < ordered.length; i++) ordered[i].id: i};
      if (rows.any((r) => !order.containsKey(r.shot.id))) {
        throw StateError('A selected segment is no longer available');
      }
      rows = [...rows]
        ..sort((a, b) => order[a.shot.id]!.compareTo(order[b.shot.id]!));
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        try {
          final id = row.shot.adoptedAssetId;
          if (id == null) {
            throw StateError('No selected video');
          }
          final asset = await service.requireAsset(id, type: 'video');
          final media = await service.requireFile(asset.path!, type: 'video');
          final file = File(service.library.resolvePath(media.path));
          sources[row.shot.id] = file;
          final title = row.shot.title
              .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
              .trim();
          names[row.shot.id] =
              '${(i + 1).toString().padLeft(4, '0')}_${title.isEmpty ? 'segment' : title.substring(0, title.length.clamp(0, 80))}${p.extension(file.path)}';
        } catch (error, stack) {
          missing.add(row.number);
          _log.error(
            'unreadable shot=${row.shot.id}',
            error: error,
            stackTrace: stack,
          );
        }
      }
      if (missing.isNotEmpty) {
        return ProductionExportReport(
          null,
          const [],
          rows.map((r) => r.number).toList(),
          unreadable: missing,
          error: StateError('Missing videos'),
        );
      }
      if (cancellation.cancelled) {
        return ProductionExportReport(
          null,
          const [],
          rows.map((r) => r.number).toList(),
          cancelled: true,
        );
      }
      // createTemp is atomic and never reuses an existing directory.
      folder = await destination.createTemp('production-');
      for (final row in rows) {
        if (cancellation.cancelled) {
          break;
        }
        final target = File(p.join(folder.path, names[row.shot.id]!));
        final sink = target.openWrite();
        try {
          await for (final chunk in sources[row.shot.id]!.openRead()) {
            if (cancellation.cancelled) {
              break;
            }
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (cancellation.cancelled) {
          break;
        }
        completed.add(row.number);
      }
      final exported = rows.where((r) => completed.contains(r.number)).toList();
      for (final csv in [false, true]) {
        await File(
          p.join(folder.path, 'prompts.${csv ? 'csv' : 'md'}'),
        ).writeAsString(
          exportStoryboard(
            exported,
            csv: csv,
            headings: headings,
            statusLabel: statusLabel,
            videoFiles: names,
          ),
          flush: true,
        );
      }
      return ProductionExportReport(
        folder.path,
        completed,
        rows
            .where((r) => !completed.contains(r.number))
            .map((r) => r.number)
            .toList(),
        cancelled: cancellation.cancelled,
      );
    } catch (error, stack) {
      _log.error(
        'failed completed=${completed.length}',
        error: error,
        stackTrace: stack,
      );
      return ProductionExportReport(
        folder?.path,
        completed,
        rows
            .where((r) => !completed.contains(r.number))
            .map((r) => r.number)
            .toList(),
        error: error,
      );
    }
  }
}
