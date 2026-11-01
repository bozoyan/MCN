// 职责: 验证会话 Todo 的持久化、隔离和活跃快照合并语义
// 关联文件:
//   lib/shared/providers/todo_providers.dart
//   lib/shared/database/daos/todo_dao.dart
//   lib/shared/models/todo.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/daos/todo_dao.dart';
import 'package:reveric/shared/models/todo.dart';
import 'package:reveric/shared/providers/todo_providers.dart';

void main() {
  test(
    'saveTodos from an unlistened notifier persists without unmounting',
    () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          todoDaoProvider.overrideWith((ref) async => TodoDao(database)),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final todos = [createTodo(content: 'Persist after tool callback')];
      final save = container
          .read(sessionTodosProvider('persisted_session').notifier)
          .saveTodos(todos);

      await Future<void>.delayed(Duration.zero);
      final saved = await save;

      expect(saved, hasLength(1));
      expect(
        await TodoDao(database).getTodosBySession('persisted_session'),
        hasLength(1),
      );
    },
  );

  test('same todo id is isolated by session', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final dao = TodoDao(database);
    addTearDown(database.close);

    await dao.saveTodos('parent_session', [
      _todo(id: 'todo_1', content: 'parent', sessionId: 'parent_session'),
    ]);
    await dao.saveTodos('child_session', [
      _todo(id: 'todo_1', content: 'child', sessionId: 'child_session'),
    ]);

    expect(
      (await dao.getTodosBySession('parent_session')).single.content,
      'parent',
    );
    expect(
      (await dao.getTodosBySession('child_session')).single.content,
      'child',
    );

    final parent = await dao.getTodoById('parent_session', 'todo_1');
    expect(parent?.content, 'parent');
    await dao.updateTodo(parent!.copyWith(content: 'updated parent'));
    expect(
      (await dao.getTodoById('parent_session', 'todo_1'))?.content,
      'updated parent',
    );
    expect(
      (await dao.getTodoById('child_session', 'todo_1'))?.content,
      'child',
    );

    await dao.deleteTodo('parent_session', 'todo_1');
    expect(await dao.getTodoById('parent_session', 'todo_1'), isNull);
    expect(await dao.getTodoById('child_session', 'todo_1'), isNotNull);
  });

  test(
    'persists TodoWrite snapshot order after later todos are added',
    () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      final dao = TodoDao(database);
      addTearDown(database.close);
      final firstCreatedAt = DateTime(2026, 8, 4, 15, 23, 34);
      final laterCreatedAt = DateTime(2026, 8, 4, 15, 27, 14);

      await dao.saveTodos('session', [
        _todo(
          id: '1',
          content: 'create chapter',
          sessionId: 'session',
          createdAt: firstCreatedAt,
        ),
        _todo(
          id: '2',
          content: 'first review',
          sessionId: 'session',
          createdAt: firstCreatedAt,
        ),
        _todo(
          id: '3',
          content: 'apply fixes',
          sessionId: 'session',
          createdAt: firstCreatedAt,
        ),
      ]);

      final saved = await dao.saveTodos('session', [
        _todo(
          id: '1',
          content: 'create chapter',
          status: 'completed',
          sessionId: 'session',
          createdAt: laterCreatedAt,
        ),
        _todo(
          id: '2',
          content: 'first review',
          status: 'completed',
          sessionId: 'session',
          createdAt: laterCreatedAt,
        ),
        _todo(
          id: '3',
          content: 'apply fixes',
          status: 'completed',
          sessionId: 'session',
          createdAt: laterCreatedAt,
        ),
        _todo(
          id: '4',
          content: 'second review',
          status: 'in_progress',
          sessionId: 'session',
          createdAt: laterCreatedAt,
        ),
        _todo(
          id: '5',
          content: 'final delivery',
          sessionId: 'session',
          createdAt: laterCreatedAt,
        ),
      ]);

      expect(saved.map((todo) => todo.id), ['1', '2', '3', '4', '5']);
      expect((await dao.getTodosBySession('session')).map((todo) => todo.id), [
        '1',
        '2',
        '3',
        '4',
        '5',
      ]);

      // 快照顺序波动不改变既有位置：位置在首次入库时定下。
      await dao.saveTodos('session', [
        saved[2],
        saved[0],
        saved[4],
        saved[1],
        saved[3],
      ]);
      expect((await dao.getTodosBySession('session')).map((todo) => todo.id), [
        '1',
        '2',
        '3',
        '4',
        '5',
      ]);
    },
  );

  test(
    'omitted terminal todos stay visible while omitted active todos leave',
    () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      final dao = TodoDao(database);
      addTearDown(database.close);

      await dao.saveTodos('session', [
        _todo(
          id: 'todo_1',
          content: 'completed history',
          status: 'completed',
          sessionId: 'session',
        ),
        _todo(
          id: 'todo_2',
          content: 'old active',
          status: 'in_progress',
          sessionId: 'session',
        ),
        _todo(
          id: 'todo_4',
          content: 'old cancelled',
          status: 'cancelled',
          sessionId: 'session',
        ),
      ]);

      final merged = await dao.saveTodos('session', [
        _todo(
          id: 'todo_3',
          content: 'new active',
          status: 'in_progress',
          sessionId: 'session',
        ),
      ]);

      expect(
        merged.map((todo) => todo.id),
        containsAll(<String>['todo_1', 'todo_3', 'todo_4']),
      );
      expect(merged, hasLength(3));
      expect(merged.map((todo) => todo.id), isNot(contains('todo_2')));
      final persistedIds = (await dao.getTodosBySession(
        'session',
      )).map((todo) => todo.id).toSet();
      expect(persistedIds, <String>{'todo_1', 'todo_3', 'todo_4'});
      // 历史终态留在它首次入库的位置，新提交的活跃项追加到末尾。
      expect(merged.map((todo) => todo.id), ['todo_1', 'todo_4', 'todo_3']);
      expect((await dao.getTodosBySession('session')).map((todo) => todo.id), [
        'todo_1',
        'todo_4',
        'todo_3',
      ]);

      final reopened = await dao.saveTodos('session', [
        _todo(
          id: 'todo_4',
          content: 'reopened',
          status: 'pending',
          sessionId: 'session',
        ),
      ]);
      expect(reopened, hasLength(2));
      final reopenedTodo = reopened.singleWhere((todo) => todo.id == 'todo_4');
      expect(reopenedTodo.status, 'pending');
      expect(reopenedTodo.content, 'reopened');
      // 重新打开不改变位置，todo_4 仍排在 todo_1 之后。
      expect(reopened.map((todo) => todo.id), ['todo_1', 'todo_4']);
      expect((await dao.getTodosBySession('session')).map((todo) => todo.id), [
        'todo_1',
        'todo_4',
      ]);
    },
  );
}

Todo _todo({
  required String id,
  required String content,
  required String sessionId,
  String status = 'pending',
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime.now();
  return Todo(
    id: id,
    content: content,
    status: status,
    priority: 'medium',
    sessionId: sessionId,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}
