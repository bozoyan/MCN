// 职责: 验证远程 Assistant 的小说列表回调只暴露已加入书架的作品。
// 关联文件:
//   lib/shared/providers/remote_bridge_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/database/daos/novel_dao.dart
//   lib/shared/models/novel.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/remote_bridge_providers.dart';

void main() {
  test('list_novels excludes quick-start drafts', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await database.novelDao.create(
      id: 'shelf-novel',
      title: 'Shelf Novel',
      description: '',
    );
    await database.novelDao.create(
      id: 'quick-start-draft',
      title: 'Quick Start Draft',
      description: '',
      draft: true,
    );

    final listNovels = container.read(assistantNovelListCallbackProvider);
    final result = await listNovels();

    expect(result.map((novel) => novel['id']), ['shelf-novel']);
  });
}
