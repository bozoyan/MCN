// 职责: 将媒体输出复制到会话快照并交付到指定路径，拒绝覆盖已有文件。
// 关联文件:
//   lib/shared/services/ai/files/session_files.dart
//   lib/shared/services/ai/ffmpeg/outputs.dart
//   lib/shared/services/ai/tool_operations.dart
import 'dart:io';
import '../../../logger/app_logger.dart';
import '../files/session_files.dart';
import '../ffmpeg/outputs.dart';
import '../tool_operations.dart';

final _log = AppLogger.forModule('MediaDelivery');

class MediaOutputDelivery {
  MediaOutputDelivery(this.files);
  final SessionFiles files;
  Future<File> target(String session, String path) =>
      FfmpegOutputs.resolveTarget(files, session, path);
  Future<Map<String, dynamic>> deliver(
    String session,
    File source,
    File destination,
    ToolOperationContext operation,
  ) async {
    operation.checkCancelled();
    final snapshot = await files.copy(
      session,
      source,
      cancelled: () => operation.cancellation.isCancellationRequested,
    );
    var owned = false;
    try {
      await destination.parent.create(recursive: true);
      operation.checkCancelled();
      await destination.create(exclusive: true);
      owned = true;
      final sink = destination.openWrite();
      try {
        await for (final chunk in snapshot.openRead()) {
          operation.checkCancelled();
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      operation.checkCancelled();
    } on FileSystemException catch (error) {
      _log.warning('delivery failed os_code=${error.osError?.errorCode}');
      if (owned && await destination.exists()) {
        await destination.delete();
      }
      return {
        'delivered': false,
        'file_path': files.reference(snapshot),
        'snapshot_path': files.reference(snapshot),
        'requested_path': destination.path,
        'error_code': 'file_delivery_failed',
        'error':
            'The output is saved in the session but could not be delivered to the requested path.',
      };
    } catch (_) {
      if (owned && await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
    return {
      'delivered': true,
      'file_path': files.reference(destination),
      'snapshot_path': files.reference(snapshot),
      'bytes': await destination.length(),
    };
  }
}
