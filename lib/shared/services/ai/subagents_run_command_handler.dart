// 职责: 执行 Run 的 subagents 子命令，管理全局 SubAgent 配置。
// 关联文件:
//   lib/shared/services/ai/tools_run.dart
//   lib/shared/models/subagent.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/services/ai/builtin_agent_tools.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../logger/app_logger.dart';
import '../../models/subagent.dart';
import '../../providers/subagent_providers.dart';
import 'builtin_agent_tools.dart';
import 'tool_error_normalize.dart';

final _log = AppLogger.forModule('SubagentsRunCommandHandler');

class SubagentsRunCommandHandler {
  SubagentsRunCommandHandler({required this.container});

  final ProviderContainer container;

  Future<Map<String, dynamic>> run(Map<String, dynamic> command) async {
    final action = _text(command['action']);
    return switch (action) {
      'list' => _list(),
      'create' => _create(command),
      'update' => _update(command),
      'delete' => _delete(command),
      _ => _failure(
        'unknown subagents action: $action',
        code: ToolErrorCode.invalid_argument,
      ),
    };
  }

  Future<Map<String, dynamic>> _list() async {
    try {
      final agents = await container.read(globalSubAgentsProvider.future);
      final sorted = [...agents]
        ..removeWhere((agent) => _isBuiltin(agent))
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return {
        'ok': true,
        'entries': sorted.map(_agentJson).toList(growable: false),
      };
    } catch (error, stackTrace) {
      _log.error('subagents list failed', error: error, stackTrace: stackTrace);
      return _failure('Failed to load subagents', code: ToolErrorCode.internal);
    }
  }

