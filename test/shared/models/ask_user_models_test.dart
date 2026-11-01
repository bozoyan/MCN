// 职责: 验证 AskUser 解析、结果状态映射与序列化兼容。
// 关联文件:
//   lib/shared/models/ask_user_models.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ask_user_models.dart';
import 'package:reveric/shared/models/ai_message_block.dart';

void main() {
  test('maps every result to its card status in one place', () {
    final cases = <AskUserResult, AiAskUserStatus>{
      const AskUserResult(ok: true, resolution: AskUserResolution.timeout):
          AiAskUserStatus.timed_out,
      const AskUserResult(
        ok: false,
        cancelled: true,
        resolution: AskUserResolution.interrupted,
      ): AiAskUserStatus.interrupted,
      const AskUserResult(ok: false, cancelled: true):
          AiAskUserStatus.cancelled,
      const AskUserResult(ok: true): AiAskUserStatus.answered,
      const AskUserResult(ok: false, error: 'failed'): AiAskUserStatus.error,
    };
    for (final entry in cases.entries) {
      expect(AiAskUserStatus.fromResult(entry.key), entry.value);
    }
  });

  test('typed resolutions preserve existing tool and block JSON values', () {
    for (final entry in {
      'timeout': AskUserResolution.timeout,
      'interrupted': AskUserResolution.interrupted,
    }.entries) {
      final result = AskUserResult(ok: true, resolution: entry.value);
      expect(result.toJson()['resolution'], entry.key);
      final block = AiAskUserBlock.fromJson({
        'id': 'ask',
        'call_id': 'call',
        'questions': [],
        'status': AiAskUserStatus.fromResult(result).name,
        'resolution': entry.key,
      });
      expect(block.resolution, entry.value);
      expect(block.toJson()['resolution'], entry.key);
      expect(block.copyWith().resolution, entry.value);
    }
  });

  test(
    'timeout with no recommendations explicitly reports unanswered questions',
    () {
      final result = AskUserResult.timeout(const [
        AskUserQuestion(id: 'text', question: 'Text'),
        AskUserQuestion(
          id: 'ordinary',
          question: 'Choice',
          options: [AskUserOption(label: 'First')],
        ),
      ]).toJson();
      expect(result['ok'], true);
      expect(result['cancelled'], false);
      expect(result['resolution'], 'timeout');
      expect(result['answers'], isEmpty);
      expect(result['unanswered_question_ids'], ['text', 'ordinary']);
      expect(result['message'], '用户未回答，请根据现有上下文继续');
    },
  );

  test('reads legacy answered blocks without new result fields', () {
    final block = AiAskUserBlock.fromJson({
      'id': 'old',
      'call_id': 'old',
      'questions': [],
      'status': 'answered',
      'answers': [
        {'question_id': 'q', 'answer': 'Yes'},
      ],
    });
    expect(block.isAnswered, true);
    expect(block.answers!.single['answer'], 'Yes');
    expect(block.resolution, isNull);
    expect(block.unansweredQuestionIds, isNull);
  });

  test('treats blank option descriptions as absent', () {
    final option = AskUserOption.fromJson({'label': '男性', 'description': '  '});

    expect(option.description, isNull);
  });
}
