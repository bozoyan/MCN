// 职责: GitHub 风格 diff 视图 — 只读统一视图（行号双列、+/- gutter、字符级高亮、hunk 折叠）与按行审阅（删增混合双栏逐行退回/恢复切换；纯增/纯删单栏只读展示）。
// 关联文件:
//   lib/shared/utils/line_diff.dart
//   lib/shared/utils/line_accept.dart
//   lib/shared/utils/simple_diff.dart
//   lib/desktop/widgets/history/change_history_panel.dart
//   lib/shared/widgets/ai/tool_activity_group.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/diff.json
//   assets/translations/zh-CN/diff.json
import 'package:flutter/material.dart';

import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/utils/line_accept.dart';
import 'package:reveric/shared/utils/line_diff.dart';
import 'package:reveric/shared/utils/simple_diff.dart';

/// 审阅按钮列宽：单个 22px 切换按钮 + 两侧间距。
const double _kReviewButtonWidth = 26;

/// GitHub 风格的 diff 视图。
///
/// 只读模式（默认）：
/// - 统一视图，每行展示 `[old#][new#][sign][content]`，sign 为 `+`/`-`/空格；
/// - 行内对配对的删除/新增行做字符级高亮；
/// - 大段未变更的上下文折叠成 `... N 行未变更` 提示。
///
/// 审阅模式（[reviewMode]）：
/// - 删除+新增混合 → 双栏 side-by-side（左旧右新），每个变更行两栏之间有
///   单个退回/恢复切换按钮；两侧均无可见文本的空行不渲染按钮；
/// - 纯新增 / 纯删除 → 单栏只读展示（左侧细条标识方向），不做按行退回；
/// - 默认全部已接受，被退回的行以预览样式渲染
///   （新增行划线变暗、删除行恢复正常）。
class AiDiffView extends StatelessWidget {
  const AiDiffView({
    super.key,
    this.title,
    required this.oldText,
    required this.newText,
    this.showLabels = true,
    this.contextLines = 3,
    this.collapseThreshold = 8,
    this.reviewMode = false,
    this.rejectedLineKeys = const <String>{},
    this.lockedLineKeys = const <String>{},
    this.onSetLinesRejected,
  });

  /// 顶部文件名 / 路径标题。
  final String? title;
  final String oldText;
  final String newText;

  /// 是否显示 `+/-` 字符列；为 false 时仅靠背景色区分。
  final bool showLabels;

  /// 变更行前后保留的上下文行数。
  final int contextLines;

  /// 连续未变更行达到该阈值才会折叠为 hint。
  final int collapseThreshold;

  /// 按行审阅模式：变更行显示「退回 / 恢复」切换按钮。
  final bool reviewMode;

  /// 已被标记退回的行键集合（待退回 + 已退回的并集），用于预览样式。
  final Set<String> rejectedLineKeys;

  /// 已退回并落库的行键集合（[rejectedLineKeys] 的子集）；这些行锁定，按钮禁用。
  final Set<String> lockedLineKeys;

  /// 设置若干行退回状态的回调；为 null 时箭头禁用。
  final void Function(List<String> lineKeys, bool rejected)? onSetLinesRejected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final entries = computeLineDiff(oldText, newText);
    final hunks = groupHunks(
      entries,
      contextLines: contextLines,
      collapseThreshold: collapseThreshold,
    );
    final pairs = reviewMode ? const <int>[] : pairChangeLines(entries);

