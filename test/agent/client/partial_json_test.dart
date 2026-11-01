// 职责: parseStreamingJson 单元测试
// 关联文件:
//   lib/shared/agent/client/_partial_json.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/shared/agent/client/_partial_json.dart';

void main() {
  group('parseStreamingJson', () {
    test('returns empty map for empty string', () {
      expect(parseStreamingJson(''), <String, dynamic>{});
    });

    test('parses fully closed JSON object', () {
      expect(parseStreamingJson('{"a":1,"b":"x"}'), {'a': 1, 'b': 'x'});
    });

    test('parses nested objects/arrays', () {
      expect(parseStreamingJson('{"a":{"b":[1,2,3]}}'), {
        'a': {
          'b': [1, 2, 3],
        },
      });
    });

    test('repairs partial unclosed object', () {
      final out = parseStreamingJson('{"name":"foo","value":42');
      expect(out['name'], 'foo');
      expect(out['value'], 42);
    });

    test('repairs partial unclosed string', () {
      final out = parseStreamingJson('{"name":"fo');
      expect(out.containsKey('name'), isTrue);
    });

    test('drops dangling key without value', () {
      final out = parseStreamingJson('{"a":1,"b"');
      expect(out['a'], 1);
      expect(out.containsKey('b'), isFalse);
    });

    test('repairs unclosed array', () {
      final out = parseStreamingJson('{"items":[1,2,3');
      expect(out['items'], [1, 2, 3]);
    });

    test('returns empty for irrecoverable garbage', () {
      expect(parseStreamingJson('@@@@'), <String, dynamic>{});
    });

    test('handles escape sequences inside strings', () {
      final out = parseStreamingJson(r'{"path":"a\\b\"c"}');
      expect(out['path'], r'a\b"c');
    });

    test('top-level non-object yields empty map', () {
      expect(parseStreamingJson('[1,2,3]'), <String, dynamic>{});
    });
  });
}
