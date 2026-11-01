import '../lib/toon_format.dart';
import 'json_formatter.dart';

void main() {
  print('=== 7. Decoding Examples ===\n');

  // Decode a simple TOON string
  final toonString = '''
name: John Doe
age: 30
active: true
''';

  print('TOON Input:');
  print(toonString);
  print('');

  final decoded = decode(toonString);
  print('Decoded JSON:');
  printJson(decoded);
  print('');

  // Decode tabular array
  final tabularToon = '''
products[3]{id,name,price}:
  1,Widget,9.99
  2,Gadget,19.99
  3,Thingy,29.99
''';

  print('Tabular TOON Input:');
  print(tabularToon);
  print('');

  final decodedTabular = decode(tabularToon);
  print('Decoded JSON:');
  printJson(decodedTabular);
  print('');

  // Decode with inline array
  final inlineArrayToon = '''
tags[3]: reading,gaming,coding
''';

  print('Inline Array TOON Input:');
  print(inlineArrayToon);
  print('');

  final decodedInline = decode(inlineArrayToon);
  print('Decoded JSON:');
  printJson(decodedInline);
  print('');

  // Decode nested structure
  final nestedToon = '''
user:
  id: 1
  name: Alice
  profile:
    age: 28
    email: alice@example.com
''';

  print('Nested TOON Input:');
  print(nestedToon);
  print('');

  final decodedNested = decode(nestedToon);
  print('Decoded JSON:');
  printJson(decodedNested);
}
