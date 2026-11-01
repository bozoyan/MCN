// dart format width=80
// ignore_for_file: type=lint
part of 'generation_task_dao.dart';

mixin _$GenerationTaskDaoMixin on DatabaseAccessor<AppDatabase> {
  $GenerationTasksTable get generationTasks => attachedDatabase.generationTasks;
  GenerationTaskDaoManager get managers => GenerationTaskDaoManager(this);
}

class GenerationTaskDaoManager {
  final _$GenerationTaskDaoMixin _db;
  GenerationTaskDaoManager(this._db);
  $$GenerationTasksTableTableManager get generationTasks =>
      $$GenerationTasksTableTableManager(
        _db.attachedDatabase,
        _db.generationTasks,
      );
}
