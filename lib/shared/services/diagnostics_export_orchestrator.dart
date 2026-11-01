// 职责: 把反馈上下文、当前日志与最近崩溃转储打包成 zip，并交给系统保存或分享。
// 关联文件:
//   lib/shared/widgets/ai/chat/feedback_dialog.dart
//   lib/shared/services/crash_reporting/native_crash_reporting.dart
//   lib/shared/logger/log_manager.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/file-access.md
//   .agents/rules/error-handling.md

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../logger/app_logger.dart';
import 'crash_reporting/native_crash_reporting.dart';

final _log = AppLogger.forModule('DiagnosticsExport');

enum DiagnosticsExportStatus { saved, shared, cancelled }

/// 诊断包只落在本机，由用户决定是否、以及通过什么渠道发送。
class DiagnosticsExportOrchestrator {
  static const _cacheDirName = 'reveric_diagnostics_exports';

  /// 打包 `feedback.json`，以及存在时的 `latest.log` 与 `latest.dump`。
  Future<Uint8List> buildBundle({
    required Map<String, dynamic> feedback,
    required String? logPath,
  }) async {
    final logFile = logPath == null ? null : File(logPath);
    final logBytes = logFile != null && await logFile.exists()
        ? await logFile.readAsBytes()
        : null;
    final dump = logFile == null
        ? null
        : await NativeCrashReporting.prepareLatestDump(
            p.join(logFile.parent.parent.path, 'crashes'),
          );
    final dumpBytes = await dump?.readAsBytes();
    final feedbackBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(feedback),
    );
    return Isolate.run(() {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('feedback.json', feedbackBytes));
      if (logBytes != null) {
        archive.addFile(ArchiveFile.bytes('latest.log', logBytes));
      }
      if (dumpBytes != null) {
        archive.addFile(ArchiveFile.bytes('latest.dump', dumpBytes));
      }
      return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    });
  }

  /// 桌面弹系统保存对话框；移动端写入 App 临时目录后走系统分享面板。
  Future<DiagnosticsExportStatus> export({
    required Map<String, dynamic> feedback,
    required String? logPath,
    required String fileName,
  }) async {
    var stage = 'bundle';
    try {
      final bytes = await buildBundle(feedback: feedback, logPath: logPath);
      if (Platform.isAndroid || Platform.isIOS) {
        stage = 'share';
        final cacheRoot = Directory(
          p.join((await getTemporaryDirectory()).path, _cacheDirName),
        );
        await cacheRoot.create(recursive: true);
        final file = File(p.join(cacheRoot.path, fileName));
        await file.writeAsBytes(bytes, flush: true);
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/zip')],
            fileNameOverrides: [fileName],
            sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
          ),
        );
        _log.info('exported via share bytes=${bytes.length}');
        return result.status == ShareResultStatus.dismissed
            ? DiagnosticsExportStatus.cancelled
            : DiagnosticsExportStatus.shared;
      }
      stage = 'save';
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'ZIP',
            extensions: ['zip'],
            uniformTypeIdentifiers: ['public.zip-archive'],
          ),
        ],
      );
      if (location == null) {
        return DiagnosticsExportStatus.cancelled;
      }
      await File(location.path).writeAsBytes(bytes, flush: true);
      _log.info('exported via save dialog bytes=${bytes.length}');
      return DiagnosticsExportStatus.saved;
    } catch (error, stackTrace) {
      _log.error(
        'diagnostics export failed stage=$stage '
        'platform=${Platform.operatingSystem}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
