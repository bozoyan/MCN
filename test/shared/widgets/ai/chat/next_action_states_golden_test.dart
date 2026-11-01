// 职责: 下一步建议三态黄金图（加载真实字体），人工目检「有建议 / 无建议 / 空态」的视觉落点（非 CI 断言）。
// 关联文件:
//   lib/shared/widgets/ai/chat/next_action_bar.dart
//   lib/shared/widgets/ai/chat/assistant_empty_state.dart
//   lib/shared/heuristic/chat_next_action.dart
//   assets/translations/zh-CN/heuristic.json

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/heuristic/chat_next_action.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/feature_id.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/assistant_empty_state.dart';
import 'package:reveric/shared/widgets/ai/chat/next_action_bar.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
  });

  // 三态放同一棵树出一张图：EasyLocalization 的 delegate 在同一个测试里只加载
  // 一次，拆成多个 testWidgets 时后续用例拿到空子树（见 .agents/rules/testing.md）。
  testWidgets('golden: next action states (suggest / none / empty)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('next-action-golden')),
      matchesGoldenFile('goldens/next_action_states.png'),
    );
  });
}

const _modelActions = [
  ChatNextAction(
    id: 'check_timeline',
    label: '核对第 03 章的时间线与老沈行踪',
    target: PromptActionTarget('请核对第 03 章的时间线与老沈行踪'),
  ),
  ChatNextAction(
    id: 'goto_council',
    feature: FeatureId.ai_council,
    label: '木匣的交代时机去圆桌听几个视角',
    target: FeatureActionTarget(FeatureId.ai_council, seedText: '木匣该何时交代'),
  ),
  ChatNextAction(
    id: 'goto_theater',
    feature: FeatureId.ai_theater,
    label: '先把三舱对峙演一遍',
    target: FeatureActionTarget(FeatureId.ai_theater),
  ),
];

Widget _wrap() {
  // 空态卡片用的 RevericElevatedInkWell 是 ConsumerWidget（读背景态）。
  // 背景态往下会读设置库（path_provider），测试环境没有插件，直接 override 成关闭。
  return ProviderScope(
    overrides: [appBackgroundActiveProvider.overrideWithValue(false)],
    child: EasyLocalization(
      supportedLocales: const [Locale('zh', 'CN')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('zh', 'CN'),
      startLocale: const Locale('zh', 'CN'),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            // UI 文本样式不指定 family，测试环境默认字体没有中文字形（渲染成方框）。
            // 把加载好的中文字体设为主题 family，golden 才能人工目检文案。
            theme: RevericThemeData.reveric.toThemeData(
              fontFamily: 'LXGWWenKai',
            ),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Builder(
                builder: (context) {
                  final colors = RevericTheme.colorsOf(context);
                  return Scaffold(
                    backgroundColor: colors.surfaceContainerHigh,
                    body: RepaintBoundary(
                      key: const ValueKey('next-action-golden'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Section(
                            label: '① 有建议：chip 条贴在输入框上方',
                            child: Column(
                              children: [
                                NextActionBar(
                                  actions: _modelActions,
                                  onPick: (_) {},
                                ),
                                const _FakeComposer(),
                              ],
                            ),
                          ),
                          _Section(
                            label: '② 无建议：不渲染、不占高度、无残留间距',
                            child: Column(
                              children: const [
                                NextActionBar(actions: [], onPick: _noop),
                                _FakeComposer(),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _Section(
                              label: '③ 空会话：客户端固定目录',
                              child: AssistantEmptyState(
                                actions: emptyStateActions(
                                  const ChatNextActionEnvironment(
                                    metadataReady: true,
                                    setupDone: true,
                                  ),
                                ),
                                onActionTap: (_) {},
                                illustrationHeight: 96,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

void _noop(ChatNextAction _) {}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: colors.surfaceDim,
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.lg,
              vertical: RevericSpacing.xs,
            ),
            child: Text(
              label,
              style: typo.uiTiny.copyWith(color: colors.textSubtle),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// 输入框占位：用来目检建议条与它之间的间距，不是真实 composer。
class _FakeComposer extends StatelessWidget {
  const _FakeComposer();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        RevericSpacing.lg,
        0,
        RevericSpacing.lg,
        RevericSpacing.lg,
      ),
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderInput),
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      child: Text(
        '和 AI 聊聊这一章…',
        style: typo.uiSmall.copyWith(color: colors.textSubtle),
      ),
    );
  }
}
