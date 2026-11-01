// 职责: 验证照片旧格式读取、结构化序列化和只修改目标照片名称的持久化行为。
// 关联文件:
//   lib/shared/models/subject_photo.dart
//   lib/shared/database/type_converters.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/services/maps_service.dart

import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/database/type_converters.dart';
import 'package:reveric/shared/services/maps_service.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  const converter = SubjectPhotoListConverter();
  test('asset references round trip without losing order or names', () {
    final photos = converter.fromSql(
      '[{"asset_id":"images/old.png","name":""},{"asset_id":"images/new.png","name":"冬装"}]',
    );
    expect(photos, const [
      SubjectPhoto(assetId: 'images/old.png'),
      SubjectPhoto(assetId: 'images/new.png', name: '冬装'),
    ]);
    expect(jsonDecode(converter.toSql(photos)), [
      {'asset_id': 'images/old.png', 'name': ''},
      {'asset_id': 'images/new.png', 'name': '冬装'},
    ]);
    expect(converter.fromSql('[]'), isEmpty);
    for (final invalid in [
      '{}',
      '[42]',
      '[{"asset_id":42,"name":"x"}]',
      '[{"asset_id":"a"}]',
    ]) {
      expect(() => converter.fromSql(invalid), throwsA(anything));
    }
  });

  for (final character in [true, false]) {
    test(
      '${character ? 'character' : 'location'} reads asset rows and renames the latest list',
      () async {
        final db = NovelContentDatabase.forTest(NativeDatabase.memory());
        addTearDown(db.close);
        final content = NovelContentService(db);
        final locations = LocationsService(db);
        final id = character
            ? await content.createCharacterProfile(name: 'Subject')
            : await locations.createLocation(name: 'Subject');
        final table = character ? 'character_profiles' : 'locations';
        Future<List<SubjectPhoto>?> read() async => character
            ? (await db.characterProfileDao.getById(id))!.photos
            : (await db.locationDao.getById(id))!.photos;
        Future<List<SubjectPhoto>> rename(String path, String name) => character
            ? content.renameCharacterPhoto(id: id, assetId: path, name: name)
            : locations.renamePhoto(id: id, assetId: path, name: name);

        expect(await read(), isNull);
        await db.customStatement('UPDATE $table SET photos = ? WHERE id = ?', [
          '[{"asset_id":"images/a.png","name":""}]',
          id,
        ]);
        expect(await read(), const [SubjectPhoto(assetId: 'images/a.png')]);
        // A background generation added a photo after the editor loaded its list.
        await db.customStatement('UPDATE $table SET photos = ? WHERE id = ?', [
          '[{"asset_id":"images/a.png","name":""},{"asset_id":"images/b.png","name":"冬装"}]',
          id,
        ]);
        expect(await rename('images/a.png', ' 冬装 '), const [
          SubjectPhoto(assetId: 'images/a.png', name: '冬装'),
          SubjectPhoto(assetId: 'images/b.png', name: '冬装'),
        ]);
        await rename('images/a.png', '  ');
        final expected = const [
          SubjectPhoto(assetId: 'images/a.png'),
          SubjectPhoto(assetId: 'images/b.png', name: '冬装'),
        ];
        expect(await read(), expected);
        await expectLater(
          rename('images/missing.png', 'Missing'),
          throwsStateError,
        );
        expect(await read(), expected);
        // Asset identity is unchanged by renaming a photo.
        await rename('images/a.png', '冬装');
        expect((await read())!.first.name, '冬装');
        await rename('images/a.png', '');

        if (character) {
          final row = (await db.characterProfileDao.getById(id))!;
          expect(
            CharacterProfile.fromJson({
              ...row.toJson(),
              'photos': jsonDecode(jsonEncode(row.toJson()['photos'])),
            }).photos,
            expected,
          );
        } else {
          final row = (await db.locationDao.getById(id))!;
          expect(
            Location.fromJson(jsonDecode(jsonEncode(row.toJson()))).photos,
            expected,
          );
        }
      },
    );
  }
}
