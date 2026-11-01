// 职责: 验证桌面新建表单切换小说 / 剧本时横幅换成对应入口、对话框不变形，改编横幅切到改编类型。
// 关联文件:
//   lib/desktop/widgets/novel_form_dialog.dart
//   lib/shared/providers/dictionary_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/components/dialog_feedback.dart';
import 'package:reveric/shared/components/reveric_segmented_control.dart';
import 'package:reveric/desktop/widgets/novel_form_dialog.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/providers/dictionary_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('switching work kind swaps the banner without resizing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pumpDialog(String contentKind) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelCategoriesProvider.overrideWith(
              (ref) async => const <String>[],
            ),
            novelTagsProvider.overrideWith((ref) async => const <String>[]),
            novelsProvider.overrideWith((ref) => Stream.value(const <Novel>[])),
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
                  child: DialogFeedback.scope(
                    builder: (_) => NovelFormDialog.create(
                      initialContentKind: contentKind,
                      onQuickStart: () {},
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder kindTab(String label) => find.descendant(
      of: find.byType(RevericSegmentedControl<String>),
      matching: find.text(label),
    );

    await pumpDialog(contentKindNovel);
    expect(find.text('Quick Start'), findsOneWidget);
    expect(find.text('Planned episodes'), findsNothing);
    final dialogRect = tester.getRect(find.byType(Dialog));

    // 快速开书只建小说；剧本同一槽位换成从小说改编，作者行并入计划集数，尺寸不变。
    await tester.tap(kindTab('Screenplay'));
    await tester.pumpAndSettle();
    expect(find.text('Quick Start'), findsNothing);
    expect(find.text('Adapt a novel'), findsOneWidget);
    expect(find.text('Planned episodes'), findsOneWidget);
    expect(tester.getRect(find.byType(Dialog)), dialogRect);

    await tester.tap(find.text('Adapt a novel'));
    await tester.pumpAndSettle();
    expect(find.text('Adapted from'), findsOneWidget);

    // 小说不能是改编：切回小说时类型回到原创，来源字段随之收起。
    await tester.tap(kindTab('Novel'));
    await tester.pumpAndSettle();
    expect(find.text('Adapted from'), findsNothing);
    expect(find.text('Quick Start'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
