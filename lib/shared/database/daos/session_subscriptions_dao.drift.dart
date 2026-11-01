// dart format width=80
// ignore_for_file: type=lint
part of 'session_subscriptions_dao.dart';

mixin _$SessionSubscriptionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionSubscriptionsTable get sessionSubscriptions =>
      attachedDatabase.sessionSubscriptions;
  SessionSubscriptionsDaoManager get managers =>
      SessionSubscriptionsDaoManager(this);
}

class SessionSubscriptionsDaoManager {
  final _$SessionSubscriptionsDaoMixin _db;
  SessionSubscriptionsDaoManager(this._db);
  $$SessionSubscriptionsTableTableManager get sessionSubscriptions =>
      $$SessionSubscriptionsTableTableManager(
        _db.attachedDatabase,
        _db.sessionSubscriptions,
      );
}
