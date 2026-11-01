import '../lib/toon_format.dart';
import 'json_formatter.dart';

void main() {
  print('=== 1. Simple JSON Example ===\n');

  // Simple object with primitive values
  final data = {
    'name': 'John Doe',
    'age': 30,
    'active': true,
    'score': 95.5,
    'email': 'john@example.com',
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
