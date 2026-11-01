// 职责: 按精准工具名优先、字段加权 BM25 和子串召回排列当前工具目录。
// 关联文件:
//   lib/shared/services/ai/tool_catalog.dart
import 'dart:math' as math;

class ToolSearchDocument {
  const ToolSearchDocument({
    required this.name,
    this.rawName,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String? rawName;
  final String description;
  final Map<String, dynamic> inputSchema;
}

/// 每次使用当前可见目录统计词频，避免停用服务或工具更新后残留旧索引。
List<String> rankToolSearch(String query, List<ToolSearchDocument> documents) {
  final literal = query.trim().toLowerCase();
  if (literal.isEmpty) {
    throw ArgumentError('Search query must not be empty');
  }
  if (documents.isEmpty) {
    return [];
  }
  final terms = _tokenize(query).toSet();
  final fields = documents
      .map(
        (document) => [
          '${document.name} ${document.rawName ?? ''}',
          document.description,
          _schemaText(document.inputSchema).join(' '),
        ],
      )
      .toList();
  final counts = fields
      .map(
        (parts) => parts.map((part) {
          final frequencies = <String, int>{};
          for (final term in _tokenize(part)) {
            frequencies.update(term, (count) => count + 1, ifAbsent: () => 1);
          }
          return frequencies;
        }).toList(),
      )
      .toList();
  final lengths = counts
      .map(
        (parts) => parts
            .map((part) => part.values.fold(0, (sum, count) => sum + count))
            .toList(),
      )
      .toList();
  final averages = List.generate(
    3,
    (field) => math.max(
      1.0,
      lengths.fold(0, (sum, parts) => sum + parts[field]) / documents.length,
    ),
  );
  final idf = <String, double>{};
  for (final term in terms) {
    final frequency = counts
        .where((parts) => parts.any((part) => part.containsKey(term)))
        .length;
    idf[term] = math.log(
      1 + (documents.length - frequency + 0.5) / (frequency + 0.5),
    );
  }
  const weights = [8.0, 4.0, 1.0];
  const k1 = 1.2;
  const b = 0.75;
  final matches = <({String name, int exact, double score, double partial})>[];
  for (var i = 0; i < documents.length; i++) {
    final document = documents[i];
    var score = 0.0;
    var partial = 0.0;
    for (var field = 0; field < weights.length; field++) {
      final norm = k1 * (1 - b + b * lengths[i][field] / averages[field]);
      for (final term in terms) {
        final frequency = counts[i][field][term] ?? 0;
        score +=
            weights[field] *
            idf[term]! *
            frequency *
            (k1 + 1) /
            (frequency + norm);
      }
      // 保留旧搜索的片段召回；只在 BM25 同分时用于排序，不稀释完整词匹配。
      final text = fields[i][field].toLowerCase();
      for (final term in {literal, ...terms}) {
        if (text.contains(term)) {
          partial += weights[field];
        }
      }
    }
    final exact = _namePriority(literal, document);
    if (exact > 0 || score > 0 || partial > 0) {
      matches.add((
        name: document.name,
        exact: exact,
        score: score,
        partial: partial,
      ));
    }
  }
  matches.sort((a, b) {
    var order = b.exact.compareTo(a.exact);
    if (order == 0) {
      order = b.score.compareTo(a.score);
    }
    if (order == 0) {
      order = b.partial.compareTo(a.partial);
    }
    return order != 0 ? order : a.name.compareTo(b.name);
  });
  return matches.map((match) => match.name).toList();
}

int _namePriority(String query, ToolSearchDocument document) {
  if (document.name.toLowerCase() == query) {
    return 3;
  }
  if (document.rawName?.toLowerCase() == query) {
    return 2;
  }
  final normalized = _normalizeName(query);
  final name = _normalizeName(document.name);
  if (normalized.isNotEmpty &&
      (name == normalized ||
          name.endsWith('__$normalized') ||
          (document.rawName != null &&
              _normalizeName(document.rawName!) == normalized))) {
    return 1;
  }
  return 0;
}

String _normalizeName(String value) => value.trim().toLowerCase().replaceAll(
  RegExp(r'[^\p{L}\p{N}_]+', unicode: true),
  '_',
);

final _camelBoundary = RegExp(r'([a-z0-9])([A-Z])');
final _acronymBoundary = RegExp(r'([A-Z]+)([A-Z][a-z])');
final _words = RegExp(r'[\u3400-\u9fff]+|[a-z0-9]+');
final _chinese = RegExp(r'^[\u3400-\u9fff]+$');
const _stopWords = {
  'a',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'by',
  'for',
  'from',
  'in',
  'is',
  'it',
  'of',
  'on',
  'or',
  'that',
  'the',
  'this',
  'to',
  'with',
};

Iterable<String> _tokenize(String text) sync* {
  final split = text
      .replaceAllMapped(_camelBoundary, (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(_acronymBoundary, (m) => '${m[1]} ${m[2]}')
      .toLowerCase();
  for (final match in _words.allMatches(split)) {
    final word = match.group(0)!;
    if (_chinese.hasMatch(word)) {
      if (word.length == 1) {
        yield word;
      } else {
        for (var i = 0; i < word.length - 1; i++) {
          yield word.substring(i, i + 2);
        }
      }
    } else if (!_stopWords.contains(word)) {
      yield _singular(word);
    }
  }
}

String _singular(String word) {
  if (word.length > 4 && word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.length > 4 && RegExp(r'(ches|shes|sses|xes|zes)$').hasMatch(word)) {
    return word.substring(0, word.length - 2);
  }
  if (word.length > 3 &&
      word.endsWith('s') &&
      !word.endsWith('ss') &&
      !word.endsWith('us') &&
      !word.endsWith('is')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

// 只索引参数语义，不把 type、required 等 JSON Schema 结构词当成工具用途。
Iterable<String> _schemaText(Object? schema) sync* {
  if (schema is! Map) {
    return;
  }
  for (final key in ['title', 'description', 'const']) {
    if (schema[key] case final String text) {
      yield text;
    }
  }
  if (schema['enum'] case final List values) {
    yield* values.whereType<String>();
  }
  for (final key in ['properties', r'$defs', 'definitions']) {
    if (schema[key] case final Map properties) {
      for (final entry in properties.entries) {
        yield entry.key.toString();
        yield* _schemaText(entry.value);
      }
    }
  }
  for (final key in ['items', 'additionalProperties']) {
    yield* _schemaText(schema[key]);
  }
  for (final key in ['anyOf', 'oneOf', 'allOf', 'prefixItems']) {
    if (schema[key] case final List variants) {
      for (final variant in variants) {
        yield* _schemaText(variant);
      }
    }
  }
}
