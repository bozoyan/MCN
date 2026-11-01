// 职责: 验证角色选择内容体的排序、搜索过滤、键盘选中与新建入口出现时机。
// 关联文件:
//   lib/shared/widgets/screenplay/character_picker.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/screenplay/character_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _path = 'memory:character_picker';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('orders scene cast first, filters and picks by keyboard', (
    tester,
  ) async {
    final picked = <String>[];
    var cancelled = 0;
    var switched = 0;

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            characterProfilesProvider(_path).overrideWith(
              (ref) => Stream.value([
                _character(id: 'a', name: 'Xiao Yan'),
                _character(id: 'b', name: 'Yao Lao'),
                _character(id: 'c', name: 'Xiao Xun Er'),
              ]),
            ),
          ],
          child: ScreenplayCharacterPickerBody(
            databasePath: _path,
            priorityIds: const ['c'],
            selectedId: 'c',
            showShortcutHints: true,
            onPick: picked.add,
            onCancel: () => cancelled += 1,
            onSwitchToAction: () => switched += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 本场出场过的人物排在最前，其余保持原顺序。
    expect(_names(tester), ['Xiao Xun Er', 'Xiao Yan', 'Yao Lao']);

    // 空查询时没有新建入口 —— 没名字可建（键盘提示行不算入口）。
    expect(find.textContaining('Create “'), findsNothing);

    // ↓ 一次落到第二行，回车交出该人物。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, ['a']);

    // 连续输入重置 250ms 计时；等待期间不能误选上次结果。
    final search = find.byType(TextField);
    await tester.enterText(search, 'y');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_names(tester), ['Xiao Xun Er', 'Xiao Yan', 'Yao Lao']);
    await tester.enterText(search, 'yao');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 249));
    expect(_names(tester), ['Xiao Xun Er', 'Xiao Yan', 'Yao Lao']);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, ['a']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_names(tester), ['Yao Lao']);
    expect(find.textContaining('Create “yao”'), findsOneWidget);

    // 回车落在唯一匹配上，而不是去新建同名人物。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, ['a', 'b']);

    // 名字与已有人物完全一致时不给新建入口，避免建出重名记录。
    await tester.enterText(search, 'Yao Lao');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Create “'), findsNothing);

    // 新建入口也等待防抖，且不把名字强制转成小写。
    await tester.enterText(search, 'New Person');
    await tester.pump();
    expect(find.textContaining('Create “'), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Create “New Person”'), findsOneWidget);

    // 清空立即恢复全部人物，并取消尚未生效的查询。
    await tester.enterText(search, 'yao');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(search, '');
    await tester.pump();
    expect(_names(tester), ['Xiao Xun Er', 'Xiao Yan', 'Yao Lao']);
    expect(find.textContaining('Create “'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_names(tester), ['Xiao Xun Er', 'Xiao Yan', 'Yao Lao']);

    // 组词期间保留输入连接，回车交给输入法，不创建拼音名字。
    const composing = TextEditingValue(
      text: 'xiao',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<TextField>(search).controller!.value, composing);
    expect(find.textContaining('Create “'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, ['a', 'b']);
    await tester.enterText(search, 'Xiao');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(_names(tester), ['Xiao Xun Er', 'Xiao Yan']);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(switched, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(cancelled, 1);

    // 带未完成的 debounce 关闭时，定时器随组件释放。
    await tester.enterText(search, 'pending');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

List<String> _names(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .where((value) => value.startsWith('Xiao') || value.startsWith('Yao'))
      .toList();
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
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

CharacterProfile _character({required String id, required String name}) {
  return CharacterProfile(
    id: id,
    name: name,
    role: 'supporting',
    gender: 'unknown',
    aliases: const [],
    tags: const [],
    biography: '',
    appearance: '',
    description: '',
    currentState: '',
    identity: '',
    age: '',
    motivation: '',
    arc: '',
    personality: '',
    behaviorTags: const [],
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    deletedAt: notDeletedSentinel,
  );
}
