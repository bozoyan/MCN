// 职责: 读写、按名称去重与软删除用户自定义的生成风格。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/production/style.dart
//   lib/shared/services/production/style_service.dart

import 'package:drift/drift.dart';

import '../../logger/app_logger.dart';
import '../../models/production/style.dart';
import '../app_database.dart';

part 'production_style_dao.drift.dart';

final _log = AppLogger.forModule('ProductionStyleDao');

@DriftAccessor(tables: [ProductionStyles])
class ProductionStyleDao extends DatabaseAccessor<AppDatabase>
    with _$ProductionStyleDaoMixin {
  ProductionStyleDao(super.db);

  /// 未删除的自定义风格，新建的在前。
  Stream<List<ProductionStyleRow>> watchStyles() =>
      (select(productionStyles)
            ..where((t) => t.deletedAt.equals(notDeletedSentinel))
            ..orderBy([
              (t) => OrderingTerm.desc(t.createdAt),
              (t) => OrderingTerm.desc(t.id),
            ]))
          .watch();

  /// 单个风格；不存在或已软删除时为 null。
  Future<ProductionStyleRow?> getStyle(String id) =>
      (select(productionStyles)..where(
            (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
          ))
          .getSingleOrNull();

  /// 已有同名风格时补「 (2)」「 (3)」…直到不重名；[exceptId] 是正在改名的风格自己。
  Future<String> uniqueName(String name, {String? exceptId}) async {
    final taken = {
      for (final row
          in await (selectOnly(productionStyles)
                ..addColumns([productionStyles.name])
                ..where(
                  productionStyles.deletedAt.equals(notDeletedSentinel) &
                      (exceptId == null
                          ? const Constant(true)
                          : productionStyles.id.equals(exceptId).not()),
                ))
              .get())
        row.read(productionStyles.name),
    };
    var candidate = name;
    for (var n = 2; taken.contains(candidate); n++) {
      candidate = '$name ($n)';
    }
    return candidate;
  }

  Future<void> insertStyle(
    String id,
    String name,
    ProductionStylePrompt prompt,
  ) async {
    try {
      if (name.trim().isEmpty) {
        throw ArgumentError('Style name required');
      }
      await into(productionStyles).insert(
        ProductionStylesCompanion.insert(
          id: id,
          name: Value(await uniqueName(name.trim())),
          before: Value(prompt.before),
          after: Value(prompt.after),
        ),
      );
    } catch (error, stack) {
      _log.error(
        '[DB] production_styles INSERT id=$id',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> updateStyle(
    String id,
    String name,
    ProductionStylePrompt prompt,
  ) async {
    try {
      if (name.trim().isEmpty || await getStyle(id) == null) {
        throw ArgumentError('Invalid style edit');
      }
      await (update(productionStyles)..where((t) => t.id.equals(id))).write(
        ProductionStylesCompanion(
          name: Value(await uniqueName(name.trim(), exceptId: id)),
          before: Value(prompt.before),
          after: Value(prompt.after),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (error, stack) {
      _log.error(
        '[DB] production_styles UPDATE id=$id',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> softDeleteStyle(String id) async {
    try {
      await (update(productionStyles)..where((t) => t.id.equals(id))).write(
        ProductionStylesCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (error, stack) {
      _log.error(
        '[DB] production_styles UPDATE soft-delete id=$id',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
