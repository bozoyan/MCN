// 职责: 验证回滚和剧本保存历史记录的本地化标题，并保留用户自定义提交说明。
// 关联文件:
//   lib/shared/widgets/history/change_history_components.dart
//   lib/shared/localization/merging_asset_loader.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/history.json
//   assets/translations/zh-CN/history.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/history/change_history_components.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  for (final (locale, expected) in [
    (
      const Locale('en'),
      {
        'history.commit_message.rollback_turn': 'Roll back AI changes',
        'history.commit_message.rollback_change_lines': 'Revert selected lines',
        'history.commit_message.rollback_selected_commit':
            'Roll back this change',
        'history.commit_message.restore_to_historical_version':
            'Restore to historical version',
        'history.commit_message.manual_scene_save': 'Manual scene save',
        'history.commit_message.manual_episode_outline_save':
            'Manual episode outline save',
      },
    ),
    (
      const Locale('zh', 'CN'),
      {
        'history.commit_message.rollback_turn': '回滚 AI 变更',
        'history.commit_message.rollback_change_lines': '按行退回变更',
        'history.commit_message.rollback_selected_commit': '回滚本次变更',
        'history.commit_message.restore_to_historical_version': '恢复到历史版本',
        'history.commit_message.manual_scene_save': '手动保存场次',
        'history.commit_message.manual_episode_outline_save': '手动保存集大纲',
      },
    ),
  ]) {
    testWidgets(
      'localizes persisted commit titles in $locale',
      (tester) async {
        const customMessage = 'My revision';
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
            path: 'assets/translations',
            assetLoader: const MergingAssetLoader(),
            fallbackLocale: const Locale('en'),
            startLocale: locale,
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                theme: RevericThemeData.reveric.toThemeData(),
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => Column(
                        children: [
                          for (final rawMessage in expected.keys)
                            Text(localizedCommitMessage(context, rawMessage)),
                          Text(localizedCommitMessage(context, customMessage)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final entry in expected.entries) {
          expect(find.text(entry.value), findsOneWidget);
          expect(find.text(entry.key), findsNothing);
        }
        expect(find.text(customMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
