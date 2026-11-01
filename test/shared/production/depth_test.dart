// 职责: 验证深度模型安装校验、取消重试以及尺寸与时间线边界。
// 关联文件:
//   lib/shared/services/depth/model_service.dart
//   lib/shared/services/depth/timeline.dart
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/depth/model.dart';
import 'package:reveric/shared/services/depth/model_service.dart';
import 'package:reveric/shared/services/depth/timeline.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/models/production/media.dart';

void main() {
  test('profiles preserve landscape, portrait, square and pixel budget', () {
    for (final (width, height, expected) in [
      (1920, 1080, (504, 280)),
      (1080, 1920, (280, 504)),
      (1080, 1080, (280, 280)),
    ]) {
      final profile = DepthProfile.forVideo(width, height);
      expect((profile.width, profile.height), expected);
    }
    for (final (w, h) in [(10000, 100), (100, 10000), (1, 1), (720, 576)]) {
      final profile = DepthProfile.forVideo(w, h);
      expect(profile.pixels, lessThanOrEqualTo(141120));
      expect(profile.width % 14, 0);
      expect(profile.height % 14, 0);
    }
  });
  test('rotation and variable frame timestamps retain duration', () {
    final timeline = DepthTimeline.fromProbe({
      'streams': [
        {
          'width': 1920,
          'height': 1080,
          'start_time': '2',
          'duration': '0.22',
          'side_data_list': [
            {'rotation': -90},
          ],
        },
      ],
      'frames': [
        for (final time in ['2.0', '2.04', '2.12'])
          {'best_effort_timestamp_time': time, 'pkt_duration_time': '0.04'},
      ],
    });
    expect((timeline.width, timeline.height), (1080, 1920));
    expect(timeline.timestamps, [0, 40000, 120000]);
    expect(timeline.lastDurationUs, 100000);
    expect(timeline.durationUs, 220000);
    expect(
      () => DepthTimeline.fromProbe({
        'streams': [
          {'width': 2, 'height': 2},
        ],
        'frames': [
          {'best_effort_timestamp_time': '0'},
          {'best_effort_timestamp_time': '0'},
        ],
      }),
      throwsA(isA<DepthException>()),
    );
  });
  group('model preparation', () {
    late Directory directory;
    late HttpServer server;
    late DepthModelService service;
    final bytes = List<int>.generate(128 * 1024, (i) => i % 256);
    var corrupt = false;
    var requests = 0;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('depth-model-test-');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      corrupt = false;
      requests = 0;
      server.listen((request) async {
        requests++;
        request.response.contentLength = bytes.length;
        request.response.add(corrupt ? List.filled(bytes.length, 0) : bytes);
        await request.response.close();
      });
      service = DepthModelService(
        directory,
        DepthModelManifest(
          bytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
          source: 'http://127.0.0.1:${server.port}/model',
        ),
      );
    });
    tearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    test(
      'reports connecting, download bytes and verification separately',
      () async {
        final stages = <DepthStage>[];
        final amounts = <double>[];
        await service.prepare(MediaCancellation(), (stage, progress) {
          stages.add(stage);
          if (stage == DepthStage.downloading && progress != null) {
            amounts.add(progress);
          }
        });
        expect(stages.toSet().toList(), [
          DepthStage.preparing,
          DepthStage.connecting,
          DepthStage.downloading,
          DepthStage.verifying,
        ]);
        expect(amounts.first, 0);
        expect(amounts.last, 1);
        expect(await service.isReady(MediaCancellation()), true);
      },
    );
    test(
      'connection errors are model download failures, never native failures',
      () async {
        final failing = DepthModelService(
          directory,
          service.manifest,
          createClient: () => throw const SocketException('Connection refused'),
        );
        await expectLater(
          failing.prepare(MediaCancellation(), (_, _) {}),
          throwsA(
            isA<DepthException>().having(
              (e) => e.reason,
              'reason',
              DepthFailure.model_source,
            ),
          ),
        );
        expect(await directory.list().length, 0);
        await service.prepare(MediaCancellation(), (_, _) {});
        expect(await service.isReady(MediaCancellation()), true);
      },
    );
    test('verified model is reused and corruption is repaired', () async {
      await service.prepare(MediaCancellation(), (_, _) {});
      await service.prepare(MediaCancellation(), (_, _) {});
      expect(requests, 1);
      await service.file.writeAsBytes(List.filled(bytes.length, 0));
      expect(await service.isReady(MediaCancellation()), false);
      await service.prepare(MediaCancellation(), (_, _) {});
      expect(requests, 2);
      expect(await service.isReady(MediaCancellation()), true);
      expect(await directory.list().length, 1);
    });
    test('wrong hash never installs and a retry succeeds', () async {
      corrupt = true;
      await expectLater(
        service.prepare(MediaCancellation(), (_, _) {}),
        throwsA(isA<DepthException>()),
      );
      expect(await service.file.exists(), false);
      expect(await directory.list().length, 0);
      corrupt = false;
      await service.prepare(MediaCancellation(), (_, _) {});
      expect(await service.isReady(MediaCancellation()), true);
    });
    test('insufficient disk space fails before downloading', () async {
      final lowSpace = DepthModelService(
        directory,
        service.manifest,
        freeBytes: (_) => 1,
      );
      await expectLater(
        lowSpace.prepare(MediaCancellation(), (_, _) {}),
        throwsA(
          isA<DepthException>().having(
            (e) => e.reason,
            'reason',
            DepthFailure.insufficient_space,
          ),
        ),
      );
      expect(requests, 0);
      expect(await directory.list().length, 0);
    });
    test('cancel removes partial files and allows retry', () async {
      final token = MediaCancellation();
      await expectLater(
        service.prepare(token, (_, value) {
          if (value != null) {
            token.cancel();
          }
        }),
        throwsA(isA<MediaException>()),
      );
      expect(await service.file.exists(), false);
      expect(await directory.list().length, 0);
      await service.prepare(MediaCancellation(), (_, _) {});
      expect(await service.isReady(MediaCancellation()), true);
    });
  });
}
