// 职责: 验证分类选择在两端保留旧值、切换平台、自由输入及表单重置的行为。
// 关联文件:
//   lib/shared/widgets/novel/category_field.dart
//   lib/shared/models/novel_form_fields.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/form/form.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/novel_form_fields.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/novel/category_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(FormFieldsController<NovelFormField> form, bool mobile) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: RevericThemeData.reveric.toThemeData().copyWith(
          platform: mobile ? TargetPlatform.android : TargetPlatform.macOS,
        ),
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: HookedForm<NovelFormField>(
                form: form,
                child: const NovelCategoryField(
                  fieldHook: NovelFormField.category,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final mobile in [false, true]) {
    testWidgets('legacy and custom categories survive browsing ($mobile)', (
      tester,
    ) async {
      tester.view.physicalSize = Size(mobile ? 375 : 500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final form = FormFieldsController<NovelFormField>(
        GlobalKey<FormState>(),
        initialValues: {NovelFormField.category: '旧分类 / 自定义'},
      );
      addTearDown(form.dispose);
      await tester.pumpWidget(_wrap(form, mobile));
      await tester.pumpAndSettle();

      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      String value() => form.getValue<String>(NovelFormField.category)!;
      String displayed() => tester
          .widget<EditableText>(find.byType(EditableText))
          .controller
          .text;

      expect(displayed(), '旧分类 / 自定义');
      expect(form.hasChanged, isFalse);
      await tap('Browse categories');
      await tap('Female');
      expect(find.text('古代言情'), findsOneWidget);
      expect(value(), '旧分类 / 自定义');
      expect(form.hasChanged, isFalse);
      await tap('古代言情');
      expect(value(), '古代言情');
      await tap('Male');
      await tap('诸天无限');
      expect(displayed(), '诸天无限');
      expect(value(), '诸天无限');

      await tester.ensureVisible(find.byType(TextField));
      await tester.showKeyboard(find.byType(TextField));
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'zidingyi',
          selection: TextSelection.collapsed(offset: 8),
          composing: TextRange(start: 0, end: 8),
        ),
      );
      await tester.pump();
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(
        editor.widget.controller.value.composing,
        const TextRange(start: 0, end: 8),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '自定义',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(editor),
      );
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(value(), '自定义');
      await tester.enterText(find.byType(TextField), '自创宇宙 / 太空歌剧');
      await tester.pump();
      await tap('Female');
      expect(value(), '自创宇宙 / 太空歌剧');
      expect(displayed(), value());
      expect(form.hasChanged, isTrue);
      expect(form.validate(), isTrue);

      form.reset();
      await tester.pump();
      expect(value(), '旧分类 / 自定义');
      expect(displayed(), value());
      expect(form.hasChanged, isFalse);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(value(), '');
      expect(form.validate(), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
