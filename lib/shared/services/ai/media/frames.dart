// 职责: 保存检查拼图并生成模型可直接查看的会话图片结果。
// 关联文件:
//   lib/shared/services/production/contact_sheet.dart
//   lib/shared/services/ai/files/session_files.dart
import '../../production/contact_sheet.dart';
import '../../production/ffmpeg_runner.dart';
import '../../../models/production/media.dart';
import '../files/session_files.dart';

Future<Map<String, dynamic>> deliverFrameSheet(
  SessionFiles files,
  String sessionId,
  ContactSheet sheet,
  MediaCancellation cancellation,
) async {
  final file = await files.allocate(sessionId, '.jpg');
  try {
    if (cancellation.cancelled) {
      throw const MediaException(MediaFailure.cancelled);
    }
    await file.writeAsBytes(sheet.jpeg, flush: true);
    if (cancellation.cancelled) {
      throw const MediaException(MediaFailure.cancelled);
    }
    final path = files.reference(file);
    return {
      'ok': true,
      'width': sheet.width,
      'height': sheet.height,
      'cells': sheet.cells,
      'content_format': 'session_files_v1',
      'file_path': path,
      'content': [
        {'type': 'image', 'file_path': path, 'mime_type': 'image/jpeg'},
      ],
    };
  } catch (_) {
    if (await file.exists()) {
      await file.delete();
    }
    rethrow;
  }
}
