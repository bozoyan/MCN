// 职责: 验证制作页恢复分集选择时显示加载反馈，恢复后才显示真正的未选择状态。
// 关联文件:
//   lib/desktop/features/production/region.dart
//   lib/shared/providers/screenplay_workspace_state_provider.dart
//   lib/shared/widgets/screenplay/loading.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/region.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/screenplay_workspace_state.dart';
import 'package:reveric/shared/providers/screenplay_workspace_state_provider.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/screenplay/loading.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RestoringWorkspace extends ScreenplayWorkspaceStateController {
  @override
  ScreenplayWorkspaceState build(String workId, String databasePath) =>
      ScreenplayWorkspaceState.initial();

  void finishWithoutEpisodes() {
    state = state.copyWith(isHydrated: true);
  }
}

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  testWidgets(
    'restoring selection is loading, not an empty episode selection',
    (tester) async {
      final controller = _RestoringWorkspace();
      final now = DateTime(2026);
      final novel = Novel(
        id: 'work',
        title: 'Screenplay',
        authorName: '',
        description: '',
        status: 'in_progress',
        type: 'original',
        contentKind: 'screenplay',
        contentDatabasePath: 'test',
        wordCount: 0,
        draft: false,
        category: '',
        tags: const [],
        createdAt: now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            screenplayWorkspaceStateControllerProvider(
              'work',
              'test',
            ).overrideWith(() => controller),
          ],
          child: EasyLocalization(
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
                theme: RevericThemeData.reveric.toThemeData(),
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: ProductionRegion(novel: novel, registerFlush: (_) {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // 保持恢复未完成，观察异步资源加载后的第一份有效 UI。
      for (
        var i = 0;
        i < 30 && find.byType(ProductionRegion).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();
      expect(find.text('Select an episode first'), findsNothing);
      expect(find.byType(ScreenplayLoading), findsOneWidget);
      expect(find.text('Opening screenplay…'), findsOneWidget);
      controller.finishWithoutEpisodes();
      await tester.pumpAndSettle();
      expect(find.byType(ScreenplayLoading), findsNothing);
      expect(find.text('Select an episode first'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );
}
