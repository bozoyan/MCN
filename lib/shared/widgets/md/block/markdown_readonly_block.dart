// 职责: Markdown 可见块渲染 — 用同一 RenderParagraph 绘制富文本、全文选区、IME 草稿与光标并提供几何命中
// 关联文件:
//   lib/shared/widgets/md/markdown_span_builder.dart
//   lib/shared/widgets/md/block/markdown_block_controller.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
//   lib/shared/widgets/md/block/markdown_block_style.dart
//   lib/shared/widgets/text_find_replace_scope.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../text_find_replace_scope.dart';
import '../markdown_span_builder.dart';
import 'markdown_block_controller.dart';
import 'markdown_block_document.dart';
import 'markdown_block_style.dart';

class MarkdownReadonlyBlock extends StatefulWidget {
  const MarkdownReadonlyBlock({
    super.key,
    required this.controller,
    required this.block,
    required this.style,
    required this.enabled,
    required this.hintText,
  });

  final MarkdownBlockController controller;
  final MarkdownBlock block;
  final MarkdownBlockStyle style;
  final bool enabled;
  final String hintText;

  @override
  State<MarkdownReadonlyBlock> createState() => MarkdownReadonlyBlockState();
}

/// 暴露当前挂载块的命中和光标几何，供列表级选择状态机复用。
class MarkdownReadonlyBlockState extends State<MarkdownReadonlyBlock> {
  static final RegExp _spaceOrPunctuation = RegExp(
    r'[\p{Space_Separator}\p{Punctuation}]',
    unicode: true,
  );

  final GlobalKey _paragraphKey = GlobalKey();

  RenderParagraph? get _paragraph {
    final renderObject = _paragraphKey.currentContext?.findRenderObject();
    return renderObject is RenderParagraph ? renderObject : null;
  }

  // 全局坐标换算会调用祖先的 applyPaintTransform；Transform/FittedBox
  // 即使子段落已 layout，也可能尚未有自己的 size。
  bool _hasGlobalLayout(RenderParagraph paragraph) {
    RenderObject? current = paragraph;
    while (current != null) {
      if (!current.attached || (current is RenderBox && !current.hasSize)) {
        return false;
      }
      current = current.parent;
    }
    return true;
  }

  int get visualEnd {
    final block = widget.block;
    return block.separatorEnd > block.end
        ? block.separatorEnd - 1
        : block.separatorEnd;
  }

  Rect? get paragraphGlobalRect {
    final paragraph = _paragraph;
    if (paragraph == null || !_hasGlobalLayout(paragraph)) {
      return null;
    }
    return paragraph.localToGlobal(Offset.zero) & paragraph.size;
  }

  /// 全局指针坐标映射到唯一全文位置；越过块边缘时夹到该块可视范围。
  TextPosition globalTextPositionForPosition(Offset globalPosition) {
    final paragraph = _paragraph;
    if (paragraph == null || !_hasGlobalLayout(paragraph)) {
      return TextPosition(offset: widget.block.start);
    }
    final local = paragraph.globalToLocal(globalPosition);
    final position = paragraph.getPositionForOffset(
      Offset(
        local.dx.clamp(0, paragraph.size.width),
        local.dy.clamp(0, paragraph.size.height),
      ),
    );
    return TextPosition(
      offset: (widget.block.start + position.offset).clamp(
        widget.block.start,
        visualEnd,
      ),
      affinity: position.affinity,
    );
  }

  /// 返回命中位置对应的 Unicode 单词范围。
  TextRange? globalWordRangeAt(TextPosition globalPosition) {
    final paragraph = _paragraph;
    if (paragraph == null || !paragraph.attached || !paragraph.hasSize) {
      return null;
    }
    final localLength = visualEnd - widget.block.start;
    final localOffset = (globalPosition.offset - widget.block.start).clamp(
      0,
      localLength,
    );
    if (localOffset >= localLength) {
      return TextRange.collapsed(widget.block.start + localOffset);
    }
    final range = paragraph.getWordBoundary(
      TextPosition(offset: localOffset, affinity: globalPosition.affinity),
    );
    return TextRange(
      start: widget.block.start + range.start.clamp(0, localLength),
      end: widget.block.start + range.end.clamp(0, localLength),
    );
  }

