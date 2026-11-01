// 职责: 验证视频节点悬停预览的延迟、取消与点击播放边界。
// 关联文件:
//   lib/desktop/features/production/inline_media.dart
//   lib/shared/services/production/playback_service.dart
//   test/desktop/director/harness.dart

import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:reveric/desktop/features/production/inline_media.dart';
import 'package:reveric/desktop/features/production/node_card.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/providers/production_media.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/production/playback_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import '../../director/harness.dart';

void main() {
  late AppDatabase assets;
  late NovelContentDatabase db;
  late ProductionCanvasService service;
  late _Playback playback;
  setUpAll(initializeDirectorTest);
  setUp(() {
    rootBundle.clear();
    assets = AppDatabase.forTest(NativeDatabase.memory());
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = ProductionCanvasService(
      StoryboardService(db),
      MediaLibraryService(
        assets,
        MediaService(FfmpegRunner()),
        Directory.systemTemp,
      ),
      'work',
    );
    playback = _Playback();
  });
  tearDown(() async {
    await playback.dispose();
    await db.close();
    await assets.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    String path = 'file_workspaces/work/video.mp4',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackServiceProvider.overrideWithValue(playback)],
        child: directorTestApp(
          Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: ProductionInlineVideo(
                service: service,
                nodeId: 'node',
                filePath: path,
                selected: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<TestGesture> hover(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ProductionInlineVideo)));
    await tester.pump();
    return mouse;
  }

  testWidgets(
    'hover waits 500ms, plays an unselected node and exits to its poster',
    (tester) async {
      await mount(tester);
      final mouse = await hover(tester);
      await tester.pump(const Duration(milliseconds: 499));
      expect(playback.opens, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(playback.opens, ['video.mp4']);
      expect(playback.player.value.isPlaying, isTrue);
      expect(find.byType(VideoPlayer), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(playback.active.value, isNull);
      expect(find.byType(ProductionPlayMark), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('brief hover and removal cancel the delayed open', (
    tester,
  ) async {
    await mount(tester);
    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(playback.opens, isEmpty);
    await mouse.moveTo(tester.getCenter(find.byType(ProductionInlineVideo)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(playback.opens, isEmpty);
  });

  testWidgets('exiting while opening releases the pending preview', (
    tester,
  ) async {
    playback.gate = Completer<void>();
    await mount(tester);
    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(playback.opens, ['video.mp4']);
    await mouse.moveTo(Offset.zero);
    playback.gate!.complete();
    await tester.pump();
    expect(playback.active.value, isNull);
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('click plays immediately and cancels the hover timer', (
    tester,
  ) async {
    await mount(tester);
    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(ProductionPlayMark));
    await tester.pump();
    expect(playback.opens, ['video.mp4']);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(playback.opens, hasLength(1));
    expect(playback.active.value, productionInlineOwner('node'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('replacing the video cancels the old hover timer', (
    tester,
  ) async {
    await mount(tester);
    await hover(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await mount(tester, path: 'file_workspaces/work/replacement.mp4');
    await tester.pump(const Duration(seconds: 1));
    expect(playback.opens, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _Playback extends PlaybackService {
  final opens = <String>[];
  Completer<void>? gate;
  String? owner;
  @override
  final player = VideoPlayerController.file(File('unused.mp4'));

  @override
  Future<void> open({
    required String owner,
    required String path,
    bool play = false,
  }) async {
    this.owner = owner;
    opens.add(path.split(Platform.pathSeparator).last);
    await gate?.future;
    if (this.owner != owner) {
      return;
    }
    player.value = VideoPlayerValue(
      duration: const Duration(seconds: 5),
      size: const Size(320, 180),
      isInitialized: true,
      isPlaying: play,
    );
    active.value = owner;
  }

  @override
  Future<void> release(String owner) async {
    if (this.owner == owner) {
      this.owner = null;
      await Future<void>.value();
      active.value = null;
    }
  }

  @override
  Future<void> dispose() async {
    await player.dispose();
    active.dispose();
  }
}
