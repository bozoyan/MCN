import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:test/test.dart';
import '../lib/toon_format.dart';

/// Test fixture structure
class TestFixture {
  final String version;
  final String category;
  final String description;
  final List<TestCase> tests;

  TestFixture({
    required this.version,
    required this.category,
    required this.description,
    required this.tests,
  });

  factory TestFixture.fromJson(Map<String, dynamic> json) {
    return TestFixture(
      version: json['version'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
      tests: (json['tests'] as List)
          .map((t) => TestCase.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TestCase {
  final String name;
  final dynamic input;
  final dynamic expected;
  final Map<String, dynamic>? options;
  final bool shouldError;
  final String? specSection;
  final String? note;
  final String? minSpecVersion;

  TestCase({
    required this.name,
    required this.input,
    required this.expected,
    this.options,
    this.shouldError = false,
    this.specSection,
    this.note,
    this.minSpecVersion,
  });

  factory TestCase.fromJson(Map<String, dynamic> json) {
    return TestCase(
      name: json['name'] as String,
      input: json['input'],
      expected: json['expected'],
      options: json['options'] as Map<String, dynamic>?,
      shouldError: json['shouldError'] as bool? ?? false,
      specSection: json['specSection'] as String?,
      note: json['note'] as String?,
      minSpecVersion: json['minSpecVersion'] as String?,
    );
  }
}

/// Loads a test fixture from local file
Future<TestFixture> loadFixture(String category, String filename) async {
  final file = File('test/fixtures/$category/$filename');
  if (!await file.exists()) {
    throw Exception(
      'Fixture file not found: ${file.path}. Run: dart run test/download_fixtures.dart',
    );
  }
  final content = await file.readAsString();
  final json = jsonDecode(content) as Map<String, dynamic>;
  return TestFixture.fromJson(json);
}

/// Runs a single test case and prints the result
void runTestCase(
  TestCase testCase,
  void Function() testFn, [
  List<String>? results,
]) {
  try {
    testFn();
  } catch (e) {
    print('  FAIL ${testCase.name}: $e');
    rethrow;
  }
}

/// Helper function to run encode tests
Future<void> runEncodeTest(String testName, String filename) async {
  final fixture = await loadFixture('encode', filename);
  print('' * 0);
  final results = <String>[];
  for (final testCase in fixture.tests) {
    runTestCase(testCase, () {
      if (testCase.shouldError) {
        expect(
          () => encode(
            testCase.input,
            options: _parseEncodeOptions(testCase.options),
          ),
          throwsException,
          reason: testCase.name,
        );
      } else {
        final result = encode(
          testCase.input,
          options: _parseEncodeOptions(testCase.options),
        );
        expect(
          result,
          equals(testCase.expected),
          reason:
              '${testCase.name}${testCase.note != null ? " (${testCase.note})" : ""}',
        );
      }
    }, results);
  }
}

/// Helper function to run decode tests
Future<void> runDecodeTest(String testName, String filename) async {
  final fixture = await loadFixture('decode', filename);
  print('' * 0);
  final results = <String>[];
  for (final testCase in fixture.tests) {
    runTestCase(testCase, () {
      if (testCase.shouldError) {
        expect(
          () => decode(
            testCase.input as String,
            options: _parseDecodeOptions(testCase.options),
          ),
          throwsA(anything),
          reason: testCase.name,
        );
      } else {
        final result = decode(
          testCase.input as String,
          options: _parseDecodeOptions(testCase.options),
        );
        expect(
          _normalizeJson(result),
          equals(_normalizeJson(testCase.expected)),
          reason: testCase.name,
        );
      }
    }, results);
  }
}

/// Runs conformance tests from the spec repository
void main() {
  group('TOON Conformance Tests', () {
    // Encode tests
    group('Encode Tests', () {
      test('Primitives', () => runEncodeTest('Primitives', 'primitives.json'));
      test('Objects', () => runEncodeTest('Objects', 'objects.json'));
      test(
        'Arrays - Primitive',
        () => runEncodeTest('Arrays - Primitive', 'arrays-primitive.json'),
      );
      test(
        'Arrays - Tabular',
        () => runEncodeTest('Arrays - Tabular', 'arrays-tabular.json'),
      );
      test(
        'Arrays - Nested',
        () => runEncodeTest('Arrays - Nested', 'arrays-nested.json'),
      );
      test(
        'Arrays - Objects',
        () => runEncodeTest('Arrays - Objects', 'arrays-objects.json'),
      );
      test('Delimiters', () => runEncodeTest('Delimiters', 'delimiters.json'));
      test('Options', () => runEncodeTest('Options', 'options.json'));
      test('Whitespace', () => runEncodeTest('Whitespace', 'whitespace.json'));
    });

    // Decode tests
    group('Decode Tests', () {
      test('Numbers', () => runDecodeTest('Numbers', 'numbers.json'));
      test('Primitives', () => runDecodeTest('Primitives', 'primitives.json'));
      test('Objects', () => runDecodeTest('Objects', 'objects.json'));
      test(
        'Arrays - Primitive',
        () => runDecodeTest('Arrays - Primitive', 'arrays-primitive.json'),
      );
      test(
        'Arrays - Tabular',
        () => runDecodeTest('Arrays - Tabular', 'arrays-tabular.json'),
      );
      test(
        'Arrays - Nested',
        () => runDecodeTest('Arrays - Nested', 'arrays-nested.json'),
      );
      test('Delimiters', () => runDecodeTest('Delimiters', 'delimiters.json'));
      test('Whitespace', () => runDecodeTest('Whitespace', 'whitespace.json'));
      test('Root Form', () => runDecodeTest('Root Form', 'root-form.json'));
      test(
        'Validation Errors',
        () => runDecodeTest('Validation Errors', 'validation-errors.json'),
      );
      test(
        'Indentation Errors',
        () => runDecodeTest('Indentation Errors', 'indentation-errors.json'),
      );
      test(
        'Blank Lines',
        () => runDecodeTest('Blank Lines', 'blank-lines.json'),
      );
    });
  });
}

/// Parses encode options from JSON
EncodeOptions? _parseEncodeOptions(Map<String, dynamic>? options) {
  if (options == null) return null;
  return EncodeOptions(
    indent: options['indent'] as int? ?? 2,
    delimiter: options['delimiter'] as String? ?? ',',
    lengthMarker: options['lengthMarker'] as String?,
  );
}

/// Parses decode options from JSON
DecodeOptions? _parseDecodeOptions(Map<String, dynamic>? options) {
  if (options == null) return null;
  return DecodeOptions(
    indent: options['indent'] as int? ?? 2,
    strict: options['strict'] as bool? ?? true,
  );
}

/// Normalizes JSON values for comparison (handles int/double differences)
dynamic _normalizeJson(dynamic value) {
  if (value is Map) {
    return Map.fromEntries(
      value.entries.map(
        (e) => MapEntry(e.key.toString(), _normalizeJson(e.value)),
      ),
    );
  } else if (value is List) {
    return value.map(_normalizeJson).toList();
  } else if (value is num) {
    // Normalize numbers - convert integers to doubles for comparison
    if (value is int) {
      return value.toDouble();
    }
    return value;
  }
  return value;
}
