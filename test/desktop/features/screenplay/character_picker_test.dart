// 职责: 验证桌面人物选择浮层在搜索、中文组词和结果更新时保持位置稳定。
// 关联文件:
//   lib/desktop/features/screenplay/character_picker.dart
//   lib/shared/widgets/screenplay/character_picker.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/screenplay/character_picker.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/screenplay/character_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _path = 'memory:desktop_character_picker';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('keeps search and popover stable as results change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final updates = StreamController<List<CharacterProfile>>();
    addTearDown(updates.close);
    final characters = List.generate(
      12,
      (index) => _character(id: '$index', name: 'Character $index'),
    );
    var anchor = const Rect.fromLTWH(100, 500, 180, 28);
    ScreenplayCharacterPickerResult? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          characterProfilesProvider(
            _path,
          ).overrideWith((ref) => updates.stream),
        ],
        child: _wrap(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showScreenplayCharacterPickerPopover(
                    context,
                    anchor: anchor,
                    databasePath: _path,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final body = find.byType(ScreenplayCharacterPickerBody);
    final search = find.byType(TextField);
    updates.add(characters);
    await tester.pumpAndSettle();
    final initialPopover = tester.getRect(body);
    final initialSearch = tester.getRect(search);
    expect(initialPopover.bottom, lessThan(anchor.top));

    void expectStable() {
      expect(tester.getRect(body), initialPopover);
      expect(tester.getRect(search), initialSearch);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
    }

    // 原实现会因列表缩短，判断下方放得下并翻到角色行下方。
    await tester.enterText(search, 'Character 0');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Character 0'),
      ),
      findsOneWidget,
    );
    expect(find.text('Character 1'), findsNothing);
    expectStable();

    await tester.enterText(search, 'New name');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.textContaining('Create “New name”'), findsOneWidget);
    expectStable();

    const composing = TextEditingValue(
      text: 'xiao',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pumpAndSettle();
    expectStable();
    expect(tester.widget<TextField>(search).controller!.value, composing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(body, findsOneWidget);
    expect(result, isNull);
    expectStable();

    await tester.enterText(search, '萧');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expectStable();
    await tester.enterText(search, '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expectStable();

    updates.add([]);
    await tester.pumpAndSettle();
    expect(find.text('Character 0'), findsNothing);
    expectStable();
    updates.add(characters);
    await tester.pumpAndSettle();
    expectStable();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result?.characterId, '1');
    expect(body, findsNothing);

    // 靠近窗口上方时仍向下打开，小窗口时约束在视口内。
    anchor = const Rect.fromLTWH(100, 20, 180, 28);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getRect(body).top, greaterThan(anchor.bottom));
    await tester.enterText(search, 'No match');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.getRect(body).top, greaterThan(anchor.bottom));
    await tester.binding.setSurfaceSize(const Size(260, 260));
    await tester.pumpAndSettle();
    final compact = tester.getRect(body);
    expect(compact.left, greaterThanOrEqualTo(8));
    expect(compact.right, lessThanOrEqualTo(252));
    expect(compact.top, greaterThanOrEqualTo(8));
    expect(compact.bottom, lessThanOrEqualTo(252));
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(body, findsNothing);
    expect(result, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => RevericTheme(
        data: RevericThemeData.revericDark,
        child: MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.revericDark.toThemeData(),
          home: Scaffold(body: child),
        ),
      ),
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
