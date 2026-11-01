// 职责: 验证 Markdown span 构建的标记显隐、原文无损、标题层级与查找高亮
// 关联文件:
//   lib/shared/widgets/md/markdown_span_builder.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/code-style.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/md/markdown_span_builder.dart';

const String _markdown = '**alpha**\n**beta**\n# gamma';
const TextStyle _baseStyle = TextStyle(fontSize: 14, color: Colors.black);
const Color _syntaxColor = Colors.blueGrey;

void main() {
  test('光标行显示语法标记，其余行隐藏，整体 span 仍等于原文', () {
    final firstLineActive = _build(activeStart: 0, activeEnd: 0);
    var markers = _markerSpans(firstLineActive, '**');
    expect(markers.length, 4);
    expect(_isVisibleMarker(markers[0]), isTrue);
    expect(_isVisibleMarker(markers[1]), isTrue);
    expect(_isVisibleMarker(markers[2]), isFalse);
    expect(_isVisibleMarker(markers[3]), isFalse);
    expect(firstLineActive.toPlainText(), _markdown);

    final secondLineActive = _build(activeStart: 1, activeEnd: 1);
    markers = _markerSpans(secondLineActive, '**');
    expect(_isVisibleMarker(markers[0]), isFalse);
    expect(_isVisibleMarker(markers[1]), isFalse);
    expect(_isVisibleMarker(markers[2]), isTrue);
    expect(_isVisibleMarker(markers[3]), isTrue);
    expect(
      _isVisibleMarker(_markerSpans(secondLineActive, '# ').single),
      isFalse,
    );
  });

  test('编辑一行后仍产出完整原文', () {
    const edited = '**alpha**\n**betaX**\n# gamma';
    final span = RevericMarkdownSpanBuilder.buildWithColors(
      text: edited,
      style: _baseStyle,
      syntaxColor: _syntaxColor,
      activeStart: 1,
      activeEnd: 1,
    );
    expect(span.toPlainText(), edited);
  });

  test('标题行按级别放大内容字号', () {
    final span = RevericMarkdownSpanBuilder.buildWithColors(
      text: '# title\nbody',
      style: _baseStyle,
      syntaxColor: _syntaxColor,
    );
    final title = _spanWithText(span, 'title');
    final body = _spanWithText(span, 'body');
    expect(title.style!.fontSize, greaterThan(body.style!.fontSize!));
    expect(title.style!.fontWeight, FontWeight.w700);
  });

  test('段落后的缩进无序列表始终显示项目符号', () {
    const markdown = '说明\n  - 第一项\n   * 第二项';
    final span = RevericMarkdownSpanBuilder.buildWithColors(
      text: markdown,
      style: _baseStyle,
      syntaxColor: _syntaxColor,
      activeStart: 2,
      activeEnd: 2,
    );

    final bullets = _flatten(
      span,
    ).where((leaf) => leaf.text?.contains('•') ?? false).toList();
    expect(bullets.map((leaf) => leaf.text), <String>['  • ', '   • ']);
    expect(
      bullets.every(
        (leaf) =>
            leaf.style?.color == _baseStyle.color &&
            leaf.style?.fontSize == _baseStyle.fontSize,
      ),
      isTrue,
    );
    final rendered = span.toPlainText(includeSemanticsLabels: false);
    expect(rendered, '说明\n  • 第一项\n   • 第二项');
    expect(rendered.length, markdown.length);
  });

  test('缩进有序列表保留可见编号', () {
    const markdown = '说明\n  1. 第一项\n  2. 第二项';
    final span = RevericMarkdownSpanBuilder.buildWithColors(
      text: markdown,
      style: _baseStyle,
      syntaxColor: _syntaxColor,
      activeStart: 2,
      activeEnd: 2,
    );

    final prefixes = _flatten(
      span,
    ).where((leaf) => leaf.text == '  1. ' || leaf.text == '  2. ').toList();
    expect(prefixes, hasLength(2));
    expect(
      prefixes.every(
        (leaf) =>
            leaf.style?.color == _baseStyle.color &&
            leaf.style?.fontSize == _baseStyle.fontSize,
      ),
      isTrue,
    );
  });

  test('查找高亮只覆盖命中范围且不改变纯文本', () {
    const highlight = Color(0xFF00FF00);
    final span = RevericMarkdownSpanBuilder.buildWithColors(
      text: '**alpha** beta',
      style: _baseStyle,
      syntaxColor: _syntaxColor,
      highlightRanges: const <TextRange>[TextRange(start: 2, end: 7)],
      highlightColor: highlight,
    );
    expect(span.toPlainText(), '**alpha** beta');
    final highlighted = _flatten(
      span,
    ).where((leaf) => leaf.style?.backgroundColor == highlight);
    expect(highlighted.map((leaf) => leaf.text).join(), 'alpha');
  });
}

TextSpan _build({required int activeStart, required int activeEnd}) {
  return RevericMarkdownSpanBuilder.buildWithColors(
    text: _markdown,
    style: _baseStyle,
    syntaxColor: _syntaxColor,
    activeStart: activeStart,
    activeEnd: activeEnd,
  );
}

List<TextSpan> _flatten(TextSpan root) {
  final spans = <TextSpan>[];
  root.visitChildren((span) {
    if (span is TextSpan && span.text != null) {
      spans.add(span);
    }
    return true;
  });
  return spans;
}

List<TextSpan> _markerSpans(TextSpan root, String marker) {
  return _flatten(root).where((span) => span.text == marker).toList();
}

TextSpan _spanWithText(TextSpan root, String text) {
  return _flatten(root).firstWhere((span) => span.text == text);
}

bool _isVisibleMarker(TextSpan span) {
  return span.style?.color == _syntaxColor && span.style?.fontSize != 0;
}
