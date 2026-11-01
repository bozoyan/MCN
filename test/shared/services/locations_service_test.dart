// 职责: 验证同一父级下地点名称唯一性、照片增删以及服务写入失败时的事务边界。
// 关联文件:
//   lib/shared/services/maps_service.dart
//   lib/shared/database/novel_content_database.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/maps_service.dart';

void main() {
  late NovelContentDatabase db;
  late LocationsService service;
  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = LocationsService(db);
  });
  tearDown(() => db.close());

  test(
    'quick creation picks unique names across parents and concurrent calls',
    () async {
      final firstParent = await service.createLocation(name: 'World A');
      final secondParent = await service.createLocation(name: 'World B');
      await service.createLocation(
        name: ' New location ',
        parentId: firstParent,
      );
      final ids = await Future.wait([
        service.createLocationWithDefaultName(
          defaultName: 'New location',
          parentId: firstParent,
        ),
        LocationsService(db).createLocationWithDefaultName(
          defaultName: 'New location',
          parentId: firstParent,
        ),
        service.createLocationWithDefaultName(
          defaultName: 'New location',
          parentId: secondParent,
        ),
      ]);
      final created = await Future.wait(ids.map(service.getLocationById));
      expect(created.map((row) => row!.name).toSet(), {
        'New location (2)',
        'New location (3)',
        'New location',
      });
      expect(created.map((row) => row!.parentId).toSet(), {
        firstParent,
        secondParent,
      });
      await expectLater(
        service.createLocation(name: 'New location (2)', parentId: firstParent),
        throwsA(isA<DuplicateLocationNameException>()),
      );
      expect(await service.getLocations(), hasLength(6));
    },
  );

  test(
    'quick creation keeps parent validation and does not insert on failure',
    () async {
      await expectLater(
        service.createLocationWithDefaultName(
          defaultName: 'New location',
          parentId: 'missing',
        ),
        throwsArgumentError,
      );
      expect(await service.getLocations(), isEmpty);
    },
  );

  test(
    'same normalized name is rejected only within the same parent',
    () async {
      final firstParent = await service.createLocation(name: '世界甲');
      final secondParent = await service.createLocation(name: '世界乙');
      final id = await service.createLocation(
        name: '\u3000江城\u00a0',
        parentId: firstParent,
      );
      final before = await service.getLocationById(id);
      await expectLater(
        service.createLocation(name: '\t江城 ', parentId: firstParent),
        throwsException,
      );
      expect(await service.getLocations(), hasLength(3));
      expect(await service.getLocationById(id), before);
      await service.createLocation(name: '江城', parentId: secondParent);
      await service.createLocation(name: '江城');
      expect(await service.getLocations(), hasLength(5));
    },
  );

  test(
    'moving checks the destination parent even when name is omitted',
    () async {
      final firstParent = await service.createLocation(name: 'World A');
      final secondParent = await service.createLocation(name: 'World B');
      await service.createLocation(name: 'City', parentId: firstParent);
      final id = await service.createLocation(
        name: 'City',
        parentId: secondParent,
      );
      final before = await service.getLocationById(id);
      await expectLater(
        service.updateLocation(
          id: id,
          parentId: firstParent,
          description: 'Must not save',
        ),
        throwsA(isA<DuplicateLocationNameException>()),
      );
      expect(await service.getLocationById(id), before);
      await service.updateLocation(
        id: id,
        parentId: firstParent,
        name: 'New city',
      );
      expect((await service.getLocationById(id))!.parentId, firstParent);
      await expectLater(
        service.updateLocation(id: id, name: 'City'),
        throwsA(isA<DuplicateLocationNameException>()),
      );
      await service.updateLocation(
        id: id,
        parentId: secondParent,
        name: 'City',
      );
      expect((await service.getLocationById(id))!.name, 'City');
    },
  );

  test(
    'clearing the parent checks root siblings and preserves failed writes',
    () async {
      final parent = await service.createLocation(name: 'World');
      await service.createLocation(name: 'City');
      final id = await service.createLocation(name: 'City', parentId: parent);
      final before = await service.getLocationById(id);
      await expectLater(
        service.updateLocation(id: id, clearParentId: true),
        throwsA(isA<DuplicateLocationNameException>()),
      );
      expect(await service.getLocationById(id), before);
      await service.updateLocation(
        id: id,
        clearParentId: true,
        name: 'New city',
      );
      expect((await service.getLocationById(id))!.parentId, isNull);
    },
  );

  test(
    'duplicate rename rejects every field and keeps the original timestamp',
    () async {
      await service.createLocation(name: '旧都');
      final id = await service.createLocation(name: '新城', description: '原描述');
      final before = await service.getLocationById(id);
      await expectLater(
        service.updateLocation(id: id, name: ' 旧都 ', description: '不应保存'),
        throwsException,
      );
      expect(await service.getLocationById(id), before);
    },
  );

  test('own name and case-distinct names remain valid', () async {
    final id = await service.createLocation(name: 'City');
    await service.createLocation(name: 'city');
    await service.updateLocation(id: id, name: 'City', description: '已更新');
    expect((await service.getLocationById(id))!.description, '已更新');
  });

  test('another work has an independent name namespace', () async {
    final other = NovelContentDatabase.forTest(NativeDatabase.memory());
    try {
      await service.createLocation(name: '江城');
      await LocationsService(other).createLocation(name: '江城');
      expect(await service.getLocations(), hasLength(1));
      expect(await LocationsService(other).getLocations(), hasLength(1));
    } finally {
      await other.close();
    }
  });

  test(
    'concurrent service instances cannot insert the same name twice',
    () async {
      final outcomes = await Future.wait([
        for (final instance in [service, LocationsService(db)])
          instance
              .createLocation(name: '江城')
              .then((_) => true, onError: (Object _) => false),
      ]);
      expect(outcomes.where((success) => success), hasLength(1));
      expect(await service.getLocations(), hasLength(1));
    },
  );

  test(
    'legacy duplicate rows can retain their own names without cleanup',
    () async {
      for (final id in ['legacy_a', 'legacy_b']) {
        await db
            .into(db.locations)
            .insert(LocationsCompanion.insert(id: id, name: '旧同名'));
      }
      await service.updateLocation(
        id: 'legacy_a',
        name: '旧同名',
        description: '仅更新描述',
      );
      expect((await service.getLocationById('legacy_a'))!.description, '仅更新描述');
      expect((await service.getLocationById('legacy_b'))!.name, '旧同名');
      await expectLater(service.createLocation(name: '旧同名'), throwsException);
    },
  );
  test('photo add and remove keep names and the latest stored list', () async {
    final id = await service.createLocation(name: 'Harbor');
    expect(
      await service.addPhotos(
        id: id,
        assetIds: ['images/a.png', 'images/b.png'],
      ),
      const [
        SubjectPhoto(assetId: 'images/a.png'),
        SubjectPhoto(assetId: 'images/b.png'),
      ],
    );
    await service.renamePhoto(id: id, assetId: 'images/a.png', name: 'Night');
    // Another writer appended a photo after the editor loaded its list.
    await service.updateLocation(
      id: id,
      photos: const [
        SubjectPhoto(assetId: 'images/a.png', name: 'Night'),
        SubjectPhoto(assetId: 'images/b.png'),
        SubjectPhoto(assetId: 'images/c.png', name: 'Pier'),
      ],
    );

    // Re-importing an existing path does not duplicate it or reset its name.
    await service.addPhotos(id: id, assetIds: ['images/a.png', 'images/d.png']);
    await service.removePhoto(id: id, assetId: 'images/b.png');
    expect((await service.getLocationById(id))!.photos, const [
      SubjectPhoto(assetId: 'images/a.png', name: 'Night'),
      SubjectPhoto(assetId: 'images/c.png', name: 'Pier'),
      SubjectPhoto(assetId: 'images/d.png'),
    ]);

    await expectLater(
      service.addPhotos(id: 'missing', assetIds: ['images/e.png']),
      throwsA(isA<StateError>()),
    );
  });
}
