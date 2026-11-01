import 'dart:convert';

import 'package:json_repair_flutter/json_repair_flutter.dart';

/// ---------------------------------------------------------------
/// `decodeWithJSONRepair` vs `tryExtractJson`
///
/// Both strip markdown fences and attempt JSON repair, but differ in
/// candidate strategy and error handling. Choose based on input trust:
///
/// **decodeWithJSONRepair** — use when the text is *expected* to be a
/// single JSON object/array with possible fence wrapping. It extracts
/// the first `{` → last `}` (or first `[` → last `]`) and feeds the
/// result to [repairJson]. On failure it throws, so the caller can
/// retry or escalate. Suitable for structured prompts where the model
/// is told to output JSON only.
///
/// **tryExtractJson** — use when the text is *unpredictable*: the
/// model may include explanatory prose, multiple code blocks, or
/// stray `{`/`}` characters. It tries multiple candidates in order
/// (raw text → fenced blocks → outermost bracket pair) and returns
/// the first that parses, or `null` if none do. Suitable for free-
/// form agent output.
///
/// In short: `decodeWithJSONRepair` is strict and fast (one-shot
/// bracket extraction); `tryExtractJson` is lenient and defensive
/// (multiple candidates, null-safe). Pick the one that matches how
/// tightly you control the prompt.
/// ---------------------------------------------------------------

/// Decodes a JSON string expected to be a single JSON object/array
/// with possible ```json fence wrapping.
///
/// Extracts the outermost `{…}` or `[…]` block and passes through
/// [repairJson] for tolerance against trailing commas, single-quoted
/// keys, unquoted strings, etc.
///
/// Throws on failure — caller should catch and retry if needed.
///
/// @see [tryExtractJson] for a lenient, null-returning alternative.
dynamic decodeWithJSONRepair(String text) {
  final trimmed = text.trim();
  final withoutFence = trimmed
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
  final firstArray = withoutFence.indexOf('[');
  final firstObject = withoutFence.indexOf('{');
  if (firstArray == -1 && firstObject == -1) {
    return repairJson(withoutFence);
  }
  final useArray =
      firstArray != -1 && (firstObject == -1 || firstArray < firstObject);
  final start = useArray ? firstArray : firstObject;
  final end = useArray
      ? withoutFence.lastIndexOf(']')
      : withoutFence.lastIndexOf('}');
  if (end <= start) {
    return repairJson(withoutFence);
  }
  return repairJson(withoutFence.substring(start, end + 1));
}

/// Tries to extract a JSON value from [text] by testing multiple
/// candidate substrings in order of specificity:
///
/// 1. The raw trimmed text as-is.
/// 2. Content inside ```(json) ... ``` fence blocks (all matches).
/// 3. The outermost `{…}` or `[…]` bracket pair via regex.
///
/// The first candidate that [repairJson] can parse is returned.
/// Returns `null` if no candidate parses — the caller decides how
/// to handle absence.
///
/// Use this when the model output is unpredictable (explanatory
/// prose, multiple code blocks, stray brackets). For tightly
/// controlled prompts prefer [decodeWithJSONRepair], which
/// fails loud on malformed output.
Object? tryExtractJson(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  for (final candidate in _jsonCandidates(trimmed)) {
    try {
      return repairJson(candidate);
    } catch (_) {
      try {
        return jsonDecode(candidate);
      } catch (_) {
        // Try the next candidate.
      }
    }
  }
  return null;
}

/// Yields candidate JSON substrings from [text] in priority order:
/// raw text → fenced blocks → outermost bracket pair.
Iterable<String> _jsonCandidates(String text) sync* {
  yield text;
  final fencedJson = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  );
  for (final match in fencedJson.allMatches(text)) {
    final candidate = match.group(1)?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      yield candidate;
    }
  }
  final rawJson = RegExp(r'(\{[\s\S]*\}|\[[\s\S]*\])');
  final rawMatch = rawJson.firstMatch(text);
  final candidate = rawMatch?.group(1)?.trim();
  if (candidate != null && candidate.isNotEmpty) {
    yield candidate;
  }
}

/// Returns [value] coerced to [Map<String, dynamic>], or throws if it cannot
/// be coerced. Useful after [decodeWithJSONRepair] when an object is expected.
Map<String, dynamic> ensureMap(dynamic value, [String label = 'value']) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('$label must be a JSON object');
}

/// Returns [value] coerced to [List], or throws if it cannot be coerced.
List<dynamic> ensureList(dynamic value, [String label = 'value']) {
  if (value is List) return value;
  throw FormatException('$label must be a JSON array');
}

/// Returns the string value at [key] in [map], or throws if missing or not a
/// string.
String requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String) return value.trim();
  throw FormatException('Missing or non-string field: $key');
}
