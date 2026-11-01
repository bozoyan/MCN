// 职责: 回归「作品名称先出必填错误、再输入中文时首个拼音被吞」—— 错误文案增删不得重挂载输入框。
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/components/dialog_feedback.dart';
import 'package:reveric/desktop/widgets/novel_form_dialog.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';

/// 纯组件用：RevericTextField 不含可本地化文案，跳过 EasyLocalization。
Widget _wrapPlain(Widget child) {
  return MaterialApp(
    theme: RevericThemeData.reveric.toThemeData(),
    home: RevericTheme(
      data: RevericThemeData.reveric,
      child: Scaffold(body: child),
    ),
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}

void main() {
  testWidgets('RevericTextField 无 label 时错误增删不重挂载输入框', (tester) async {
    final controller = TextEditingController(text: 'n');

    Future<void> pump(String? errorText) async {
      await tester.pumpWidget(
        _wrapPlain(
          RevericTextField(controller: controller, errorText: errorText),
        ),
      );
      await tester.pump();
    }

    await pump(null);
    final before = tester.state<EditableTextState>(find.byType(EditableText));

    await pump('必填');
    final withError = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    expect(identical(before, withError), isTrue);

    await pump(null);
    final afterClear = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    expect(identical(before, afterClear), isTrue);
  });

  testWidgets('作品名称：必填错误消失时 IME 组词不被打断', (tester) async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            novelsProvider.overrideWith((ref) => Stream.value(<Novel>[])),
          ],
          child: DialogFeedback.scope(
            builder: (_) => NovelFormDialog.create(
              onSubmit:
                  ({
                    required title,
                    required authorName,
                    required description,
                    required category,
                    required type,
                    required contentKind,
                    required plannedEpisodeCount,
                    required sourceNovelId,
                    required coverSourcePath,
                    required removeCover,
                    required tags,
                  }) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    EditableTextState titleState() =>
        tester.state<EditableTextState>(find.byType(EditableText).first);

    // 先制造「必填」错误：输入一个字符再清空。
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'x',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();

    final beforeComposing = titleState();

    // 模拟 macOS 拼音逐键组词；第一键会让必填错误消失。
    for (final text in ['n', 'ni', 'nis', 'nish', 'nishi']) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange(start: 0, end: text.length),
        ),
      );
      await tester.pump();

      final current = titleState();
      expect(
        identical(beforeComposing, current),
        isTrue,
        reason: '输入 "$text" 时输入框被重挂载，IME 组词会被 discardMarkedText 打断',
      );
      expect(current.textEditingValue.text, text);
      expect(
        current.textEditingValue.composing,
        TextRange(start: 0, end: text.length),
      );
    }
  });
}
