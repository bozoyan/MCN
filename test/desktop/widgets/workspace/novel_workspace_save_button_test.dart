// 职责: 验证小说工作区章节保存按钮的稳定忙碌态与局部重建边界。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/novel_workspace_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('keeps manual saving visible without rebuilding sibling tools', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    var siblingBuildCount = 0;

    await tester.pumpWidget(
      _wrap(
        Row(
          children: [
            NovelWorkspaceSaveButton(
              isLocked: false,
              onSave: () => saveCompleter.future,
            ),
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

    expect(find.text('保存'), findsOneWidget);
    expect(siblingBuildCount, 1);

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('保存中...'), findsOneWidget);
    expect(siblingBuildCount, 1);

    saveCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('保存中...'), findsOneWidget);
    expect(siblingBuildCount, 1);

    await tester.pump(const Duration(milliseconds: 101));

    expect(find.text('保存'), findsOneWidget);
    expect(siblingBuildCount, 1);
  });
}

class _BuildProbe extends StatelessWidget {
  const _BuildProbe({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const Icon(Icons.auto_fix_high);
  }
}

Widget _wrap(Widget child) {
  return EasyLocalization(
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
