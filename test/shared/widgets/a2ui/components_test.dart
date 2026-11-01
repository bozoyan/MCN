// 职责: 验证 A2UI 组件目录在桌面与移动端的渲染、双向绑定、IME 组词、checks 禁用、action 刷新与列表构建契约。
// 关联文件:
//   lib/shared/widgets/a2ui/surface_view.dart
//   lib/shared/widgets/a2ui/session.dart
//   lib/shared/widgets/a2ui/components/text_field.dart
//   lib/shared/widgets/a2ui/components/button.dart
//   lib/shared/widgets/a2ui/preview/samples.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/components/reveric_checkbox.dart';
import 'package:reveric/shared/components/reveric_filter_chip.dart';
import 'package:reveric/shared/components/reveric_switch.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/a2ui/node_view.dart';
import 'package:reveric/shared/widgets/a2ui/preview/samples.dart';
import 'package:reveric/shared/widgets/a2ui/session.dart';
import 'package:reveric/shared/widgets/a2ui/surface_view.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, {bool boundedHeight = true}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [appBackgroundActiveProvider.overrideWithValue(false)],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: boundedHeight
                    ? SizedBox(width: 900, height: 700, child: child)
                    : SingleChildScrollView(
                        child: SizedBox(width: 900, child: child),
                      ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

A2uiSurfaceSession _session(A2uiSample sample, {A2uiActionHandler? onAction}) =>
    A2uiSurfaceSession.load(
      surfaceId: 'test-${sample.id}',
      messages: sample.messages,
      onAction: onAction,
    );

/// 渲染界面；测试结束时先拆树再释放会话（会话必须晚于界面释放）。
Future<A2uiSurfaceSession> _pump(
  WidgetTester tester,
  A2uiSample sample, {
  A2uiActionHandler? onAction,
  bool boundedHeight = true,
}) async {
  final session = _session(sample, onAction: onAction);
  addTearDown(session.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    _wrap(A2uiSurfaceView(session: session), boundedHeight: boundedHeight),
  );
  await tester.pumpAndSettle();
  return session;
}

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(RevericTextField, label),
  matching: find.byType(TextField),
);

Finder _button(String label) => find.widgetWithText(RevericButton, label);

Map<String, Object?> _form(A2uiSurfaceSession session) =>
    (session.dataSnapshot()! as Map)['form'] as Map<String, Object?>;

