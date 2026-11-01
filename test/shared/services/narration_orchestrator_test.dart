// 职责: 验证朗读暂停、预取、快速跳段、迟到响应与失败重试的时序边界。
// 关联文件:
//   lib/shared/services/screenplay/narration_orchestrator.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/narration.dart';
import 'package:reveric/shared/services/screenplay/narration_orchestrator.dart';

class FakePlayer implements NarrationPlayer {
  FakePlayer(this.id);
  final int id;
  bool playing = false;
  bool disposed = false;
  double speed = 1;
  void Function(Object?)? finished;
  @override
  Future<void> play() async {
    expect(disposed, isFalse);
    playing = true;
  }

  @override
  Future<void> pause() async {
    expect(disposed, isFalse);
    playing = false;
  }

  @override
  Future<void> setSpeed(double value) async {
    expect(disposed, isFalse);
    speed = value;
  }

  @override
  Future<void> dispose() async {
    expect(disposed, isFalse);
    disposed = true;
    playing = false;
  }

  @override
  void onFinished(void Function(Object?) callback) => finished = callback;
}

Future<void> drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late NarrationOrchestrator controller;
  late List<FakePlayer> players;
  late List<({int index, Completer<NarrationAudio> result})> requests;
  late List<int> cancelled;
  var closed = false;
  setUp(() {
    closed = false;
    players = [];
    requests = [];
    cancelled = [];
    controller = NarrationOrchestrator()
      ..configure(
        segments: [
          for (var i = 0; i < 4; i++)
            NarrationSegment(text: '$i', voice: 'v$i', sceneId: 's'),
        ],
        generate: (segment, abort) {
          final index = int.parse(segment.text);
          final result = Completer<NarrationAudio>();
          requests.add((index: index, result: result));
          unawaited(
            abort.then((_) {
              cancelled.add(index);
            }),
          );
          return result.future;
        },
        createPlayer: (audio) async {
          final player = FakePlayer(audio.bytes.first);
          players.add(player);
          return player;
        },
      );
  });
  tearDown(() async {
    if (!closed) {
      controller.dispose();
    }
    await controller.settled;
  });
  void complete(int request) {
    requests[request].result.complete(
      NarrationAudio(Uint8List.fromList([requests[request].index]), 'mp3'),
    );
  }

  test(
    'pause during synthesis caches the result without autoplay or another request',
    () async {
      controller.play();
      controller.pause();
      complete(0);
      await drain();
      expect(players, isEmpty);
      expect(requests.length, 1);
      controller.play();
      await drain();
      expect(players.single.playing, isTrue);
      expect(requests.map((r) => r.index), [0, 1]);
      controller.pause();
      complete(1);
      await drain();
      expect(players.single.playing, isFalse);
      expect(requests.length, 2);
      controller.play();
      await drain();
      expect(players.length, 1);
      expect(players.single.playing, isTrue);
    },
  );

  test(
    'rapid jumps ignore late synthesis and cancel unused requests',
    () async {
      controller.play();
      controller.jump(2);
      controller.jump(3);
      complete(0);
      complete(1);
      complete(2);
      await drain();
      expect(players.map((p) => p.id), [3]);
      expect(cancelled, containsAll([0, 2]));
      expect(controller.index, 3);
      players.single.finished!(null);
      await drain();
      expect(controller.completed, isTrue);
      expect(players.single.disposed, isTrue);
    },
  );

  test(
    'prefetch failure stops at its segment and retries only on explicit retry',
    () async {
      controller.play();
      complete(0);
      await drain();
      requests[1].result.completeError(StateError('offline'));
      await drain();
      expect(controller.error, isNull);
      players.single.finished!(null);
      await drain();
      expect(controller.index, 1);
      expect(controller.error, isA<StateError>());
      expect(requests.length, 2);
      controller.play(retry: true);
      expect(requests.length, 3);
      complete(2);
      await drain();
      expect(players.last.id, 1);
      expect(players.last.playing, isTrue);
    },
  );

  test(
    'completed cache avoids charging again when returning to an earlier segment',
    () async {
      controller.play();
      complete(0);
      await drain();
      complete(1);
      await drain();
      controller.setSpeed(1.5);
      controller.jump(1);
      await drain();
      expect(players.first.disposed, isTrue);
      expect(players.last.id, 1);
      expect(players.last.speed, 1.5);
      controller.jump(0);
      await drain();
      expect(players.last.id, 0);
      expect(requests.where((r) => r.index == 0).length, 1);
      expect(requests.where((r) => r.index == 1).length, 1);
      expect(players.where((p) => p.playing).length, 1);
    },
  );

  test(
    'disposal during native initialization never starts the stale player',
    () async {
      controller.dispose();
      final initialized = Completer<NarrationPlayer>();
      final player = FakePlayer(9);
      controller = NarrationOrchestrator()
        ..configure(
          segments: [
            const NarrationSegment(text: 'x', voice: 'v', sceneId: 's'),
          ],
          generate: (_, _) async => NarrationAudio(Uint8List(1), 'mp3'),
          createPlayer: (_) => initialized.future,
        );
      controller.play();
      await drain();
      controller.dispose();
      closed = true;
      initialized.complete(player);
      await drain();
      expect(player.disposed, isTrue);
      expect(player.playing, isFalse);
    },
  );
  test('disposal during synthesis cancels and rejects late audio', () async {
    controller.play();
    controller.dispose();
    closed = true;
    complete(0);
    await drain();
    expect(players, isEmpty);
    expect(cancelled, [0]);
  });

  test(
    'retrying a native playback failure does not regenerate paid audio',
    () async {
      controller.dispose();
      var generated = 0;
      var created = 0;
      controller = NarrationOrchestrator()
        ..configure(
          segments: [
            const NarrationSegment(text: 'line', voice: 'v', sceneId: 's'),
          ],
          generate: (_, _) async {
            generated++;
            return NarrationAudio(Uint8List.fromList([1]), 'mp3');
          },
          createPlayer: (_) async {
            if (created++ == 0) {
              throw StateError('decoder unavailable');
            }
            final player = FakePlayer(1);
            players.add(player);
            return player;
          },
        );
      controller.play();
      await drain();
      expect(controller.error, isNotNull);
      controller.play(retry: true);
      await drain();
      expect(generated, 1);
      expect(players.single.playing, isTrue);
    },
  );
}
