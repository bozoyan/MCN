// 职责: Patrol 移动阅读控制验证 — 覆盖中部唤起控制栏、目录 Bottom Sheet 选章与护眼背景入口。
// 关联文件:
//   lib/mobile/features/reading/reading_page.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/utils/storage_paths.dart
//   assets/translations/en/reading.json
//   assets/translations/zh-CN/reading.json
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/features/reading/reading_page.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:reveric/shared/widgets/reading/reading_theme_palette.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _databasePath = 'reading_controls_patrol_db';

void main() {
  final systemUiModes = <String>[];
  late Directory tempSupport;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    tempSupport = await Directory.systemTemp.createTemp(
      'reveric_reading_controls_patrol_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory' ||
              call.method == 'getTemporaryDirectory') {
            return tempSupport.path;
          }
          return null;
        });
    await RevericPaths.initialize();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempSupport.exists()) {
      await tempSupport.delete(recursive: true);
    }
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    systemUiModes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryChannel, (call) async {
          if (call.method == 'getBatteryLevel') {
            return 64;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryStateChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemUiChannel, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            systemUiModes.add(call.arguments! as String);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appSystemUiChannel, (_) async => null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryStateChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemUiChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appSystemUiChannel, null);
  });

  patrolTest(
    'opens the directory sheet, changes chapter, and exposes eye-care theme',
    ($) async {
      _setMobileSurface($, const Size(390, 844));
      final chapters = [
        _chapter(id: 'chapter_1', title: 'Chapter one'),
        _chapter(id: 'chapter_2', title: 'Chapter two'),
      ];

      await $.pumpWidgetAndSettle(_ReadingHarness(chapters: chapters));

      final scaffold = $.tester.widget<Scaffold>(
        find.byKey(const ValueKey('reading-page-scaffold')),
      );
      expect(
        scaffold.backgroundColor,
        ReadingPalette.of(ReadingBackgroundTheme.eye_care).background,
      );

      await $.tester.tapAt(const Offset(195, 420));
      await $.pumpAndSettle();

      expect($(const ValueKey('reading-controls')), findsOneWidget);
      expect($(const ValueKey('reading-control-previous')), findsOneWidget);
      expect($(const ValueKey('reading-control-toc')), findsOneWidget);
      expect($(const ValueKey('reading-control-settings')), findsOneWidget);
      expect($(const ValueKey('reading-control-next')), findsOneWidget);

      systemUiModes.clear();
      await $(const ValueKey('reading-control-toc')).tap();
      await $.pumpAndSettle();

      expect(systemUiModes, contains('SystemUiMode.edgeToEdge'));
      expect($(const ValueKey('reading-toc-sheet')), findsOneWidget);
      expect($('Reading patrol novel'), findsOneWidget);
      expect(
        $(const ValueKey('reading-toc-chapter-chapter_2')),
        findsOneWidget,
      );

      await $(const ValueKey('reading-toc-chapter-chapter_2')).tap();
      await $.pumpAndSettle();

      expect($(const ValueKey('reading-toc-sheet')), findsNothing);
      expect(
        $.tester
            .widget<Text>(find.byKey(const ValueKey('reading-context-title')))
            .data,
        'Chapter two',
      );
      expect(systemUiModes, contains('SystemUiMode.immersiveSticky'));

      await $.tester.tapAt(const Offset(195, 420));
      await $.pumpAndSettle();
      systemUiModes.clear();

      await $(const ValueKey('reading-control-settings')).tap();
      await $.pumpAndSettle();

      expect(systemUiModes, contains('SystemUiMode.edgeToEdge'));
      expect(
        $(const ValueKey('reading-background-theme-eye_care')),
        findsOneWidget,
      );
      expect($('Eye Care'), findsOneWidget);

      await $(find.byTooltip('Close')).tap();
      await $.pumpAndSettle();

      expect(systemUiModes, contains('SystemUiMode.immersiveSticky'));
      expect($.tester.takeException(), isNull);
    },
  );
}

void _setMobileSurface(PatrolIntegrationTester $, Size size) {
  $.tester.view.devicePixelRatio = 1;
  $.tester.view.physicalSize = size;
  addTearDown(() {
    $.tester.view.resetPhysicalSize();
    $.tester.view.resetDevicePixelRatio();
  });
}

class _ReadingHarness extends StatelessWidget {
  const _ReadingHarness({required this.chapters});

  final List<Chapter> chapters;

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: ProviderScope(
        overrides: [
          readingBackgroundThemeProvider.overrideWithValue(
            ReadingBackgroundTheme.eye_care,
          ),
          chapterTreeProvider(
            _databasePath,
          ).overrideWith((ref) => Stream.value(chapters)),
          for (final chapter in chapters)
            chapterByIdProvider(
              path: _databasePath,
              chapterId: chapter.id,
            ).overrideWith((ref) => Stream.value(chapter)),
        ],
        child: Builder(
          builder: (context) {
            return MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              builder: (context, child) => RevericTheme(
                data: RevericThemeData.reveric,
                child: child!,
              ),
              home: const MobileReadingPage(
                novelId: 'reading_controls_patrol_novel',
                novelTitle: 'Reading patrol novel',
                databasePath: _databasePath,
              ),
            );
          },
        ),
      ),
    );
  }
}

Chapter _chapter({required String id, required String title}) {
  final now = DateTime(2026);
  return Chapter(
    id: id,
    type: nodeTypeChapter,
    siblingOrder: int.parse(id.substring(id.length - 1)),
    title: title,
    content: 'Reader content for $title.',
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

const _batteryChannel = MethodChannel('dev.fluttercommunity.plus/battery');
const _batteryStateChannel = MethodChannel(
  'dev.fluttercommunity.plus/charging',
);
const _systemUiChannel = MethodChannel('flutter/platform', JSONMethodCodec());
const _appSystemUiChannel = MethodChannel('reveric/system_ui');
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