  /// 返回光标在段落本地坐标中的矩形。
  Rect? localCaretRect(int globalOffset, {TextAffinity? affinity}) {
    final paragraph = _paragraph;
    // 同 paragraphGlobalRect：getOffsetForCaret 也要求 TextPainter 已 layout。
    if (paragraph == null || !paragraph.attached || !paragraph.hasSize) {
      return null;
    }
    final localOffset = (globalOffset - widget.block.start).clamp(
      0,
      visualEnd - widget.block.start,
    );
    final selection = widget.controller.selection;
    final effectiveAffinity =
        affinity ??
        (selection.extentOffset == globalOffset
            ? selection.affinity
            : TextAffinity.downstream);
    final position = TextPosition(
      offset: localOffset,
      affinity: effectiveAffinity,
    );
    final prototype = Rect.fromLTWH(
      0,
      0,
      MarkdownBlockStyle.cursorWidth,
      widget.style.preferredLineHeight(context),
    );
    final caretOffset = paragraph.getOffsetForCaret(position, prototype);
    final caretHeight = paragraph.getFullHeightForCaret(position);
    return Rect.fromLTWH(
      caretOffset.dx,
      caretOffset.dy,
      MarkdownBlockStyle.cursorWidth,
      caretHeight,
    );
  }

  Rect? globalCaretRect(int globalOffset, {TextAffinity? affinity}) {
    final paragraph = _paragraph;
    if (paragraph == null || !_hasGlobalLayout(paragraph)) {
      return null;
    }
    final localRect = localCaretRect(globalOffset, affinity: affinity);
    if (localRect == null) {
      return null;
    }
    return localRect.shift(paragraph.localToGlobal(Offset.zero));
  }

  /// 用段落本地 x/y 计算全文位置，供上下方向键保持视觉 x 与软换行 affinity。
  TextPosition globalTextPositionForLocalPosition(Offset localPosition) {
    final paragraph = _paragraph;
    if (paragraph == null || !paragraph.attached || !paragraph.hasSize) {
      return TextPosition(offset: widget.block.start);
    }
    final position = paragraph.getPositionForOffset(
      Offset(
        localPosition.dx.clamp(0, paragraph.size.width),
        localPosition.dy.clamp(0, paragraph.size.height),
      ),
    );
    return TextPosition(
      offset: (widget.block.start + position.offset).clamp(
        widget.block.start,
        visualEnd,
      ),
      affinity: position.affinity,
    );
  }

  /// 返回与当前 RenderParagraph 完全一致的视觉行边界。
  TextRange? globalLineBoundary(TextPosition globalPosition) {
    final paragraph = _paragraph;
    if (paragraph == null || !paragraph.attached || !paragraph.hasSize) {
      return null;
    }
    final caret = localCaretRect(
      globalPosition.offset,
      affinity: globalPosition.affinity,
    );
    if (caret == null) {
      return null;
    }
    final lineY = caret.center.dy;
    final start = paragraph.getPositionForOffset(Offset(0, lineY)).offset;
    final end = paragraph
        .getPositionForOffset(Offset(paragraph.size.width, lineY))
        .offset;
    return TextRange(
      start: widget.block.start + start,
      end: widget.block.start + end,
    );
  }

