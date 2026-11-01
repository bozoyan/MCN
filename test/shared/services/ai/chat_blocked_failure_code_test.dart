// 职责: 验证聊天发送被模型配置阻止时的失败码归类。
// 关联文件:
//   lib/shared/services/ai/chat_session_controller.dart
//   lib/shared/models/ai_provider.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/chat_session_controller.dart';

void main() {
  group('classifyChatBlockedFailureCode', () {
    test('keeps an unavailable provider classified as feature_not_enabled', () {
      final failureCode = classifyChatBlockedFailureCode(
        providerId: 'openai',
        model: 'gpt-5.4',
        config: null,
      );

      expect(failureCode, 'feature_not_enabled');
    });
  });
}
