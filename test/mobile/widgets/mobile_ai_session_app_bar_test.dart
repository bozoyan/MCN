// 职责: 验证窄屏长标题下 AI 标题栏的触控区、文字边界与操作回调（含头像打开助手权限）。
// 关联文件:
//   lib/mobile/widgets/mobile_ai_session_app_bar.dart
//   lib/shared/components/reveric_icon_button.dart
//   lib/shared/widgets/ai/ai_avatar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/widgets/mobile_ai_session_app_bar.dart';
import 'package:reveric/mobile/widgets/mobile_ai_mode.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/components/reveric_icon_button.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/ai_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  const data = RevericThemeData.reveric;
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: data.toThemeData().copyWith(platform: TargetPlatform.android),
        builder: (context, child) => RevericTheme(data: data, child: child!),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());
  testWidgets('320px long title preserves action targets and callbacks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var history = 0;
    var created = 0;
    var permissions = 0;
    const title = '这是一个很长的作品标题，用来检查窄屏标题栏';
    await tester.pumpWidget(
      _wrap(
        MobileAiSessionScaffold(
          title: title,
          subtitle: '这是一个很长的会话说明，用来检查省略显示',
          currentMode: AiSessionMode.chat,
          novelContext: const MobileAiNovelContext(
            novelId: 'test',
            novelName: title,
            databasePath: '',
          ),
          historyTooltip: 'History',
          newSessionTooltip: 'New',
          onHistory: () => history++,
          onNew: () => created++,
          onPermissions: () => permissions++,
          onModeSelected: (_) {},
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final actions = find.byType(RevericIconButton);
    expect(actions, findsNWidgets(3));
    final avatarSize = tester.getSize(find.byType(AiAvatar));
    expect(avatarSize.width, greaterThanOrEqualTo(48));
    expect(avatarSize.height, greaterThanOrEqualTo(48));
    for (final element in actions.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    final titleRect = tester.getRect(find.text(title));
    final historyRect = tester.getRect(find.byTooltip('History'));
    expect(titleRect.width, greaterThan(100));
    expect(titleRect.right, lessThanOrEqualTo(historyRect.left));
    expect(
      tester.widget<Text>(find.text(title)).overflow,
      TextOverflow.ellipsis,
    );
    await tester.tap(find.byTooltip('History'));
    await tester.tap(find.byTooltip('New'));
    await tester.tap(find.byType(AiAvatar));
    expect(history, 1);
    expect(created, 1);
    expect(permissions, 1);
  });
}
