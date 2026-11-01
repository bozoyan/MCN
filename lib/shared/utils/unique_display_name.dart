// 职责: 自动创建内容时生成不重复的显示名称。
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/services/documents_service.dart
//   lib/shared/services/outline_service.dart
//   lib/shared/services/maps_service.dart

String buildUniqueDisplayName({
  required String baseName,
  required Iterable<String> existingNames,
}) {
  final normalizedBaseName = baseName.trim();
  if (normalizedBaseName.isEmpty) {
    throw ArgumentError.value(baseName, 'baseName', 'baseName cannot be empty');
  }

  final usedNames = existingNames.map((name) => name.trim()).toSet();
  if (!usedNames.contains(normalizedBaseName)) {
    return normalizedBaseName;
  }

  var nextNumber = 2;
  while (usedNames.contains('$normalizedBaseName ($nextNumber)')) {
    nextNumber += 1;
  }
  return '$normalizedBaseName ($nextNumber)';
}
