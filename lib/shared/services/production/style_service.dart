// 职责: 新建、编辑与删除用户自定义的生成风格。
// 关联文件:
//   lib/shared/database/daos/production_style_dao.dart
//   lib/shared/models/production/style.dart
//   lib/shared/providers/production_media.dart
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../../models/production/style.dart';

class ProductionStyleService {
  ProductionStyleService(this.database);
  final AppDatabase database;

  Future<ProductionStyleRow> save({
    String? id,
    required String name,
    required ProductionStylePrompt prompt,
  }) async {
    final styleId = id ?? const Uuid().v4();
    if (id != null) {
      await database.productionStyleDao.updateStyle(id, name, prompt);
    } else {
      await database.productionStyleDao.insertStyle(styleId, name, prompt);
    }
    return (await database.productionStyleDao.getStyle(styleId))!;
  }

  Future<void> delete(String id) =>
      database.productionStyleDao.softDeleteStyle(id);
}
