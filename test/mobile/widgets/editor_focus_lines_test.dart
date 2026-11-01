// 职责: 测试移动端参考划线层从 RenderEditable 读取的行底边与真实排版一致、空正文不绘制。
// 关联文件:
//   lib/mobile/widgets/editor_focus_lines.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/widgets/editor_focus_lines.dart';
import 'package:reveric/shared/providers/settings_providers.dart';

MobileFocusLinePainter? _focusPainter(WidgetTester tester) {
  for (final element in find.byType(CustomPaint).evaluate()) {
    final painter = (element.widget as CustomPaint).painter;
    if (painter is MobileFocusLinePainter) {
      return painter;
    }
  }
  return null;
}

Future<void> _pumpField(
  WidgetTester tester, {
  required GlobalKey fieldKey,
  required TextEditingController controller,
  required ScrollController scrollController,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          width: 240,
          child: Stack(
            children: [
              TextField(
                key: fieldKey,
                controller: controller,
                scrollController: scrollController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                strutStyle: const StrutStyle(
                  fontSize: 16,
                  height: 1.8,
                  leadingDistribution: TextLeadingDistribution.even,
                  forceStrutHeight: true,
                ),
                style: const TextStyle(fontSize: 16, height: 1.8),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              MobileEditorFocusLines(
                fieldKey: fieldKey,
                controller: controller,
                scrollController: scrollController,
                lineStyle: EditorLineStyle.solid,
                lineColor: const Color(0xFFFF0000),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // 触发 180ms 防抖后的几何读取，再让 setState 重建一帧。
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

void main() {
  testWidgets(
    'draws one ruled line per visual line at RenderEditable bottoms',
    (tester) async {
      final fieldKey = GlobalKey();
      final controller = TextEditingController(
        text: '第一行很长的内容用来强制软换行测试测试测试测试测试测试测试\n第二段\n\n第四段也来一点',
      );
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      await _pumpField(
        tester,
        fieldKey: fieldKey,
        controller: controller,
        scrollController: scrollController,
      );

      // 直接从 RenderEditable 枚举出的期望行底边。
      final re = tester
          .firstState<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final expected = <double>[];
      final seen = <double>{};
      var offset = 0;
      final length = controller.text.length;
      var guard = 0;
      while (offset <= length && guard++ < 100000) {
        final caret = re.getLocalRectForCaret(TextPosition(offset: offset));
        if (seen.add(caret.top.roundToDouble())) {
          expected.add(caret.bottom);
        }
        final line = re.getLineAtOffset(TextPosition(offset: offset));
        offset = line.end > offset ? line.end : offset + 1;
      }

      final painter = _focusPainter(tester);
      expect(painter, isNotNull);
      expect(painter!.lineBottoms, isNotEmpty);
      expect(painter.lineBottoms, expected);
    },
  );

  testWidgets('draws no lines for empty body', (tester) async {
    final fieldKey = GlobalKey();
    final controller = TextEditingController(text: '');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await _pumpField(
      tester,
      fieldKey: fieldKey,
      controller: controller,
      scrollController: scrollController,
    );

    final painter = _focusPainter(tester);
    expect(painter, isNotNull);
    expect(painter!.lineBottoms, isEmpty);
  });
}
