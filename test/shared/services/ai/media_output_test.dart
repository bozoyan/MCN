// 职责: 验证媒体交付副本独立于源文件且不会覆盖既有交付。
// 关联文件:
//   lib/shared/services/ai/media/output_delivery.dart
//   lib/shared/services/ai/files/session_files.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/services/ai/files/session_files.dart';
import 'package:reveric/shared/services/ai/media/output_delivery.dart';
import 'package:reveric/shared/services/ai/tool_operations.dart';
import 'package:reveric/shared/models/tool_permission.dart';

void main() {
  test(
    'delivery retains a session snapshot and rejects a later overwrite',
    () async {
      final root = await Directory.systemTemp.createTemp('media-delivery-');
      addTearDown(() => root.delete(recursive: true));
      final files = SessionFiles(root: root.path, novelId: 'work');
      final delivery = MediaOutputDelivery(files);
      final source = File('${root.path}/source.mp4')
        ..writeAsBytesSync([1, 2, 3]);
      final token = AgentCancellationController();
      final op = ToolOperationContext(token.token, ({taskId, progress}) {}, {});
      final target = await delivery.target('session', 'videos/export.mp4');
      final result = await delivery.deliver('session', source, target, op);
      await source.writeAsBytes([9]);
      expect(
        await (await files.resolve(
          result['snapshot_path'] as String,
        )).readAsBytes(),
        [1, 2, 3],
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
      await expectLater(
        delivery.target('session', 'videos/export.mp4'),
        throwsA(isA<ToolOperationException>()),
      );
      final failed = await delivery.deliver('session', source, target, op);
      expect(failed['delivered'], false);
      expect(
        await (await files.resolve(
          failed['snapshot_path'] as String,
        )).readAsBytes(),
        [9],
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
    },
  );
}
