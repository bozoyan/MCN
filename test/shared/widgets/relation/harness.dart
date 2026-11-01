// 职责: 为共享关系组件提供隔离内容库、真实本地化与主题测试环境。
// 关联文件:
//   lib/shared/widgets/relation/detail.dart
//   lib/shared/widgets/relation/history.dart
//   lib/shared/localization/merging_asset_loader.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/theme/theme.dart';

Widget relationHarness(
  NovelContentDatabase db,
  Widget child, {
  double width = 440,
  double height = 700,
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: [
    novelContentDatabaseProvider('test').overrideWithValue(db),
    novelContentServiceProvider(
      'test',
    ).overrideWithValue(NovelContentService(db)),
  ],
  child: EasyLocalization(
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
        theme: RevericThemeData.reveric.toThemeData().copyWith(
          platform: platform,
        ),
        builder: (context, child) =>
            RevericTheme(data: RevericThemeData.reveric, child: child!),
        home: Scaffold(
          body: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  ),
);
