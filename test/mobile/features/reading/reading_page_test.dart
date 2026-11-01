// 职责: 验证移动端阅读页加载正文、按需展示控制，并在设置页前后切换沉浸式系统栏。
// 关联文件:
//   lib/mobile/features/reading/reading_page.dart
//   lib/shared/components/fullscreen_system_ui.dart
//   lib/shared/services/system_ui_service.dart
//   lib/shared/models/chapter.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/reading.json
//   assets/translations/zh-CN/reading.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

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
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var batteryReadCount = 0;
  final batteryStateMethodCalls = <String>[];
  final systemUiModes = <String>[];
  final statusBarBrightnesses = <String?>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    batteryReadCount = 0;
    batteryStateMethodCalls.clear();
    systemUiModes.clear();
    statusBarBrightnesses.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryChannel, (call) async {
          if (call.method == 'getBatteryLevel') {
            batteryReadCount++;
            return 64;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryStateChannel, (call) async {
          batteryStateMethodCalls.add(call.method);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemUiChannel, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            systemUiModes.add(call.arguments! as String);
          }
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            final arguments = call.arguments as Map<Object?, Object?>;
            statusBarBrightnesses.add(
              arguments['statusBarBrightness'] as String?,
            );
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_batteryStateChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemUiChannel, null);
  });

  testWidgets(
    'loads body from chapter detail and reveals controls after a middle tap',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              chapterTreeProvider(
                'reading_test_db',
              ).overrideWith((ref) => Stream.value([_chapter(content: '')])),
              chapterContentByIdProvider(
                path: 'reading_test_db',
                chapterId: 'chapter_test',
              ).overrideWith(
                (ref) => Stream.value(_chapter(content: 'Reader content')),
              ),
            ],
            child: const MobileReadingPage(
              novelId: 'reading_test_novel',
              novelTitle: 'A long work title',
              databasePath: 'reading_test_db',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(batteryStateMethodCalls, contains('listen'));
      expect(systemUiModes, contains('SystemUiMode.immersiveSticky'));
      expect(statusBarBrightnesses, contains('Brightness.light'));
      expect(tester.widget<SafeArea>(find.byType(SafeArea).first).top, isFalse);
      final content = find.text('\u3000\u3000Reader content');
      expect(content, findsOneWidget);
      final contextTitle = find.byKey(const ValueKey('reading-context-title'));
      expect(contextTitle, findsOneWidget);
      expect(tester.widget<Text>(contextTitle).data, 'Chapter one');
      expect(find.text('64%'), findsOneWidget);
      expect(find.byTooltip('Contents'), findsNothing);

      await tester.tapAt(const Offset(195, 420));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Contents'), findsOneWidget);
      expect(find.byTooltip('Reading Settings'), findsOneWidget);
      expect(find.byTooltip('Night mode'), findsOneWidget);
      expect(find.byTooltip('Exit Reading'), findsOneWidget);
      expect(tester.takeException(), isNull);

      systemUiModes.clear();
      await tester.tap(find.byTooltip('Reading Settings'));
      await tester.pumpAndSettle();

      expect(systemUiModes, contains('SystemUiMode.edgeToEdge'));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(systemUiModes, contains('SystemUiMode.immersiveSticky'));

      final initialBatteryReadCount = batteryReadCount;
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(batteryReadCount, greaterThan(initialBatteryReadCount));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final pausedBatteryReadCount = batteryReadCount;
      await tester.pump(const Duration(minutes: 1));
      expect(batteryReadCount, pausedBatteryReadCount);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(batteryReadCount, greaterThan(pausedBatteryReadCount));

      systemUiModes.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(batteryStateMethodCalls, contains('cancel'));
      expect(systemUiModes, ['SystemUiMode.edgeToEdge']);
      final disposedBatteryReadCount = batteryReadCount;
      await tester.pump(const Duration(minutes: 2));
      expect(batteryReadCount, disposedBatteryReadCount);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

const _batteryChannel = MethodChannel('dev.fluttercommunity.plus/battery');
const _batteryStateChannel = MethodChannel(
  'dev.fluttercommunity.plus/charging',
);
const _systemUiChannel = MethodChannel('flutter/platform', JSONMethodCodec());

Chapter _chapter({required String content}) {
  final now = DateTime(2026);
  return Chapter(
    id: 'chapter_test',
    type: nodeTypeChapter,
    siblingOrder: 0,
    title: 'Chapter one',
    content: content,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
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
            home: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}
