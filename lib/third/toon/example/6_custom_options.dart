import '../lib/toon_format.dart';

void main() {
  print('=== 6. Custom Encoding Options ===\n');

  final data = {
    'items': [
      {'sku': 'A1', 'name': 'Widget', 'qty': 2, 'price': 9.99},
      {'sku': 'B2', 'name': 'Gadget', 'qty': 1, 'price': 14.5},
    ],
  };

  // Default encoding (comma delimiter)
  print('Default (comma delimiter):');
  print(encode(data));
  print('');

  // Tab delimiter
  print('Tab delimiter:');
  print(encode(data, options: EncodeOptions(delimiter: '\t')));
  print('');

  // Pipe delimiter
  print('Pipe delimiter:');
  print(encode(data, options: EncodeOptions(delimiter: '|')));
  print('');

  // With length marker
  print('With length marker (#):');
  print(encode(data, options: EncodeOptions(lengthMarker: '#')));
  print('');

  // Custom indent
  print('Custom indent (4 spaces):');
  print(encode(data, options: EncodeOptions(indent: 4)));
  print('');

  // Combined options
  print('Combined (tab + length marker):');
  print(
    encode(
      data,
      options: EncodeOptions(delimiter: '\t', lengthMarker: '#'),
    ),
  );
}
