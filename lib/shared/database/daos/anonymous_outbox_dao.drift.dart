// dart format width=80
// ignore_for_file: type=lint
part of 'anonymous_outbox_dao.dart';

mixin _$AnonymousOutboxDaoMixin on DatabaseAccessor<AppDatabase> {
  $AnonymousOutboxEventsTable get anonymousOutboxEvents =>
      attachedDatabase.anonymousOutboxEvents;
  AnonymousOutboxDaoManager get managers => AnonymousOutboxDaoManager(this);
}

class AnonymousOutboxDaoManager {
  final _$AnonymousOutboxDaoMixin _db;
  AnonymousOutboxDaoManager(this._db);
  $$AnonymousOutboxEventsTableTableManager get anonymousOutboxEvents =>
      $$AnonymousOutboxEventsTableTableManager(
        _db.attachedDatabase,
        _db.anonymousOutboxEvents,
      );
}
