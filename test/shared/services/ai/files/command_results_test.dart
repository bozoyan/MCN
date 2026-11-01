// 职责: 验证作品相对命令结果仍能持久化、重放图片并收集备份副本。
// 关联文件:
//   lib/shared/services/ai/files/attachments.dart
//   lib/shared/services/ai/files/command_paths.dart
//   lib/shared/services/ai/agent_message_mapping.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/files/attachments.dart';
import 'package:reveric/shared/services/ai/files/command_paths.dart';
import 'package:reveric/shared/services/ai/files/reader.dart';
import 'package:reveric/shared/services/ai/files/session_files.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';

void main() {
  late Directory root;
  late SessionFiles files;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('command-result-');
    files = SessionFiles(root: root.path, novelId: 'work');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'relative image results round-trip without losing their snapshot',
    () async {
      final original = File('${root.path}/input.png');
      await original.writeAsBytes(
        img.encodePng(img.Image(width: 4, height: 4)),
      );
      final stored = await FileReader(
        files,
        FfmpegRunner(),
      ).read('chat', {'path': original.path}, MediaCancellation());
      final result = commandFileResult(stored, files);
      final path = result['file_path'] as String;
      expect(path, startsWith('sessions/chat/'));
      expect(result['snapshot_path'], stored['file_path']);
      expect(stored.containsKey('snapshot_path'), isFalse);
      expect(
        (await CommandPaths(files).resolve(path)).path,
        (await files.resolve(stored['file_path'] as String)).path,
      );
      expect(resultFilePaths(result).toSet(), resultFilePaths(stored).toSet());
      final content = await assembleToolResultContent(result, root: root.path);
      expect(content.whereType<ImageBlock>(), hasLength(1));
      expect(
        jsonDecode(
          content.whereType<TextBlock>().elementAt(1).text,
        )['file_path'],
        path,
      );
      final persisted = prepareSpawnAgentRunMessagesForPersistence([
        const AgentMessage(
          id: 'call',
          role: AgentMessageRole.assistant,
          blocks: [
            ToolCallBlock(
              callId: 'read',
              toolName: 'Run',
              arguments: {'command': 'files', 'subcommand': 'view-image'},
            ),
          ],
        ),
        AgentMessage(
          id: 'result',
          role: AgentMessageRole.user,
          type: AgentMessageType.tool_result,
          blocks: [
            ToolResultBlock(
              toolCallId: 'read',
              toolName: 'Run',
              content: content,
            ),
          ],
        ),
      ]);
      final payload = persisted.first.blocks
          .whereType<AiToolCallBlock>()
          .single
          .result!;
      expect(payload['file_path'], path);
      expect(payload['snapshot_path'], stored['file_path']);
      await original.delete();
      final replayed = await restoreAgentMessages(persisted, root: root.path);
      final replay = replayed
          .expand((message) => message.blocks)
          .whereType<ToolResultBlock>()
          .single
          .content;
      expect(
        replay.whereType<ImageBlock>().single.data,
        content.whereType<ImageBlock>().single.data,
      );
      expect(jsonDecode((replay.first as TextBlock).text)['file_path'], path);
    },
  );

  test(
    'preview paths are reusable and backup paths keep their workspace',
    () async {
      final snapshot = await files.allocate('chat', '.mp4');
      await snapshot.writeAsBytes([1]);
      final stored = files.reference(snapshot);
      final result = commandFileResult({
        'ok': true,
        'result': {
          'ok': true,
          'files': [
            {'delivered': true, 'file_path': stored, 'snapshot_path': stored},
          ],
        },
      }, files);
      final output = result['result']['files'][0] as Map;
      expect(
        (await CommandPaths(files).resolve(output['file_path'] as String)).path,
        snapshot.path,
      );
      expect(output['snapshot_path'], stored);
      expect(resultFilePaths(result), [stored]);
      final shared = commandFileResult({
        'file_path': 'file_workspaces/shared/images/map.png',
      }, files);
      expect(
        shared['file_path'],
        '${root.resolveSymbolicLinksSync()}/file_workspaces/shared/images/map.png',
      );
      final legacy = commandFileResult({
        'file_path': 'images/legacy.png',
      }, files);
      expect(
        legacy['file_path'],
        '${root.resolveSymbolicLinksSync()}/images/legacy.png',
      );
    },
  );

  test('metadata paths change without rewriting the file text', () async {
    final original = File('${root.path}/notes.txt');
    const text = 'Keep file_workspaces/work/files/example.txt as written.';
    await original.writeAsString(text);
    final stored = await FileReader(
      files,
      FfmpegRunner(),
    ).read('chat', {'path': original.path}, MediaCancellation());
    final result = commandFileResult(stored, files);
    final content = await assembleToolResultContent(result, root: root.path);
    final metadata = jsonDecode(
      content.whereType<TextBlock>().elementAt(1).text,
    );
    expect(metadata['file_path'], result['file_path']);
    expect(metadata['text'], stored['text']);
    expect(jsonEncode(result), contains(text));
  });
}
