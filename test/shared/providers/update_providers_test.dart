// 职责: 验证更新检查去重、前台刷新节流、失败保旧与提醒历史持久化。
// 关联文件:
//   lib/shared/providers/update_providers.dart
//   lib/shared/services/update.dart
import 'dart:async';
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
  Future<UpdateCheckResult> Function() response = () async =>
      const UpdateAvailable(
        UpdateInfo(
          version: '9.0.0',
          downloadUrl: 'https://example.com/update.zip',
        ),
      );

  @override
  Future<UpdateCheckResult> checkForUpdate(String currentVersion) {
    calls++;
    return response();
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

  test('startup and overlapping refreshes share one request', () async {
    final source = _Source();
    final pending = Completer<UpdateCheckResult>();
    source.response = () => pending.future;
    final container = create(source);
    final startup = container.read(latestReleaseProvider.future);
    final refresh = container
        .read(latestReleaseProvider.notifier)
        .refresh(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(source.calls, 1);
    pending.complete(const UpdateUpToDate());
    await startup;
    await refresh;
    expect(container.read(latestReleaseProvider).value, isA<UpdateUpToDate>());
  });

  test(
    'foreground checks are throttled, manual checks bypass interval',
    () async {
      final source = _Source();
      final container = create(source);
      await container.read(latestReleaseProvider.future);
      final notifier = container.read(latestReleaseProvider.notifier);
      await notifier.refresh();
      expect(source.calls, 1);
      await notifier.refresh(now: DateTime.now().add(const Duration(hours: 7)));
      expect(source.calls, 2);
      await notifier.refresh(force: true);
      expect(source.calls, 3);
    },
  );

  test(
    'background refresh keeps existing version while pending and after failure',
    () async {
      final source = _Source();
      final container = create(source);
      final initial = await container.read(latestReleaseProvider.future);
      final pending = Completer<UpdateCheckResult>();
      source.response = () => pending.future;
      final notifier = container.read(latestReleaseProvider.notifier);
      final refresh = notifier.refresh(
        now: DateTime.now().add(const Duration(hours: 7)),
      );
      expect(container.read(latestReleaseProvider).value, same(initial));
      expect(container.read(latestReleaseProvider).isLoading, false);
      pending.complete(const UpdateCheckFailed('offline'));
      await refresh;
      expect(container.read(latestReleaseProvider).value, same(initial));
      source.response = () async => const UpdateUpToDate();
      await notifier.refresh(force: true);
      expect(container.read(availableUpdateProvider), isNull);
    },
  );

  for (final initial in <UpdateCheckResult>[
    const UpdateUpToDate(),
    const UpdateAvailable(
      UpdateInfo(
        version: '9.0.0',
        downloadUrl: 'https://example.com/update.zip',
      ),
    ),
  ]) {
    test(
      'manual check exposes failure and can recover from $initial',
      () async {
        final source = _Source()..response = () async => initial;
        final container = create(source);
        await container.read(latestReleaseProvider.future);
        final pending = Completer<UpdateCheckResult>();
        source.response = () => pending.future;
        final notifier = container.read(latestReleaseProvider.notifier);
        final refresh = notifier.refresh(force: true);
        expect(container.read(latestReleaseProvider).value, same(initial));
        expect(container.read(latestReleaseProvider).isLoading, false);
        final duplicate = notifier.refresh(force: true);
        pending.complete(const UpdateCheckFailed('offline'));
        await Future.wait([refresh, duplicate]);
        expect(source.calls, 2);
        expect(
          container.read(latestReleaseProvider).value,
          isA<UpdateCheckFailed>(),
        );
        source.response = () async => const UpdateAvailable(
          UpdateInfo(
            version: '9.1.0',
            downloadUrl: 'https://example.com/update.zip',
          ),
        );
        await notifier.refresh(force: true);
        expect(container.read(availableUpdateProvider)?.version, '9.1.0');
      },
    );
  }

  test(
    'manual check joining a background request still exposes failure',
    () async {
      final source = _Source()..response = () async => const UpdateUpToDate();
      final container = create(source);
      await container.read(latestReleaseProvider.future);
      final pending = Completer<UpdateCheckResult>();
      source.response = () => pending.future;
      final notifier = container.read(latestReleaseProvider.notifier);
      final background = notifier.refresh(
        now: DateTime.now().add(const Duration(hours: 7)),
      );
      final manual = notifier.refresh(force: true);
      pending.complete(const UpdateCheckFailed('offline'));
      await Future.wait([background, manual]);
      expect(source.calls, 2);
      expect(
        container.read(latestReleaseProvider).value,
        isA<UpdateCheckFailed>(),
      );
    },
  );

  test('initial failure can recover through a manual check', () async {
    final source = _Source()
      ..response = () async => const UpdateCheckFailed('offline');
    final container = create(source);
    expect(
      await container.read(latestReleaseProvider.future),
      isA<UpdateCheckFailed>(),
    );
    source.response = () async => const UpdateUpToDate();
    await container.read(latestReleaseProvider.notifier).refresh(force: true);
    expect(container.read(latestReleaseProvider).value, isA<UpdateUpToDate>());
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
