// 职责: 验证 LoRA 清单选择器的加载、搜索与选中回传。
// 关联文件:
//   lib/shared/widgets/production/modelscope_lora_picker.dart
//   lib/shared/services/ai/modelscope_catalog.dart
//   modelscope_models.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/services/ai/modelscope_catalog.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/production/modelscope_lora_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  startLocale: const Locale('en'),
  fallbackLocale: const Locale('en'),
  saveLocale: false,
  path: 'assets/translations',
  assetLoader: const MergingAssetLoader(),
  child: Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: RevericThemeData.reveric.toThemeData(),
      home: RevericTheme(
        data: RevericThemeData.reveric,
        child: Scaffold(body: child),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    ModelScopeLoraCatalog.resetCacheForTesting();
  });

  testWidgets('读取清单后展示条目，搜索可过滤，点选回传条目', (tester) async {
    ModelScopeCatalogEntry? picked;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                picked = await showModelScopeLoraPicker(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    // EasyLocalization 异步加载文案，首帧可能是空的。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 清单是真实文件 IO，不是 fake async，需要让真实事件循环跑几轮。
    for (var i = 0; i < 60 && find.text('YANBO').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Select LoRA'), findsOneWidget);
    // 清单首条（LORA 分类的 YANBO）应可见。
    expect(find.text('YANBO'), findsOneWidget);
    expect(find.text('bozoyan/YANBO'), findsOneWidget);

    // 搜索：只剩命中项。
    await tester.enterText(find.byType(TextField).first, 'bozoyan/z-yanbo');
    await tester.pumpAndSettle();
    expect(find.text('bozoyan/z-yanbo'), findsWidgets);
    expect(find.text('YANBO'), findsNothing);

    final tile = find
        .ancestor(
          of: find.text('bozoyan/z-yanbo'),
          matching: find.byType(InkWell),
        )
        .first;
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(picked?.modelId, 'bozoyan/z-yanbo');
    expect(picked?.triggerWord, isNotEmpty);
  });
}
