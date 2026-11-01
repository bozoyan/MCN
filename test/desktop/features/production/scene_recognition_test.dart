// 职责: 验证导演台识图弹窗的来源筛选、选图与插入／覆盖选择结果。
// 关联文件:
//   lib/desktop/features/production/scene_recognition.dart
//   lib/shared/services/production/canvas_service.dart
import 'dart:io';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/scene_recognition.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/production/asset_content.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import '../../director/harness.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(initializeDirectorTest);

  testWidgets(
    'history lists only uploads, scenes list location photos, and the choice carries the mode',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppDatabase.forTest(NativeDatabase.memory());
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      addTearDown(app.close);
      addTearDown(db.close);
      final root = Directory.systemTemp.createTempSync('scene-recognition-');
      addTearDown(() => root.deleteSync(recursive: true));
      final service = ProductionCanvasService(
        StoryboardService(db),
        MediaLibraryService(app, MediaService(FfmpegRunner()), root),
        'work',
      );
      await tester.runAsync(() async {
        for (final (id, purpose) in [
          ('uploaded', AssetPurpose.director_scene_recognition.value),
          ('generated', AssetPurpose.production_generated.value),
          ('photo', AssetPurpose.photo.value),
        ]) {
          await app.assetDao.insertAsset(
            AssetsCompanion.insert(
              id: id,
              type: 'image',
              name: Value(id),
              path: Value('file_workspaces/work/$id.png'),
              content: const Value(ImageAssetContent(mimeType: 'image/png')),
              novelId: const Value('work'),
              purpose: purpose,
            ),
          );
        }
        await db
            .into(db.locations)
            .insert(
              LocationsCompanion.insert(
                id: 'hall',
                name: 'Hall',
                photos: const Value([
                  SubjectPhoto(assetId: 'photo', name: 'Night'),
                ]),
              ),
            );
      });
      SceneRecognitionChoice? result;
      await tester.pumpWidget(
        directorTestApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showSceneRecognitionDialog(
                context,
                service: service,
                canvasId: 'canvas',
              ),
              child: const Text('Launch'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('scene-recognition-confirm'));
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.descendant(
                of: confirm,
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Scenes in this work'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Hall · Night'), findsOneWidget);

      await tester.tap(find.text('Upload history'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scene-recognition-image:uploaded')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scene-recognition-image:generated')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('scene-recognition-image:uploaded')),
      );
      await tester.tap(
        find.byKey(const ValueKey('scene-recognition-mode:true')),
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result, (assetId: 'uploaded', overwrite: true));
    },
  );
}
