// 职责: 测试 AskUser 工具卡片的多问题展示、输入与提交行为
// 关联文件:
//   lib/desktop/widgets/ai/tools/ask_user_card.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/models/ask_user_models.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/ai/tools/ask_user_card.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/models/ask_user_models.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Cached asset Futures cannot be shared across testWidgets FakeAsync zones.
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final width in [360.0, 900.0]) {
    testWidgets(
      'timeout replaces drafts with automatic results at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const pending = AiAskUserBlock(
          id: 'ask',
          callId: 'call',
          questions: [
            {
              'id': 'choice',
              'question': 'Choose',
              'options': [
                {'label': 'Suggested', 'recommended': true},
                {'label': 'Draft'},
              ],
            },
            {'id': 'text', 'question': 'Write something'},
          ],
        );
        var submissions = 0;
        Widget card(AiAskUserBlock block) => _wrapCard(
          AskUserCard(
            block: block,
            onSubmit: (_) {
              submissions++;
            },
            onCancel: () {},
          ),
        );
        await tester.pumpWidget(card(pending));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Draft'));
        await tester.enterText(find.byType(TextField).last, 'private draft');
        await tester.pumpWidget(
          card(
            pending.copyWith(
              status: AiAskUserStatus.timed_out,
              resolution: AskUserResolution.timeout,
              answers: [
                {
                  'question_id': 'choice',
                  'selected_options': ['Suggested'],
                },
              ],
              unansweredQuestionIds: ['text'],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Handled automatically'), findsOneWidget);
        expect(
          find.text('No answer received. AI will continue.'),
          findsOneWidget,
        );
        expect(find.text('Confirm'), findsNothing);
        expect(find.text('Cancel'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('private draft'), findsNothing);
        expect(submissions, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('interrupted questions have no submission controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapCard(
        AskUserCard(
          block: const AiAskUserBlock(
            id: 'old',
            callId: 'old',
            questions: [
              {'question': 'Old'},
            ],
            status: AiAskUserStatus.interrupted,
          ),
          onSubmit: (_) => fail('submitted'),
          onCancel: () => fail('cancelled'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Interrupted'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('deadline is checked even when draft validation would fail', (
    tester,
  ) async {
    var checked = false;
    await tester.pumpWidget(
      _wrapCard(
        AskUserCard(
          block: const AiAskUserBlock(
            id: 'old',
            callId: 'old',
            questions: [
              {'question': 'Question'},
            ],
          ),
          canSubmit: () {
            checked = true;
            return false;
          },
          onSubmit: (_) => fail('submitted'),
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(checked, true);
    expect(
      find.text('Please select an option or enter your answer'),
      findsNothing,
    );
  });

  testWidgets('renders multiple questions and submits each custom answer', (
    tester,
  ) async {
    AskUserResult? submitted;

    await tester.pumpWidget(
      _wrapCard(
        AskUserCard(
          block: const AiAskUserBlock(
            id: 'askuser_call_1',
            callId: 'call_1',
            questions: [
              {
                'id': 'genre',
                'question': '这段剧情更偏向什么类型？',
                'options': [
                  {'label': '悬疑'},
                  {'label': '恋爱'},
                ],
                'allow_free_text': true,
              },
              {'id': 'ending', 'question': '这一章以什么情绪收束？'},
            ],
          ),
          onSubmit: (result) {
            submitted = result;
          },
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AskUserCard), findsOneWidget);
    expect(find.text('1. 这段剧情更偏向什么类型？'), findsOneWidget);
    expect(find.text('2. 这一章以什么情绪收束？'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.text('悬疑'));
    await tester.enterText(find.byType(TextField).at(0), '偏黑色电影一点');
    await tester.enterText(find.byType(TextField).at(1), '收在不安感上');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.answers, hasLength(2));
    expect(submitted!.answers![0].questionId, 'genre');
    expect(submitted!.answers![0].selectedOptions, ['悬疑']);
    expect(submitted!.answers![0].answer, '偏黑色电影一点');
    expect(submitted!.answers![1].questionId, 'ending');
    expect(submitted!.answers![1].answer, '收在不安感上');
  });
}

Widget _wrapCard(Widget child) {
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
            child: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}
