// 职责: 为旧手动集合回归断言读取分离后的定义及各自成员结果。
// 关联文件:
//   lib/shared/database/daos/novel_collection_dao.dart
//   lib/shared/models/novel_collection.dart
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/novel_collection.dart';

Future<List<ManualCollectionSnapshot>> manualSnapshots(AppDatabase db) async {
  final definitions = await db.novelCollectionDao.watchDefinitions().first;
  return Future.wait([
    for (final record in definitions.where((c) => c.filterMode == 'manual'))
      db.novelCollectionDao
          .getWorks(record.id)
          .then((works) => ManualCollectionSnapshot(record, works)),
  ]);
}

class ManualCollectionSnapshot {
  ManualCollectionSnapshot(this.record, this.works);
  final NovelCollection record;
  final List<Novel> works;
  String get id => record.id;
  String get name => record.name;
  Set<String> get workIds => works.map((n) => n.id).toSet();
  bool? membership(Iterable<String> ids) => collectionMembership(workIds, ids);
}
