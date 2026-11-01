// 职责: 验证短实体 ID 分配对存量、同批、并发碰撞及非主键错误的处理边界。
// 关联文件:
//   lib/shared/utils/short_entity_id_allocator.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';
import 'package:reveric/shared/utils/short_entity_id_allocator.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database database;

  setUp(() {
    database = sqlite3.openInMemory();
    database.execute(
      'CREATE TABLE entries ('
      'id TEXT PRIMARY KEY, '
      'title TEXT NOT NULL UNIQUE'
      ')',
    );
  });

  tearDown(() {
    database.close();
  });

  test(
    'skips persisted and same-batch candidates before strict insert',
    () async {
      database.execute('INSERT INTO entries (id, title) VALUES (?, ?)', [
        'cha_AAAAAA',
        'persisted',
      ]);
      final candidates = ['cha_AAAAAA', 'cha_BBBBBB', 'cha_CCCCCC'];
      var cursor = 0;
      final reserved = {'cha_BBBBBB'};

      final id = await insertWithShortEntityId(
        type: ShortEntityIdType.character,
        tableName: 'entries',
        idExists: (candidate) async {
          return database.select('SELECT 1 FROM entries WHERE id = ? LIMIT 1', [
            candidate,
          ]).isNotEmpty;
        },
        insert: (candidate) async {
          database.execute('INSERT INTO entries (id, title) VALUES (?, ?)', [
            candidate,
            'created',
          ]);
        },
        reservedIds: reserved,
        buildId: (_) => candidates[cursor++],
      );

      expect(id, 'cha_CCCCCC');
      expect(reserved, contains('cha_CCCCCC'));
    },
  );

  test('retries an id primary-key race but not another unique error', () async {
    database.execute('INSERT INTO entries (id, title) VALUES (?, ?)', [
      'cha_AAAAAA',
      'existing-title',
    ]);
    final candidates = ['cha_AAAAAA', 'cha_BBBBBB'];
    var cursor = 0;

    final id = await insertWithShortEntityId(
      type: ShortEntityIdType.character,
      tableName: 'entries',
      idExists: (_) async => false,
      insert: (candidate) async {
        database.execute('INSERT INTO entries (id, title) VALUES (?, ?)', [
          candidate,
          'new-title',
        ]);
      },
      buildId: (_) => candidates[cursor++],
    );
    expect(id, 'cha_BBBBBB');

    var attempts = 0;
    await expectLater(
      insertWithShortEntityId(
        type: ShortEntityIdType.character,
        tableName: 'entries',
        idExists: (_) async => false,
        insert: (candidate) async {
          attempts += 1;
          database.execute('INSERT INTO entries (id, title) VALUES (?, ?)', [
            candidate,
            'existing-title',
          ]);
        },
        buildId: (_) => 'cha_CCCCCC',
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(attempts, 1);
  });

  test('fails explicitly after 32 rejected candidates', () async {
    var candidates = 0;

    await expectLater(
      insertWithShortEntityId(
        type: ShortEntityIdType.chapter,
        tableName: 'entries',
        idExists: (_) async => true,
        insert: (_) async => fail('insert must not run'),
        buildId: (_) {
          candidates += 1;
          return 'chp_AAAAAA';
        },
      ),
      throwsA(isA<ShortEntityIdAllocationException>()),
    );
    expect(candidates, shortEntityIdMaxAttempts);
  });
}
