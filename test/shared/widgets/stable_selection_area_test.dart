// 职责: 验证流式文本禁用选区、内容稳定后恢复可选。
// 关联文件:
//   lib/shared/widgets/stable_selection_area.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/stable_selection_area.dart';

void main() {
  testWidgets(
    'disables selection while streaming and restores it when stable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StableSelectionArea(
              selectable: false,
              child: Text('Streaming reasoning'),
            ),
          ),
        ),
      );

      expect(find.byType(SelectionArea), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StableSelectionArea(child: Text('Completed reasoning')),
          ),
        ),
      );

      expect(find.byType(SelectionArea), findsOneWidget);
    },
  );
}
