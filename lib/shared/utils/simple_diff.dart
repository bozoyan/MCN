/// Lightweight, self-contained diff utility based on Myers' LCS algorithm.
///
/// Produces a list of [DiffOp] spans that describe how to transform [a] into
/// [b]. The diff is character-level when [mode] is [DiffMode.character] and
/// word-level (split on whitespace while preserving tokens) when it is
/// [DiffMode.word].
///
/// This is intentionally small (a few dozen lines) so the AI diff view does
/// not depend on a heavyweight third-party diff library.
enum DiffOpKind { equal, delete, insert }

enum DiffMode { character, word }

class DiffOp {
  const DiffOp(this.kind, this.text);
  final DiffOpKind kind;
  final String text;

  @override
  String toString() => '${kind.name}(${text.replaceAll('\n', r'\n')})';
}

List<DiffOp> computeDiff(
  String a,
  String b, {
  DiffMode mode = DiffMode.character,
}) {
  if (a == b) {
    return a.isEmpty ? const [] : [DiffOp(DiffOpKind.equal, a)];
  }
  final aTokens = _tokenize(a, mode);
  final bTokens = _tokenize(b, mode);

  // Trim common prefix / suffix to keep the LCS table small.
  var prefix = 0;
  while (prefix < aTokens.length &&
      prefix < bTokens.length &&
      aTokens[prefix] == bTokens[prefix]) {
    prefix += 1;
  }
  var suffix = 0;
  while (suffix < aTokens.length - prefix &&
      suffix < bTokens.length - prefix &&
      aTokens[aTokens.length - 1 - suffix] ==
          bTokens[bTokens.length - 1 - suffix]) {
    suffix += 1;
  }

  final aMid = aTokens.sublist(prefix, aTokens.length - suffix);
  final bMid = bTokens.sublist(prefix, bTokens.length - suffix);
  final midOps = _lcsDiff(aMid, bMid);

  final result = <DiffOp>[];
  if (prefix > 0) {
    result.add(DiffOp(DiffOpKind.equal, aTokens.sublist(0, prefix).join()));
  }
  result.addAll(midOps);
  if (suffix > 0) {
    result.add(
      DiffOp(DiffOpKind.equal, aTokens.sublist(aTokens.length - suffix).join()),
    );
  }
  return _coalesce(result);
}

/// Paragraph-aware diff tuned for streaming humanization, where [a] is the full
/// source and [b] is a growing prefix of the rewrite.
///
/// Content paragraphs are paired by **index**, then each changed pair is refined
/// with a character-level diff. Blank lines are separators, not pairing tokens:
/// an extra `\n` on either side is skipped as whitespace so later paragraphs
/// stay aligned. Aborting on that mismatch used to dump the rest of the chapter
/// as one delete+insert, even when only a few words changed.
///
/// Mid-stream, [b] is a prefix with fewer paragraphs. Pairing by content index
/// stays correct; unlike an LCS whose only anchors are blank lines, it does not
/// mis-anchor and cascade a whole-chapter false diff. Per-paragraph refinement
/// also bounds the O(n*m) character diff to one paragraph.
///
/// Source lines past the end of [b] (paragraphs not yet streamed) collapse into
/// a single trailing delete for the UI to render as pending.
List<DiffOp> computeSegmentedDiff(String a, String b) {
  if (a == b) {
    return a.isEmpty ? const [] : [DiffOp(DiffOpKind.equal, a)];
  }
  final aLines = _splitParagraphs(a);
  final bLines = _splitParagraphs(b);

  final out = <DiffOp>[];
  var i = 0;
  var j = 0;
  while (i < aLines.length && j < bLines.length) {
    final aLine = aLines[i];
    final bLine = bLines[j];
    final aBlank = _isBlankLine(aLine);
    final bBlank = _isBlankLine(bLine);

    if (aBlank && bBlank) {
      if (aLine == bLine) {
        out.add(DiffOp(DiffOpKind.equal, aLine));
      } else {
        out.addAll(computeDiff(aLine, bLine));
      }
      i += 1;
      j += 1;
      continue;
    }
    if (aBlank) {
      // Extra blank in source — skip so later content paragraphs stay aligned.
      out.add(DiffOp(DiffOpKind.delete, aLine));
      i += 1;
      continue;
    }
    if (bBlank) {
      // Extra blank in result — skip so later content paragraphs stay aligned.
      out.add(DiffOp(DiffOpKind.insert, bLine));
      j += 1;
      continue;
    }

    if (aLine == bLine) {
      out.add(DiffOp(DiffOpKind.equal, aLine));
    } else if (aLine.length * bLine.length <= 200_000) {
      out.addAll(computeDiff(aLine, bLine));
    } else {
      out.add(DiffOp(DiffOpKind.delete, aLine));
      out.add(DiffOp(DiffOpKind.insert, bLine));
    }
    i += 1;
    j += 1;
  }

  final remainingA = aLines.sublist(i).join();
  final remainingB = bLines.sublist(j).join();
  if (remainingA.isNotEmpty) {
    out.add(DiffOp(DiffOpKind.delete, remainingA));
  }
  if (remainingB.isNotEmpty) {
    out.add(DiffOp(DiffOpKind.insert, remainingB));
  }
  return _coalesce(out);
}

