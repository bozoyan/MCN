// 职责: 区分模型配置的继承与显式空值，合并按媒体类型划分的覆盖项，并从渠道型号 ID 识别目录型号。
// 关联文件:
//   lib/shared/models/audio/config.dart
//   lib/shared/models/video/config.dart
//   lib/shared/models/image/config.dart

/// 参数未传表示继承；ConfigValue(null) 表示明确取消限制或不发送参数。
class ConfigValue<T> {
  const ConfigValue(this.value);
  final T? value;
}

/// 按媒体类型合并参考限制：覆盖层未列出的类型继承，值为 null 的类型被移除，
/// 空 map 表示清空全部类型。
Map<K, V?>? mergeModelReferences<K, V extends Object>(
  Map<K, V?>? base,
  Map<K, V?>? overrides,
  V Function(V base, V override) merge,
) {
  if (overrides == null) {
    return base;
  }
  if (overrides.isEmpty) {
    return const {};
  }
  return Map.unmodifiable({
    ...?base,
    for (final MapEntry(:key, :value) in overrides.entries)
      key: switch ((base?[key], value)) {
        (_, null) => null,
        (final V inherited, final V override) => merge(inherited, override),
        (_, final V override) => override,
      },
  });
}

/// 从任意渠道的型号 ID 中识别目录型号：精确 ID 优先，再按完整型号名匹配
/// 渠道前缀、日期后缀和任务路径；未登记的变体（如 -fast）不回退到基础型号。
/// 例如 doubao-seedream-4-5-251128、bytedance/seedance-2.5/image-to-video。
/// 只返回目录 ID，不改写请求 ID，也不推断渠道协议。
class ModelIdRecognizer {
  ModelIdRecognizer(Map<String, Set<String>> aliasesById)
    : _ids = aliasesById.keys.toSet(),
      _matchers = [
        for (final MapEntry(key: id, value: aliases) in aliasesById.entries)
          for (final name in {_normalize(id), ...aliases.map(_normalize)})
            (
              id: id,
              length: name.length,
              pattern: RegExp(
                '(^|[^a-z0-9])${RegExp.escape(name)}'
                r'(?:-(?:[0-9]{6}|[0-9]{8}|[0-9]{4}-[0-9]{2}-[0-9]{2}))?'
                r'(?=$|[/@:])',
              ),
            ),
      ];

  final Set<String> _ids;
  final List<({String id, int length, RegExp pattern})> _matchers;

  static String _normalize(String id) =>
      id.trim().toLowerCase().replaceAll(RegExp(r'[._]'), '-');

  String? recognize(String? modelId) {
    final id = modelId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    if (_ids.contains(id)) {
      return id;
    }
    final normalized = _normalize(id);
    String? matched;
    var longest = 0;
    for (final matcher in _matchers) {
      if (matcher.length > longest && matcher.pattern.hasMatch(normalized)) {
        matched = matcher.id;
        longest = matcher.length;
      }
    }
    return matched;
  }
}
