import '../lib/toon_format.dart';

void main() {
  print('=== 8. Edge Cases ===\n');

  // Empty structures
  print('Empty object:');
  print(encode({}));
  print('');

  print('Empty array:');
  print(encode({'items': []}));
  print('');

  // Special string values
  print('Special strings (need quoting):');
  final specialStrings = {
    'values': [
      'hello, world', // contains comma
      'key: value', // contains colon
      'item[1]', // contains brackets
      'item{field}', // contains braces
      '  spaced  ', // leading/trailing spaces
      'true', // looks like boolean
      'null', // looks like null
      '123', // looks like number
    ],
  };
  print(encode(specialStrings));
  print('');

  // Numbers edge cases
  print('Number edge cases:');
  final numbers = {
    'values': [0, -0, 42, -42, 3.14, -3.14, 1e10, -1e10],
  };
  print(encode(numbers));
  print('');

  // Mixed with null and booleans
  print('Null and boolean values:');
  final mixed = {
    'data': [true, false, null, 'string', 42],
  };
  print(encode(mixed));
  print('');

  // Single item arrays
  print('Single item array:');
  print(
    encode({
      'items': ['single'],
    }),
  );
  print('');

  // Very nested structure
  print('Deeply nested:');
  final deep = {
    'level1': {
      'level2': {
        'level3': {
          'level4': {'value': 'deep'},
        },
      },
    },
  };
  print(encode(deep));
}
