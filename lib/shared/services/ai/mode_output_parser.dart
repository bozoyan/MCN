// 职责: 解析 AI 模式的分段输出 — 小剧场/独白的【】标记段，以及议会总结的 Markdown 小节；编排器落库与 UI 流式展示共用同一套规则。
// 关联文件:
//   lib/shared/services/ai/theater_orchestrator.dart
//   lib/shared/services/ai/monologue_orchestrator.dart
//   lib/shared/services/ai/agent_council_orchestrator.dart
//   assets/prompts/agent/theater_actor.md
//   assets/prompts/system/council_summarizer.md

/// 流式中途末尾可能停在半个标记上（如「【舞台」），展示时先去掉。
final _danglingTag = RegExp(r'【[^】]*$');

String _prepare(String raw, bool partial) =>
    partial ? raw.replaceFirst(_danglingTag, '') : raw;

/// 段落标记出现过但目标段尚未开始时，流式展示应为空而不是回退成原文。
String _fallback(String text, bool partial) =>
    partial && text.contains('【') ? '' : text.trim();

/// 小剧场单句输出。[partial] 为 true 表示仍在流式生成。
({String? addressee, String? stageDirection, String dialogue})
parseTheaterOutput(String raw, {bool partial = false}) {
  final text = _prepare(raw, partial);
  final addressee = RegExp(
    r'【对象】(.*?)(?=【|$)',
    dotAll: true,
  ).firstMatch(text)?.group(1)?.trim();
  final stage = RegExp(
    r'【舞台指示】(.*?)(?=【台词】|【对象】|$)',
    dotAll: true,
  ).firstMatch(text)?.group(1)?.trim();
  final dialogue = RegExp(
    r'【台词】(.*?)(?=【对象】|$)',
    dotAll: true,
  ).firstMatch(text)?.group(1)?.trim();
  return (
    addressee: addressee == null || addressee.isEmpty || addressee == '无'
        ? null
        : addressee,
    // 格式要求无动作时写「无」，不当作舞台指示展示。
    stageDirection: stage == null || stage.isEmpty || stage == '无'
        ? null
        : stage,
    dialogue: dialogue ?? _fallback(text, partial),
  );
}

/// 独白单次输出。[partial] 为 true 表示仍在流式生成。
({String innerThoughts, String plannedActions}) parseMonologueOutput(
  String raw, {
  bool partial = false,
}) {
  final text = _prepare(raw, partial);
  final inner = RegExp(
    r'【内心活动】(.*?)(?=【接下来的行动】|$)',
    dotAll: true,
  ).firstMatch(text)?.group(1)?.trim();
  final actions = RegExp(
    r'【接下来的行动】(.*?)$',
    dotAll: true,
  ).firstMatch(text)?.group(1)?.trim();
  return (
    innerThoughts: inner ?? _fallback(text, partial),
    plannedActions: actions ?? '',
  );
}

final _councilHeading = RegExp(r'^#{1,6}\s*(.+?)\s*$');
final _councilListItem = RegExp(r'^(?:[-*•]\s+|\d+[.、)]\s*)(.+)$');

/// 议会总结按 `council_summarizer.md` 的小节取出列表项；只收紧跟标题的顶层条目，
/// 「关键分歧」下缩进的论据不算。没有对应小节时该项为空。
({List<String> keyPoints, List<String> openQuestions, List<String> actionItems})
parseCouncilSummary(String raw) {
  final keyPoints = <String>[];
  final openQuestions = <String>[];
  final actionItems = <String>[];
  List<String>? target;
  for (final line in raw.split('\n')) {
    final heading = _councilHeading.firstMatch(line.trim())?.group(1);
    if (heading != null) {
      target = switch (heading) {
        _ when heading.contains('共识') => keyPoints,
        _ when heading.contains('待决') => openQuestions,
        _ when heading.contains('下一步') || heading.contains('行动') => actionItems,
        _ => null,
      };
      continue;
    }
    if (target == null || line.trim().isEmpty) continue;
    if (line.startsWith(RegExp(r'\s'))) continue;
    final item = _councilListItem.firstMatch(line)?.group(1)?.trim();
    // 小节内出现普通段落即视为列表结束，后面的条目不再归入本节。
    if (item == null) {
      target = null;
    } else if (item.isNotEmpty) {
      target.add(item);
    }
  }
  return (
    keyPoints: keyPoints,
    openQuestions: openQuestions,
    actionItems: actionItems,
  );
}

final _councilAddressee = RegExp(r'\n?\s*【请回应】([^\n]*)\s*$');

/// 议会成员单次发言。末行「【请回应】成员名」是给调度器的点名，不属于正文。
/// [partial] 为 true 表示仍在流式生成。
({String content, String? addressee}) parseCouncilOutput(
  String raw, {
  bool partial = false,
}) {
  final text = _prepare(raw, partial);
  final match = _councilAddressee.firstMatch(text);
  final addressee = match?.group(1)?.trim();
  return (
    content: (match == null ? text : text.substring(0, match.start)).trim(),
    addressee: addressee == null || addressee.isEmpty || addressee == '无'
        ? null
        : addressee,
  );
}
