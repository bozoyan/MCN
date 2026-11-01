// 职责: 审批卡片详情弹窗回归 — 弹窗内批准后只关闭弹窗，不连带弹出下层页面。
// 关联文件:
//   lib/shared/widgets/ai/tool_approval_card.dart
//   lib/shared/agent/tool_approval.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/tool_approval.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/tool_permission.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tool_approval_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('allowing once from details keeps the host page', (tester) async {
    final controller = AiToolApprovalController();
    final request = AiToolApprovalRequest(
      ownerSessionId: 's',
      approvalId: 'a',
      callId: 'c',
      toolName: 'generate_image',
      action: 'generation.image',
      permissionContext: const ToolPermissionContext(
        workId: 'w',
        sessionId: 's',
      ),
      targetPath: 'scene/1',
      targetLabel: '监测大厅',
      arguments: {'model': 'gpt-image-2', 'ratio': '16:9'},
      saveRule: (_, _) async {},
    );
    final outcome = controller.request(request);
    const theme = RevericThemeData.reveric;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiToolApprovalControllerProvider.overrideWithValue(controller),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('zh', 'CN')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          fallbackLocale: const Locale('zh', 'CN'),
          startLocale: const Locale('zh', 'CN'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: theme.toThemeData(),
              builder: (_, child) => RevericTheme(data: theme, child: child!),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Column(
                          children: [
                            const Text('host page'),
                            ToolApprovalCard(request: request),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('允许').last);
    await tester.pumpAndSettle();

    expect(await outcome, ToolApprovalOutcome.allowed);
    expect(find.text('host page'), findsOneWidget);
  });
}
