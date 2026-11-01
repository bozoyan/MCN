// 职责: 测试桌面端编辑器参考划线层的排版 Y 坐标计算与空正文不绘制。
// 关联文件:
//   lib/desktop/widgets/workspace/editor_focus_lines_layer.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/editor_focus_lines_layer.dart';

void main() {
  test('computeEditorLineYs returns empty list for empty text', () {
    expect(
      computeEditorLineYs(
        span: const TextSpan(text: ''),
        maxWidth: 320,
        textDirection: TextDirection.ltr,
        strutStyle: const StrutStyle(fontSize: 16, height: 1.8),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: true,
          applyHeightToLastDescent: true,
        ),
        fontSize: 16,
      ),
      isEmpty,
    );
  });

  test('computeEditorLineYs returns line positions for wrapped text', () {
    final ys = computeEditorLineYs(
      span: const TextSpan(
        text: '第一行\n第二行',
        style: TextStyle(fontSize: 16, height: 1.8),
      ),
      maxWidth: 320,
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontSize: 16,
        height: 1.8,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      ),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
      fontSize: 16,
    );

    expect(ys, hasLength(2));
    expect(ys.first, lessThan(ys.last));
  });

  // 参考线必须落在文字下方、且仍在本行行框内：高于行框底（不挤下一行）、
  // 低于本行基线（不穿过字形中部）。锚在 baseline 而非「(i+1)*行高」是修复
  // 划线穿字的关键——后者按行高累加忽略首行 leading 偏移，会整体上移穿过字形。
  test('computeEditorLineYs places line below baseline within the row', () {
    const fontSize = 16.0;
    const lineHeight = 1.8;
    final rowHeight = fontSize * lineHeight;
    final ys = computeEditorLineYs(
      span: const TextSpan(
        text: '第一行',
        style: TextStyle(fontSize: fontSize, height: lineHeight),
      ),
      maxWidth: 320,
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontSize: fontSize,
        height: lineHeight,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      ),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
      fontSize: fontSize,
    );

    expect(ys, hasLength(1));
    // 低于行框竖直中点（即在文字下半区），且不越过行框底边进入下一行。
    expect(ys.first, greaterThan(rowHeight * 0.5));
    expect(ys.first, lessThanOrEqualTo(rowHeight));
  });

  test('computeEditorLineYs respects textScaler on mobile-like scaling', () {
    const fontSize = 16.0;
    const lineHeight = 1.8;
    const scale = 1.3;
    final unscaled = computeEditorLineYs(
      span: const TextSpan(
        text: '第一行',
        style: TextStyle(fontSize: fontSize, height: lineHeight),
      ),
      maxWidth: 320,
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontSize: fontSize,
        height: lineHeight,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      ),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
      fontSize: fontSize,
    );
    final scaled = computeEditorLineYs(
      span: const TextSpan(
        text: '第一行',
        style: TextStyle(fontSize: fontSize, height: lineHeight),
      ),
      maxWidth: 320,
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontSize: fontSize,
        height: lineHeight,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      ),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
      fontSize: fontSize,
      textScaler: const TextScaler.linear(scale),
    );

    expect(scaled.first, greaterThan(unscaled.first * 1.1));
  });
}
