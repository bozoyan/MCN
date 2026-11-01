// 职责: 测试通用资料条目编辑器在紧凑高度下整体滚动，并在素材阅读态隐藏标题/分类。
// 关联文件:
//   lib/desktop/widgets/workspace/workspace_item_editor.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/workspace_item_editor.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('scrolls instead of overflowing on compact heights', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapEditor(_editor()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    final pageScrollView = find.ancestor(
      of: find.byType(RevericMarkdownEditor),
      matching: find.byType(CustomScrollView),
    );
    expect(pageScrollView, findsOneWidget);

    await tester.drag(pageScrollView, const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrapEditor(_editor(showMetadataFields: false)));
    await tester.pumpAndSettle();

    expect(find.text('标题'), findsNothing);
    expect(find.text('分类'), findsNothing);
    expect(find.byType(RevericMarkdownEditor), findsOneWidget);
  });
}

Widget _editor({bool showMetadataFields = true}) {
  return WorkspaceEntryEditor(
    selectedItemId: null,
    isCreating: true,
    entries: const [],
    title: '物品',
    description: '编辑物品资料',
    typeLabel: '物品',
    categoryHint: '如：武器、装备、遗物',
    newEntryLabel: '新建物品',
    titleController: TextEditingController(text: '玉佩'),
    contentController: TextEditingController(),
    categoryController: TextEditingController(),
    titleFocusNode: FocusNode(),
    contentFocusNode: FocusNode(),
    categoryFocusNode: FocusNode(),
    showMetadataFields: showMetadataFields,
    onCreateEntry: () {},
  );
}

Widget _wrapEditor(Widget child) {
  return EasyLocalization(
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
