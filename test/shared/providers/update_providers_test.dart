// 职责: 验证自动更新关闭时不发起检查请求，以及更新源与提醒历史的独立行为。
// 关联文件:
//   lib/shared/providers/update_providers.dart
//   lib/shared/services/update.dart
//   lib/shared/app_config.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/providers/update_providers.dart';
import 'package:reveric/shared/services/update.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Source implements UpdateSource {
  int calls = 0;

  @override
  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    calls++;
    return const UpdateAvailable(
      UpdateInfo(
        version: '9.0.0',
        downloadUrl: 'https://example.com/update.zip',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer create(_Source source) => ProviderContainer.test(
    overrides: [updateSourceProvider.overrideWithValue(source)],
  );

  test('default update source targets Reveric GitHub release assets', () async {
    final requests = <Uri>[];
    final assets = {
      'macos': 'reveric-9.2.0-macos-arm64.zip',
      'windows': 'reveric-9.2.0-windows-setup.exe',
      'android': 'reveric-9.2.0-android-arm64-v8a.apk',
      'linux': 'reveric-9.2.0-linux.zip',
    };
    final result = await http.runWithClient(
      () async {
        final container = ProviderContainer.test();
        final configured =
            container.read(updateSourceProvider) as GitHubReleasesSource;
        return GitHubReleasesSource(
          owner: configured.owner,
          repo: configured.repo,
        ).checkForUpdate('0.0.0');
      },
      () => MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'tag_name': 'v9.2.0',
            'body': 'Release notes',
            'assets': [
              for (final name in assets.values)
                {
                  'name': name,
                  'size': 1024,
                  'browser_download_url':
                      'https://github.com/bozoyan/MCN/releases/download/v9.2.0/$name',
                },
            ],
          }),
          200,
        );
      }),
    );
    expect(requests, [
      Uri.parse('https://api.github.com/repos/looplj/reveric/releases/latest'),
    ]);
    expect(result, isA<UpdateAvailable>());
    final info = (result as UpdateAvailable).info;
    expect(info.version, '9.2.0');
    expect(info.downloadUrl, endsWith(assets[Platform.operatingSystem]!));
    expect(info.fileSize, 1024);
  });

  test('update checks stay disabled and never reach the source', () async {
    final source = _Source();
    final container = create(source);
    expect(
      await container.read(latestReleaseProvider.future),
      isA<UpdateUpToDate>(),
    );
    final notifier = container.read(latestReleaseProvider.notifier);
    await notifier.refresh();
    await notifier.refresh(force: true);
    expect(source.calls, 0);
    expect(container.read(availableUpdateProvider), isNull);
  });

  test(
    'shown versions stay suppressed across containers; a new version can notify',
    () async {
      final first = create(_Source());
      await first.read(latestReleaseProvider.future);
      final notifier = first.read(latestReleaseProvider.notifier);
      expect(await notifier.shouldNotify('9.0.0'), true);
      await notifier.markNotified('9.0.0');
      expect(await notifier.shouldNotify('9.0.0'), false);
      final second = create(_Source());
      await second.read(latestReleaseProvider.future);
      final restored = second.read(latestReleaseProvider.notifier);
      expect(await restored.shouldNotify('9.0.0'), false);
      expect(await restored.shouldNotify('9.1.0'), true);
    },
  );
}