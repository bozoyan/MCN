// 职责: 验证小说工作区底部状态栏只展示需要人工处理的变更，并适配紧凑宽度。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/novel_workspace_panel.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  test('manual autosave changes do not enter the pending review badge', () {
    expect(
      countReviewableWorkspaceChanges([
        _workingChange(source: workingChangeSourceManual),
        _workingChange(source: workingChangeSourceAi),
        _workingChange(
          source: workingChangeSourceAi,
          status: workingChangeStatusCommitted,
        ),
      ]),
      1,
    );
  });

  testWidgets('keeps chapter metrics visible at compact widths', (
    tester,
  ) async {
    Widget buildStatusBar(double width) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 32,
              child: const NovelWorkspaceStatusBarLayout(
                primaryStatus: SizedBox(width: 111),
                secondaryStatus: Text('字数 1', key: Key('secondary-status')),
                actions: SizedBox(width: 350),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildStatusBar(711.7));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('secondary-status')), findsOneWidget);
    expect(find.text('字数 1'), findsOneWidget);

    await tester.pumpWidget(buildStatusBar(540));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('secondary-status')), findsOneWidget);
    expect(find.text('字数 1'), findsOneWidget);
  });

  testWidgets('shows compact auto-save and reading-time feedback', (
    tester,
  ) async {
    final savedSignal = ValueNotifier<int>(0);
    var siblingBuildCount = 0;

    await tester.pumpWidget(
      _wrap(
        Row(
          children: [
            NovelWorkspaceAutoSaveStatus(
              savedSignal: savedSignal,
              successDisplayDuration: const Duration(milliseconds: 600),
              fadeDuration: const Duration(milliseconds: 100),
              now: () => DateTime(2026, 1, 2, 9, 8, 7),
            ),
            NovelWorkspaceSaveButton(isLocked: false, onSave: () async {}),
            _BuildProbe(
              onBuild: () {
                siblingBuildCount += 1;
              },
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusFinder = find.byType(NovelWorkspaceAutoSaveStatus);
    final initialWidth = tester.getSize(statusFinder).width;
    expect(_opacity(tester, 'auto-save-enabled-opacity'), 1);
    expect(_opacity(tester, 'auto-save-success-opacity'), 0);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('保存中...'), findsNothing);
    expect(siblingBuildCount, 1);

    savedSignal.value += 1;
    await tester.pump();

    expect(_opacity(tester, 'auto-save-enabled-opacity'), 0);
    expect(_opacity(tester, 'auto-save-success-opacity'), 1);
    expect(find.text('09:08:07 自动保存成功'), findsOneWidget);
    expect(tester.getSize(statusFinder).width, initialWidth);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('保存中...'), findsNothing);
    expect(siblingBuildCount, 1);

    await tester.pump(const Duration(milliseconds: 601));

    expect(_opacity(tester, 'auto-save-enabled-opacity'), 1);
    expect(_opacity(tester, 'auto-save-success-opacity'), 0);
    expect(tester.getSize(statusFinder).width, initialWidth);
    expect(siblingBuildCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    savedSignal.dispose();
    final controller = TextEditingController(
      text: List<String>.filled(201, '字').join(),
    );

    await tester.pumpWidget(
      _wrap(NovelWorkspaceChapterStatusMetrics(controller: controller)),
    );
    await tester.pumpAndSettle();

    final tooltipFinder = find.byType(Tooltip);
    final tooltip = tester.widget<Tooltip>(tooltipFinder);
    expect(tooltip.message, '预计阅读 2 分钟');
    expect(find.text(tooltip.message!), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(tooltipFinder));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(tooltip.message!), findsOneWidget);

    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

double _opacity(WidgetTester tester, String key) {
  return tester.widget<AnimatedOpacity>(find.byKey(Key(key))).opacity;
}

class _BuildProbe extends StatelessWidget {
  const _BuildProbe({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox(width: 40);
  }
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    key: UniqueKey(),
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
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

WorkingChange _workingChange({
  required String source,
  String status = workingChangeStatusActive,
}) {
  final now = DateTime(2026);
  return WorkingChange(
    id: 'change_$source',
    resourcePath: '/chapters/chapter_1/content',
    resourceType: 'chapters',
    resourceId: 'chapter_1',
    field: 'content',
    changeType: 'write',
    source: source,
    summary: 'Update chapter content',
    oldText: 'old',
    newText: 'new',
    baseVersion: 0,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}
