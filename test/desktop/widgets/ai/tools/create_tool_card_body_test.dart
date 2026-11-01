// 职责: 测试 Create 工具卡片对流式/历史参数形态的兼容展示。
// 关联文件:
//   lib/desktop/widgets/ai/tools/create_tool_card_body.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/ai/tools/create_tool_card_body.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  testWidgets('does not crash when unified Create fields is a string', (
    tester,
  ) async {
    final block = AiToolCallBlock(
      id: 'block_create',
      callId: 'call_create',
      toolName: 'Create',
      arguments: const {'path': '/characters', 'fields': 'partial stream'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: Scaffold(body: CreateToolCardBody(block: block)),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
