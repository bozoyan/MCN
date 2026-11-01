// 职责: 验证序列直接写入目标、拒绝路径冲突、执行资源限额并保留失败产物。
// 关联文件:
//   lib/shared/services/ai/ffmpeg/arguments.dart
//   lib/shared/services/ai/ffmpeg/command.dart
//   lib/shared/services/ai/ffmpeg/outputs.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:reveric/shared/models/tool_permission.dart';
import 'package:reveric/shared/services/ai/ffmpeg/arguments.dart';
import 'package:reveric/shared/services/ai/ffmpeg/command.dart';
import 'package:reveric/shared/services/ai/files/session_files.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';

class _SequenceRunner extends FfmpegRunner {
  final outputDirectories = <String>[];
  var calls = 0;
  Future<void> Function()? afterEncode;
  int actualFrames = 6;
  bool cancel = false, gap = false;
  @override
  Future<FfmpegExecutionResult> executeCommand(
    List<String> args, {
    required MediaCancellation cancellation,
  }) async {
    calls++;
    var start = 1;
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '-start_number' || args[i] == '-segment_start_number') {
        start = int.parse(args[++i]);
        continue;
      }
      final match = RegExp(r'%(?:0([1-9]))?d').firstMatch(args[i]);
      if (match == null) {
        continue;
      }
      final template = args[i];
      outputDirectories.add(p.dirname(template));
      for (var n = 0; n < actualFrames; n++) {
        final number = start + n + (gap && n > 0 ? 1 : 0);
        final file = File(
          template.replaceFirst(
            match.group(0)!,
            '$number'.padLeft(int.parse(match.group(1) ?? '0'), '0'),
          ),
        );
        await file.writeAsBytes(
          img.encodePng(img.Image(width: 64, height: 32)),
        );
      }
      start = 1;
    }
    await afterEncode?.call();
    if (cancel) {
      await cancellation.cancel();
    }
    return FfmpegExecutionResult(
      exitCode: cancellation.cancelled ? 255 : 0,
      output: 'native log',
      cancelled: cancellation.cancelled,
    );
  }
}

