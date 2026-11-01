// 职责: 为导演台测试提供真实主题与本地化资源。
// 关联文件:
//   lib/shared/localization/merging_asset_loader.dart
//   lib/shared/theme/theme.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';

Future<void> initializeDirectorTest() async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
}

Widget directorTestApp(Widget child, {Locale locale = const Locale('en')}) =>
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      startLocale: locale,
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          builder: (context, child) =>
              RevericTheme(data: RevericThemeData.reveric, child: child!),
          home: Scaffold(body: child),
        ),
      ),
    );
