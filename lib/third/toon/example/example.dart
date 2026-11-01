import '../lib/toon_format.dart';
import 'json_formatter.dart';

void main() {
  // Example: Simple JSON with array of objects (tabular format)
  final data = {
    'users': [
      {'id': 1, 'name': 'Alice', 'role': 'admin'},
      {'id': 2, 'name': 'Bob', 'role': 'user'},
    ],
  };

  final toon = encode(data);
  print('=== Simple JSON Example ===');
  print(toon);
  print('');

  // Decode it back
  final decoded = decode(toon);
  print('Decoded JSON:');
  printJson(decoded);
}
