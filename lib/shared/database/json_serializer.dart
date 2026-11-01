// 职责: 提供 snake_case JSON 序列化的 ValueSerializer
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/database/app_database.dart

import 'package:drift/drift.dart';

class SnakeCaseSerializer implements ValueSerializer {
  const SnakeCaseSerializer();

  static const ValueSerializer _default = ValueSerializer.defaults();

  @override
  T fromJson<T>(json) => _default.fromJson<T>(json);

  @override
  Object? toJson<T>(T value) => _default.toJson<T>(value);

  static String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  static Map<String, dynamic> toSnakeCaseJson(DataClass dataClass) {
    final camelCaseJson = dataClass.toJson();
    return camelCaseJson.map(
      (key, value) => MapEntry(_toSnakeCase(key), value),
    );
  }
}

extension SnakeCaseJson on DataClass {
  Map<String, dynamic> toSnakeCaseJson() =>
      SnakeCaseSerializer.toSnakeCaseJson(this);
}
