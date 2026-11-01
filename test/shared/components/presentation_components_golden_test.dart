// 职责: 用真实字体检查分段选择、占位状态及移动弹层的跨平台明暗主题外观。
// 关联文件:
//   lib/shared/components/reveric_segmented_control.dart
//   lib/shared/components/reveric_placeholder.dart
//   lib/mobile/widgets/sheet.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_segmented_control.dart';
import 'package:reveric/shared/components/reveric_placeholder.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/mobile/widgets/sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

RevericTypography _withFont(RevericTypography source) {
  TextStyle font(TextStyle style) =>
      style.copyWith(fontFamily: 'PresentationTest');
  return RevericTypography(
    display: font(source.display),
    heading2: font(source.heading2),
    body: font(source.body),
    bodySmall: font(source.bodySmall),
    bodyItalic: font(source.bodyItalic),
    ui: font(source.ui),
    uiMedium: font(source.uiMedium),
    uiSemibold: font(source.uiSemibold),
    uiSmall: font(source.uiSmall),
    uiSmallSemibold: font(source.uiSmallSemibold),
    uiTiny: font(source.uiTiny),
    uiTinySemibold: font(source.uiTinySemibold),
    mono: font(source.mono),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final loader = FontLoader('PresentationTest');
    loader.addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'));
    await loader.load();
  });
  setUp(() => rootBundle.clear());
  for (final mobile in [false, true]) {
    for (final dark in [false, true]) {
      final name =
          '${mobile ? 'mobile' : 'desktop'}_${dark ? 'dark' : 'light'}';
      testWidgets('presentation $name', (tester) async {
        tester.view.physicalSize = Size(mobile ? 375 : 640, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final data =
            (dark ? RevericThemeData.revericDark : RevericThemeData.reveric)
                .copyWith(
                  typography: _withFont(
                    mobile
                        ? RevericTypography.mobile
                        : RevericTypography.desktop,
                  ),
                );
        await tester.pumpWidget(
          _wrap(
            data,
            mobile,
            Column(
              children: [
                const SizedBox(height: 24),
                Padding(padding: const EdgeInsets.all(16), child: _segments()),
                RevericPlaceholder.empty(
                  icon: RevericIcons.account_tree,
                  title: '还没有文档',
                  description: '创建文档，整理作品的设定与写作资料。',
                  action: RevericButton.primary(
                    label: '新建文档',
                    icon: RevericIcons.add,
                    onPressed: () {},
                  ),
                ),
                RevericPlaceholder.error(
                  title: '暂时无法加载列表',
                  description: '请稍后重试。已有内容会保留。',
                  action: RevericButton.secondary(
                    label: '重试',
                    onPressed: () {},
                  ),
                ),
                const RevericPlaceholder.empty(
                  icon: RevericIcons.menu_book_outlined,
                  title: 'No chapters yet',
                  compact: true,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('capture')),
          matchesGoldenFile('goldens/presentation_$name.png'),
        );
      });
      if (mobile) {
        testWidgets('sheet $name', (tester) async {
          tester.view.physicalSize = const Size(375, 667);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final data =
              (dark ? RevericThemeData.revericDark : RevericThemeData.reveric)
                  .copyWith(typography: _withFont(RevericTypography.mobile));
          await tester.pumpWidget(
            _wrap(
              data,
              true,
              Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () => showMobileSheet<void>(
                    context: context,
                    builder: (context) => MobileSheetScaffold(
                      header: MobileSheetHeader.closable(
                        title: '文档设置',
                        onClose: () => Navigator.of(context).pop(),
                      ),
                      footer: RevericButton.primary(
                        label: '保存',
                        onPressed: () {},
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const RevericTextField(
                                label: '名称',
                                hintText: '章节润色',
                              ),
                              const SizedBox(height: 16),
                              const RevericTextField(
                                label: '说明',
                                multiline: true,
                                minLines: 3,
                                maxLines: 3,
                                hintText: '描述文档的用途',
                              ),
                              const SizedBox(height: 16),
                              _segments(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('capture')),
            matchesGoldenFile('goldens/sheet_$name.png'),
          );
        });
      }
    }
  }
}

Widget _segments() => RevericSegmentedControl<int>(
  selected: 0,
  onChanged: (_) {},
  segments: const [
    RevericSegment(
      value: 0,
      label: '自动运行',
      icon: RevericIcons.clock,
      badgeLabel: '12',
    ),
    RevericSegment(value: 1, label: 'Manual execution'),
  ],
);

Widget _wrap(
  RevericThemeData data,
  bool mobile,
  Widget child,
) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  path: 'assets/translations',
  assetLoader: const MergingAssetLoader(),
  startLocale: const Locale('en'),
  fallbackLocale: const Locale('en'),
  child: Builder(
    builder: (context) => MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: data
          .toThemeData(fontFamily: 'PresentationTest')
          .copyWith(
            platform: mobile ? TargetPlatform.android : TargetPlatform.macOS,
          ),
      builder: (context, child) => RevericTheme(
        data: data,
        child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
      ),
      home: Scaffold(body: child),
    ),
  ),
);
