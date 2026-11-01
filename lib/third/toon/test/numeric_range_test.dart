import 'package:test/test.dart';

import '../lib/toon_format.dart';

void main() {
  group('Numeric Range and Precision', () {
    test('should encode int64 max limit without decimal points', () {
      // 2^63 - 1
      const double int64Max = 9223372036854775807.0;
      final result = encode(int64Max);

      expect(
        result,
        isNot(contains('.')),
        reason: 'Should be encoded as an integer',
      );
    });

    test('should encode int64 min limit without decimal points', () {
      // -2^63
      const double int64Min = -9223372036854775808.0;
      final result = encode(int64Min);

      expect(
        result,
        isNot(contains('.')),
        reason: 'Should be encoded as an integer',
      );
    });

    test('should prevent clamping on values beyond int64 range (VM fix)', () {
      // This is the critical test for the Dart VM
      const double beyondInt64 = 1e20;
      final result = encode(beyondInt64);

      expect(
        result,
        equals('100000000000000000000'),
        reason: 'Should not clamp to 9223372036854775807',
      );
    });

    test('should maintain precision for MAX_SAFE_INTEGER (Web context)', () {
      // 2^53 - 1
      const double maxSafeInt = 9007199254740991.0;
      final result = encode(maxSafeInt);

      expect(result, equals('9007199254740991'));
    });
  });
}
