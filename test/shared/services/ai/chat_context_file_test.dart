// 职责: 验证聊天文本附件的格式、解码、总字符上限与同文件替换行为。
// 关联文件:
//   lib/shared/services/ai/chat_context_file.dart
//   lib/shared/models/novel_workspace.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/services/ai/chat_context_file.dart';

void main() {
  group('loadChatContextFile', () {
    test('loads txt and md content without exposing the local path', () async {
      final attachment = await loadChatContextFile(
        _textFile('/private/novel/notes.MD', '# 标题\n正文'),
        const [],
      );

      expect(attachment.kind, AiContextReferenceKind.file);
      expect(attachment.label, 'notes.MD');
      expect(attachment.content, '# 标题\n正文');
      expect(attachment.path, isNull);
      expect(attachment.itemId, startsWith('local_file_'));
      expect(attachment.itemId, isNot(contains('/private/novel')));
    });

    test('loads csv content', () async {
      final attachment = await loadChatContextFile(
        _textFile('/private/novel/data.CSV', 'name,value\nAda,1'),
        const [],
      );

      expect(attachment.label, 'data.CSV');
      expect(attachment.content, 'name,value\nAda,1');
    });

    test('rejects unsupported and empty files with typed failures', () async {
      await expectLater(
        loadChatContextFile(_textFile('/tmp/notes.pdf', 'content'), const []),
        throwsA(_failure(ChatContextFileFailure.unsupportedType)),
      );
      await expectLater(
        loadChatContextFile(_textFile('/tmp/notes.txt', '  \n'), const []),
        throwsA(_failure(ChatContextFileFailure.empty)),
      );
    });

    test('enforces a 100,000 character aggregate limit', () async {
      final existing = AiContextReference.file(
        itemId: 'existing',
        label: 'existing.txt',
        content: _repeat('a', chatContextFileMaxCharacters - 1),
      );

      final accepted = await loadChatContextFile(
        _textFile('/tmp/one.txt', '中'),
        [existing],
      );
      expect(
        chatContextFileCharacterCount([existing, accepted]),
        chatContextFileMaxCharacters,
      );

      await expectLater(
        loadChatContextFile(_textFile('/tmp/two.md', '中文'), [existing]),
        throwsA(_failure(ChatContextFileFailure.tooLarge)),
      );
    });

    test('reselecting the same path replaces its previous content', () async {
      final original = await loadChatContextFile(
        _textFile('/tmp/notes.txt', '旧内容'),
        const [],
      );
      final updated = await loadChatContextFile(
        _textFile('/tmp/notes.txt', '新内容'),
        [original],
      );

      final references = upsertChatContextFileReference([original], updated);
      expect(references, hasLength(1));
      expect(references.single.content, '新内容');
    });
  });
}

XFile _textFile(String path, String content) {
  return XFile.fromData(
    Uint8List.fromList(utf8.encode(content)),
    path: path,
    mimeType: 'text/plain',
  );
}

Matcher _failure(ChatContextFileFailure failure) {
  return isA<ChatContextFileException>().having(
    (error) => error.failure,
    'failure',
    failure,
  );
}

String _repeat(String value, int count) => List.filled(count, value).join();
