// 职责: 按切镜或固定机位渲染指定帧，拼成带帧号与机位序号标注的检查拼图。
// 关联文件:
//   lib/shared/services/director/renderer.dart
//   lib/shared/models/director/document.dart
//   lib/shared/services/ai/stagings_run_command_handler.dart
//   lib/shared/services/ai/files/attachments.dart
import 'dart:typed_data';
import '../../models/director/document.dart';
import 'renderer.dart';

export '../production/contact_sheet.dart'
    show ContactSheet, contactSheetMaxFrames;
import '../production/contact_sheet.dart';

/// [cameraId] 为空时每帧使用该帧生效的切镜机位。
Future<ContactSheet> renderContactSheet(
  DirectorDocument document,
  List<int> frames, {
  String? cameraId,
  required FrameRenderer renderer,
}) async {
  final cameras = document.cameras.map((c) => c['id']).toList();
  final captures = <Uint8List>[], cells = <Json>[];
  try {
    for (final frame in frames) {
      final camera = cameraId ?? document.cameraAt(frame);
      captures.add(await renderer.capture(document, frame, camera));
      final label = 'F$frame C${cameras.indexOf(camera) + 1}';
      cells.add({
        'label': label,
        'frame': frame,
        'camera_id': camera,
        'camera_name': document.camera(camera)?['name'],
      });
    }
  } finally {
    renderer.dispose();
  }
  return composeContactSheet(captures, cells, document.width, document.height);
}
