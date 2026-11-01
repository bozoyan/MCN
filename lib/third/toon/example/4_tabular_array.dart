import '../lib/toon_format.dart';
import 'json_formatter.dart';

void main() {
  print('=== 4. Tabular Array (Array of Objects) ===\n');

  // Array of objects with uniform structure (best for tabular format)
  final data = {
    'products': [
      {'id': 1, 'name': 'Widget', 'price': 9.99, 'stock': 100},
      {'id': 2, 'name': 'Gadget', 'price': 19.99, 'stock': 50},
      {'id': 3, 'name': 'Thingy', 'price': 29.99, 'stock': 25},
    ],
  };

  final toon = encode(data);
  print('TOON Format (Tabular):');
  print(toon);
  print('');

  // Decode back
  final decoded = decode(toon);
  print('Decoded JSON:');
  printJson(decoded);
}
