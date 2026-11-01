// 职责: 验证 Codemode 源码解包 — 兼容 Markdown 围栏与 JSON 包装，合法 JS 原样保留。
// 关联文件:
//   lib/shared/services/ai/codemode/tool.dart
//   lib/shared/services/ai/codemode/orchestrator.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/codemode/tool.dart';

void main() {
  const js = "const r = await tools.Read({path: '/'});\nreturn r;";

  test('strips markdown fences with or without language tag', () {
    expect(normalizeCodemodeSource('```js\n$js\n```'), js);
    expect(normalizeCodemodeSource('```\n$js```'), js);
    expect(normalizeCodemodeSource('  ```javascript\r\n$js\r\n```\n'), js);
  });

  test('unwraps JSON string and {"code": ...} object', () {
    expect(normalizeCodemodeSource(jsonEncode(js)), js);
    expect(normalizeCodemodeSource(jsonEncode({'code': js})), js);
  });

  test('unwraps nested fence and JSON layers', () {
    final fencedJson =
        '```json\n${jsonEncode({'code': '```js\n$js\n```'})}\n```';
    expect(normalizeCodemodeSource(fencedJson), js);
  });

  test('keeps valid JavaScript untouched', () {
    expect(normalizeCodemodeSource(js), js);
    const block = "{ const a = 1; return a; }";
    expect(normalizeCodemodeSource(block), block);
    const objectLike = '{"code": 1}';
    expect(normalizeCodemodeSource(objectLike), objectLike);
    const inner = "text('```js\\nx\\n```');";
    expect(normalizeCodemodeSource(inner), inner);
  });
}
