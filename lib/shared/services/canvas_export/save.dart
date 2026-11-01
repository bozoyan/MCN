// 职责: 将导出产物保存到桌面系统选择的位置，区分取消、选择失败与可能部分写入。
// 关联文件:
//   lib/shared/models/canvas_export.dart
//   lib/desktop/features/canvas/export_button.dart
// 遵循的 Rules:
//   .agents/rules/file-access.md
//   .agents/rules/error-handling.md

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import '../../logger/app_logger.dart';
import '../../models/canvas_export.dart';

final _log = AppLogger.forModule('CanvasExportSave');

enum CanvasExportSaveStatus { saved, cancelled, failed }

class CanvasExportSaveResult {
  const CanvasExportSaveResult(this.status, {this.mayHavePartialFile = false});
  final CanvasExportSaveStatus status;
  final bool mayHavePartialFile;
}

typedef CanvasExportLocationPicker =
    Future<String?> Function(String suggestedName, CanvasExportFormat format);
typedef CanvasExportFileWriter =
    Future<void> Function(String path, Uint8List bytes);

String canvasExportFileName(String title, CanvasExportFormat format) {
  final extension = '.${format.name}';
  final budget = 255 - utf8.encode(extension).length;
  var base = title
      .replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  base = _truncateFileStem(base, budget).replaceAll(RegExp(r'[. ]+$'), '');
  if (base.isEmpty || base == '.' || base == '..') {
    base = 'Canvas';
  }
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(base)) {
    base = '_$base';
  }
  // 保留名可能补了下划线；重新按总预算截断，并清理新的尾点/空格。
  base = _truncateFileStem(base, budget).replaceAll(RegExp(r'[. ]+$'), '');
  return '$base$extension';
}

String _truncateFileStem(String text, int maxBytes) {
  final result = StringBuffer();
  var bytes = 0;
  for (final rune in text.runes) {
    final scalar = String.fromCharCode(rune);
    final length = utf8.encode(scalar).length;
    if (bytes + length > maxBytes) {
      break;
    }
    result.write(scalar);
    bytes += length;
  }
  return result.toString();
}

Future<CanvasExportSaveResult> saveCanvasExport(
  CanvasExportArtifact artifact, {
  CanvasExportLocationPicker chooseLocation = _chooseLocation,
  CanvasExportFileWriter writeFile = _writeFile,
}) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    throw const CanvasExportException('unsupported_platform');
  }
  _log.info('export platform=${Platform.operatingSystem} stage=select');
  String? path;
  try {
    path = await chooseLocation(
      canvasExportFileName(artifact.title, artifact.format),
      artifact.format,
    );
  } catch (error) {
    _log.warning(
      'export stage=select result=failed errorType=${error.runtimeType}',
    );
    return const CanvasExportSaveResult(CanvasExportSaveStatus.failed);
  }
  if (path == null) {
    _log.info('export stage=select result=cancelled');
    return const CanvasExportSaveResult(CanvasExportSaveStatus.cancelled);
  }
  try {
    // 桌面选择器授予普通文件路径；覆盖确认由系统负责，无 App 临时副本。
    await writeFile(path, artifact.bytes);
    _log.info(
      'export stage=write result=success files=1 bytes=${artifact.bytes.length}',
    );
    return const CanvasExportSaveResult(CanvasExportSaveStatus.saved);
  } catch (error) {
    // 目标可能已有部分内容；不能把删除用户文件视为回滚。
    _log.warning(
      'export stage=write result=failed files=1 errorType=${error.runtimeType}',
    );
    return const CanvasExportSaveResult(
      CanvasExportSaveStatus.failed,
      mayHavePartialFile: true,
    );
  }
}

Future<void> _writeFile(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<String?> _chooseLocation(String name, CanvasExportFormat format) async =>
    (await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(
          label: format.name.toUpperCase(),
          extensions: [format.name],
          uniformTypeIdentifiers: [
            format == CanvasExportFormat.zip
                ? 'public.zip-archive'
                : 'public.json',
          ],
        ),
      ],
    ))?.path;
