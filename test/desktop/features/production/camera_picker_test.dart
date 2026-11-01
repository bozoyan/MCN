// 职责: 验证运镜库按类别展示新增模板并返回可插入的提示词。
// 关联文件:
//   lib/desktop/features/production/camera_picker.dart
//   test/desktop/director/harness.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/camera_picker.dart';
import 'package:reveric/shared/components/reveric_filter_chip.dart';
import '../../director/harness.dart';

void main() {
  setUpAll(initializeDirectorTest);
  setUp(() => rootBundle.clear());
  for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
    testWidgets('select an aerial prompt in $locale', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? selected;
      await tester.pumpWidget(
        directorTestApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  selected = await pickProductionCamera(context),
              child: const Text('Open'),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.childrenDelegate.estimatedChildCount, 33);
      await tester.tap(find.byType(RevericFilterChip).last);
      await tester.pumpAndSettle();
      final title = find.text(
        locale.languageCode == 'en' ? 'FPV flight' : '穿越机运镜',
      );
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(selected, '第一视角高速向前飞行，随空间转弯起伏，穿过障碍间的开口。');
      expect(tester.takeException(), isNull);
    });
  }
}
