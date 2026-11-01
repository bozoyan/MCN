// 职责: 校验按名称寻址的 AI 路径资源名，拦截会让路径无法解析的结构字符。
// 关联文件:
//   lib/shared/services/canvas_service.dart
//   lib/shared/services/documents_service.dart
//   lib/shared/services/outline_service.dart
//   lib/shared/services/novel_content.dart

/// 名称是否含 AI 路径结构符。
///
/// usesNamePath 集合（canvas/lore/outlines/
/// materials）的名称/标题就是路径键 `/集合/{name}`。路径解析把首个 `?` 截为
/// 查询串起点、按 `/` 切段（tools_support.dart ParsedPath.parse），名称含任一
/// 字符都会让资源无法按路径寻址；多级路径是逐段建行实现的，存储名称里本就
/// 不该出现 `/`。新建与改名入口都应先经此校验。
bool nameHasAiPathStructuralChars(String name) {
  return name.contains('?') || name.contains('/');
}
