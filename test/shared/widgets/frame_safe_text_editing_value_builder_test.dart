// 职责: 测试文本编辑值监听构建器在 Flutter 持久帧回调期间延后重建。
// 关联文件:
//   lib/shared/widgets/frame_safe_text_editing_value_builder.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/frame_safe_text_editing_value_builder.dart';

void main() {
  testWidgets(
    'defers rebuild when controller changes during persistent frame',
    (tester) async {
      final controller = TextEditingController();
      var changedDuringFrame = false;

      await tester.pumpWidget(
        MaterialApp(
          home: FrameSafeTextEditingValueBuilder(
            controller: controller,
            builder: (context, value, child) {
              return Text(value.text.isEmpty ? 'empty' : value.text);
            },
          ),
        ),
      );

      tester.binding.addPersistentFrameCallback((_) {
        if (changedDuringFrame) {
          return;
        }
        changedDuringFrame = true;
        controller.text = 'fj';
      });

      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('empty'), findsOneWidget);

      await tester.pump();

      expect(find.text('fj'), findsOneWidget);

      controller.dispose();
    },
  );
}
