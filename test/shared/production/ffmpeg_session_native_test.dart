// 职责: 使用应用实际打包的 FFmpegKit 验证连续会话的覆盖策略隔离及已有文件保护。
// 关联文件:
//   lib/shared/services/production/ffmpeg_runner.dart
//   test/shared/production/fixtures/ffmpeg_sessions.m
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';

const _frameworks = String.fromEnvironment('FFMPEGKIT_TEST_FRAMEWORKS');

void main() {
  group(
    'bundled FFmpegKit session isolation',
    () {
      late Directory root;
      late String binary;

      setUpAll(() async {
        root = await Directory.systemTemp.createTemp('ffmpeg-session-test-');
        binary = '${root.path}/sessions';
        final frameworks = Directory(_frameworks).absolute.path;
        final compile = await Process.run('xcrun', [
          'clang',
          '-fobjc-arc',
          '-fblocks',
          'test/shared/production/fixtures/ffmpeg_sessions.m',
          '-F',
          frameworks,
          '-framework',
          'Foundation',
          '-framework',
          'ffmpegkit',
          '-Wl,-rpath,$frameworks',
          '-o',
          binary,
        ]);
        expect(compile.exitCode, 0, reason: '${compile.stderr}');
      });

      tearDownAll(() => root.delete(recursive: true));

      List<String> frame(String path, List<String> flags) => [
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        ...flags,
        '-f',
        'lavfi',
        '-i',
        'color=c=red:s=16x16:d=0.04',
        '-frames:v',
        '1',
        path,
      ];

      Future<void> run(List<List<String>> commands, List<int> expected) async {
        final result = await Process.run(binary, [
          jsonEncode(commands.map(ffmpegSessionArguments).toList()),
        ]).timeout(const Duration(seconds: 30));
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          jsonDecode(result.stdout as String),
          expected,
          reason: '${result.stderr}',
        );
      }

      for (final flags in [
        ['-y', '-n', '-n'],
        ['-n', '-y', '-n'],
      ]) {
        test(
          'alternating ${flags.join(" ")} uses only this call’s flags',
          () async {
            final directory = await root.createTemp('alternating-');
            await run(
              [
                for (var i = 0; i < flags.length; i++)
                  frame('${directory.path}/frame-$i.png', [flags[i]]),
              ],
              [0, 0, 0],
            );
            for (var i = 0; i < flags.length; i++) {
              expect(
                await File('${directory.path}/frame-$i.png').length(),
                greaterThan(0),
              );
            }
          },
        );
      }

      test(
        'no-overwrite and default policy preserve existing files after -y',
        () async {
          final directory = await root.createTemp('protected-');
          final protected = File('${directory.path}/existing.png');
          await protected.writeAsString('existing contents');
          await run(
            [
              frame('${directory.path}/first.png', ['-y']),
              frame(protected.path, []),
              frame(protected.path, ['-n']),
              frame('${directory.path}/last.png', ['-n']),
            ],
            [0, 1, 1, 0],
          );
          expect(await protected.readAsString(), 'existing contents');
        },
      );

      test(
        'explicit overwrite still works after a no-overwrite session',
        () async {
          final directory = await root.createTemp('overwrite-');
          final target = File('${directory.path}/existing.png');
          await target.writeAsString('old contents');
          await run(
            [
              frame('${directory.path}/first.png', ['-n']),
              frame(target.path, ['-y']),
            ],
            [0, 0],
          );
          expect((await target.readAsBytes()).take(8).toList(), [
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
          ]);
        },
      );

      test(
        'conflicting flags still fail and do not poison the next session',
        () async {
          final directory = await root.createTemp('conflict-');
          await run(
            [
              frame('${directory.path}/bad.png', ['-y', '-n']),
              frame('${directory.path}/good.png', ['-n']),
            ],
            [1, 0],
          );
          expect(await File('${directory.path}/bad.png').exists(), false);
          expect(
            await File('${directory.path}/good.png').length(),
            greaterThan(0),
          );
        },
      );
    },
    skip: !Platform.isMacOS || _frameworks.isEmpty
        ? 'Requires macOS and --dart-define=FFMPEGKIT_TEST_FRAMEWORKS=<built frameworks directory>.'
        : false,
  );
}
