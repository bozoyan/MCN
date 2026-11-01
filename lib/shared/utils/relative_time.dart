// 职责: 将时间格式化为中文相对时间文案（刚刚 / X 分钟前 / X 天前 …），供列表卡片复用。
// 关联文件:
//   lib/mobile/features/agent_skills/official_tab.dart
//   lib/desktop/features/agent_skills/official_catalog_tab.dart

/// 将 [time] 格式化为中文相对时间；[time] 为 null 时返回空串。
String formatRelativeTimeZh(DateTime? time) {
  if (time == null) {
    return '';
  }
  final delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) {
    return '刚刚';
  }
  if (delta.inHours < 1) {
    return '${delta.inMinutes} 分钟前';
  }
  if (delta.inDays < 1) {
    return '${delta.inHours} 小时前';
  }
  if (delta.inDays < 30) {
    return '${delta.inDays} 天前';
  }
  if (delta.inDays < 365) {
    return '${(delta.inDays / 30).floor()} 个月前';
  }
  return '${(delta.inDays / 365).floor()} 年前';
}

/// 将 ISO 字符串格式化为中文相对时间；空串返回空串，
/// 解析失败则原样返回（输入可能已是相对时间文案）。
String formatRelativeTimeFromIso(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) {
    return trimmed;
  }
  return formatRelativeTimeZh(parsed);
}
