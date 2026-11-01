import '../lib/toon_format.dart';
import 'json_formatter.dart';

void main() {
  print('=== 3. Nested JSON with Children ===\n');

  // Nested objects with different data types
  final data = {
    'user': {
      'id': 1,
      'name': 'Alice',
      'active': true,
      'profile': {
        'age': 28,
        'email': 'alice@example.com',
        'preferences': {'theme': 'dark', 'notifications': true, 'score': 95.5},
      },
      'tags': ['developer', 'designer', 'writer'],
    },
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
