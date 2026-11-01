// dart format width=80
// ignore_for_file: type=lint
part of 'ai_provider_dao.dart';

mixin _$AiProviderDaoMixin on DatabaseAccessor<AppDatabase> {
  $AiProvidersTable get aiProviders => attachedDatabase.aiProviders;
  AiProviderDaoManager get managers => AiProviderDaoManager(this);
}

class AiProviderDaoManager {
  final _$AiProviderDaoMixin _db;
  AiProviderDaoManager(this._db);
  $$AiProvidersTableTableManager get aiProviders =>
      $$AiProvidersTableTableManager(_db.attachedDatabase, _db.aiProviders);
}
