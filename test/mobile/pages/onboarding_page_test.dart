// 职责: 验证引导页预填随机称呼、头像选择防重入、失败恢复与页面卸载后的回调安全。
// 关联文件:
//   lib/mobile/pages/onboarding_page.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/providers/official_skill_sync_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/pages/onboarding_page.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/official_skill_sync_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/official_skill_sync.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
const _avatarKey = ValueKey('onboarding-avatar-picker');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Completer<String?>> requests;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    rootBundle.clear();
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, (call) {
          expect(call.method, 'pickImage');
          final request = Completer<String?>();
          requests.add(request);
          return request.future;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, null);
  });

  testWidgets('first launch prefills a random name so start is enabled', (
    tester,
  ) async {
    await _pumpOnboarding(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.trim(), isNotEmpty);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('avatar picker rejects repeated taps and unlocks after cancel', (
    tester,
  ) async {
    await _pumpOnboarding(tester);
    await tester.tap(find.byKey(_avatarKey));
    await tester.tap(find.byKey(_avatarKey));
    await tester.pump();
    final callsWhilePending = requests.length;
    for (final request in requests) {
      request.complete(null);
    }
    await tester.pumpAndSettle();
    expect(callsWhilePending, 1);

    await tester.tap(find.byKey(_avatarKey));
    await tester.pump();
    expect(requests, hasLength(2));
    requests.last.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar picker reports platform failure and allows retry', (
    tester,
  ) async {
    await _pumpOnboarding(tester);
    await tester.tap(find.byKey(_avatarKey));
    await tester.pump();
    requests.single.completeError(PlatformException(code: 'already_active'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.byKey(_avatarKey));
    await tester.pump();
    expect(requests, hasLength(2));
    requests.last.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar result is ignored after onboarding is disposed', (
    tester,
  ) async {
    await _pumpOnboarding(tester);
    await tester.tap(find.byKey(_avatarKey));
    await tester.pump();
    expect(requests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    requests.single.complete('unused-avatar.png');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpOnboarding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWith(_Settings.new),

        officialSkillSyncProvider.overrideWith(
          (ref) => const OfficialSkillSyncResult(),
        ),
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
            theme: RevericThemeData.reveric.toThemeData(),
            builder: (_, child) =>
                RevericTheme(data: RevericThemeData.reveric, child: child!),
            home: const MobileOnboardingPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Settings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings(
    theme: AppTheme.reveric,
    themeMode: AppThemeMode.light,
    language: 'en',
    aiSettings: AiSettings(),
  );

  @override
  Future<void> applyOnboardingDefaults({
    required AppTheme theme,
    required AppThemeMode themeMode,
    Map<AiModelRole, String>? defaultModelsForRoles,
    Map<AiModelKind, String>? defaultModelsForKinds,
  }) async {}
}
