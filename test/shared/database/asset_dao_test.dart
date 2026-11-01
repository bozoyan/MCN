// 职责: 验证图片 DAO 与其他媒体资产隔离。
// 关联文件:
//   lib/shared/database/daos/asset_dao.dart
//   lib/shared/database/daos/image_asset_dao.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/production/asset_content.dart';

void main() {
  test('image DAO excludes non-image IDs, hashes and list entries', () async {
    final db = AppDatabase.forTest(NativeDatabase.memory());
    try {
      await db.assetDao.insertAsset(
        AssetsCompanion.insert(
          id: 'video',
          type: 'video',
          purpose: 'general',
          path: const Value('video.mp4'),
          content: const Value(VideoAssetContent(mimeType: 'video/mp4')),
          sha256: const Value('same'),
        ),
      );
      expect(await db.imageAssetDao.getAsset('video'), isNull);
      expect(await db.imageAssetDao.watchAssets().first, isEmpty);
      expect(
        (await db.assetDao.watchAssets(type: 'video').first).single.id,
        'video',
      );
      await expectLater(
        db.assetDao.insertAsset(
          AssetsCompanion.insert(
            id: 'invalid',
            type: 'audio',
            purpose: 'cover',
            batchId: const Value('batch'),
            path: const Value('audio.wav'),
            content: const Value(AudioAssetContent(mimeType: 'audio/wav')),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        db.assetDao.insertAsset(
          AssetsCompanion.insert(id: 'empty', type: 'image', purpose: 'cover'),
        ),
        throwsArgumentError,
      );
    } finally {
      await db.close();
    }
  });
}