    // 行号列宽：基于最大可能行号位数。
    final maxOld = oldText.isEmpty ? 0 : '\n'.allMatches(oldText).length + 1;
    final maxNew = newText.isEmpty ? 0 : '\n'.allMatches(newText).length + 1;
    final maxDigits = _digits(maxOld > maxNew ? maxOld : maxNew);
    final lineNoWidth = (maxDigits * 8.0).clamp(24.0, 64.0);

    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: typo.uiSmall.fontSize,
      height: 1.5,
      color: colors.textPrimary,
    );

    final gutterStyle = monoStyle.copyWith(color: colors.textSubtle);

    final children = <Widget>[];

    if (title != null && title!.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
          child: Row(
            children: [
              RevericIcon(
                RevericIcons.description_outlined,
                size: 13,
                color: colors.textMuted,
              ),
              const SizedBox(width: RevericSpacing.xxs),
              Flexible(
                child: SelectableText(
                  title!,
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (entries.isEmpty) {
      // 两端都为空，给个轻提示。
      children.add(_emptyPlaceholder(context, colors, typo));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    final hasChange = entries.any((e) => e.kind != LineDiffKind.context);
    // 审阅布局：删除+新增混合走双栏 side-by-side；纯新增/纯删除走单栏只读。
    final reviewLayout = reviewMode
        ? lineReviewLayoutOf(entries)
        : LineReviewLayout.none;
    final reviewSideBySide = reviewLayout == LineReviewLayout.mixed;
    final reviewPure =
        reviewLayout == LineReviewLayout.pure_insert ||
        reviewLayout == LineReviewLayout.pure_delete;

    final body = <Widget>[];
    var entryCursor = 0;
    for (var h = 0; h < hunks.length; h++) {
      final hunk = hunks[h];
      if (hunk.isCollapsed) {
        body.add(
          _CollapsedHunkRow(
            label: context.t(
              LocaleKeys.diffUnchangedHidden,
              namedArgs: {'count': '${hunk.collapsedLineCount}'},
            ),
            lineNoWidth: reviewSideBySide ? 0 : lineNoWidth,
            showLabels: !reviewSideBySide && showLabels,
            colors: colors,
            typo: typo,
          ),
        );
        entryCursor += hunk.entries.length;
        continue;
      }
      if (!reviewMode) {
        for (var i = 0; i < hunk.entries.length; i++) {
          final entry = hunk.entries[i];
          final globalIdx = entryCursor + i;
          final pairIdx = pairs[globalIdx];
          final pairEntry = pairIdx >= 0 ? entries[pairIdx] : null;
          body.add(
            _DiffLineRow(
              entry: entry,
              pairText: pairEntry?.text,
              lineNoWidth: lineNoWidth,
              showLabels: showLabels,
              colors: colors,
              monoStyle: monoStyle,
              gutterStyle: gutterStyle,
            ),
          );
        }
      } else if (reviewSideBySide) {
        for (final row in alignLineReviewRows(hunk.entries)) {
          body.add(
            _ReviewSideBySideRow(
              row: row,
              lineNoWidth: lineNoWidth,
              colors: colors,
              monoStyle: monoStyle,
              gutterStyle: gutterStyle,
              reverted: isLineReviewRowReverted(row, rejectedLineKeys),
              locked:
                  row.lineKeys.isNotEmpty &&
                  lockedLineKeys.containsAll(row.lineKeys),
              onSetLinesRejected: onSetLinesRejected,
            ),
          );
        }
      } else if (reviewPure) {
        // 纯新增/纯删除：单栏只读展示，不做按行退回。
        body.add(
          _ReviewPureColumn(
            entries: hunk.entries,
            lineNoWidth: lineNoWidth,
            colors: colors,
            monoStyle: monoStyle,
            gutterStyle: gutterStyle,
          ),
        );
      }
      entryCursor += hunk.entries.length;
    }

    if (!hasChange) {
      // 全是 context（罕见：两端字符串恰好相等但非空）。
      body.add(_emptyPlaceholder(context, colors, typo));
    }

    children.add(
      Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          border: Border.all(color: colors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: body,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _emptyPlaceholder(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.md,
        vertical: RevericSpacing.sm,
      ),
      child: Text('—', style: typo.uiSmall.copyWith(color: colors.textMuted)),
    );
  }

  static int _digits(int n) {
    if (n <= 0) return 1;
    var v = n;
    var d = 0;
    while (v > 0) {
      d++;
      v ~/= 10;
    }
    return d;
  }
}

/// 行内字符级高亮：配对行之间做 character diff，本行方向（删除/新增）的
/// 差异段加深底色，另一侧的 op 忽略。
Widget _charHighlightedLine({
  required String text,
  required String pairText,
  required LineDiffKind kind,
  required TextStyle monoStyle,
  required RevericColors colors,
}) {
  final ops = computeDiff(
    kind == LineDiffKind.delete ? text : pairText,
    kind == LineDiffKind.delete ? pairText : text,
    mode: DiffMode.character,
  );

  final highlightBg = kind == LineDiffKind.delete
      ? colors.deletionBorder.withValues(alpha: 0.28)
      : colors.additionBorder.withValues(alpha: 0.28);

  final spans = <InlineSpan>[];
  for (final op in ops) {
    if (op.kind == DiffOpKind.equal) {
      spans.add(TextSpan(text: op.text, style: monoStyle));
    } else if (kind == LineDiffKind.delete && op.kind == DiffOpKind.delete) {
      spans.add(
        TextSpan(
          text: op.text,
          style: monoStyle.copyWith(backgroundColor: highlightBg),
        ),
      );
    } else if (kind == LineDiffKind.insert && op.kind == DiffOpKind.insert) {
      spans.add(
        TextSpan(
          text: op.text,
          style: monoStyle.copyWith(backgroundColor: highlightBg),
        ),
      );
    }
    // 其它方向的 op 在另一侧的行里展示，本行忽略。
  }

  if (spans.isEmpty) {
    return Text(text.isEmpty ? ' ' : text, style: monoStyle);
  }
  return Text.rich(TextSpan(children: spans));
}

/// 只读统一视图的单行。
class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({
    required this.entry,
    required this.pairText,
    required this.lineNoWidth,
    required this.showLabels,
    required this.colors,
    required this.monoStyle,
    required this.gutterStyle,
  });

  final LineDiffEntry entry;
  final String? pairText;
  final double lineNoWidth;
  final bool showLabels;
  final RevericColors colors;
  final TextStyle monoStyle;
  final TextStyle gutterStyle;

  @override
  Widget build(BuildContext context) {
    final isDelete = entry.kind == LineDiffKind.delete;
    final isInsert = entry.kind == LineDiffKind.insert;
    final isContext = entry.kind == LineDiffKind.context;

    final rowBg = isDelete
        ? colors.deletionBg
        : isInsert
        ? colors.additionBg
        : Colors.transparent;
    final sign = isDelete ? '-' : (isInsert ? '+' : ' ');
    final signColor = isDelete
        ? colors.deletionBorder
        : isInsert
        ? colors.additionBorder
        : colors.textSubtle;

    final Widget content;
    if (isContext || pairText == null) {
      content = Text(entry.text.isEmpty ? ' ' : entry.text, style: monoStyle);
    } else {
      content = _charHighlightedLine(
        text: entry.text,
        pairText: pairText!,
        kind: entry.kind,
        monoStyle: monoStyle,
        colors: colors,
      );
    }

    return Container(
      color: rowBg,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xs,
        vertical: 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: SizedBox(
              width: lineNoWidth,
              child: Text(
                entry.oldLineNumber?.toString() ?? '',
                textAlign: TextAlign.right,
                style: gutterStyle,
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.xs),
          SelectionContainer.disabled(
            child: SizedBox(
              width: lineNoWidth,
              child: Text(
                entry.newLineNumber?.toString() ?? '',
                textAlign: TextAlign.right,
                style: gutterStyle,
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          if (showLabels)
            SelectionContainer.disabled(
              child: SizedBox(
                width: 12,
                child: Text(
                  sign,
                  textAlign: TextAlign.center,
                  style: monoStyle.copyWith(color: signColor),
                ),
              ),
            ),
          const SizedBox(width: RevericSpacing.xs),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// 审阅模式纯新增/纯删除的单栏只读视图：无逐行操作，左侧细条标识变更方向。
class _ReviewPureColumn extends StatelessWidget {
  const _ReviewPureColumn({
    required this.entries,
    required this.lineNoWidth,
    required this.colors,
    required this.monoStyle,
    required this.gutterStyle,
  });

  /// 全部为 insert 或全部为 delete 的行。
  final List<LineDiffEntry> entries;
  final double lineNoWidth;
  final RevericColors colors;
  final TextStyle monoStyle;
  final TextStyle gutterStyle;

  @override
  Widget build(BuildContext context) {
    final isInsert = entries.first.kind == LineDiffKind.insert;
    final barColor = isInsert ? colors.additionBorder : colors.deletionBorder;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: barColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.xs,
                vertical: 1,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectionContainer.disabled(
                    child: SizedBox(
                      width: lineNoWidth,
                      child: Text(
                        (isInsert ? entry.newLineNumber : entry.oldLineNumber)
                                ?.toString() ??
                            '',
                        textAlign: TextAlign.right,
                        style: gutterStyle,
                      ),
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  Expanded(
                    child: Text(
                      entry.text.isEmpty ? ' ' : entry.text,
                      style: monoStyle,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 审阅模式双栏行：左旧右新，中间为退回/恢复切换按钮。
class _ReviewSideBySideRow extends StatelessWidget {
  const _ReviewSideBySideRow({
    required this.row,
    required this.lineNoWidth,
    required this.colors,
    required this.monoStyle,
    required this.gutterStyle,
    required this.reverted,
    required this.locked,
    required this.onSetLinesRejected,
  });

  final LineReviewRow row;
  final double lineNoWidth;
  final RevericColors colors;
  final TextStyle monoStyle;
  final TextStyle gutterStyle;

  /// 该行整体已被标记退回。
  final bool reverted;

  /// 该行退回已落库，本会话内锁定。
  final bool locked;

  final void Function(List<String> lineKeys, bool rejected)? onSetLinesRejected;

  @override
  Widget build(BuildContext context) {
    final left = row.left;
    final right = row.right;
    final isContext = row.isContext;
    // 空行规则：两侧均无可见文本（空行 / 空单元格）时不显示按钮。
    final leftBlank = left == null || left.text.isEmpty;
    final rightBlank = right == null || right.text.isEmpty;
    final showButton = !isContext && !(leftBlank && rightBlank);
    final keyPrefix = row.lineKeys.join('|');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildCell(entry: left, pair: right, isLeft: true),
          ),
          SizedBox(
            width: _kReviewButtonWidth,
            child: showButton
                ? Align(
                    alignment: Alignment.topCenter,
                    child: SelectionContainer.disabled(
                      child: _ReviewToggleButton(
                        keyPrefix: keyPrefix,
                        reverted: reverted,
                        locked: locked,
                        onToggle: onSetLinesRejected == null
                            ? null
                            : () =>
                                  onSetLinesRejected!(row.lineKeys, !reverted),
                        colors: colors,
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: _buildCell(entry: right, pair: left, isLeft: false),
          ),
        ],
      ),
    );
  }

  /// 单侧单元格：行号 + 文本；[entry] 为 null 时是对侧无行的占位格。
  Widget _buildCell({
    required LineDiffEntry? entry,
    required LineDiffEntry? pair,
    required bool isLeft,
  }) {
    const padding = EdgeInsets.symmetric(
      horizontal: RevericSpacing.xs,
      vertical: 1,
    );
    if (entry == null) {
      return Container(color: colors.surfaceDim, padding: padding);
    }

    final isDelete = entry.kind == LineDiffKind.delete;
    final isInsert = entry.kind == LineDiffKind.insert;
    final isChange = isDelete || isInsert;
    final bg = reverted
        ? Colors.transparent
        : isDelete
        ? colors.deletionBg
        : isInsert
        ? colors.additionBg
        : Colors.transparent;

    final Widget content;
    if (reverted && isInsert) {
      // 被退回的新增行：划线 + 变暗，预览「将被丢弃」。
      content = Text(
        entry.text.isEmpty ? ' ' : entry.text,
        style: monoStyle.copyWith(
          color: colors.textMuted,
          decoration: TextDecoration.lineThrough,
          decorationColor: colors.textMuted,
        ),
      );
    } else if (reverted && isDelete) {
      // 被退回的删除行：恢复正常文本，预览「保留在文档中」。
      content = Text(entry.text.isEmpty ? ' ' : entry.text, style: monoStyle);
    } else if (isChange && pair != null && pair.kind != LineDiffKind.context) {
      // 配对的修改行：字符级高亮。
      content = _charHighlightedLine(
        text: entry.text,
        pairText: pair.text,
        kind: entry.kind,
        monoStyle: monoStyle,
        colors: colors,
      );
    } else {
      content = Text(entry.text.isEmpty ? ' ' : entry.text, style: monoStyle);
    }

    final lineNumber = isLeft ? entry.oldLineNumber : entry.newLineNumber;
    return Container(
      color: bg,
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: SizedBox(
              width: lineNoWidth,
              child: Text(
                lineNumber?.toString() ?? '',
                textAlign: TextAlign.right,
                style: gutterStyle,
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.xs),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// 行级「退回 / 恢复」切换按钮：默认态为暗色退回图标，退回态为红色恢复图标；
/// 锁定（退回已落库）或无回调时禁用，禁用态不挂动作 tooltip。
class _ReviewToggleButton extends StatelessWidget {
  const _ReviewToggleButton({
    required this.keyPrefix,
    required this.reverted,
    required this.locked,
    required this.onToggle,
    required this.colors,
  });

  /// 行键拼接，用于测试定位（`diff-review-toggle-<keyPrefix>`）。
  final String keyPrefix;
  final bool reverted;
  final bool locked;
  final VoidCallback? onToggle;
  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    final onTap = locked ? null : onToggle;
    final color = onTap == null
        ? colors.textSubtle.withValues(alpha: 0.45)
        : reverted
        ? colors.deletionBorder
        : colors.textSubtle;
    // 点击盒高与单行行高一致（12px 字号 × 1.5 + 上下各 1px padding = 20px），
    // 避免 IntrinsicHeight 把带按钮的行撑高；Center 让图标按 14px 渲染，
    // 否则 SizedBox 紧约束会把 SVG 拉伸到整个点击盒。
    final button = InkWell(
      key: ValueKey('diff-review-toggle-$keyPrefix'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.small),
      child: SizedBox(
        width: 22,
        height: 20,
        child: Center(
          child: RevericIcon(
            reverted
                ? RevericIcons.arrow_clockwise
                : RevericIcons.arrow_counter_clockwise,
            size: 14,
            color: color,
          ),
        ),
      ),
    );
    if (onTap == null) {
      return button;
    }
    return Tooltip(
      message: context.t(
        reverted
            ? LocaleKeys.diffReviewRestoreLine
            : LocaleKeys.diffReviewRevertLine,
      ),
      child: button,
    );
  }
}

class _CollapsedHunkRow extends StatelessWidget {
  const _CollapsedHunkRow({
    required this.label,
    required this.lineNoWidth,
    required this.showLabels,
    required this.colors,
    required this.typo,
  });

  final String label;
  final double lineNoWidth;
  final bool showLabels;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Container(
        color: colors.surfaceDim,
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.xs,
          vertical: 2,
        ),
        child: Row(
          children: [
            SizedBox(width: lineNoWidth + RevericSpacing.xs + lineNoWidth),
            const SizedBox(width: RevericSpacing.sm),
            if (showLabels) const SizedBox(width: 12 + RevericSpacing.xs),
            RevericIcon(
              RevericIcons.more_horiz_rounded,
              size: 14,
              color: colors.textMuted,
            ),
            const SizedBox(width: RevericSpacing.xs),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
