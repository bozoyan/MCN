// 职责: Markdown 文本样式构建 — 将源码解析为可供预览、只读块与编辑块复用的 TextSpan
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/widgets/md/block/markdown_readonly_block.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// 构建 Reveric 编辑器支持的 Markdown 样式。
class RevericMarkdownSpanBuilder {
  RevericMarkdownSpanBuilder._();

  static final _headingRe = RegExp(r'^(#{1,6})\s');
  static final _blockquoteRe = RegExp(r'^>\s');
  static final _ulRe = RegExp(r'^( {0,3})([-*])([ \t]+)');
  static final _olRe = RegExp(r'^( {0,3})(\d+\.)([ \t]+)');
  static final _inlineRe = RegExp(
    r'\*\*\*(.+?)\*\*\*'
    r'|\*\*(.+?)\*\*'
    r'|\*(.+?)\*'
    r'|~~(.+?)~~',
  );

  static final _PreviewSpanCache _previewCache = _PreviewSpanCache();

  /// 使用当前 Reveric theme 构建 span。
  static TextSpan build({
    required BuildContext context,
    required String text,
    TextStyle? style,
    int activeStart = 0,
    int activeEnd = -1,
    List<TextRange> highlightRanges = const <TextRange>[],
  }) {
    final colors = RevericTheme.colorsOf(context);
    return buildWithColors(
      text: text,
      style: style ?? const TextStyle(),
      syntaxColor: colors.textSubtle,
      activeStart: activeStart,
      activeEnd: activeEnd,
      highlightRanges: highlightRanges,
      highlightColor: colors.accent.withValues(alpha: 0.38),
    );
  }

  /// 不依赖 inherited theme 的构建入口，供控制器与纯解析测试复用。
  static TextSpan buildWithColors({
    required String text,
    required TextStyle style,
    required Color syntaxColor,
    int activeStart = 0,
    int activeEnd = -1,
    List<TextRange> highlightRanges = const <TextRange>[],
    Color? highlightColor,
  }) {
    final canUsePreviewCache =
        activeEnd < activeStart && highlightRanges.isEmpty;
    final span = canUsePreviewCache
        ? _previewCache.resolve(
            _PreviewSpanKey(text, style, syntaxColor),
            () => _buildMarkdownTextSpan(
              text: text,
              styles: _MarkdownStyleSet(style, syntaxColor),
            ),
          )
        : _buildMarkdownTextSpan(
            text: text,
            styles: _MarkdownStyleSet(style, syntaxColor),
            activeStart: activeStart,
            activeEnd: activeEnd,
          );
    if (highlightRanges.isEmpty || highlightColor == null) {
      return span;
    }
    return _applyHighlights(span, highlightRanges, highlightColor);
  }

  /// 光标 / 选区覆盖的行区间（闭区间）。
  static (int, int) activeLineRange(String text, TextSelection selection) {
    if (!selection.isValid) {
      return (0, -1);
    }
    final selectionStart = selection.start.clamp(0, text.length);
    final selectionEnd = selection.end.clamp(0, text.length);
    var line = 0;
    var index = 0;
    for (; index < selectionStart; index++) {
      if (text.codeUnitAt(index) == 0x0A) {
        line++;
      }
    }
    final startLine = line;
    for (; index < selectionEnd; index++) {
      if (text.codeUnitAt(index) == 0x0A) {
        line++;
      }
    }
    return (startLine, line);
  }

  static bool _mightContainMarkdown(String text) {
    for (var i = 0; i < text.length; i++) {
      switch (text.codeUnitAt(i)) {
        case 0x23:
        case 0x2A:
        case 0x7E:
        case 0x3E:
        case 0x2D:
          return true;
        case 0x2E:
          if (i > 0) {
            final previous = text.codeUnitAt(i - 1);
            if (previous >= 0x30 && previous <= 0x39) {
              return true;
            }
          }
      }
    }
    return false;
  }