void main() {
  FfmpegArguments parse(List<String> args) =>
      FfmpegArguments.parse(args, probe: false);
  test(
    'scopes sequence limits and start numbers to their own output and accepts ordinary percent paths',
    () {
      final parsed = parse([
        '-i',
        '100%complete.mp4',
        '-vf',
        "select='not(mod(n,2))',tile=2x2",
        '-fps_mode',
        'passthrough',
        '-q:v',
        '2',
        '-frames:v',
        '2',
        '-start_number',
        '99',
        'media/镜头-%03d.png',
        '-frames:v',
        '3',
        'second-%d.jpg',
        '100%result.mp4',
      ]);
      final specs = parsed.sequences.values.toList();
      expect(specs[0].at(0), 'media/镜头-099.png');
      expect(specs[0].at(1), 'media/镜头-100.png');
      expect(specs[1].at(0), 'second-1.jpg');
      expect(specs[1].limit, 3);
    },
  );
  test(
    'rejects unbounded outputs, malformed templates and network or wildcard inputs',
    () {
      for (final args in <List<String>>[
        ['-i', 'in.mp4', 'f-%03d.png'],
        ['-i', 'in.mp4', '-frames:v', '241', 'f-%03d.png'],
        [
          '-i',
          'in.mp4',
          '-frames:v',
          '200',
          'a-%d.png',
          '-frames:v',
          '200',
          'b-%d.png',
        ],
        ['-i', 'in.mp4', '-frames:v', '1', 'a.png', 'b-%d.png'],
        ['-frames:v', '1', '-i', 'in.mp4', 'b-%d.png'],
        ['-i', 'in.mp4', '-frames:v', '1', 'dir-%d/f.png'],
        ['-i', 'in.mp4', '-frames:v', '1', 'f-%03d-%d.png'],
        ['-i', 'in.mp4', '-frames:v', '1', 'f-%010d.png'],
        ['-i', 'in.mp4', '-frames:v', '1', 'f-%d.mp4'],
        ['-i', 'in.mp4', '-frames:v', '1', '-f', 'mp4', 'f-%d.jpg'],
        ['-i', 'in.mp4', '-start_number', '1', 'f.jpg'],
        ['-i', 'in.mp4', '-q:v', 'NaN', 'f.jpg'],
        ['-i', 'in.mp4', '-fps_mode', 'invented', 'f.jpg'],
      ]) {
        expect(() => parse(args), throwsFormatException, reason: '$args');
      }
      for (final path in ['*.png', 'https://example.com/a.mp4']) {
        expect(
          () => parse(['-i', path, 'out.mp4']),
          throwsA(isA<ToolOperationException>()),
        );
      }
    },
  );

  late Directory support;
  late Directory root;
  late SessionFiles files;
  late _SequenceRunner runner;
  late FfmpegCommand command;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('sequence-test-');
    support = Directory(await support.resolveSymbolicLinks());
    root = await Directory(
      '${support.path}/file_workspaces/work',
    ).create(recursive: true);
    files = SessionFiles(root: support.path, novelId: 'work');
    await File('${root.path}/source.mp4').writeAsBytes([1, 2, 3]);
    runner = _SequenceRunner();
    command = FfmpegCommand(files, runner);
  });
  tearDown(() => support.delete(recursive: true));
  FfmpegArguments request({
    int count = 6,
    String output = 'media/frame-%03d.png',
  }) => parse([
    '-i',
    'source.mp4',
    '-frames:v',
    '$count',
    '-start_number',
    '9',
    output,
  ]);
  Future<Map<String, dynamic>> run(
    FfmpegArguments parsed,
    MediaCancellation cancellation,
  ) async {
    final plan = await command.inspect(parsed);
    await plan.verify();
    return command.run('session', plan, cancellation);
  }

  test(
    'writes only final sequence files and returns no previews or file list',
    () async {
      final result = await run(request(count: 8), MediaCancellation());
      expect(result['ok'], true);
      expect(result['exit_code'], 0);
      expect(result.containsKey('files'), false);
      expect(result.containsKey('content'), false);
      for (var n = 9; n <= 14; n++) {
        expect(
          await File(
            '${root.path}/media/frame-${'$n'.padLeft(3, '0')}.png',
          ).exists(),
          true,
        );
      }
      expect(runner.calls, 1);
      expect(await Directory('${root.path}/sessions').exists(), false);
    },
  );
  test(
    'rejects overlaps, traversal and existing targets before encoding',
    () async {
      await Directory('${root.path}/media').create();
      await File('${root.path}/media/frame-010.png').writeAsString('original');
      await expectLater(
        run(request(), MediaCancellation()),
        throwsA(
          isA<ToolOperationException>()
              .having((e) => e.code, 'code', 'already_exists')
              .having((e) => e.message, 'path', contains('media/frame-010.png'))
              .having(
                (e) => e.hint,
                'hint',
                allOf(
                  contains('Run files list'),
                  contains('Run files remove'),
                  contains('Confirm the output path is available'),
                ),
              ),
        ),
      );
      expect(runner.outputDirectories, isEmpty);
      expect(
        await File('${root.path}/media/frame-010.png').readAsString(),
        'original',
      );
      for (final path in [
        '../frame-%d.png',
        '../../other/frame-%d.png',
        '${root.path}/frame-%d.png',
      ]) {
        await expectLater(
          run(request(output: path), MediaCancellation()),
          throwsFormatException,
        );
      }
      await expectLater(
        run(
          parse(['-i', 'source.mp4', '-frames:v', '2', 'f-%d.png', 'f-1.png']),
          MediaCancellation(),
        ),
        throwsFormatException,
      );
      expect(runner.outputDirectories, isEmpty);
    },
  );

  for (final outputArgs in <List<String>>[
    ['Out.png', 'out.png'],
    ['media/Batch/out.png', 'media/batch/out.png'],
    ['-frames:v', '1', 'Frame-%d.png', 'frame-1.png'],
    ['-frames:v', '1', 'Frame-%d.png', '-frames:v', '1', 'frame-%d.png'],
  ]) {
    test(
      'rejects case-only output collisions before encoding: $outputArgs',
      () async {
        await expectLater(
          run(parse(['-i', 'source.mp4', ...outputArgs]), MediaCancellation()),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Output filenames overlap after sequence expansion.',
            ),
          ),
        );
        expect(runner.calls, 0);
        expect(
          (await root.list(recursive: true).toList()).whereType<File>().map(
            (file) => file.path,
          ),
          [p.join(root.path, 'source.mp4')],
        );
      },
      skip: !(Platform.isWindows || Platform.isMacOS)
          ? 'Case-insensitive output policy applies to Windows and macOS.'
          : false,
    );
  }

  for (final segment in [false, true]) {
    test(
      'ignores existing out-of-range ${segment ? "segment" : "image"} files',
      () async {
        final extension = segment ? 'mp4' : 'png';
        final old = File('${root.path}/media/frame-999.$extension');
        await old.parent.create();
        await old.writeAsString('original');
        final earlier = await File(
          '${root.path}/media/frame-001.$extension',
        ).writeAsString('earlier');
        final otherWidth = await File(
          '${root.path}/media/frame-0009.$extension',
        ).writeAsString('different width');
        runner.actualFrames = 2;
        final result = await run(
          parse([
            '-i',
            'source.mp4',
            if (segment) ...[
              '-f',
              'segment',
              '-segment_start_number',
              '9',
            ] else ...[
              '-frames:v',
              '2',
              '-start_number',
              '9',
            ],
            'media/frame-%03d.$extension',
          ]),
          MediaCancellation(),
        );
        expect(result['ok'], true);
        expect(runner.calls, 1);
        expect(
          await File('${root.path}/media/frame-009.$extension').exists(),
          true,
        );
        expect(
          await File('${root.path}/media/frame-010.$extension').exists(),
          true,
        );
        expect(await old.readAsString(), 'original');
        expect(await earlier.readAsString(), 'earlier');
        expect(await otherWidth.readAsString(), 'different width');
      },
    );
  }

  test(
    'disjoint ranges with shared prefixes have independent output budgets',
    () async {
      runner.actualFrames = 2;
      final result = await run(
        parse([
          '-i',
          'source.mp4',
          '-frames:v',
          '2',
          '-start_number',
          '999',
          'media/frame-%03d.png',
          '-frames:v',
          '2',
          '-start_number',
          '1002',
          'media/frame-%d.png',
        ]),
        MediaCancellation(),
      );
      expect(result['ok'], true);
      for (final number in [999, 1000, 1002, 1003]) {
        expect(
          await File(
            '${root.path}/media/frame-${'$number'.padLeft(3, '0')}.png',
          ).exists(),
          true,
        );
      }
    },
  );

  test('writes distinct sequences in different directories', () async {
    runner.actualFrames = 1;
    final result = await run(
      parse([
        '-i',
        'source.mp4',
        '-frames:v',
        '1',
        'media/left/Frame-%d.png',
        '-frames:v',
        '1',
        'media/right/frame-%d.png',
      ]),
      MediaCancellation(),
    );
    expect(result['ok'], true);
    for (final name in ['media/left/Frame-1.png', 'media/right/frame-1.png']) {
      expect(await File('${root.path}/$name').exists(), true);
    }
  });

  for (final mode in ['gap', 'empty']) {
    test(
      'does not override native success for $mode sequence output',
      () async {
        runner.gap = mode == 'gap';
        runner.actualFrames = mode == 'empty' ? 0 : 2;
        final result = await run(request(), MediaCancellation());
        expect(result['ok'], true);
        expect(runner.calls, 1);
      },
    );
  }

  test('cancellation keeps files already written', () async {
    runner.cancel = true;
    final result = await run(request(), MediaCancellation());
    expect(result['status'], 'cancelled');
    expect(result['exit_code'], 255);
    expect(await File('${root.path}/media/frame-009.png').exists(), true);
  });

  test(
    'output count limit reports an application failure without deleting files',
    () async {
      runner.actualFrames = 7;
      final result = await run(request(), MediaCancellation());
      expect(result['ok'], false);
      expect(result['error_code'], 'resource_exhausted');
      expect(result['exit_code'], 0);
      expect(result['log'], 'native log');
      expect(await File('${root.path}/media/frame-015.png').exists(), true);
    },
  );

  test(
    'a single output sharing the sequence prefix is excluded from its budget',
    () async {
      runner.actualFrames = 2;
      runner.afterEncode = () async {
        await File(
          '${root.path}/media/frame-999.png',
        ).writeAsString('ordinary output');
      };
      final result = await run(
        parse([
          '-i',
          'source.mp4',
          '-frames:v',
          '2',
          '-start_number',
          '9',
          'media/frame-%03d.png',
          'media/frame-999.png',
        ]),
        MediaCancellation(),
      );
      expect(result['ok'], true);
      expect(await File('${root.path}/media/frame-009.png').exists(), true);
      expect(
        await File('${root.path}/media/frame-999.png').readAsString(),
        'ordinary output',
      );
    },
  );
}
