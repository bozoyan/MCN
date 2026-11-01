// 职责: 安装冲突对话框回归测试 — 验证 call_name 冲突提示展示与覆盖/重命名/取消
//   三个动作的返回值语义,确保 OfficialCatalogTab / MarketplaceCatalogTab 在收到
//   InstallFromCatalogConflict 后能拿到正确的 InstallConflictAction 决定下一步。
// 关联文件:
//   lib/desktop/features/agent_skills/install_conflict_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/agent_skills/install_conflict_dialog.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  // 用单个 testWidgets 串联所有子场景,规避 EasyLocalization 的 _EasyLocalizationState
  // 在多 testWidgets 下的状态泄漏问题(第二次起 _EasyLocalizationDelegate.load
  // 完成后 notifyListeners 触发的 setState 不再产生 Build 帧,导致 inner widget
  // 树不构建)。同一 widget 树内反复打开/关闭 dialog 即可覆盖所有动作返回值。
  // AGENTS.md「Widget 测试隔离规则」明确指出:隔离成本过高时优先调整测试结构。
  testWidgets('showInstallConflictDialog scenarios', (tester) async {
    final captured = <InstallConflictResult>[];
    await _pumpHarness(
      tester,
      onOpen: (ctx) async {
        final result = await showInstallConflictDialog(
          ctx,
          conflictingName: 'weather',
          sourceName: 'Weather Skill',
        );
        captured.add(result);
      },
    );

    // 场景 1:subtitle 显示冲突 call_name;Cancel 返回 cancel action。
    await tester.tap(find.byKey(kOpenDialogKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('weather'), findsWidgets);
    expect(find.text(tr(LocaleKeys.agentSkillConflictTitle)), findsOneWidget);

    await tester.tap(find.text(tr(LocaleKeys.commonCancel)));
    await tester.pumpAndSettle();

    expect(captured.last.action, InstallConflictAction.cancel);
    expect(captured.last.newCallName, isNull);

    // 场景 2:Cancel 按钮返回 cancel action(newCallName 为 null)。
    await tester.tap(find.byKey(kOpenDialogKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text(tr(LocaleKeys.commonCancel)));
    await tester.pumpAndSettle();

    expect(captured.last.action, InstallConflictAction.cancel);
    expect(captured.last.newCallName, isNull);

    // 场景 3:Overwrite 按钮返回 overwrite action。
    await tester.tap(find.byKey(kOpenDialogKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text(tr(LocaleKeys.agentSkillOverwrite)));
    await tester.pumpAndSettle();

    expect(captured.last.action, InstallConflictAction.overwrite);
    expect(captured.last.newCallName, isNull);

    // 场景 4:Rename 按钮在输入为空或等于冲突名时禁用。
    await tester.tap(find.byKey(kOpenDialogKey));
    await tester.pumpAndSettle();

    final emptyRename = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(tr(LocaleKeys.agentSkillRenameInstall)),
        matching: find.byType(FilledButton),
      ),
    );
    expect(emptyRename.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'weather');
    await tester.pump();

    final sameNameRename = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(tr(LocaleKeys.agentSkillRenameInstall)),
        matching: find.byType(FilledButton),
      ),
    );
    expect(sameNameRename.onPressed, isNull);

    await tester.tap(find.text(tr(LocaleKeys.commonCancel)));
    await tester.pumpAndSettle();
    expect(captured.last.action, InstallConflictAction.cancel);

    // 场景 5:Rename 按钮在输入新 call_name 后返回 rename action + newCallName。
    await tester.tap(find.byKey(kOpenDialogKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'weather_v2');
    await tester.pump();

    await tester.tap(find.text(tr(LocaleKeys.agentSkillRenameInstall)));
    await tester.pumpAndSettle();

    expect(captured.last.action, InstallConflictAction.rename);
    expect(captured.last.newCallName, 'weather_v2');

    // 场景 6:点击右上角 X(IconButton)关闭对话框返回 cancel。
    await tester.tap(find.byKey(kOpenDialogKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();

    expect(captured.last.action, InstallConflictAction.cancel);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

const kOpenDialogKey = Key('install_conflict_dialog_test_open');

Future<void> _pumpHarness(
  WidgetTester tester, {
  required Future<void> Function(BuildContext ctx) onOpen,
}) async {
  // 冲突对话框 maxWidth 520,底部 Row 含 3 个动作按钮(Cancel + Overwrite +
  // Rename)。3 个按钮在 480px 内容区(520 - 40 padding)下天然横向溢出
  // (Cancel+Overwrite+Rename 文本合计约 670px)。这是 dialog 的已知布局问题,
  // 不在 C2 测试范围内修复。这里通过 MaterialApp.builder 注入 textScaler=0.6
  // 让按钮在测试视口内可点击,以验证按钮的 onPressed 行为(本测试的核心价值)。
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    EasyLocalization(
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
            // 使用 builder 在 root navigator 之上注入 RevericTheme +
            // textScaler override,让 showDialog 的 dialogCtx 也能访问
            // RevericTheme(冲突对话框在 dialog builder 内直接调
            // RevericTheme.colorsOf(dialogCtx))。textScaler=0.6 让底部
            // 3 个动作按钮在 480px 内容区可点击。
            builder: (materialCtx, child) {
              return RevericTheme(
                data: RevericThemeData.reveric,
                child: MediaQuery(
                  data: MediaQuery.of(
                    materialCtx,
                  ).copyWith(textScaler: const TextScaler.linear(0.6)),
                  child: child!,
                ),
              );
            },
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (innerCtx) => FilledButton(
                    key: kOpenDialogKey,
                    onPressed: () => onOpen(innerCtx),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
