// 职责: 测试 AgentSkill 安装冲突 dialog — 显示冲突 call_name,并按按钮返回
//   overwrite / rename / cancel 三种结果。验证 dialog 是安装冲突流程的
//   唯一交互入口,任何按钮错误路由都会破坏覆盖/重命名/取消语义。
// 关联文件:
//   lib/mobile/features/agent_skills/install_conflict_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/en/common.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/features/agent_skills/install_conflict_dialog.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  // 三个验证阶段合并到一个 testWidgets 中,遵循 .agents/rules/testing.md
  // 的模式:阶段间用 pumpWidget(SizedBox.shrink()) 清理 widget 树。
  // 原因:跨 testWidgets 时 widget 树无法渲染(详见 AGENTS.md Widget 测试隔离规则)。
  testWidgets(
    'install conflict dialog shows call_name and returns overwrite/rename/cancel',
    (tester) async {
      // ── 阶段 1:显示冲突 call_name + overwrite 按钮 ──
      InstallConflictAction? result;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showInstallConflictDialog(
                        context,
                        conflictCallName: 'Weather',
                      );
                    },
                    child: const Text('open-dialog'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open-dialog'));
      await tester.pumpAndSettle();

      // 冲突 call_name 必须出现在 dialog 正文中,这是用户判断该覆盖哪个技能的唯一线索。
      // en 翻译:This novel already has a skill with call name "Weather"
      expect(find.textContaining('Weather'), findsWidgets);
      expect(find.text(tr(LocaleKeys.agentSkillConflictTitle)), findsOneWidget);
      expect(find.text(tr(LocaleKeys.agentSkillOverwrite)), findsOneWidget);
      expect(find.text(tr(LocaleKeys.agentSkillRenameInstall)), findsOneWidget);
      expect(find.text(tr(LocaleKeys.commonCancel)), findsOneWidget);

      await tester.tap(find.text(tr(LocaleKeys.agentSkillOverwrite)));
      await tester.pumpAndSettle();

      expect(result, InstallConflictAction.overwrite);

      // 清理 widget 树,避免上一个 dialog 触达下一阶段。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // ── 阶段 2:rename 按钮 ──
      result = null;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showInstallConflictDialog(
                        context,
                        conflictCallName: 'Weather',
                      );
                    },
                    child: const Text('open-dialog'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open-dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(tr(LocaleKeys.agentSkillRenameInstall)));
      await tester.pumpAndSettle();

      expect(result, InstallConflictAction.rename);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // ── 阶段 3:cancel 按钮 ──
      result = null;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showInstallConflictDialog(
                        context,
                        conflictCallName: 'Weather',
                      );
                    },
                    child: const Text('open-dialog'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open-dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(tr(LocaleKeys.commonCancel)));
      await tester.pumpAndSettle();

      expect(result, InstallConflictAction.cancel);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return RevericTheme(
          data: RevericThemeData.reveric,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: child,
          ),
        );
      },
    ),
  );
}
