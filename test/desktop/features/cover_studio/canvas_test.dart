// 职责: 验证封面画布能构建 — 空态、失败格与工具带在真实列宽下无溢出，失败格给出可操作的下一步。
// 关联文件:
//   lib/desktop/features/cover_studio/canvas.dart
//   lib/shared/providers/cover_studio_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/features/cover_studio/canvas.dart';
import 'package:reveric/shared/providers/cover_studio_providers.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  late AppDatabase database;

  setUp(() => database = AppDatabase.forTest(NativeDatabase.memory()));
  tearDown(() => database.close());

  // 同一文件只放一个 testWidgets：第二个重包 EasyLocalization 会拿到空子树。
  testWidgets('画布在真实列宽下渲染空态与失败格，且不溢出', (tester) async {
    // 编辑器布局里画布大约这么宽（1470 - 侧栏 - 332 设计师列）。
    await tester.binding.setSurfaceSize(const Size(880, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reworked = <int>[];
    await tester.pumpWidget(
      _wrap(
        database: database,
        child: CoverStudioCanvas(
          novelId: 'novel_test',
          novelTitle: '南渡记',
          slots: const [],
          appliedAssetId: null,
          onRework: reworked.add,
          onApply: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 空态标题使用当前翻译文案，且不再提供误导性的生成按钮。
    expect(find.text('Cover preview'), findsOneWidget);
    expect(find.text('Generate 1 schemes'), findsNothing);

    // 换成「第 2 格未过审」的批次：失败格要说清是哪一类错、下一步做什么。
    await tester.pumpWidget(
      _wrap(
        database: database,
        child: CoverStudioCanvas(
          novelId: 'novel_test',
          novelTitle: '南渡记',
          slots: const [
            CoverSlotView(ordinal: 0, status: imageBatchSlotStatusPending),
            CoverSlotView(
              ordinal: 1,
              status: imageBatchSlotStatusFailed,
              errorCode: 'moderation',
            ),
          ],
          appliedAssetId: null,
          onRework: reworked.add,
          onApply: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 默认选中第 0 格（还在画），工具带与底部动作都在。
    // 缩放读数跟比例与舞台尺寸走，这里只要求工具带上有一个百分比读数。
    expect(find.textContaining(RegExp(r'^\d+%$')), findsOneWidget);
    expect(find.text('Set as novel cover'), findsOneWidget);

    // 点到失败的那一格。
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Blocked by content policy'), findsOneWidget);
    expect(find.text('Redo this one'), findsWidgets);

    // 失败格里的「重出这张」要能把序号传回去。
    await tester.tap(find.text('Redo this one').first);
    await tester.pump();
    expect(reworked, [1]);

    // 缩略图列贴着主图放，不能被工具带或说明行推走。
    final paper = tester.getRect(
      find.byKey(const ValueKey('cover-stage-paper')),
    );
    final strip = tester.getRect(find.byKey(const ValueKey('cover-filmstrip')));
    expect(strip.left - paper.right, greaterThan(0));

    expect(find.text('2K'), findsOneWidget);
    expect(find.text('Generate similar'), findsNothing);
  });
}

Widget _wrap({required AppDatabase database, required Widget child}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      // 门禁会 watch Reveric 封面模型；测试不接 settings DB，固定为无配置。
      coverStudioImageModelSelectionProvider.overrideWithValue(null),
    ],
    child: EasyLocalization(
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
    ),
  );
}