/// Split into line tokens, keeping each trailing `\n` attached so the
/// reconstructed text is identical. A run like `\n\n` yields two empty-line
/// tokens (blank-line separators).
List<String> _splitParagraphs(String source) {
  if (source.isEmpty) return const [];
  final regex = RegExp(r'[^\n]*\n|[^\n]+');
  return regex.allMatches(source).map((m) => m.group(0)!).toList();
}

bool _isBlankLine(String line) => line.trim().isEmpty;

List<String> _tokenize(String source, DiffMode mode) {
  if (source.isEmpty) return const [];
  if (mode == DiffMode.character) {
    return source.split('');
  }
  // Word mode: split so that whitespace tokens are preserved as separate
  // entries to keep spacing intact after reconstruction.
  final regex = RegExp(r'\s+|\S+');
  return regex.allMatches(source).map((m) => m.group(0)!).toList();
}

List<DiffOp> _lcsDiff(List<String> a, List<String> b) =>
    _coalesce(_lcsDiffRaw(a, b));

/// Token-level LCS diff, one [DiffOp] per token (no coalescing). Callers that
/// need per-token boundaries preserved (e.g. paragraph pairing) use this;
/// [_lcsDiff] wraps it with [_coalesce] for the usual merged output.
List<DiffOp> _lcsDiffRaw(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  if (n == 0 && m == 0) return const [];
  if (n == 0) return [for (final t in b) DiffOp(DiffOpKind.insert, t)];
  if (m == 0) return [for (final t in a) DiffOp(DiffOpKind.delete, t)];

  // Guard: if the LCS table would be huge, fall back to a single delete+insert
  // span. This keeps worst-case memory bounded for large payloads.
  if (n * m > 2_000_000) {
    return [
      DiffOp(DiffOpKind.delete, a.join()),
      DiffOp(DiffOpKind.insert, b.join()),
    ];
  }

  final dp = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (a[i] == b[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  final ops = <DiffOp>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add(DiffOp(DiffOpKind.equal, a[i]));
      i += 1;
      j += 1;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      ops.add(DiffOp(DiffOpKind.delete, a[i]));
      i += 1;
    } else {
      ops.add(DiffOp(DiffOpKind.insert, b[j]));
      j += 1;
    }
  }
  while (i < n) {
    ops.add(DiffOp(DiffOpKind.delete, a[i]));
    i += 1;
  }
  while (j < m) {
    ops.add(DiffOp(DiffOpKind.insert, b[j]));
    j += 1;
  }
  return ops;
}

List<DiffOp> _coalesce(List<DiffOp> input) {
  if (input.isEmpty) return input;
  final merged = <DiffOp>[];
  for (final op in input) {
    if (merged.isNotEmpty && merged.last.kind == op.kind) {
      final prev = merged.removeLast();
      merged.add(DiffOp(prev.kind, prev.text + op.text));
    } else {
      merged.add(op);
    }
  }
  return merged;
}
