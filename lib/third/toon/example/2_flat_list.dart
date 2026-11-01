import '../lib/toon_format.dart';
import 'json_formatter.dart';

void main() {
  print('=== 2. Flat List with Different Data Types ===\n');

  // Array with different primitive types
  final data = {
    'items': ['apple', 42, 3.14, true, false, null, 'cherry'],
  };

  final toon = encode(data);
  print('TOON Format:');
  print(toon);
  print('');

  // Decode back
  final decoded = decode(toon);
  print('Decoded JSON:');
  printJson(decoded);
}