  /// 使用当前 RenderParagraph 的 Unicode 词边界寻找下一个编辑器词边界。
  ///
  /// [searchOffset] 向后移动时应传入光标前一个 code unit；标点和空格的
  /// 跳过规则与 Flutter [TextPainter.wordBoundaries] 的编辑快捷键语义一致。
  int? globalWordBoundaryAt(int searchOffset, {required bool forward}) {
    final paragraph = _paragraph;
    if (paragraph == null || !paragraph.attached || !paragraph.hasSize) {
      return null;
    }
    final text = widget.controller.document.source.substring(
      widget.block.start,
      visualEnd,
    );
    var search = searchOffset - widget.block.start;
    if (search < 0 || search >= text.length) {
      return null;
    }
    while (search >= 0 && search < text.length) {
      final range = paragraph.getWordBoundary(TextPosition(offset: search));
      final boundary = forward ? range.end : range.start;
      if (_keepsWordBoundary(text, boundary, forward: forward)) {
        return widget.block.start + boundary;
      }
      final nextSearch = forward ? boundary : boundary - 1;
      if (nextSearch == search) {
        return null;
      }
      search = nextSearch;
    }
    return null;
  }

  bool _keepsWordBoundary(String text, int offset, {required bool forward}) {
    final inner = _codePointAt(text, forward ? offset - 1 : offset);
    final outerIndex = forward ? offset : offset - 1;
    final outer = outerIndex >= 0 && outerIndex < text.length
        ? text.codeUnitAt(outerIndex)
        : null;
    if (inner == null ||
        outer == null ||
        _isNewline(inner) ||
        _isNewline(outer)) {
      return true;
    }
    return !_spaceOrPunctuation.hasMatch(String.fromCharCode(inner));
  }

  int? _codePointAt(String text, int index) {
    if (index < 0 || index >= text.length) {
      return null;
    }
    final current = text.codeUnitAt(index);
    if ((current & 0xFC00) == 0xD800 && index + 1 < text.length) {
      final low = text.codeUnitAt(index + 1);
      return (current << 10) + low + (0x010000 - (0xD800 << 10) - 0xDC00);
    }
    if ((current & 0xFC00) == 0xDC00 && index > 0) {
      final high = text.codeUnitAt(index - 1);
      return (high << 10) + current + (0x010000 - (0xD800 << 10) - 0xDC00);
    }
    return current;
  }

