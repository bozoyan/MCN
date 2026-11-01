// 职责: 在真实文件系统验证朗读临时目录创建、音频落盘与成功及失败后的定向清理。
// 关联文件:
//   lib/desktop/features/narration/player.dart
//   lib/shared/services/screenplay/narration_orchestrator.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:reveric/desktop/features/narration/player.dart';
import 'package:reveric/shared/services/screenplay/narration_orchestrator.dart';

class _Controller extends VideoPlayerController {
  _Controller(super.file, {this.failInitialization = false}) : super.file();
  final bool failInitialization;
  bool released = false;

  @override
  Future<void> initialize() async {
    if (failInitialization) {
      throw StateError('decoder initialization failed');
    }
    value = const VideoPlayerValue(
      duration: Duration(seconds: 1),
      isInitialized: true,
    );
  }

  @override
  Future<void> dispose() async {
    released = true;
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late Directory cache;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final audio = NarrationAudio(Uint8List.fromList([1, 2, 3, 4]), 'mp3');

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reveric_narration_test_');
    cache = Directory('${sandbox.path}/application-cache');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getTemporaryDirectory');
          return cache.path;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await sandbox.delete(recursive: true);
  });

  for (final cacheExists in [true, false]) {
    test(
      'creates an isolated audio directory when cache exists=$cacheExists',
      () async {
        if (cacheExists) {
          await cache.create();
        }
        final files = <File>[];
        final controllers = <_Controller>[];
        Future<NarrationPlayer> create() => DesktopNarrationPlayer.create(
          audio,
          initializeRuntime: () async {},
          createController: (file) {
            files.add(file);
            final controller = _Controller(file);
            controllers.add(controller);
            return controller;
          },
        );
        final first = await create();
        final second = await create();
        expect(files[0].parent.path, isNot(files[1].parent.path));
        for (final file in files) {
          expect(file.parent.parent.path, cache.path);
          expect(
            file.parent.uri.pathSegments.where((s) => s.isNotEmpty).last,
            startsWith('reveric_narration_'),
          );
          expect(await file.readAsBytes(), audio.bytes);
        }
        final other = File('${cache.path}/unrelated')
          ..writeAsStringSync('keep');
        await first.dispose();
        expect(await files[0].parent.exists(), isFalse);
        expect(await files[1].exists(), isTrue);
        await second.dispose();
        expect(await files[1].parent.exists(), isFalse);
        expect(await other.readAsString(), 'keep');
        expect(controllers.every((c) => c.released), isTrue);
      },
    );
  }

  test(
    'initialization failure releases the controller and only its temporary directory',
    () async {
      await cache.create();
      final other = File('${cache.path}/unrelated')..writeAsStringSync('keep');
      late _Controller controller;
      late File audioFile;
      await expectLater(
        DesktopNarrationPlayer.create(
          audio,
          initializeRuntime: () async {},
          createController: (file) {
            audioFile = file;
            return controller = _Controller(file, failInitialization: true);
          },
        ),
        throwsStateError,
      );
      expect(controller.released, isTrue);
      expect(await audioFile.parent.exists(), isFalse);
      expect(await other.readAsString(), 'keep');
    },
  );
}
