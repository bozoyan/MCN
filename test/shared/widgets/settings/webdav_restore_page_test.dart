// 职责: 验证 WebDAV 恢复子页面在小视口中展示并提交远端备份。
// 关联文件:
//   lib/shared/widgets/settings/webdav_restore_page.dart
//   lib/shared/services/webdav_backup_service.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/webdav_backup_config.dart';
import 'package:reveric/shared/services/webdav_backup_service.dart';
import 'package:reveric/shared/services/webdav_transport.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/settings/webdav_restore_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('lists a remote backup and returns the downloaded path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? downloadedPath;

    await tester.pumpWidget(
      _wrap(
        WebDavRestorePage(
          config: const WebDavBackupConfig(
            enabled: true,
            serverUrl: 'https://dav.example.com',
            username: 'author',
          ),
          service: _FakeWebDavBackupService(),
          compact: true,
          onBack: () {},
          onDownloaded: (path) async {
            downloadedPath = path;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('reveric_backup_20260806.zip'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(downloadedPath, '/tmp/reveric_backup_20260806.zip');
    expect(tester.takeException(), isNull);
  });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const <Locale>[Locale('en')],
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
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

class _FakeWebDavBackupService extends WebDavBackupService {
  _FakeWebDavBackupService() : super(transport: const WebDavTransport());

  @override
  Future<WebDavListResult> listBackups(WebDavBackupConfig config) async {
    return WebDavListResult.success(<WebDavBackupFile>[
      WebDavBackupFile(
        name: 'reveric_backup_20260806.zip',
        remotePath: '/Reveric/Backups/reveric_backup_20260806.zip',
        size: 1024,
        modifiedAt: DateTime(2026, 8, 6, 10),
      ),
    ]);
  }

  @override
  Future<WebDavDownloadResult> downloadBackup({
    required WebDavBackupConfig config,
    required WebDavBackupFile remoteFile,
  }) async {
    return const WebDavDownloadResult.success(
      '/tmp/reveric_backup_20260806.zip',
    );
  }
}
