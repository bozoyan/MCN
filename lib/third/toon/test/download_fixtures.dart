import 'dart:convert';
import 'dart:io';

/// Downloads test fixtures from the TOON spec repository
Future<void> main() async {
  final baseUrl =
      'https://raw.githubusercontent.com/toon-format/spec/main/tests/fixtures';
  final fixturesDir = Directory('test/fixtures');

  // Create directories
  await fixturesDir.create(recursive: true);
  await Directory('test/fixtures/encode').create(recursive: true);
  await Directory('test/fixtures/decode').create(recursive: true);

  final encodeFiles = [
    'primitives.json',
    'objects.json',
    'arrays-primitive.json',
    'arrays-tabular.json',
    'arrays-nested.json',
    'arrays-objects.json',
    'delimiters.json',
    'whitespace.json',
    'options.json',
  ];

  final decodeFiles = [
    'primitives.json',
    'numbers.json',
    'objects.json',
    'arrays-primitive.json',
    'arrays-tabular.json',
    'arrays-nested.json',
    'delimiters.json',
    'whitespace.json',
    'root-form.json',
    'validation-errors.json',
    'indentation-errors.json',
    'blank-lines.json',
  ];

  final client = HttpClient();

  print('Downloading encode fixtures...');
  for (final file in encodeFiles) {
    try {
      final url = '$baseUrl/encode/$file';
      print('  Downloading $file...');
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final content = await response.transform(utf8.decoder).join();
      await File('test/fixtures/encode/$file').writeAsString(content);
    } catch (e) {
      print('  Error downloading $file: $e');
    }
  }

  print('Downloading decode fixtures...');
  for (final file in decodeFiles) {
    try {
      final url = '$baseUrl/decode/$file';
      print('  Downloading $file...');
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final content = await response.transform(utf8.decoder).join();
      await File('test/fixtures/decode/$file').writeAsString(content);
    } catch (e) {
      print('  Error downloading $file: $e');
    }
  }

  client.close();
  print('Done!');
}
