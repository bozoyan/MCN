// 职责: 按行接受计算、双栏对齐与审阅布局判定 — 根据被退回的行键集合合成目标文本、把统一 diff 对齐为审阅行，并按审阅行统计退回行数。
// 关联文件:
//   lib/shared/utils/line_diff.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/widgets/ai/diff/diff_view.dart
//   lib/desktop/widgets/ai/diff/pending_changes_detail_dialog.dart
import 'line_diff.dart';

/// 变更行在按行审阅中的稳定标识：
/// 删除行为 `d:<old行号>`，新增行为 `i:<new行号>`；context 行不参与审阅，返回空串。
///
/// old/new 文本绑定一份不可变审阅快照（可引用多条 WorkingChange），[computeLineDiff] 重算结果确定，
/// 因此行键在渲染（diff 视图）与应用（overlay 回写）之间保持一致。
String lineAcceptKeyFor(LineDiffEntry entry) {
  if (entry.kind == LineDiffKind.delete) {
    return 'd:${entry.oldLineNumber}';
  }
  if (entry.kind == LineDiffKind.insert) {
    return 'i:${entry.newLineNumber}';
  }
  return '';
}

/// 按行接受合成目标文本，即「原文 + 保留的 AI 行」：
/// - context 行始终保留；
/// - delete 行被退回（key 在 [rejectedLineKeys] 中）→ 保留原行，否则丢弃；
/// - insert 行被退回 → 丢弃，否则保留新行。
///
/// 无有效退回时结果等于 [newText]；全部变更行被退回时结果等于 [oldText]。
String computeLineAcceptResult(
  String? oldText,
  String? newText,
  Set<String> rejectedLineKeys,
) {
  final entries = computeLineDiff(oldText, newText);
  if (entries.isEmpty) {
    return '';
  }
  final kept = <String>[];
  for (final entry in entries) {
    if (entry.kind == LineDiffKind.context) {
      kept.add(entry.text);
    } else if (entry.kind == LineDiffKind.delete) {
      if (rejectedLineKeys.contains(lineAcceptKeyFor(entry))) {
        kept.add(entry.text);
      }
    } else {
      if (!rejectedLineKeys.contains(lineAcceptKeyFor(entry))) {
        kept.add(entry.text);
      }
    }
  }
  return kept.join('\n');
}

/// 按行审阅的布局形态。
///
/// 纯新增 / 纯删除没有「旧文 vs 新文」的对照关系，只做单栏展示、不提供按行退回；
/// 只有删增混合的修改才进入双栏审阅。
enum LineReviewLayout {
  /// 无变更（两端相等或均为空）。
  none,

  /// 纯新增（如新建章节）：单栏展示新文本。
  pure_insert,

  /// 纯删除（如清空字段）：单栏展示旧文本。
  pure_delete,

  /// 删除+新增混合：双栏 side-by-side，逐行 ◀退回 / ▶接受。
  mixed,
}

/// 由 diff entries 判定审阅布局形态。
LineReviewLayout lineReviewLayoutOf(List<LineDiffEntry> entries) {
  var hasDeletes = false;
  var hasInserts = false;
  for (final entry in entries) {
    if (entry.kind == LineDiffKind.delete) {
      hasDeletes = true;
    } else if (entry.kind == LineDiffKind.insert) {
      hasInserts = true;
    }
  }
  if (hasDeletes && hasInserts) {
    return LineReviewLayout.mixed;
  }
  if (hasInserts) {
    return LineReviewLayout.pure_insert;
  }
  if (hasDeletes) {
    return LineReviewLayout.pure_delete;
  }
  return LineReviewLayout.none;
}

/// [oldText]→[newText] 的审阅布局形态，供审阅 UI 判断展示方式。
LineReviewLayout lineReviewLayoutFor(String? oldText, String? newText) {
  return lineReviewLayoutOf(computeLineDiff(oldText, newText));
}

/// 按行审阅的双栏对齐行：[left] 为 delete/context，[right] 为 insert/context。
///
/// 修改行左右同时非空；纯删除行仅 [left]，纯新增行仅 [right]；
/// context 行左右指向同一个 entry。
class LineReviewRow {
  const LineReviewRow({this.left, this.right});

  final LineDiffEntry? left;
  final LineDiffEntry? right;

  /// context 行（左右同文，不参与审阅）。
  bool get isContext => left != null && left!.kind == LineDiffKind.context;

  /// 行内全部变更行键（见 [lineAcceptKeyFor]）；context 行为空列表。
  List<String> get lineKeys {
    return [
      if (left != null && left!.kind == LineDiffKind.delete)
        lineAcceptKeyFor(left!),
      if (right != null && right!.kind == LineDiffKind.insert)
        lineAcceptKeyFor(right!),
    ];
  }
}

/// 把统一 diff entries 对齐为双栏审阅行：context 左右同文；
/// 连续 delete/insert 块按下标配对，多余的一侧留空（与 [pairChangeLines] 同序）。
List<LineReviewRow> alignLineReviewRows(List<LineDiffEntry> entries) {
  final rows = <LineReviewRow>[];
  var i = 0;
  while (i < entries.length) {
    final entry = entries[i];
    if (entry.kind == LineDiffKind.context) {
      rows.add(LineReviewRow(left: entry, right: entry));
      i++;
      continue;
    }
    final dels = <LineDiffEntry>[];
    final ins = <LineDiffEntry>[];
    while (i < entries.length && entries[i].kind != LineDiffKind.context) {
      if (entries[i].kind == LineDiffKind.delete) {
        dels.add(entries[i]);
      } else {
        ins.add(entries[i]);
      }
      i++;
    }
    final paired = dels.length < ins.length ? dels.length : ins.length;
    for (var p = 0; p < paired; p++) {
      rows.add(LineReviewRow(left: dels[p], right: ins[p]));
    }
    for (var d = paired; d < dels.length; d++) {
      rows.add(LineReviewRow(left: dels[d]));
    }
    for (var n = paired; n < ins.length; n++) {
      rows.add(LineReviewRow(right: ins[n]));
    }
  }
  return rows;
}

/// 审阅行是否整体被退回（行内全部行键都在 [rejectedLineKeys] 中）。
/// context 行（无行键）始终视为未退回。
bool isLineReviewRowReverted(LineReviewRow row, Set<String> rejectedLineKeys) {
  final keys = row.lineKeys;
  return keys.isNotEmpty && rejectedLineKeys.containsAll(keys);
}

/// 统计 [rejectedLineKeys] 覆盖的审阅行数：配对的删增修改行算 1 行，
/// 纯删除 / 纯新增行各算 1 行；行内行键未全部退回的不计入。
///
/// 面向用户的计数展示（如「已标记退回 N 行」）应使用审阅行数而非行键数，
/// 与逐行切换按钮的行语义一致。
int countRejectedReviewRows(
  String? oldText,
  String? newText,
  Set<String> rejectedLineKeys,
) {
  if (rejectedLineKeys.isEmpty) {
    return 0;
  }
  var count = 0;
  for (final row in alignLineReviewRows(computeLineDiff(oldText, newText))) {
    if (isLineReviewRowReverted(row, rejectedLineKeys)) {
      count++;
    }
  }
  return count;
}
