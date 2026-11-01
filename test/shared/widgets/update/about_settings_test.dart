// 职责: 验证更新入口的检查反馈、页面退出后安装与重启的完整性，以及开源署名展示。
// 关联文件:
//   lib/shared/widgets/settings/about_settings_section.dart
//   lib/shared/providers/update_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/app_config.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/update_providers.dart';
import 'package:reveric/shared/services/update.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/settings/about_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Source implements UpdateSource {
  int calls = 0;
  Future<UpdateCheckResult> Function() response = () async =>
      const UpdateUpToDate();

  @override
  Future<UpdateCheckResult> checkForUpdate(String currentVersion) {
    calls++;
    return response();
  }
}

class _PendingUpdateService extends UpdateService {
  _PendingUpdateService() : super(source: _Source());

  final applied = Completer<bool>();
  final events = <String>[];
  UpdateProgress _progress = const UpdateProgress.downloaded();
  void Function(UpdateProgress)? callback;

  @override
  UpdateProgress get progress => _progress;

  @override
  set onProgressChanged(void Function(UpdateProgress)? value) {
    callback = value;
    if (value == null) {
      events.add('disposed');
    }
  }

  @override
  Future<bool> applyUpdate() async {
    events.add('applying');
    _progress = const UpdateProgress.applying();
    callback?.call(_progress);
    final success = await applied.future;
    events.add(success ? 'applied' : 'failed');
    _progress = success
        ? const UpdateProgress.idle()
        : const UpdateProgress.error('apply failed');
    callback?.call(_progress);
    return success;
  }

  @override
  Future<void> restartApp() async {
    events.add('restarted');
  }
}

Widget _wrap(
  _Source source,
  bool compact, {
  Locale locale = const Locale('en'),
  UpdateService? service,
  Widget? child,
}) => ProviderScope(
  overrides: [
    updateSourceProvider.overrideWithValue(source),
    if (service != null) updateServiceProvider.overrideWithValue(service),
  ],
  child: EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: RevericThemeData.reveric.toThemeData().copyWith(
          platform: compact ? TargetPlatform.android : TargetPlatform.macOS,
        ),
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: Scaffold(
            body: child ?? AboutSettingsSection(compact: compact),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  for (final success in [true, false]) {
    test(
      'update command without a listener completes success=$success',
      () async {
        final service = _PendingUpdateService();
        final container = ProviderContainer.test(
          overrides: [updateServiceProvider.overrideWithValue(service)],
        );
        final update = container
            .read(updateDownloadProvider.notifier)
            .applyUpdateAndRestart();
        await container.pump();
        expect(container.exists(updateDownloadProvider), isFalse);
        expect(service.events, ['applying', 'disposed']);
        service.applied.complete(success);
        expect(await update, success);
        expect(service.events, [
          'applying',
          'disposed',
          success ? 'applied' : 'failed',
          if (success) 'restarted',
        ]);
      },
    );
  }

  for (final entry in ['desktop about', 'mobile about']) {
    testWidgets('update restarts after $entry is removed', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _PendingUpdateService();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        _wrap(
          _Source(),
          entry == 'mobile about',
          service: service,
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, _) => !show
                ? const SizedBox.shrink()
                : AboutSettingsSection(compact: entry == 'mobile about'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart to Update'));
      await tester.pump();
      expect(service.events, ['applying']);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(service.events, ['applying', 'disposed']);
      service.applied.complete(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(service.events, ['applying', 'disposed', 'applied', 'restarted']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final compact in [false, true]) {
    testWidgets('manual check and retry work with compact=$compact', (
      tester,
    ) async {
      tester.view.physicalSize = Size(compact ? 390 : 1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _Source();
      await tester.pumpWidget(_wrap(source, compact));
      await tester.pumpAndSettle();
      final check = find.text('Check for Updates');
      expect(find.text("You're up to date"), findsOneWidget);
      expect(check, findsOneWidget);
      final before = tester.getRect(check);
      final pending = Completer<UpdateCheckResult>();
      source.response = () => pending.future;
      await tester.tap(check);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getRect(check), before);
      await tester.tap(check);
      await tester.pump();
      expect(source.calls, 2);
      pending.complete(const UpdateCheckFailed('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to check for updates'), findsOneWidget);
      expect(find.text("You're up to date"), findsNothing);
      source.response = () async => const UpdateAvailable(
        UpdateInfo(
          version: '9.1.0',
          downloadUrl: 'https://example.com/update.zip',
        ),
      );
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.text('v9.1.0'), findsOneWidget);
      expect(check, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final compact in [false, true]) {
    testWidgets('shows attribution and project link with compact=$compact', (
      tester,
    ) async {
      tester.view.physicalSize = Size(compact ? 390 : 1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_Source(), compact));
      await tester.pumpAndSettle();
      expect(find.text('Open Source License'), findsOneWidget);
      expect(find.text(revericAttribution), findsOneWidget);
      expect(find.text(revericGitHubRepoUrl), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
