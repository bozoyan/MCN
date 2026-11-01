// 职责: 验证三种桌面平台的唤起失败提示能独立显示、切换语言并关闭，无需业务 Provider。
// 关联文件:
//   lib/desktop/widgets/activation_failure_app.dart
//   lib/shared/localization/merging_asset_loader.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/app.json
//   assets/translations/zh-CN/app.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/activation_failure_app.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    rootBundle.clear();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
      testWidgets(
        'standalone activation failure on $platform $locale',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            await tester.binding.setSurfaceSize(const Size(600, 360));
            var closed = false;
            var logsOpened = false;
            await tester.pumpWidget(
              EasyLocalization(
                supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
                path: 'assets/translations',
                assetLoader: const MergingAssetLoader(),
                startLocale: locale,
                saveLocale: false,
                child: ActivationFailureApp(
                  onOpenLogs: () async {
                    logsOpened = true;
                    return true;
                  },
                  onClose: () {
                    closed = true;
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text(
                locale.languageCode == 'en' ? 'Startup failed' : '启动失败',
              ),
              findsOneWidget,
            );
            await tester.tap(
              find.text(
                locale.languageCode == 'en' ? 'Open logs folder' : '打开日志文件夹',
              ),
            );
            await tester.pumpAndSettle();
            expect(logsOpened, isTrue);
            await tester.tap(
              find.text(locale.languageCode == 'en' ? 'Close' : '关闭'),
            );
            expect(closed, isTrue);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          } finally {
            await tester.binding.setSurfaceSize(null);
            debugDefaultTargetPlatformOverride = null;
          }
        },
        timeout: const Timeout(Duration(seconds: 20)),
      );
    }
  }
}
