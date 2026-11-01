import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/type_converters.dart';

void main() {
  const converter = JsonMapConverter();

  test('malformed stored JSON does not prevent reading its database row', () {
    for (final raw in ['', '  ', '{', '{"key":', '{"key":1,}', 'not json']) {
      expect(converter.fromSql(raw), isEmpty, reason: 'Invalid JSON: $raw');
    }
  });

  test('valid non-object JSON keeps the existing empty-map behavior', () {
    for (final raw in ['null', '[]', '42', 'true', '"text"']) {
      expect(converter.fromSql(raw), isEmpty);
    }
  });

  test('valid objects retain nested values through a storage round trip', () {
    final value = <String, dynamic>{
      'name': '历史地图',
      'recognition': {
        'matches': [
          {'name': '城', 'x': 0.25, 'y': 0.75},
        ],
        'unresolved': <String>[],
      },
      'optional': null,
    };
    expect(converter.fromSql(converter.toSql(value)), value);
    expect(converter.fromSql('{}'), isEmpty);
  });
}