  bool _isNewline(int codePoint) {
    return codePoint == 0x000A ||
        codePoint == 0x0085 ||
        codePoint == 0x000B ||
        codePoint == 0x000C ||
        codePoint == 0x2028 ||
        codePoint == 0x2029;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final block = widget.block;
    final source = controller.document.source;
    final text = source.substring(block.start, visualEnd);
    final selection = controller.selection;
    final activeMatch = TextFindReplaceScope.activeMatchOf(context);
    final highlightRanges = <TextRange>[
      ..._localHighlightRanges(activeMatch, text.length),
      ..._localSelectionRanges(selection, text.length),
      ..._localComposingRanges(controller.value.composing, text.length),
    ];
    final localActiveSelection = _localActiveSelection(selection, text.length);
    final (activeStart, activeEnd) = localActiveSelection == null
        ? (0, -1)
        : RevericMarkdownSpanBuilder.activeLineRange(
            text,
            localActiveSelection,
          );
    final span = RevericMarkdownSpanBuilder.build(
      context: context,
      text: text,
      style: widget.style.textStyle,
      activeStart: activeStart,
      activeEnd: activeEnd,
      highlightRanges: highlightRanges,
    );
    final showCaret =
        widget.enabled &&
        controller.focusNode.hasFocus &&
        selection.isCollapsed &&
        controller.activeBlockId == block.id;
    final cursorColor =
        Theme.of(context).textSelectionTheme.cursorColor ??
        widget.style.textStyle.color!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = text.isEmpty && widget.hintText.isNotEmpty
            ? Text(
                widget.hintText,
                key: _paragraphKey,
                style: widget.style.hintStyle,
                strutStyle: widget.style.strutStyle,
                textHeightBehavior: widget.style.textHeightBehavior,
              )
            : Text.rich(
                span,
                key: _paragraphKey,
                strutStyle: widget.style.strutStyle,
                textHeightBehavior: widget.style.textHeightBehavior,
              );
        final caretLocalOffset = (selection.extentOffset - block.start).clamp(
          0,
          text.length,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: widget.style.preferredLineHeight(context),
          ),
          child: Padding(
            padding: const EdgeInsets.only(
              right: MarkdownBlockStyle.textEndInset,
            ),
            child: CustomPaint(
              foregroundPainter: showCaret
                  ? _MarkdownCaretPainter(
                      span: span,
                      position: TextPosition(
                        offset: caretLocalOffset,
                        affinity: selection.affinity,
                      ),
                      color: cursorColor,
                      style: widget.style,
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )
                  : null,
              child: content,
            ),
          ),
        );
      },
    );
  }

  TextSelection? _localActiveSelection(
    TextSelection selection,
    int textLength,
  ) {
    if (!widget.controller.focusNode.hasFocus ||
        selection.end < widget.block.start ||
        selection.start > visualEnd) {
      return null;
    }
    return TextSelection(
      baseOffset: (selection.baseOffset - widget.block.start).clamp(
        0,
        textLength,
      ),
      extentOffset: (selection.extentOffset - widget.block.start).clamp(
        0,
        textLength,
      ),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  List<TextRange> _localSelectionRanges(
    TextSelection selection,
    int textLength,
  ) {
    if (selection.isCollapsed ||
        selection.start >= visualEnd ||
        selection.end <= widget.block.start) {
      return const <TextRange>[];
    }
    return <TextRange>[
      TextRange(
        start: (selection.start - widget.block.start).clamp(0, textLength),
        end: (selection.end - widget.block.start).clamp(0, textLength),
      ),
    ];
  }

  List<TextRange> _localHighlightRanges(TextRange? range, int textLength) {
    if (range == null ||
        !range.isValid ||
        range.isCollapsed ||
        range.start >= visualEnd ||
        range.end <= widget.block.start) {
      return const <TextRange>[];
    }
    return <TextRange>[
      TextRange(
        start: (range.start - widget.block.start).clamp(0, textLength),
        end: (range.end - widget.block.start).clamp(0, textLength),
      ),
    ];
  }

  List<TextRange> _localComposingRanges(TextRange range, int textLength) {
    if (!range.isValid ||
        range.isCollapsed ||
        range.start >= visualEnd ||
        range.end <= widget.block.start) {
      return const <TextRange>[];
    }
    return <TextRange>[
      TextRange(
        start: (range.start - widget.block.start).clamp(0, textLength),
        end: (range.end - widget.block.start).clamp(0, textLength),
      ),
    ];
  }
}

class _MarkdownCaretPainter extends CustomPainter {
  _MarkdownCaretPainter({
    required this.span,
    required this.position,
    required this.color,
    required this.style,
    required this.textDirection,
    required this.textScaler,
  });

  final TextSpan span;
  final TextPosition position;
  final Color color;
  final MarkdownBlockStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: span,
      textDirection: textDirection,
      textScaler: textScaler,
      strutStyle: style.strutStyle,
      textHeightBehavior: style.textHeightBehavior,
    )..layout(maxWidth: size.width);
    final prototype = Rect.fromLTWH(
      0,
      0,
      MarkdownBlockStyle.cursorWidth,
      painter.preferredLineHeight,
    );
    final offset = painter.getOffsetForCaret(position, prototype);
    final height = painter.getFullHeightForCaret(position, prototype);
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy,
        MarkdownBlockStyle.cursorWidth,
        height,
      ),
      Paint()..color = color,
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _MarkdownCaretPainter oldDelegate) {
    return span != oldDelegate.span ||
        position != oldDelegate.position ||
        color != oldDelegate.color ||
        style != oldDelegate.style ||
        textDirection != oldDelegate.textDirection ||
        textScaler != oldDelegate.textScaler;
  }
}
