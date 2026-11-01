# TOON Format Conformance Tests

This directory contains conformance tests that validate the Dart implementation against the [TOON specification test fixtures](https://github.com/toon-format/spec/tree/main/tests).

## Important Note

**⚠️ If new test cases are added to the TOON specification**, you must first update `test/download_fixtures.dart` to include the new fixture file names before running the download script. This ensures all test fixtures are properly downloaded and available for testing.

## Setup

Before running tests, download the test fixtures from the spec repository:

```bash
dart run test/download_fixtures.dart
```

This will download all test fixtures to `test/fixtures/`.

## Running Tests

Run all conformance tests:

```bash
dart test test/conformance_test.dart
```

Or using fvm:

```bash
fvm dart test test/conformance_test.dart
```

## Test Coverage

The conformance tests cover both encoding and decoding of TOON format, ensuring compliance with the specification across various scenarios.
