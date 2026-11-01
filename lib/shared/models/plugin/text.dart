// 职责: 解析插件清单中可本地化的文案，并按界面语言选出显示文本。
// 关联文件:
//   lib/shared/models/plugin/action.dart
//   lib/shared/widgets/settings/plugins/config_surface.dart

import 'dart:ui';

/// 清单中的文案：字符串表示所有语言共用，对象按语言标签给出各语言文本，
/// 如 `{"en": "Verify", "zh-CN": "验证"}`。
class PluginText {
  const PluginText(this.values);

  /// 所有语言共用的文案。
  PluginText.plain(String text) : values = {'': text};

  /// 语言标签到文本，按清单中的顺序；共用文案的 key 为空字符串。
  final Map<String, String> values;

  /// 依次取当前语言、宿主的回退语言 zh-CN、en，都没有时取第一项。
  String resolve(Locale locale) =>
      values[locale.toLanguageTag()] ??
      values['zh-CN'] ??
      values['en'] ??
      values.values.first;
}

/// 解析 [path] 处的文案；缺失、为空或含非字符串的语言项时抛出 [FormatException]。
PluginText parsePluginText(Object? json, String path) {
  if (json is String && json.trim().isNotEmpty) {
    return PluginText.plain(json);
  }
  if (json is Map && json.isNotEmpty) {
    final values = <String, String>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key is! String ||
          key.isEmpty ||
          value is! String ||
          value.trim().isEmpty) {
        throw FormatException('$path.$key must be a non-empty string');
      }
      values[key] = value;
    }
    return PluginText(Map.unmodifiable(values));
  }
  throw FormatException('$path is required');
}
