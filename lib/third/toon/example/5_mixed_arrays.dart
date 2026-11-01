import '../lib/toon_format.dart';
import 'json_formatter.dart';

void main() {
  print('=== 5. Mixed Arrays (Non-uniform) ===\n');

  // Array with mixed types (objects, primitives, arrays)
  final data = {
    'items': [
      'simple string',
      42,
      {'name': 'object item', 'value': 100},
      ['nested', 'array'],
      true,
      {
        'id': 1,
        'data': [1, 2, 3],
      },
    ],
  };

  final toon = encode(data);
  print('TOON Format (List format for mixed arrays):');
  print(toon);
  print('');

  // Decode back
  final decoded = decode(toon);
  print('Decoded JSON:');
  printJson(decoded);
  print('');

  // Array of arrays
  final matrix = {
    'matrix': [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ],
  };

  final toonMatrix = encode(matrix);
  print('Array of Arrays:');
  print(toonMatrix);
}
