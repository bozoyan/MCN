// 职责: 章节复制标点替换规则的加载与持久化。
// 关联文件:
//   lib/shared/utils/punctuation_replace.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/database/daos/app_settings_dao.dart
// 遵循的 Rules:
//   .agents/skills/riverpod/SKILL.md
//   .agents/rules/error-handling.md

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger/app_logger.dart';
import '../utils/punctuation_replace.dart';
import 'settings_providers.dart';

const _chapterCopyReplaceRulesKey = 'chapter_copy_replace_rules';

final _log = AppLogger.forModule('ChapterCopyReplaceRules');

class ChapterCopyReplaceRules
    extends AsyncNotifier<List<PunctuationReplaceRule>> {
  @override
  Future<List<PunctuationReplaceRule>> build() async {
    try {
      final database = ref.watch(appSettingsDatabaseProvider);
      final raw = await database.appSettingsDao.get(
        _chapterCopyReplaceRulesKey,
      );
      return _decodeRules(raw);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] Failed to SELECT app_settings key=$_chapterCopyReplaceRulesKey',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> save(List<PunctuationReplaceRule> rules) async {
    final database = ref.read(appSettingsDatabaseProvider);
    final encoded = jsonEncode(rules.map((rule) => rule.toJson()).toList());
    try {
      await database.appSettingsDao.set(
        key: _chapterCopyReplaceRulesKey,
        value: encoded,
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] Failed to UPDATE app_settings key=$_chapterCopyReplaceRulesKey',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (!ref.mounted) {
      return;
    }
    state = AsyncValue.data(List<PunctuationReplaceRule>.from(rules));
  }
}

final chapterCopyReplaceRulesProvider =
    AsyncNotifierProvider<
      ChapterCopyReplaceRules,
      List<PunctuationReplaceRule>
    >(ChapterCopyReplaceRules.new);

List<PunctuationReplaceRule> _decodeRules(String? raw) {
  if (raw == null) {
    return List<PunctuationReplaceRule>.from(defaultPunctuationReplaceRules);
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw const FormatException('Copy replace rules must be a JSON array.');
  }
  final rules = <PunctuationReplaceRule>[];
  for (final item in decoded) {
    if (item is! Map) {
      throw const FormatException('Copy replace rule must be a JSON object.');
    }
    final rule = PunctuationReplaceRule.fromJson(
      Map<String, dynamic>.from(item),
    );
    if (rule.from.isEmpty) {
      throw const FormatException(
        'Copy replace rule source must not be empty.',
      );
    }
    rules.add(rule);
  }
  return rules;
}