  static bool _lineMayHaveInlineMarkup(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x2A || unit == 0x7E) {
        return true;
      }
    }
    return false;
  }

  static TextSpan _parseLine(
    String line,
    _MarkdownStyleSet styles,
    bool isActive,
  ) {
    if (line.isEmpty) {
      return styles.base.emptySpan;
    }

    var lineStyles = styles.base;
    TextStyle? prefixStyle;
    var sourcePrefix = '';
    var renderedPrefix = '';
    var content = line;

    final listPrefix = _parseListPrefix(line);
    if (listPrefix != null) {
      sourcePrefix = listPrefix.source;
      renderedPrefix = listPrefix.rendered;
      content = line.substring(sourcePrefix.length);
      prefixStyle = lineStyles.content;
    } else {
      switch (line.codeUnitAt(0)) {
        case 0x23:
          final headingMatch = _headingRe.firstMatch(line);
          if (headingMatch != null) {
            sourcePrefix = headingMatch[0]!;
            renderedPrefix = sourcePrefix;
            content = line.substring(sourcePrefix.length);
            lineStyles = styles.heading(headingMatch[1]!.length);
            prefixStyle = isActive
                ? lineStyles.syntaxVisible
                : lineStyles.syntaxHidden;
          }
        case 0x3E:
          if (_blockquoteRe.hasMatch(line)) {
            sourcePrefix = '> ';
            renderedPrefix = sourcePrefix;
            content = line.substring(2);
            lineStyles = styles.blockquote;
          }
      }
    }

    prefixStyle ??= isActive
        ? styles.base.syntaxVisible
        : styles.base.syntaxHidden;

    if (!_lineMayHaveInlineMarkup(content)) {
      final contentSpan = TextSpan(text: content, style: lineStyles.content);
      if (sourcePrefix.isEmpty) {
        return contentSpan;
      }
      return TextSpan(
        children: <InlineSpan>[
          TextSpan(text: renderedPrefix, style: prefixStyle),
          contentSpan,
        ],
      );
    }

    final spans = <InlineSpan>[];
    if (sourcePrefix.isNotEmpty) {
      spans.add(TextSpan(text: renderedPrefix, style: prefixStyle));
    }
    _appendInlineSpans(spans, content, lineStyles, isActive);
    return TextSpan(children: spans);
  }

  static ({String source, String rendered})? _parseListPrefix(String line) {
    final unordered = _ulRe.firstMatch(line);
    if (unordered != null) {
      final source = unordered[0]!;
      final rendered = '${unordered[1]}\u2022${unordered[3]}';
      assert(source.length == rendered.length);
      return (source: source, rendered: rendered);
    }

    final ordered = _olRe.firstMatch(line);
    if (ordered == null) {
      return null;
    }
    final source = ordered[0]!;
    return (source: source, rendered: source);
  }

  static void _appendInlineSpans(
    List<InlineSpan> spans,
    String text,
    _LineStyles styles,
    bool isActive,
  ) {
    final markerStyle = isActive ? styles.syntaxVisible : styles.syntaxHidden;
    var lastEnd = 0;

    for (final match in _inlineRe.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: styles.content,
          ),
        );
      }

      if (match[1] != null) {
        spans
          ..add(TextSpan(text: '***', style: markerStyle))
          ..add(TextSpan(text: match[1], style: styles.boldItalic))
          ..add(TextSpan(text: '***', style: markerStyle));
      } else if (match[2] != null) {
        spans
          ..add(TextSpan(text: '**', style: markerStyle))
          ..add(TextSpan(text: match[2], style: styles.bold))
          ..add(TextSpan(text: '**', style: markerStyle));
      } else if (match[3] != null) {
        spans
          ..add(TextSpan(text: '*', style: markerStyle))
          ..add(TextSpan(text: match[3], style: styles.italic))
          ..add(TextSpan(text: '*', style: markerStyle));
      } else if (match[4] != null) {
        spans
          ..add(TextSpan(text: '~~', style: markerStyle))
          ..add(TextSpan(text: match[4], style: styles.strikethrough))
          ..add(TextSpan(text: '~~', style: markerStyle));
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: styles.content));
    }
  }
}

TextSpan _buildMarkdownTextSpan({
  required String text,
  required _MarkdownStyleSet styles,
  int activeStart = 0,
  int activeEnd = -1,
}) {
  if (text.isEmpty) {
    return TextSpan(style: styles.baseStyle);
  }
  if (!RevericMarkdownSpanBuilder._mightContainMarkdown(text)) {
    return TextSpan(text: text, style: styles.baseStyle);
  }

  final lines = text.split('\n');
  final children = <InlineSpan>[];
  for (var index = 0; index < lines.length; index++) {
    if (index > 0) {
      children.add(styles.newline);
    }
    final line = lines[index];
    final isActive = index >= activeStart && index <= activeEnd;
    children.add(
      RevericMarkdownSpanBuilder._parseLine(line, styles, isActive),
    );
  }
  return TextSpan(children: children);
}

TextSpan _applyHighlights(
  TextSpan source,
  List<TextRange> ranges,
  Color highlightColor,
) {
  final validRanges =
      ranges
          .where((range) => range.isValid && !range.isCollapsed)
          .toList(growable: false)
        ..sort((left, right) => left.start.compareTo(right.start));
  if (validRanges.isEmpty) {
    return source;
  }
  return _highlightSpan(source, 0, validRanges, highlightColor).span;
}

