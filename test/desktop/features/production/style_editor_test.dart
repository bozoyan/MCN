// 职责: 验证风格编辑失败保留输入，补全后保存为自定义风格。
// 关联文件:
//   lib/desktop/features/production/style_editor.dart
//   lib/shared/providers/production_media.dart
import 'package:reveric/shared/theme/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/style_editor.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/production/style.dart';
import 'package:reveric/shared/providers/production_media.dart';
import 'package:reveric/shared/services/production/style_service.dart';
import '../../director/harness.dart';

class _Styles extends ProductionStyleService {
  _Styles(super.database);
  final saved = <({String name, ProductionStylePrompt prompt})>[];
  @override
  Future<ProductionStyleRow> save({
    String? id,
    required String name,
    required ProductionStylePrompt prompt,
  }) async {
    saved.add((name: name, prompt: prompt));
    return ProductionStyleRow(
      id: id ?? 'saved',
      name: name,
      before: prompt.before,
      after: prompt.after,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: notDeletedSentinel,
    );
  }
}

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    await initializeDirectorTest();
    for (final family in ['Roboto', 'Georgia', 'Menlo', 'Ahem']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf')))
          .load();
    }
  });
  testWidgets('style keeps invalid edits then persists', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(880, 780);
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    final styles = _Styles(db);
    var closed = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productionStyleServiceProvider.overrideWithValue(styles)],
        child: directorTestApp(
          Container(
            color: RevericThemeData.reveric.colors.canvas,
            padding: const EdgeInsets.all(24),
            child: ProductionStyleEditor(
              onClose: () => closed = true,
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final inputs = find.byType(EditableText);
    await tester.enterText(inputs.at(1), 'Before');
    await tester.enterText(inputs.at(2), 'After');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(closed, false);
    expect(styles.saved, isEmpty);
    await tester.enterText(inputs.first, '雨夜');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(closed, true);
    final saved = styles.saved.single;
    expect(saved.name, '雨夜');
    expect(saved.prompt.assemble('Body'), 'Before\nBody\nAfter');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
