import 'dart:convert';

/// Formats a Dart object as pretty-printed JSON.
String formatJson(Object? value, {int indent = 2}) {
  final indentString = ' ' * indent;
  final encoder = JsonEncoder.withIndent(indentString);
  return encoder.convert(value);
}

/// Prints a Dart object as formatted JSON.
void printJson(Object? value, {int indent = 2}) {
  print(formatJson(value, indent: indent));
}
