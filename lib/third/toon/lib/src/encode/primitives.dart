import '../types.dart';
import '../utilities/constants.dart';
import '../utilities/string-utils.dart';
import '../utilities/validation.dart';
import '../utilities/int64_bounds_import.dart';

// #region Primitive encoding

/// Encodes a primitive value to a string.
String encodePrimitive(JsonPrimitive value, [String? delimiter]) {
  if (value == null) {
    return NULL_LITERAL;
  }

  if (value is bool) {
    return value.toString();
  }

  if (value is num) {
    // Format integers without decimal point, even if stored as double
    if (value is int) {
      return value.toString();
    } else if (value is double) {
      // Check if it's actually an integer value
      if (value == value.truncateToDouble() && value.isFinite) {
        // It's a whole number
        // Check if it fits in int range
        if (isInInt64Range(value)) {
          // Safe to convert to int
          return value.toInt().toString();
        } else {
          // Too large for int, but it's a whole number
          // Format without decimal point (e.g., 1e20 becomes "100000000000000000000")
          // Use toString() which will format large numbers in scientific notation,
          // then convert to fixed notation if it's a whole number
          final str = value.toStringAsFixed(0);
          return str;
        }
      }
      // It's a real decimal, format normally
      return value.toString();
    }
    return value.toString();
  }

  return encodeStringLiteral(value as String, delimiter ?? COMMA);
}

/// Encodes a string literal, adding quotes if necessary.
String encodeStringLiteral(String value, [String delimiter = COMMA]) {
  if (isSafeUnquoted(value, delimiter)) {
    return value;
  }

  return '$DOUBLE_QUOTE${escapeString(value)}$DOUBLE_QUOTE';
}

// #endregion

// #region Key encoding

/// Encodes a key, adding quotes if necessary.
String encodeKey(String key) {
  if (isValidUnquotedKey(key)) {
    return key;
  }

  return '$DOUBLE_QUOTE${escapeString(key)}$DOUBLE_QUOTE';
}

// #endregion

// #region Value joining

/// Encodes and joins primitive values with a delimiter.
String encodeAndJoinPrimitives(
  List<JsonPrimitive> values, [
  String delimiter = COMMA,
]) {
  return values.map((v) => encodePrimitive(v, delimiter)).join(delimiter);
}

// #endregion

// #region Header formatters

/// Formats an array header.
String formatHeader(
  int length, {
  String? key,
  List<String>? fields,
  String? delimiter,
  String? lengthMarker,
}) {
  final delimiterValue = delimiter ?? COMMA;
  final lengthMarkerValue = lengthMarker ?? '';

  String header = '';

  if (key != null) {
    header += encodeKey(key);
  }

  // Only include delimiter if it's not the default (comma)
  final delimiterSuffix = delimiterValue != DEFAULT_DELIMITER
      ? delimiterValue
      : '';
  header += '[$lengthMarkerValue$length$delimiterSuffix]';

  if (fields != null) {
    final quotedFields = fields.map((f) => encodeKey(f)).toList();
    final joinedFields = quotedFields.join(delimiterValue);
    header += '{$joinedFields}';
  }

  header += ':';

  return header;
}

// #endregion