({TextSpan span, int end}) _highlightSpan(
  TextSpan source,
  int start,
  List<TextRange> ranges,
  Color highlightColor,
) {
  var offset = start;
  final sourceText = source.text;
  TextSpan? textSpan;
  if (sourceText != null) {
    textSpan = _highlightLeaf(
      sourceText,
      source.style,
      offset,
      ranges,
      highlightColor,
    );
    offset += sourceText.length;
  }

  final children = <InlineSpan>[];
  if (textSpan != null) {
    children.add(textSpan);
  }
  for (final child in source.children ?? const <InlineSpan>[]) {
    if (child is! TextSpan) {
      children.add(child);
      continue;
    }
    final highlighted = _highlightSpan(child, offset, ranges, highlightColor);
    children.add(highlighted.span);
    offset = highlighted.end;
  }

  if (sourceText != null &&
      (source.children == null || source.children!.isEmpty)) {
    return (span: textSpan!, end: offset);
  }
  return (span: TextSpan(style: source.style, children: children), end: offset);
}

TextSpan _highlightLeaf(
  String text,
  TextStyle? style,
  int globalStart,
  List<TextRange> ranges,
  Color highlightColor,
) {
  final globalEnd = globalStart + text.length;
  final overlaps = ranges
      .where((range) => range.start < globalEnd && range.end > globalStart)
      .toList(growable: false);
  if (overlaps.isEmpty) {
    return TextSpan(text: text, style: style);
  }

  final children = <InlineSpan>[];
  var cursor = 0;
  for (final range in overlaps) {
    final localStart = (range.start - globalStart).clamp(0, text.length);
    final localEnd = (range.end - globalStart).clamp(localStart, text.length);
    if (localStart > cursor) {
      children.add(
        TextSpan(text: text.substring(cursor, localStart), style: style),
      );
    }
    if (localEnd > localStart) {
      children.add(
        TextSpan(
          text: text.substring(localStart, localEnd),
          style: (style ?? const TextStyle()).copyWith(
            backgroundColor: highlightColor,
          ),
        ),
      );
    }
    cursor = localEnd;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor), style: style));
  }
  return TextSpan(children: children);
}

class _MarkdownStyleSet {
  _MarkdownStyleSet(this.baseStyle, this.syntaxColor);

  final TextStyle baseStyle;
  final Color syntaxColor;

  late final _LineStyles base = _LineStyles(baseStyle, syntaxColor);
  late final TextSpan newline = TextSpan(text: '\n', style: baseStyle);
  late final _LineStyles blockquote = _LineStyles(
    baseStyle.copyWith(fontStyle: FontStyle.italic),
    syntaxColor,
  );
  final List<_LineStyles?> _headings = List<_LineStyles?>.filled(6, null);

  _LineStyles heading(int level) {
    final index = (level - 1).clamp(0, 5);
    return _headings[index] ??= _LineStyles(
      baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 16) * _headingScale(level),
        fontWeight: FontWeight.w700,
      ),
      syntaxColor,
    );
  }

  static double _headingScale(int level) {
    return switch (level) {
      1 => 1.5,
      2 => 1.3,
      3 => 1.15,
      4 => 1.075,
      5 => 1.0375,
      _ => 1.0,
    };
  }
}

class _LineStyles {
  _LineStyles(this.content, this.syntaxColor);

  final TextStyle content;
  final Color syntaxColor;

  late final TextStyle syntaxVisible = content.copyWith(color: syntaxColor);
  late final TextStyle syntaxHidden = content.copyWith(
    fontSize: 0,
    color: syntaxColor.withValues(alpha: 0),
  );
  late final TextStyle bold = content.copyWith(fontWeight: FontWeight.w700);
  late final TextStyle italic = content.copyWith(fontStyle: FontStyle.italic);
  late final TextStyle boldItalic = content.copyWith(
    fontWeight: FontWeight.w700,
    fontStyle: FontStyle.italic,
  );
  late final TextStyle strikethrough = content.copyWith(
    decoration: TextDecoration.lineThrough,
    decorationColor: content.color,
  );
  late final TextSpan emptySpan = TextSpan(text: '', style: content);
}

class _PreviewSpanCache {
  static const int _maxEntries = 64;
  static const int _maxCachedTextLength = 8000;

  final Map<_PreviewSpanKey, TextSpan> _entries = <_PreviewSpanKey, TextSpan>{};

  TextSpan resolve(_PreviewSpanKey key, TextSpan Function() build) {
    if (key.text.length > _maxCachedTextLength) {
      return build();
    }
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final span = build();
    _entries[key] = span;
    if (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return span;
  }
}

class _PreviewSpanKey {
  const _PreviewSpanKey(this.text, this.style, this.syntaxColor);

  final String text;
  final TextStyle style;
  final Color syntaxColor;

  @override
  bool operator ==(Object other) {
    return other is _PreviewSpanKey &&
        other.text == text &&
        other.style == style &&
        other.syntaxColor == syntaxColor;
  }

  @override
  int get hashCode => Object.hash(text, style, syntaxColor);
}
