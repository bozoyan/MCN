// 职责: 验证 AI 消息操作确认弹窗返回值 — 确认继续，取消中止。
// 关联文件:
//   lib/shared/widgets/ai/chat/message_action_confirm_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/message_action_confirm_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('message action confirms return true only after confirmation', (
    tester,
  ) async {
    bool? forkResult;
    bool? rollbackResult;

    await tester.pumpWidget(
      _wrapDialogLauncher(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogLauncher(
              label: 'Open fork',
              onLaunch: showAiForkSessionConfirmDialog,
              onResult: (value) => forkResult = value,
            ),
            _DialogLauncher(
              label: 'Open rollback',
              onLaunch: showAiRollbackMessageConfirmDialog,
              onResult: (value) => rollbackResult = value,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open fork'));
    await tester.pumpAndSettle();

    expect(find.text('Fork session?'), findsOneWidget);
    expect(forkResult, isNull);

    await tester.tap(find.text('Fork session'));
    await tester.pumpAndSettle();

    expect(forkResult, isTrue);

    await tester.tap(find.text('Open rollback'));
    await tester.pumpAndSettle();

    expect(find.text('Rollback message?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(rollbackResult, isFalse);
  });
}

class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher({
    required this.label,
    required this.onLaunch,
    required this.onResult,
  });

  final String label;
  final Future<bool> Function(BuildContext context) onLaunch;
  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () async {
        onResult(await onLaunch(context));
      },
      child: Text(label),
    );
  }
}

Widget _wrapDialogLauncher(Widget child) {
  return EasyLocalization(
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
            child: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}
