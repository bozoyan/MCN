// 职责: 行级 diff 与 hunk 分组工具 — 为 GitHub 风格统一 diff 视图提供数据源。
// 关联文件:
//   lib/desktop/widgets/ai/diff_view.dart
//   lib/shared/utils/simple_diff.dart
//   lib/shared/services/working_change_summary.dart

/// 行在 diff 中的角色。
enum LineDiffKind { context, delete, insert }

/// Diff 中的一行：
/// - [oldLineNumber] 与 [newLineNumber] 为 1-based；不存在时为 null。
/// - [text] 不含末尾换行符。
class LineDiffEntry {
  const LineDiffEntry({
    required this.kind,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final LineDiffKind kind;
  final String text;
  final int? oldLineNumber;
  final int? newLineNumber;
}

/// 一段连续展示区域。`isCollapsed=true` 时表示折叠的上下文（仅显示 hint）。
class DiffHunk {
  const DiffHunk({required this.entries, this.isCollapsed = false});

  final List<LineDiffEntry> entries;
  final bool isCollapsed;

  /// 折叠区跨越的旧/新行号范围（仅 isCollapsed=true 时有意义）。
  int get collapsedLineCount => isCollapsed
      ? entries.where((e) => e.kind == LineDiffKind.context).length
      : 0;
}

/// 在 [a] 与 [b] 之间做行级 LCS diff。
///
/// 返回完整的 entries 序列（含 context / delete / insert）。
/// 结果已按显示顺序排好（GitHub 风格：相邻 delete 块紧跟相邻 insert 块）。
List<LineDiffEntry> computeLineDiff(String? a, String? b) {
  final sa = a ?? '';
  final sb = b ?? '';
  if (sa.isEmpty && sb.isEmpty) return const <LineDiffEntry>[];

  final oldLines = sa.isEmpty ? const <String>[] : sa.split('\n');
  final newLines = sb.isEmpty ? const <String>[] : sb.split('\n');

  if (oldLines.isEmpty) {
    return [
      for (var j = 0; j < newLines.length; j++)
        LineDiffEntry(
          kind: LineDiffKind.insert,
          text: newLines[j],
          newLineNumber: j + 1,
        ),
    ];
  }
  if (newLines.isEmpty) {
    return [
      for (var i = 0; i < oldLines.length; i++)
        LineDiffEntry(
          kind: LineDiffKind.delete,
          text: oldLines[i],
          oldLineNumber: i + 1,
        ),
    ];
  }

  final n = oldLines.length;
  final m = newLines.length;

  // 大小保护：避免极端长文造成 O(n*m) 内存爆炸。
  if (n * m > 400_000) {
    return [
      for (var i = 0; i < n; i++)
        LineDiffEntry(
          kind: LineDiffKind.delete,
          text: oldLines[i],
          oldLineNumber: i + 1,
        ),
      for (var j = 0; j < m; j++)
        LineDiffEntry(
          kind: LineDiffKind.insert,
          text: newLines[j],
          newLineNumber: j + 1,
        ),
    ];
  }

  // 公共前缀 / 后缀剪枝（让 LCS 表更小）。
  var prefix = 0;
  while (prefix < n && prefix < m && oldLines[prefix] == newLines[prefix]) {
    prefix += 1;
  }
  var suffix = 0;
  while (suffix < n - prefix &&
      suffix < m - prefix &&
      oldLines[n - 1 - suffix] == newLines[m - 1 - suffix]) {
    suffix += 1;
  }

  final result = <LineDiffEntry>[];
  for (var k = 0; k < prefix; k++) {
    result.add(
      LineDiffEntry(
        kind: LineDiffKind.context,
        text: oldLines[k],
        oldLineNumber: k + 1,
        newLineNumber: k + 1,
      ),
    );
  }

  final midOld = oldLines.sublist(prefix, n - suffix);
  final midNew = newLines.sublist(prefix, m - suffix);
  final midOps = _midDiff(midOld, midNew, prefix);
  result.addAll(midOps);

  for (var k = 0; k < suffix; k++) {
    final oldIdx = n - suffix + k;
    final newIdx = m - suffix + k;
    result.add(
      LineDiffEntry(
        kind: LineDiffKind.context,
        text: oldLines[oldIdx],
        oldLineNumber: oldIdx + 1,
        newLineNumber: newIdx + 1,
      ),
    );
  }

  return result;
}

List<LineDiffEntry> _midDiff(
  List<String> oldLines,
  List<String> newLines,
  int baseOffset,
) {
  final n = oldLines.length;
  final m = newLines.length;
  if (n == 0 && m == 0) return const <LineDiffEntry>[];
  if (n == 0) {
    return [
      for (var j = 0; j < m; j++)
        LineDiffEntry(
          kind: LineDiffKind.insert,
          text: newLines[j],
          newLineNumber: baseOffset + j + 1,
        ),
    ];
  }
  if (m == 0) {
    return [
      for (var i = 0; i < n; i++)
        LineDiffEntry(
          kind: LineDiffKind.delete,
          text: oldLines[i],
          oldLineNumber: baseOffset + i + 1,
        ),
    ];
  }

  final dp = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (oldLines[i] == newLines[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  // 先生成混排序列，然后按 GitHub 风格在每个变更段内把 delete 排在 insert 之前。
  final raw = <LineDiffEntry>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (oldLines[i] == newLines[j]) {
      raw.add(
        LineDiffEntry(
          kind: LineDiffKind.context,
          text: oldLines[i],
          oldLineNumber: baseOffset + i + 1,
          newLineNumber: baseOffset + j + 1,
        ),
      );
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      raw.add(
        LineDiffEntry(
          kind: LineDiffKind.delete,
          text: oldLines[i],
          oldLineNumber: baseOffset + i + 1,
        ),
      );
      i++;
    } else {
      raw.add(
        LineDiffEntry(
          kind: LineDiffKind.insert,
          text: newLines[j],
          newLineNumber: baseOffset + j + 1,
        ),
      );
      j++;
    }
  }
  while (i < n) {
    raw.add(
      LineDiffEntry(
        kind: LineDiffKind.delete,
        text: oldLines[i],
        oldLineNumber: baseOffset + i + 1,
      ),
    );
    i++;
  }
  while (j < m) {
    raw.add(
      LineDiffEntry(
        kind: LineDiffKind.insert,
        text: newLines[j],
        newLineNumber: baseOffset + j + 1,
      ),
    );
    j++;
  }

  return _reorderChangeBlocks(raw);
}

/// 对相邻的非 context 段进行重排：先列出本段内全部 delete，再列出全部 insert。
List<LineDiffEntry> _reorderChangeBlocks(List<LineDiffEntry> raw) {
  final out = <LineDiffEntry>[];
  var k = 0;
  while (k < raw.length) {
    if (raw[k].kind == LineDiffKind.context) {
      out.add(raw[k]);
      k++;
      continue;
    }
    final dels = <LineDiffEntry>[];
    final ins = <LineDiffEntry>[];
    while (k < raw.length && raw[k].kind != LineDiffKind.context) {
      if (raw[k].kind == LineDiffKind.delete) {
        dels.add(raw[k]);
      } else {
        ins.add(raw[k]);
      }
      k++;
    }
    out.addAll(dels);
    out.addAll(ins);
  }
  return out;
}

/// 把 entries 切分成显示 hunk：变更前后保留 [contextLines] 行，
/// 中间过长的纯 context 段折叠为 [DiffHunk.isCollapsed] 提示。
///
/// 当所有内容都未变（无 delete/insert）时，返回单个非折叠 hunk，
/// 由调用方决定是否展示「无差异」占位。
List<DiffHunk> groupHunks(
  List<LineDiffEntry> entries, {
  int contextLines = 3,
  int collapseThreshold = 8,
}) {
  if (entries.isEmpty) return const <DiffHunk>[];

  final hasChange = entries.any((e) => e.kind != LineDiffKind.context);
  if (!hasChange) {
    return [DiffHunk(entries: List.unmodifiable(entries))];
  }

  // 标记哪些下标需要保留：所有变更行 + 其前后 contextLines 行 context。
  final keep = List<bool>.filled(entries.length, false);
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].kind != LineDiffKind.context) {
      final start = (i - contextLines).clamp(0, entries.length - 1);
      final end = (i + contextLines).clamp(0, entries.length - 1);
      for (var k = start; k <= end; k++) {
        keep[k] = true;
      }
    }
  }

