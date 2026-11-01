// 职责: 验证资产内容的序列化，以及资产库标记的筛选与切换。
// 关联文件:
//   lib/shared/models/production/asset_content.dart
//   lib/shared/database/daos/asset_dao.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/production/asset_content.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTest(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('concrete media content round-trips without mixing media shapes', () {
    const generation = AssetGeneration(
      prompt: 'original prompt',
      model: 'configured-model',
    );
    final contents = <AssetContent>[
      const ImageAssetContent(
        mimeType: 'image/png',
        width: 640,
        height: 480,
        bytes: 123,
        generation: generation,
      ),
      const VideoAssetContent(
        mimeType: 'video/mp4',
        width: 1920,
        height: 1080,
        durationMs: 1500,
        bytes: 456,
        generation: generation,
      ),
      const AudioAssetContent(
        mimeType: 'audio/wav',
        durationMs: 3000,
        bytes: 789,
      ),
    ];
    for (final content in contents) {
      final restored = AssetContent.fromJson(content.toJson());
      expect(restored.runtimeType, content.runtimeType);
      expect(restored.toJson(), content.toJson());
    }
    expect(contents[0].toJson(), isNot(contains('duration_ms')));
    expect(contents[2].toJson(), isNot(contains('width')));
  });

  test('removed authored kinds are rejected', () {
    for (final kind in ['text', 'scene', 'action', 'move', 'prop', 'style']) {
      expect(
        () => AssetContent.fromJson({'version': 1, 'kind': kind, 'text': 'x'}),
        throwsFormatException,
      );
    }
  });

  test(
    'media stays out of the library until toggled, and toggling back keeps it readable',
    () async {
      await db.assetDao.insertAsset(
        AssetsCompanion.insert(
          id: 'video',
          type: 'video',
          novelId: const Value('novel'),
          purpose: 'production.generated',
          path: const Value('media/video.mp4'),
          content: const Value(VideoAssetContent(mimeType: 'video/mp4')),
        ),
      );
      Future<List<String>> library() async => [
        for (final a
            in await db.assetDao
                .watchAssets(novelId: 'novel', inLibrary: true)
                .first)
          a.id,
      ];
      expect(await library(), isEmpty);
      expect(
        await db.assetDao.watchAssets(novelId: 'novel').first,
        hasLength(1),
      );

      await db.assetDao.setInLibrary('video', true);
      expect(await library(), ['video']);

      await db.assetDao.setInLibrary('video', false);
      expect(await library(), isEmpty);
      expect((await db.assetDao.getAsset('video'))!.inLibrary, isFalse);
    },
  );
}