void main() {
  setUp(() => rootBundle.clear());

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.android,
  ]) {
    testWidgets('every sample renders without layout errors ($platform)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        for (final sample in [
          galleryA2uiSample,
          characterOrganizerA2uiSample,
          longListA2uiSample,
        ]) {
          final session = _session(sample);
          await tester.pumpWidget(_wrap(A2uiSurfaceView(session: session)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: sample.id);
          expect(find.byType(A2uiNodeView), findsWidgets, reason: sample.id);
          await tester.pumpWidget(const SizedBox.shrink());
          session.dispose();
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('typing writes the bound data and refreshes bound text', (
    tester,
  ) async {
    final session = await _pump(tester, galleryA2uiSample);

    await tester.enterText(_field('人物名称'), '林');
    await tester.pump();

    expect(_form(session)['name'], '林');
    expect(find.text('实时预览：林'), findsOneWidget);
  });

  testWidgets('IME composing text is written only after commit', (
    tester,
  ) async {
    final session = await _pump(tester, galleryA2uiSample);
    await tester.showKeyboard(_field('人物名称'));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'lin',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();

    expect(_form(session)['name'], '');
    expect(tester.widget<TextField>(_field('人物名称')).controller!.text, 'lin');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '林',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();

    expect(_form(session)['name'], '林');
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });

  testWidgets('data changed by an action is shown in the field', (
    tester,
  ) async {
    final session = await _pump(tester, galleryA2uiSample);

    session.applyDataUpdates(const [
      A2uiDataUpdate(path: '/form/name', value: '沈'),
    ]);
    await tester.pump();

    expect(tester.widget<TextField>(_field('人物名称')).controller!.text, '沈');
  });

  testWidgets('checks disable the button until they pass', (tester) async {
    final events = <A2uiActionEvent>[];
    final gate = Completer<List<A2uiDataUpdate>>();
    final session = await _pump(
      tester,
      galleryA2uiSample,
      onAction: (event) {
        events.add(event);
        return gate.future;
      },
    );

    expect(tester.widget<RevericButton>(_button('提交')).onPressed, isNull);

    await tester.enterText(_field('人物名称'), '林');
    session.applyDataUpdates(const [
      A2uiDataUpdate(path: '/form/genre', value: ['scifi']),
    ]);
    await tester.pump();

    expect(tester.widget<RevericButton>(_button('提交')).onPressed, isNotNull);

    await tester.ensureVisible(_button('提交'));
    await tester.tap(_button('提交'));
    await tester.pump();

    expect(events.single.name, 'submit');
    expect((events.single.context['form'] as Map)['name'], '林');
    expect(tester.widget<RevericButton>(_button('提交')).loading, isTrue);

    gate.complete(const [A2uiDataUpdate(path: '/status', value: '已提交')]);
    await tester.pump();
    await tester.pump();

    expect(tester.widget<RevericButton>(_button('提交')).loading, isFalse);
    expect(find.text('已提交'), findsOneWidget);
  });

  testWidgets('field errors show the rule message after the user edits', (
    tester,
  ) async {
    await _pump(tester, galleryA2uiSample);

    expect(find.text('请填写人物名称'), findsNothing);

    await tester.enterText(_field('人物名称'), '林');
    await tester.pump();
    await tester.enterText(_field('人物名称'), '');
    await tester.pump();

    expect(find.text('请填写人物名称'), findsOneWidget);
    expect(find.text('This field is required.'), findsNothing);
  });

  testWidgets('a rule without a message shows the localized fallback', (
    tester,
  ) async {
    await _pump(
      tester,
      A2uiSample(
        id: 'no_message',
        title: 'no message',
        messages: [
          {
            'version': a2uiProtocolVersion,
            'createSurface': {
              'surfaceId': 's',
              'dataModel': {'name': 'x'},
              'components': [
                {
                  'id': 'root',
                  'component': 'TextField',
                  'label': 'Name',
                  'value': {'@path': '/name'},
                  'checks': [
                    {
                      'condition': {
                        '@call': 'required',
                        'args': {
                          'value': {'@path': '/name'},
                        },
                      },
                    },
                  ],
                },
              ],
            },
          },
        ],
      ),
    );

    await tester.enterText(_field('Name'), '');
    await tester.pump();

    expect(find.text('Invalid value'), findsOneWidget);
  });

  testWidgets('choice, check box and switch write their values', (
    tester,
  ) async {
    final session = await _pump(tester, galleryA2uiSample);

    await tester.ensureVisible(find.widgetWithText(RevericFilterChip, '群像'));
    await tester.tap(find.widgetWithText(RevericFilterChip, '群像'));
    await tester.pump();
    await tester.tap(find.widgetWithText(RevericFilterChip, '悬疑'));
    await tester.pump();
    expect(_form(session)['tags'], ['群像']);

    await tester.ensureVisible(find.text('冷峻'));
    await tester.tap(find.text('冷峻'));
    await tester.pump();
    expect(_form(session)['moods'], ['cold']);

    await tester.ensureVisible(find.text('我已确认人物设定不与已有角色冲突'));
    await tester.tap(find.text('我已确认人物设定不与已有角色冲突'));
    await tester.pump();
    expect(_form(session)['agree'], isTrue);
    expect(
      tester.widget<RevericCheckbox>(find.byType(RevericCheckbox).last).value,
      isTrue,
    );

    await tester.ensureVisible(find.byType(RevericSwitch));
    await tester.tap(find.byType(RevericSwitch));
    await tester.pump();
    expect(_form(session)['notify'], isFalse);
  });

  testWidgets('single choice opens the select menu and writes a list', (
    tester,
  ) async {
    final session = await _pump(tester, galleryA2uiSample);

    await tester.ensureVisible(find.text('Choose…'));
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('科幻').last);
    await tester.pumpAndSettle();

    expect(_form(session)['genre'], ['scifi']);
  });

  testWidgets('template lists follow data returned by an action', (
    tester,
  ) async {
    await _pump(
      tester,
      characterOrganizerA2uiSample,
      onAction: characterOrganizerA2uiSample.respond,
    );

    expect(find.text('第 6 章登场。'), findsOneWidget);
    expect(find.text('第 8 章登场。'), findsNothing);
    // 模板内 formatString 的相对路径按当前条目解析。
    expect(
      find.textContaining('人物 1 · 主角', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(_button('刷新'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('已刷新：共 8 个人物'), findsOneWidget);
    expect(find.text('第 8 章登场。', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a List root builds only the visible rows', (tester) async {
    await _pump(tester, longListA2uiSample);

    expect(find.text('人物 1'), findsOneWidget);
    expect(find.text('人物 300', skipOffstage: false), findsNothing);
  });

  testWidgets('surfaces lay out by content height when height is unbounded', (
    tester,
  ) async {
    await _pump(tester, longListA2uiSample, boundedHeight: false);

    expect(tester.takeException(), isNull);
    expect(find.text('人物 300', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a row of buttons wraps instead of overflowing', (tester) async {
    final sample = A2uiSample(
      id: 'buttons',
      title: 'buttons',
      messages: [
        {
          'version': a2uiProtocolVersion,
          'createSurface': {
            'surfaceId': 'test-buttons',
            'components': [
              {
                'id': 'root',
                'component': 'Row',
                'children': [for (var i = 0; i < 12; i++) 'b$i'],
              },
              for (var i = 0; i < 12; i++) ...[
                {
                  'id': 'b$i',
                  'component': 'Button',
                  'child': 'b${i}_label',
                  'action': {
                    'event': {'name': 'tap'},
                  },
                },
                {'id': 'b${i}_label', 'component': 'Text', 'text': '操作按钮 $i'},
              ],
            ],
          },
        },
      ],
    );
    await _pump(tester, sample);

    expect(tester.takeException(), isNull);
    expect(find.byType(Wrap), findsOneWidget);
    final first = tester.getTopLeft(_button('操作按钮 0'));
    final last = tester.getTopLeft(_button('操作按钮 11'));
    expect(last.dy, greaterThan(first.dy));
  });

  testWidgets('an invalid surface shows a local error', (tester) async {
    await _pump(tester, invalidA2uiSample);

    expect(find.text("This view can't be shown"), findsOneWidget);
  });
}
