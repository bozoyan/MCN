// 职责: 用真实字体复核标准控件和已迁移标题栏、筛选条的跨平台明暗主题布局。
// 关联文件:
//   lib/shared/components/reveric_icon_button.dart
//   lib/shared/components/reveric_filter_chip.dart
//   lib/shared/components/reveric_badge.dart
//   lib/mobile/widgets/editor_app_bar.dart
//   lib/shared/components/reveric_search_field.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/ai/shared/ai_panel_header.dart';
import 'package:reveric/mobile/features/agent_skills/category_filter_bar.dart';
import 'package:reveric/shared/components/reveric_search_field.dart';
import 'package:reveric/mobile/widgets/editor_app_bar.dart';
import 'package:reveric/shared/components/reveric_badge.dart';
import 'package:reveric/shared/components/reveric_filter_chip.dart';
import 'package:reveric/shared/components/reveric_icon_button.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

RevericTypography _withFont(RevericTypography source) {
  TextStyle font(TextStyle style) => style.copyWith(fontFamily: 'ControlsTest');
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
    final loader = FontLoader('ControlsTest');
    loader.addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'));
    await loader.load();
  });
  setUp(() => rootBundle.clear());
  for (final mobile in [false, true]) {
    for (final dark in [false, true]) {
      final name =
          '${mobile ? 'mobile' : 'desktop'}_${dark ? 'dark' : 'light'}';
      testWidgets('standard controls $name', (tester) async {
        tester.view.physicalSize = Size(mobile ? 375 : 720, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final search = TextEditingController();
        final undo = UndoHistoryController(
          value: const UndoHistoryValue(canUndo: true),
        );
        addTearDown(search.dispose);
        addTearDown(undo.dispose);
        final data =
            (dark ? RevericThemeData.revericDark : RevericThemeData.reveric)
                .copyWith(
                  typography: _withFont(
                    mobile
                        ? RevericTypography.mobile
                        : RevericTypography.desktop,
                  ),
                );
        final colors = data.colors;
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
            path: 'assets/translations',
            assetLoader: const MergingAssetLoader(),
            fallbackLocale: const Locale('en'),
            startLocale: dark ? const Locale('zh', 'CN') : const Locale('en'),
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                theme: data
                    .toThemeData(fontFamily: 'ControlsTest')
                    .copyWith(
                      platform: mobile
                          ? TargetPlatform.android
                          : TargetPlatform.macOS,
                    ),
                home: RevericTheme(
                  data: data,
                  child: Scaffold(
                    body: RepaintBoundary(
                      key: const ValueKey('controls'),
                      child: ColoredBox(
                        color: colors.canvas,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('图标操作 / Icon actions'),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  RevericIconButton(
                                    icon: RevericIcons.add,
                                    tooltip: 'New',
                                    onPressed: () {},
                                  ),
                                  RevericIconButton(
                                    icon: RevericIcons.history_rounded,
                                    tooltip: 'History',
                                    onPressed: () {},
                                  ),
                                  const RevericIconButton(
                                    icon: RevericIcons.undo,
                                    tooltip: 'Undo',
                                    onPressed: null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text('筛选 / Filters'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  RevericFilterChip(
                                    label: '全部 All',
                                    count: 42,
                                    selected: true,
                                    onTap: () {},
                                  ),
                                  RevericFilterChip(
                                    label: '人物 Characters',
                                    count: 0,
                                    selected: false,
                                    onTap: () {},
                                  ),
                                  RevericFilterChip(
                                    label: '世界设定 Worldbuilding',
                                    selected: false,
                                    onTap: () {},
                                  ),
                                  const RevericFilterChip(
                                    label: '不可用 Disabled',
                                    selected: false,
                                    onTap: null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text('状态 / Status'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  RevericBadge(
                                    label: '已完成 Completed',
                                    color: colors.success,
                                  ),
                                  RevericBadge(
                                    label: '等待处理 Pending',
                                    color: colors.warningText,
                                  ),
                                  RevericBadge(
                                    label: '失败 Failed',
                                    color: colors.error,
                                  ),
                                  RevericBadge(
                                    label: '已归档 Archived',
                                    color: colors.textMuted,
                                  ),
                                  SizedBox(
                                    width: 140,
                                    child: RevericBadge(
                                      label: '等待处理 Waiting for processing',
                                      color: colors.accent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text('已迁移的标题栏 / Header'),
                              const SizedBox(height: 8),
                              if (mobile)
                                MobileEditorAppBar(
                                  title: '很长的角色名称 Long character name',
                                  saving: false,
                                  savedAt: DateTime(2026),
                                  onBack: () {},
                                  undoController: undo,
                                )
                              else
                                AiPanelHeader(
                                  icon: RevericIcons.history_rounded,
                                  title: '角色对话 / Character conversation',
                                  onNewSession: () {},
                                  onClose: () {},
                                ),
                              const SizedBox(height: 20),
                              const Text('书库和技能筛选 / Library and skills'),
                              const SizedBox(height: 8),
                              RevericSearchField(
                                controller: search,
                                hint: '搜索作品 / Search works',
                                height: RevericSizes.buttonHeight,
                                radius: RevericRadius.pill,
                                highlightWhenFilled: true,
                              ),
                              SkillCategoryFilterBar(
                                categories: const [
                                  '写作',
                                  '世界设定',
                                  'Character development',
                                ],
                                selected: '写作',
                                onSelect: (_) {},
                              ),
                            ],
                          ),
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
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('controls')),
          matchesGoldenFile('goldens/controls_$name.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
