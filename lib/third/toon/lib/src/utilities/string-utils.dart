import '../utilities/constants.dart';

/// Escapes special characters in a string for encoding.
///
/// Handles backslashes, quotes, newlines, carriage returns, and tabs.
String escapeString(String value) {
  return value
      .replaceAll(BACKSLASH, '$BACKSLASH$BACKSLASH')
      .replaceAll(DOUBLE_QUOTE, '$BACKSLASH$DOUBLE_QUOTE')
      .replaceAll(NEWLINE, '${BACKSLASH}n')
      .replaceAll(CARRIAGE_RETURN, '${BACKSLASH}r')
      .replaceAll(TAB, '${BACKSLASH}t');
}

/// Unescapes a string by processing escape sequences.
///
/// Handles `\n`, `\t`, `\r`, `\\`, and `\"` escape sequences.
String unescapeString(String value) {
  final result = StringBuffer();
  int i = 0;

  while (i < value.length) {
    if (value[i] == BACKSLASH) {
      if (i + 1 >= value.length) {
        throw FormatException(
          'Invalid escape sequence: backslash at end of string',
        );
      }

      final next = value[i + 1];
      if (next == 'n') {
        result.write(NEWLINE);
        i += 2;
        continue;
      }
      if (next == 't') {
        result.write(TAB);
        i += 2;
        continue;
      }
      if (next == 'r') {
        result.write(CARRIAGE_RETURN);
        i += 2;
        continue;
      }
      if (next == BACKSLASH) {
        result.write(BACKSLASH);
        i += 2;
        continue;
      }
      if (next == DOUBLE_QUOTE) {
        result.write(DOUBLE_QUOTE);
        i += 2;
        continue;
      }

      throw FormatException('Invalid escape sequence: \\$next');
    }

    result.write(value[i]);
    i++;
  }

  return result.toString();
}

/// Finds the index of the closing double quote in a string, accounting for escape sequences.
///
/// [content] The string to search in
/// [start] The index of the opening quote
/// Returns the index of the closing quote, or -1 if not found
int findClosingQuote(String content, int start) {
  int i = start + 1;
  while (i < content.length) {
    if (content[i] == BACKSLASH && i + 1 < content.length) {
      // Skip escaped character
      i += 2;
      continue;
    }
    if (content[i] == DOUBLE_QUOTE) {
      return i;
    }
    i++;
  }
  return -1; // Not found
}

/// Finds the index of a specific character outside of quoted sections.
///
/// [content] The string to search in
/// [char] The character to look for
/// [start] Optional starting index (defaults to 0)
/// Returns the index of the character, or -1 if not found outside quotes
int findUnquotedChar(String content, String char, [int start = 0]) {
  bool inQuotes = false;
  int i = start;

  while (i < content.length) {
    if (content[i] == BACKSLASH && i + 1 < content.length && inQuotes) {
      // Skip escaped character
      i += 2;
      continue;
    }

    if (content[i] == DOUBLE_QUOTE) {
      inQuotes = !inQuotes;
      i++;
      continue;
    }

    if (content[i] == char && !inQuotes) {
      return i;
    }

    i++;
  }

  return -1;
}
