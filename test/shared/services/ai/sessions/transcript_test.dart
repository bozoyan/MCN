// 职责: 验证保存消息的语义分类、正文去重及 Unicode 分段。
// 关联文件:
//   lib/shared/services/ai/sessions/transcript.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/services/ai/sessions/transcript.dart';

AiChatMessage row({
  String role = 'user',
  String type = 'text',
  String content = 'body',
  List<AiMessageBlock>? blocks,
  Map<String, dynamic>? metadata,
}) => AiChatMessage(
  id: 'message',
  sessionId: 'session',
  role: role,
  type: type,
  content: content,
  blocks: blocks,
  metadata: metadata,
  inputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
  reasoningTokens: 0,
  sequence: 1,
  createdAt: DateTime.utc(2026),
);
void main() {
  test('explicit message types take precedence over roles', () {
    expect(
      normalizeTranscript(row(type: 'compact_summary')).single.kind,
      'summary',
    );
    expect(
      normalizeTranscript(row(type: 'system_remind')).single.kind,
      'system',
    );
    expect(normalizeTranscript(row(role: 'system')).single.kind, 'system');
    final tool = normalizeTranscript(
      row(
        type: 'tool_result',
        content: '{"ok":false,"error":"bad"}',
        metadata: {'tool_call_id': 'call'},
      ),
    ).single;
    expect(tool.kind, 'tool');
    expect(tool.toolName, isNull);
    expect(tool.toolStatus, 'error');
    expect(tool.callId, 'call');
    expect(tool.id, isNull);
    expect(
      () => normalizeTranscript(row(type: 'tool_result', content: 'legacy')),
      throwsFormatException,
    );
  });
  test('tool filters require saved terminal-status evidence', () {
    final unknown = normalizeTranscript(
      row(type: 'tool_result', content: '{"value":42}'),
    );
    expect(unknown.single.toolStatus, isNull);
    expect(
      filterTranscript(unknown, kinds: {'tool'}, toolStatus: 'success'),
      isEmpty,
    );

    final successful = normalizeTranscript(
      row(
        type: 'tool_result',
        content: '{"ok":true,"message":"Read complete"}',
        metadata: {
          'tool_name': 'Read',
          'tool_call_id': 'call',
          'is_error': false,
        },
      ),
    );
    expect(
      filterTranscript(
        successful,
        kinds: {'tool'},
        toolStatus: 'success',
      ).single.text,
      '{"ok":true,"message":"Read complete"}',
    );

    for (final entry in {
      '{"ok":true}': 'success',
      '{"ok":false}': 'error',
      '{"error":"failed"}': 'error',
      '{"cancelled":true}': 'cancelled',
      '{"skipped":true}': 'cancelled',
      '{"rejected":true}': 'rejected',
    }.entries) {
      expect(
        normalizeTranscript(
          row(type: 'tool_result', content: entry.key),
        ).single.toolStatus,
        entry.value,
      );
    }
    expect(
      normalizeTranscript(
        row(
          type: 'tool_result',
          content: '{"error":"failed"}',
          metadata: {'is_error': true},
        ),
      ).single.toolStatus,
      'error',
    );
  });

  test(
    'mixed blocks preserve identity and order, omit reasoning and UI metadata',
    () {
      final parts = normalizeTranscript(
        row(
          role: 'assistant',
          blocks: [
            const AiTextBlock(id: 'text', text: 'body'),
            const AiThinkingBlock(
              id: 'think',
              text: 'secret',
              signature: 'signature',
            ),
            const AiToolCallBlock(
              id: 'tool',
              callId: 'call',
              toolName: 'Read',
              arguments: {'path': '/x'},
              result: {
                'ok': true,
                '_metadata': {'ui': 'private'},
              },
              status: AiToolCallStatus.success,
            ),
            const AiToolCallBlock(
              id: 'failed',
              callId: 'call2',
              toolName: 'Run',
              arguments: {},
              status: AiToolCallStatus.error,
              errorMessage: 'broken',
            ),
            const AiAskUserBlock(
              id: 'ask',
              callId: 'q',
              questions: [
                {'question': 'Which?'},
              ],
            ),
            const AiSuggestNextActionBlock(
              id: 'next',
              callId: 's',
              suggestions: [
                {'title': 'Continue'},
              ],
            ),
            const AiImageBlock(
              id: 'image',
              prompt: 'portrait',
              imageBase64: 'binary',
              imageUrl: 'https://example.test/image',
            ),
          ],
        ),
      );
      expect(parts.map((p) => p.id), [
        'text',
        'tool',
        'failed',
        'ask',
        'next',
        'image',
      ]);
      expect(parts.map((p) => p.text).join(), isNot(contains('secret')));
      expect(parts.map((p) => p.text).join(), isNot(contains('private')));
      expect(parts.last.text, isNot(contains('binary')));
      final filtered = filterTranscript(
        parts,
        kinds: {'assistant', 'tool'},
        toolStatus: 'error',
      );
      expect(filtered.where((p) => p.kind == 'tool').single.index, 2);
      expect(filtered.first.text, 'body');
    },
  );
  test('fallback body retains session references and Unicode slices', () {
    final part = normalizeTranscript(
      row(
        content:
            '<user-remind work-id="w" path="ai-session:a">😀𐐷中</user-remind>',
      ),
    ).single;
    expect(part.text, contains('ai-session:a'));
    expect(part.id, isNull);
    final unicode = const TranscriptPart(index: 0, kind: 'user', text: '😀𐐷中');
    expect(unicode.slice(0, 2)['text'], '😀𐐷');
    expect(unicode.slice(2, 1)['text'], '中');
  });
}
