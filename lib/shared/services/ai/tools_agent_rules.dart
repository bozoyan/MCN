// 职责: Run 工具 agent-rules 子命令 — 用户自定义规则的 list/read/create/update/delete
// 关联文件:
//   lib/shared/services/ai/tools_run.dart
//   lib/shared/services/novel_content.dart
part of 'tools.dart';

mixin _AiToolManagerAgentRulesRunMixin on _AiToolManagerBase {
  Future<Map<String, dynamic>> _runAgentRulesCommand(
    String subcommand,
    Map<String, dynamic> options,
    DateTime startedAt,
  ) async {
    if (subcommand.isEmpty || subcommand == '--help') {
      return _missingBundledSkillSubcommand('agent-rules', startedAt);
    }

    if (!const {
      'list',
      'read',
      'create',
      'update',
      'delete',
    }.contains(subcommand)) {
      throw _RunCommandException(
        _unknownAgentRulesSubcommandText(subcommand),
        exitCode: 127,
      );
    }

    final result = switch (subcommand) {
      'list' => await _handleAgentRulesList(),
      'read' => await _handleAgentRulesRead(
        options,
        usage: _usageForAgentRules(subcommand),
      ),
      'create' => await _handleAgentRulesCreate(
        options,
        usage: _usageForAgentRules(subcommand),
      ),
      'update' => await _handleAgentRulesUpdate(
        options,
        usage: _usageForAgentRules(subcommand),
      ),
      'delete' => await _handleAgentRulesDelete(
        options,
        usage: _usageForAgentRules(subcommand),
      ),
      _ => _unknownAgentRulesSubcommand(subcommand),
    };

    return <String, dynamic>{
      'ok': result['ok'] != false,
      'command': 'agent-rules $subcommand',
      'exit_code': result['ok'] == false ? 1 : 0,
      'duration_ms': DateTime.now().difference(startedAt).inMilliseconds,
      ...result,
    };
  }

  Future<Map<String, dynamic>> _handleAgentRulesList() async {
    final rules = await _contentService.getAgentRules();
    return {
      'ok': true,
      'count': rules.length,
      'rules': rules.sorted
          .map(
            (rule) => {
              'id': rule.id,
              'name': rule.name,
              'enabled': rule.enabled,
              'sort_order': rule.sortOrder,
              'read_command': _agentRuleReadCommand(rule.name),
            },
          )
          .toList(growable: false),
      'hint': _agentRuleRunHint,
    };
  }

  Future<Map<String, dynamic>> _handleAgentRulesRead(
    Map<String, dynamic> options, {
    required String usage,
  }) async {
    final name = _requiredRunOption(options, 'name', usage: usage);
    final rules = await _contentService.getAgentRules();
    final existing = _findAgentRuleByTitle(rules, name);
    if (existing == null) {
      return {
        'ok': false,
        'error': 'Agent rule not found: $name',
        'error_code': ToolErrorCode.not_found.name,
      };
    }

    return {
      'ok': true,
      'id': existing.id,
      'name': existing.name,
      'content': existing.content,
      'enabled': existing.enabled,
      'sort_order': existing.sortOrder,
      'hint': _agentRuleRunHint,
    };
  }

  Future<Map<String, dynamic>> _handleAgentRulesCreate(
    Map<String, dynamic> options, {
    required String usage,
  }) async {
    final name = _requiredRunOption(options, 'name', usage: usage);
    final content = _requiredRunOption(options, 'content', usage: usage);
    if (name.trim().isEmpty) {
      return {
        'ok': false,
        'error': 'Rule name must not be empty.',
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }

    final rules = await _contentService.getAgentRules();
    if (_findAgentRuleByTitle(rules, name) != null) {
      return {
        'ok': false,
        'error': 'Agent rule title already exists: $name',
        'error_code': ToolErrorCode.already_exists.name,
      };
    }

    final enabled = _parseBoolArgument(options['disabled'])
        ? false
        : options.containsKey('enabled')
        ? _parseBoolArgument(options['enabled'])
        : true;
    final sortOrder = _parseIntArgument(options['sort-order']) ?? rules.length;
    final now = DateTime.now();
    final rule = AgentRule(
      id: buildRandomId('agent_rule'),
      name: name,
      content: content,
      enabled: enabled,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
      deletedAt: notDeletedSentinel,
    );

    try {
      await _contentService.upsertAgentRule(rule);
    } catch (error, stackTrace) {
      _log.error(
        'table=agent_rules op=INSERT id=${rule.id} error=$error',
        stackTrace: stackTrace,
      );
      return {
        'ok': false,
        'error': 'Failed to create agent rule.',
        'error_code': ToolErrorCode.internal.name,
      };
    }

    return {
      'ok': true,
      'created': true,
      'id': rule.id,
      'name': rule.name,
      'enabled': rule.enabled,
      'sort_order': rule.sortOrder,
      'read_command': _agentRuleReadCommand(rule.name),
      'hint': _agentRuleRunHint,
    };
  }

  Future<Map<String, dynamic>> _handleAgentRulesUpdate(
    Map<String, dynamic> options, {
    required String usage,
  }) async {
    final name = _requiredRunOption(options, 'name', usage: usage);
    final rules = await _contentService.getAgentRules();
    final existing = _findAgentRuleByTitle(rules, name);
    if (existing == null) {
      return {
        'ok': false,
        'error': 'Agent rule not found: $name',
        'error_code': ToolErrorCode.not_found.name,
      };
    }

    final nextName = _parseOptionalStringArgument(options['new-name']);
    final nextContent = _parseOptionalStringArgument(options['content']);
    final nextEnabled = options.containsKey('enabled')
        ? _parseBoolArgument(options['enabled'])
        : null;
    final nextSortOrder = _parseIntArgument(options['sort-order']);

    if (nextName == null &&
        nextContent == null &&
        nextEnabled == null &&
        nextSortOrder == null) {
      return {
        'ok': false,
        'error':
            'agent-rules update requires at least one of new-name, content, enabled, sort-order',
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }

    final resolvedName = nextName ?? existing.name;
    if (resolvedName.trim().isEmpty) {
      return {
        'ok': false,
        'error': 'Rule name must not be empty.',
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }

    final conflict = _findAgentRuleByTitle(rules, resolvedName);
    if (conflict != null && conflict.id != existing.id) {
      return {
        'ok': false,
        'error': 'Agent rule title already exists: $resolvedName',
        'error_code': ToolErrorCode.already_exists.name,
      };
    }

    final updated = existing.copyWith(
      name: resolvedName,
      content: nextContent ?? existing.content,
      enabled: nextEnabled ?? existing.enabled,
      sortOrder: nextSortOrder ?? existing.sortOrder,
      updatedAt: DateTime.now(),
    );

    try {
      await _contentService.upsertAgentRule(updated);
    } catch (error, stackTrace) {
      _log.error(
        'table=agent_rules op=UPDATE id=${updated.id} error=$error',
        stackTrace: stackTrace,
      );
      return {
        'ok': false,
        'error': 'Failed to update agent rule.',
        'error_code': ToolErrorCode.internal.name,
      };
    }

    return {
      'ok': true,
      'updated': true,
      'id': updated.id,
      'name': updated.name,
      'enabled': updated.enabled,
      'sort_order': updated.sortOrder,
      'read_command': _agentRuleReadCommand(updated.name),
      'hint': _agentRuleRunHint,
    };
  }

  Future<Map<String, dynamic>> _handleAgentRulesDelete(
    Map<String, dynamic> options, {
    required String usage,
  }) async {
    final name = _requiredRunOption(options, 'name', usage: usage);
    final rules = await _contentService.getAgentRules();
    final existing = _findAgentRuleByTitle(rules, name);
    if (existing == null) {
      return {
        'ok': false,
        'error': 'Agent rule not found: $name',
        'error_code': ToolErrorCode.not_found.name,
      };
    }

    try {
      await _contentService.deleteAgentRule(existing.id);
    } catch (error, stackTrace) {
      _log.error(
        'table=agent_rules op=DELETE id=${existing.id} error=$error',
        stackTrace: stackTrace,
      );
      return {
        'ok': false,
        'error': 'Failed to delete agent rule.',
        'error_code': ToolErrorCode.internal.name,
      };
    }

    return {
      'ok': true,
      'deleted': true,
      'id': existing.id,
      'name': existing.name,
      'hint': _agentRuleRunHint,
    };
  }

  Map<String, dynamic> _unknownAgentRulesSubcommand(String subcommand) {
    return {
      'ok': false,
      'output': _unknownAgentRulesSubcommandText(subcommand),
      'error': 'unknown agent-rules command: $subcommand',
      'error_code': ToolErrorCode.invalid_argument.name,
    };
  }
}

const _agentRuleRunHint =
    'Agent rules are managed only through Run command=agent-rules. '
    'Use subcommand=read options={name} to read one rule.';

Map<String, dynamic> _agentRuleReadCommand(String name) {
  return {
    'tool': 'Run',
    'input': {
      'command': 'agent-rules',
      'subcommand': 'read',
      'options': {'name': name},
    },
  };
}

String _usageForAgentRules(String subcommand) {
  return switch (subcommand) {
    'list' => 'Usage: command=agent-rules subcommand=list',
    'read' => 'Usage: command=agent-rules subcommand=read options={name}',
    'create' =>
      'Usage: command=agent-rules subcommand=create options={name, content, enabled?, sort-order?}',
    'update' =>
      'Usage: command=agent-rules subcommand=update options={name, new-name?, content?, enabled?, sort-order?}',
    'delete' => 'Usage: command=agent-rules subcommand=delete options={name}',
    _ => 'Usage: command=agent-rules subcommand=list|read|create|update|delete',
  };
}

String _unknownAgentRulesSubcommandText(String subcommand) {
  return '''[error] unknown agent-rules command: $subcommand
${_bundledSkillCommandGuidance('agent-rules')}''';
}

String _requiredRunOption(
  Map<String, dynamic> options,
  String name, {
  required String usage,
}) {
  final value = _parseStringArgument(options[name]);
  if (value.isEmpty) {
    throw _RunCommandException(
      '[error] agent-rules command requires option "$name"\n$usage',
    );
  }
  return value;
}
