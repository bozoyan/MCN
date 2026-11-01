// dart format width=80
// ignore_for_file: type=lint
part of 'production_style_dao.dart';

mixin _$ProductionStyleDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductionStylesTable get productionStyles =>
      attachedDatabase.productionStyles;
  ProductionStyleDaoManager get managers => ProductionStyleDaoManager(this);
}

class ProductionStyleDaoManager {
  final _$ProductionStyleDaoMixin _db;
  ProductionStyleDaoManager(this._db);
  $$ProductionStylesTableTableManager get productionStyles =>
      $$ProductionStylesTableTableManager(
        _db.attachedDatabase,
        _db.productionStyles,
      );
}