  final hunks = <DiffHunk>[];
  var idx = 0;
  while (idx < entries.length) {
    if (keep[idx]) {
      final start = idx;
      while (idx < entries.length && keep[idx]) {
        idx++;
      }
      hunks.add(
        DiffHunk(entries: List.unmodifiable(entries.sublist(start, idx))),
      );
    } else {
      final start = idx;
      while (idx < entries.length && !keep[idx]) {
        idx++;
      }
      final span = entries.sublist(start, idx);
      if (span.length >= collapseThreshold) {
        hunks.add(
          DiffHunk(entries: List.unmodifiable(span), isCollapsed: true),
        );
      } else {
        // 短间隙不折叠，直接合并到结果里作为 context。
        if (hunks.isNotEmpty && !hunks.last.isCollapsed) {
          final merged = <LineDiffEntry>[
            ...hunks.removeLast().entries,
            ...span,
          ];
          hunks.add(DiffHunk(entries: List.unmodifiable(merged)));
        } else {
          hunks.add(DiffHunk(entries: List.unmodifiable(span)));
        }
      }
    }
  }
  return hunks;
}

/// 把相邻的 delete/insert 行配对，返回每行（按 entries 顺序）的“配对索引”。
///
/// 用于行内字符级高亮：当某 delete 行与某 insert 行成对时，UI 可对它们再做
/// 字符级 diff 高亮变化片段。如果某行没有合理对端，返回 -1。
List<int> pairChangeLines(List<LineDiffEntry> entries) {
  final pairs = List<int>.filled(entries.length, -1);
  var k = 0;
  while (k < entries.length) {
    if (entries[k].kind == LineDiffKind.context) {
      k++;
      continue;
    }
    final blockStart = k;
    final delIdx = <int>[];
    final insIdx = <int>[];
    while (k < entries.length && entries[k].kind != LineDiffKind.context) {
      if (entries[k].kind == LineDiffKind.delete) {
        delIdx.add(k);
      } else {
        insIdx.add(k);
      }
      k++;
    }
    final paired = delIdx.length < insIdx.length
        ? delIdx.length
        : insIdx.length;
    for (var p = 0; p < paired; p++) {
      pairs[delIdx[p]] = insIdx[p];
      pairs[insIdx[p]] = delIdx[p];
    }
    // ignore: unused_local_variable
    final _ = blockStart;
  }
  return pairs;
}
