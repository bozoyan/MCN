// 职责: 验证移动聊天与圆桌入口在作品未就绪、加载失败或不存在时不会开放执行。
// 关联文件:
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/features/council/page.dart
//   lib/mobile/widgets/chat_composer.dart
//   lib/mobile/widgets/mobile_ai_mode.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/state-management.md

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/pages/novel_chat_page.dart';
import 'package:reveric/mobile/features/council/page.dart';
import 'package:reveric/mobile/widgets/chat_composer.dart';
import 'package:reveric/mobile/widgets/mobile_ai_mode.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReplacementObserver extends NavigatorObserver {
  Route<dynamic>? replacement;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacement = newRoute;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('新建移动聊天保留当前剧本季集参数', (tester) async {
    rootBundle.clear();
    final observer = _ReplacementObserver();
    late BuildContext routeContext;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelProvider(
            'work_1',
          ).overrideWith((ref) => const Stream<Novel?>.empty()),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              navigatorObservers: [observer],
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              builder: (_, child) => RevericTheme(
                data: RevericThemeData.reveric,
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  routeContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pushReplacementMobileAiModePage(
      routeContext,
      mode: AiSessionMode.chat,
      novel: const MobileAiNovelContext(
        novelId: 'work_1',
        novelName: 'Screenplay',
        databasePath: '/unused/content.sqlite',
        contentKind: contentKindScreenplay,
        currentSeasonId: 'season_2',
        currentEpisodeId: 'episode_3',
        hasMultipleSeasons: true,
      ),
      rememberCurrent: false,
      restoreRemembered: false,
      useChatPreferredFallback: false,
    );
    final route = observer.replacement! as MaterialPageRoute<void>;
    final page = route.builder(routeContext) as MobileNovelChatPage;
    expect(page.currentSeasonId, 'season_2');
    expect(page.currentEpisodeId, 'episode_3');
    expect(page.hasMultipleSeasons, isTrue);
    expect(page.existingSessionId, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final page in [
    const MobileNovelChatPage(
      novelId: 'work_1',
      databasePath: '/unused/content.sqlite',
    ),
    const MobileCouncilPage(
      novelId: 'work_1',
      novelName: 'Test work',
      databasePath: '/unused/content.sqlite',
    ),
  ]) {
    testWidgets(
      '${page.runtimeType} requires a loaded work before exposing actions',
      (tester) async {
        final work = StreamController<Novel?>.broadcast();
        addTearDown(work.close);
        // rootBundle caches Futures; each widget test has a separate fake clock.
        rootBundle.clear();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              novelProvider('work_1').overrideWith((ref) => work.stream),
            ],
            child: EasyLocalization(
              supportedLocales: const [Locale('en')],
              path: 'assets/translations',
              assetLoader: const MergingAssetLoader(),
              fallbackLocale: const Locale('en'),
              startLocale: const Locale('en'),
              child: Builder(
                builder: (context) => MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  home: RevericTheme(
                    data: RevericThemeData.reveric,
                    child: page,
                  ),
                ),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 20 && find.byType(CircularProgressIndicator).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(MobileChatComposer), findsNothing);
        expect(find.byType(FilledButton), findsNothing);

        work.addError(StateError('work unavailable'));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(MobileChatComposer), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextButton), findsOneWidget);
        expect(tester.takeException(), isNull);

        work.add(null);
        await tester.pumpAndSettle();
        expect(find.byType(MobileChatComposer), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextButton), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
