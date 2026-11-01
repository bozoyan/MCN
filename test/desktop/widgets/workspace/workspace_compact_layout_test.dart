// 职责: 测试工作区资料类编辑器在紧凑高度下整体滚动而不是竖向溢出。
// 关联文件:
//   lib/desktop/widgets/workspace/foreshadowing_editor.dart
//   lib/desktop/widgets/workspace/workspace_item_editor.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/foreshadowing_editor.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/foreshadowing.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/foreshadowing/position_links.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('foreshadowing editor scrolls on compact heights', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapEditor(_foreshadowingEditor()));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.byType(CustomScrollView));

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollbar), findsOneWidget);
    final pageScrollView = find.ancestor(
      of: find.byType(RevericMarkdownEditor),
      matching: find.byType(CustomScrollView),
    );
    expect(pageScrollView, findsOneWidget);

    await tester.drag(pageScrollView, const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 10; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _foreshadowingEditor() {
  return ForeshadowingEditor(
    selectedItemId: null,
    isCreating: true,
    foreshadowings: const [],
    titleController: TextEditingController(text: '伏笔'),
    setupController: TextEditingController(),
    payoffController: TextEditingController(),
    titleFocusNode: FocusNode(),
    setupFocusNode: FocusNode(),
    payoffFocusNode: FocusNode(),
    selectedStatus: foreshadowingStatusPending,
    onStatusChanged: (_) {},
    positions: emptyForeshadowingPositionIds,
    onPositionsChanged: (_) {},
    onCreateForeshadowing: () {},
  );
}

Widget _wrapEditor(Widget child) {
  return EasyLocalization(
    key: UniqueKey(),
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            editorFontFamilyProvider.overrideWithValue('Georgia'),
            editorFontSizeProvider.overrideWithValue(16),
            editorLetterSpacingProvider.overrideWithValue(0),
            editorLineHeightProvider.overrideWithValue(1.8),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 700, height: 360, child: child),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
