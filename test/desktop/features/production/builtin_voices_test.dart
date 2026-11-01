// 职责: 验证桌面内置音色的完整列表、取消和选择入库路径。
// 关联文件:
//   lib/desktop/features/production/builtin_voices.dart
//   lib/desktop/features/production/asset_picker.dart
//   lib/shared/services/production/builtin_voice_orchestrator.dart
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/builtin_voices.dart';
import 'package:reveric/shared/database/app_database.dart' as app;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import '../../director/harness.dart';

class _Media extends MediaService {
  _Media() : super(FfmpegRunner());
  @override
  Future<MediaInfo> probe(
    String path, {
    MediaCancellation? cancellation,
  }) async => const MediaInfo(
    duration: Duration(milliseconds: 6400),
    hasAudio: true,
    hasVideo: false,
    audioCodec: 'pcm_s16le',
    formatName: 'wav',
  );
}

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(initializeDirectorTest);
  testWidgets(
    'built-in voice selection imports a reusable reference while cancel stays empty',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('builtin-picker-'),
      ))!;
      final appDb = app.AppDatabase.forTest(NativeDatabase.memory());
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final service = ProductionCanvasService(
        StoryboardService(db),
        MediaLibraryService(appDb, _Media(), root),
        'work',
      );
      app.AssetRow? selected;
      try {
        // DB 打开和原生文件导入均在真实 Zone 启动，避免缓存的开库 Future
        // 或 IOSink 回调归属 FakeAsync，只有推进真实时钟却无法完成导入。
        await tester.runAsync(() => appDb.customSelect('SELECT 1').get());
        await tester.pumpWidget(
          directorTestApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await pickProductionBuiltinVoice(context, service);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Built-in voices'), findsOneWidget);
        expect(find.text('Warm female'), findsOneWidget);
        expect(find.text('Weathered elder'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('builtin-voice-clear-boy')),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(selected, isNull);
        expect(
          await tester.runAsync(() => appDb.select(appDb.assets).get()),
          isEmpty,
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // 选中只改行状态，确认前不导入。
        await tester.tap(find.text('Warm female'));
        await tester.pump();
        expect(
          await tester.runAsync(() => appDb.select(appDb.assets).get()),
          isEmpty,
        );
        await tester.runAsync(() => tester.tap(find.text('Confirm')));
        // 导入的文件 IO 在真实 Zone 推进；弹窗返回 Future 在打开它的
        // FakeAsync Zone 继续执行，所以每一轮也要 pump 才能收到选择结果。
        for (var i = 0; i < 30 && selected == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump();
        }
        expect(
          selected,
          isNotNull,
          reason:
              'Import and dialog completion must both finish before settling the loading animation.',
        );
        await tester.pumpAndSettle();
        expect(selected!.source, 'bundled');
        expect(selected!.type, 'audio');
        expect(selected!.novelId, 'work');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await appDb.close();
        await db.close();
        await tester.runAsync(() => root.delete(recursive: true));
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
}