  Future<Map<String, dynamic>> _create(Map<String, dynamic> command) async {
    final slug = _required(command, 'slug', action: 'create');
    final name = _required(command, 'name', action: 'create');
    final description = _required(command, 'description', action: 'create');
    final prompt = _required(command, 'prompt', action: 'create');
    final mode = command.containsKey('mode') ? _mode(command['mode']) : null;
    if (slug is Map<String, dynamic>) {
      return slug;
    }
    if (name is Map<String, dynamic>) {
      return name;
    }
    if (description is Map<String, dynamic>) {
      return description;
    }
    if (prompt is Map<String, dynamic>) {
      return prompt;
    }
    if (builtinSubAgentSlugs.contains(slug)) {
      return _reservedSlug(slug as String);
    }
    if (command.containsKey('mode') && mode == null) {
      return _failure(
        'Invalid subagent mode. Supported: chat, council.',
        code: ToolErrorCode.invalid_argument,
      );
    }
    final enabled = _bool(command, 'enabled');
    if (enabled == _invalidBool) {
      return _failure(
        'options.enabled must be true or false.',
        code: ToolErrorCode.invalid_argument,
      );
    }

    final draft = SubAgentDraft(
      slug: slug as String,
      name: name as String,
      description: description as String,
      prompt: prompt as String,
      scope: SubAgentScope.global,
      mode: mode ?? SubAgentMode.chat.value,
      enabled: enabled as bool? ?? true,
      useCustomPrompt: true,
    );
    try {
      final agent = await container
          .read(globalSubAgentsProvider.notifier)
          .createSubAgent(draft);
      return {'ok': true, 'subagent': _agentJson(agent)};
    } on SubAgentNameConflictException catch (error) {
      return _duplicateSlug(error.name);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=agents op=INSERT slug=${draft.slug}',
        error: error,
        stackTrace: stackTrace,
      );
      return _failure(
        'Failed to create subagent',
        code: ToolErrorCode.internal,
      );
    }
  }

  Future<Map<String, dynamic>> _update(Map<String, dynamic> command) async {
    final idResult = _required(command, 'id', action: 'update');
    if (idResult is Map<String, dynamic>) {
      return idResult;
    }
    final id = idResult as String;
    final existing = await _find(id);
    if (existing == null) {
      return _failure('subagent not found: $id', code: ToolErrorCode.not_found);
    }
    if (_isBuiltin(existing)) {
      return _builtinSubagentReadonly(existing);
    }

    final nextSlug = _nonEmptyOption(command, 'slug');
    final nextName = _nonEmptyOption(command, 'name');
    final nextDescription = _nonEmptyOption(command, 'description');
    final nextPrompt = _nonEmptyOption(command, 'prompt');
    final mode = command.containsKey('mode') ? _mode(command['mode']) : null;
    final enabled = _bool(command, 'enabled');
    if (nextSlug is Map<String, dynamic>) {
      return nextSlug;
    }
    if (nextName is Map<String, dynamic>) {
      return nextName;
    }
    if (nextDescription is Map<String, dynamic>) {
      return nextDescription;
    }
    if (nextPrompt is Map<String, dynamic>) {
      return nextPrompt;
    }
    if (nextSlug is String && builtinSubAgentSlugs.contains(nextSlug)) {
      return _reservedSlug(nextSlug);
    }
    if (command.containsKey('mode') && mode == null) {
      return _failure(
        'Invalid subagent mode. Supported: chat, council.',
        code: ToolErrorCode.invalid_argument,
      );
    }
    if (enabled == _invalidBool) {
      return _failure(
        'options.enabled must be true or false.',
        code: ToolErrorCode.invalid_argument,
      );
    }
    if (nextSlug == null &&
        nextName == null &&
        nextDescription == null &&
        nextPrompt == null &&
        mode == null &&
        enabled == null) {
      return _failure(
        'subagents update requires at least one mutable option.',
        code: ToolErrorCode.invalid_argument,
      );
    }

    final updated = existing.copyWith(
      slug: nextSlug as String? ?? existing.slug,
      name: nextName as String? ?? existing.name,
      description: nextDescription as String? ?? existing.description,
      prompt: nextPrompt as String? ?? existing.prompt,
      mode: mode ?? existing.mode,
      enabled: enabled as bool? ?? existing.enabled,
      useCustomPrompt: nextPrompt == null ? existing.useCustomPrompt : true,
      updatedAt: DateTime.now(),
    );
    try {
      await container
          .read(globalSubAgentsProvider.notifier)
          .updateSubAgent(updated);
      return {'ok': true, 'subagent': _agentJson(updated)};
    } on SubAgentNameConflictException catch (error) {
      return _duplicateSlug(error.name);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=agents op=UPDATE id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      return _failure(
        'Failed to update subagent',
        code: ToolErrorCode.internal,
      );
    }
  }

  Future<Map<String, dynamic>> _delete(Map<String, dynamic> command) async {
    final idResult = _required(command, 'id', action: 'delete');
    if (idResult is Map<String, dynamic>) {
      return idResult;
    }
    final id = idResult as String;
    final existing = await _find(id);
    if (existing == null) {
      return _failure('subagent not found: $id', code: ToolErrorCode.not_found);
    }
    if (_isBuiltin(existing)) {
      return _builtinSubagentReadonly(existing);
    }
    final confirmed = _bool(command, 'confirm');
    if (confirmed != true) {
      return _failure(
        'subagents delete requires options.confirm=true.',
        code: ToolErrorCode.failed_precondition,
      );
    }

    try {
      await container.read(globalSubAgentsProvider.notifier).deleteSubAgent(id);
      return {'ok': true, 'deleted_id': id};
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=agents op=SOFT_DELETE id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      return _failure(
        'Failed to delete subagent',
        code: ToolErrorCode.internal,
      );
    }
  }

  Future<SubAgent?> _find(String id) async {
    final agents = await container.read(globalSubAgentsProvider.future);
    for (final agent in agents) {
      if (agent.id == id) {
        return agent;
      }
    }
    return null;
  }

  bool _isBuiltin(SubAgent agent) => builtinSubAgentSlugs.contains(agent.slug);

  Object _required(
    Map<String, dynamic> command,
    String field, {
    required String action,
  }) {
    final value = _text(command[field]);
    if (value.isNotEmpty) {
      return value;
    }
    return _failure(
      'subagents $action requires options.$field',
      code: ToolErrorCode.invalid_argument,
    );
  }

  Object? _nonEmptyOption(Map<String, dynamic> command, String field) {
    if (!command.containsKey(field)) {
      return null;
    }
    final value = _text(command[field]);
    if (value.isNotEmpty) {
      return value;
    }
    return _failure(
      'options.$field must not be empty.',
      code: ToolErrorCode.invalid_argument,
    );
  }

  String? _mode(Object? raw) {
    final value = _text(raw);
    if (value.isEmpty) {
      return null;
    }
    return switch (value) {
      'chat' || 'council' => value,
      _ => null,
    };
  }

  Object? _bool(Map<String, dynamic> command, String field) {
    if (!command.containsKey(field)) {
      return null;
    }
    final value = command[field];
    if (value is bool) {
      return value;
    }
    final text = _text(value).toLowerCase();
    return switch (text) {
      'true' || 'yes' || '1' => true,
      'false' || 'no' || '0' => false,
      _ => _invalidBool,
    };
  }

  Map<String, dynamic> _agentJson(SubAgent agent) {
    return {
      'id': agent.id,
      'slug': agent.slug,
      'name': agent.name,
      'description': agent.description,
      'prompt': agent.prompt,
      'mode': agent.mode,
      'enabled': agent.enabled,
      'use_custom_prompt': agent.useCustomPrompt,
      'provider_id': agent.providerId,
      'model': agent.model,
      'reasoning_effort': agent.reasoningEffort,
    };
  }

  Map<String, dynamic> _duplicateSlug(String slug) {
    return _failure(
      'subagent slug already exists: $slug',
      code: ToolErrorCode.already_exists,
      extra: {'slug': slug},
    );
  }

  Map<String, dynamic> _reservedSlug(String slug) {
    return _failure(
      'subagent slug is reserved for a built-in subagent: $slug',
      code: ToolErrorCode.invalid_argument,
      extra: {'slug': slug},
    );
  }

  Map<String, dynamic> _builtinSubagentReadonly(SubAgent agent) {
    return _failure(
      'built-in subagent cannot be changed or deleted: ${agent.name}',
      code: ToolErrorCode.permission_denied,
      extra: {'id': agent.id, 'slug': agent.slug},
    );
  }

  Map<String, dynamic> _failure(
    String error, {
    required ToolErrorCode code,
    Map<String, dynamic> extra = const {},
  }) {
    return {'ok': false, 'error': error, 'error_code': code.name, ...extra};
  }
}

String _text(Object? value) => value?.toString().trim() ?? '';

const _invalidBool = Object();
