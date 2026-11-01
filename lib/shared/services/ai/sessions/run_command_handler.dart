// 职责: 校验 sessions 命令并按作品边界分页读取已保存会话。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/sessions/transcript.dart
//   lib/shared/database/daos/ai_chat_session_dao.dart
//   lib/shared/database/novel_content_daos/ai_chat_message_dao.dart
import '../tool_error_normalize.dart';
import 'dart:convert';

import '../../../database/app_database.dart';
import '../../../database/novel_content_database.dart';
import '../../../logger/app_logger.dart';
import '../tools.dart' show CrossWorkAccess, CrossWorkAccessException;
import 'transcript.dart';

class _SessionsError implements Exception {
  const _SessionsError(this.code, this.message);
  final ToolErrorCode code;
  final String message;
}

class SessionsRunCommandHandler {
  const SessionsRunCommandHandler({
    required this.database,
    required this.access,
    this.workId,
  });
  final AppDatabase database;
  final CrossWorkAccess access;
  final String? workId;

  Future<Map<String, dynamic>> run(
    String action,
    Map<String, dynamic> options, {
    String? currentSessionId,
    String? sourceSessionId,
  }) async {
    try {
      return await _run(action, options, currentSessionId, sourceSessionId);
    } on _SessionsError catch (e) {
      return {'ok': false, 'error_code': e.code.name, 'error': e.message};
    } on CrossWorkAccessException catch (e) {
      return {
        'ok': false,
        'error_code': switch (e.errorCode) {
          'work_not_found' => ToolErrorCode.not_found,
          'unsupported_content_kind' => ToolErrorCode.unsupported,
          _ => ToolErrorCode.unavailable,
        }.name,
        'error': e.message,
      };
    } catch (error, stackTrace) {
      AppLogger.forModule('Sessions').error(
        'Saved session read failed',
        error: error,
        stackTrace: stackTrace,
      );
      return {
        'ok': false,
        'error_code': ToolErrorCode.unavailable.name,
        'error': 'Saved conversations are unavailable.',
      };
    }
  }

  Future<Map<String, dynamic>> _run(
    String action,
    Map<String, dynamic> o,
    String? current,
    String? source,
  ) async {
    if (!{'list', 'read', 'search', 'get'}.contains(action)) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Expected list, read, search, or get.',
      );
    }
    final allowed = <String>{
      'work_id',
      'cursor',
      if (action == 'list') ...{
        'query',
        'mode',
        'parent_id',
        'limit',
      } else ...{
        'session_id',
        'scope',
        'kinds',
        'tool_name',
        'tool_status',
        'max_chars',
        if (action == 'get') ...{'id', 'block_id'} else ...{'limit', 'order'},
        if (action == 'search') 'query',
      },
    };
    for (final key in o.keys) {
      if (!allowed.contains(key)) {
        throw _SessionsError(
          ToolErrorCode.invalid_argument,
          'Unknown option: $key.',
        );
      }
    }
    final work = _string(o, 'work_id') ?? workId;
    if (work == null || work.isEmpty) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Specify work_id.',
      );
    }
    final limit = _integer(o, 'limit', 20, 1, 100);
    final maxChars = _integer(o, 'max_chars', 12000, 1000, 20000);
    final scope = _string(o, 'scope') ?? 'source';
    if (!{
      'source',
      'current',
      if (action == 'search') 'work',
    }.contains(scope)) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Invalid scope. Use source/current, or work for search.',
      );
    }
    final explicitSession = _string(o, 'session_id');
    if (scope == 'work' && explicitSession != null) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'scope=work cannot include session_id.',
      );
    }
    final sessionId = action == 'list' || scope == 'work'
        ? null
        : explicitSession ?? (scope == 'current' ? current : source ?? current);
    if (action != 'list' && scope != 'work' && sessionId == null) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Specify session_id or provide an active session.',
      );
    }
    final order = _string(o, 'order') ?? (action == 'search' ? 'desc' : 'asc');
    if (!{'asc', 'desc'}.contains(order)) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Invalid order.',
      );
    }
    final query = _string(o, 'query');
    if (action == 'search' && query == null) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'query is required.',
      );
    }
    final mode = _string(o, 'mode');
    if (mode != null &&
        !{
          'chat',
          'council',
          'monologue',
          'theater',
          'roleplay',
        }.contains(mode)) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Invalid mode.',
      );
    }
    final toolName = _string(o, 'tool_name');
    final status = _string(o, 'tool_status');
    if (status != null &&
        !{
          'pending',
          'rejected',
          'cancelled',
          'running',
          'success',
          'error',
        }.contains(status)) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Invalid tool_status.',
      );
    }
    final rawKinds =
        o['kinds'] ??
        (toolName != null || status != null ? ['tool'] : ['user', 'assistant']);
    if (rawKinds is! List ||
        rawKinds.isEmpty ||
        rawKinds.any(
          (k) =>
              !{'user', 'assistant', 'tool', 'summary', 'system'}.contains(k),
        )) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'kinds must be a nonempty array of known kinds.',
      );
    }
    final kinds = rawKinds.cast<String>().toSet();
    if ((toolName != null || status != null) && !kinds.contains('tool')) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'Tool filters require the tool kind.',
      );
    }
    final id = _string(o, 'id');
    final blockId = _string(o, 'block_id');
    if (action == 'get' && id == null) {
      throw const _SessionsError(
        ToolErrorCode.invalid_argument,
        'id is required.',
      );
    }
    final fingerprint = jsonEncode({
      'action': action,
      'work': work,
      'session': sessionId,
      'scope': scope,
      'query': query,
      'mode': mode,
      'parent': _string(o, 'parent_id'),
      'order': order,
      'kinds': kinds.toList()..sort(),
      'tool': toolName,
      'status': status,
      'id': id,
      'block': blockId,
    });
    final cursor = _decodeCursor(_string(o, 'cursor'), fingerprint);
    if (cursor != null) {
      if (action == 'list') {
        if (cursor['updated'] is! String) {
          _invalidCursor();
        }
      } else if (cursor['part'] is! int ||
          cursor['offset'] is! int ||
          (cursor['block'] != null && cursor['block'] is! String)) {
        _invalidCursor();
      }
    }
    final novel = await database.novelDao.get(work);
    if (novel == null || novel.draft) {
      throw const _SessionsError(
        ToolErrorCode.not_found,
        'Work was not found.',
      );
    }
    final sessions = database.aiChatSessionDao;
    if (sessionId != null &&
        await sessions.getById(sessionId, novelId: work) == null) {
      throw const _SessionsError(
        ToolErrorCode.not_found,
        'Session was not found in the selected work.',
      );
    }
    if (action == 'list') {
      AiChatSession? after;
      if (cursor != null) {
        after = await sessions.getById(
          cursor['message'] as String,
          novelId: work,
        );
        if (after == null ||
            after.updatedAt.toIso8601String() != cursor['updated']) {
          _invalidCursor();
        }
      }
      final rows = await sessions.listForTools(
        workId: work,
        titleQuery: query,
        mode: mode,
        parentId: _string(o, 'parent_id'),
        after: after,
        limit: limit + 1,
      );
      final more = rows.length > limit;
      final items = rows.take(limit).map(_sessionJson).toList();
      return _success(
        {
          'work_id': work,
          'items': items,
          'has_more': more,
          'next_cursor': more
              ? _encodeCursor(fingerprint, {
                  'message': rows[limit - 1].id,
                  'updated': rows[limit - 1].updatedAt.toIso8601String(),
                })
              : null,
        },
        'session',
        items.length,
      );
    }
    final lease = await access.acquire(work);
    try {
      final dao = lease.service.database.aiChatMessageDao;
      AiChatMessage? anchor;
      if (cursor != null) {
        anchor = await dao.getById(cursor['message'] as String);
        if (anchor == null ||
            (sessionId != null && anchor.sessionId != sessionId) ||
            (id != null && anchor.id != id)) {
          _invalidCursor();
        }
        if (await sessions.getById(anchor.sessionId, novelId: work) == null) {
          _invalidCursor();
        }
      }
      AiChatMessage? requested;
      if (action == 'get') {
        requested = await dao.getInSession(sessionId!, id!);
        if (requested == null) {
          throw const _SessionsError(
            ToolErrorCode.not_found,
            'Message was not found in this session.',
          );
        }
        if (blockId != null &&
            !(requested.blocks ?? []).any((b) => b.id == blockId)) {
          if (cursor != null) {
            _invalidCursor();
          }
          throw const _SessionsError(
            ToolErrorCode.not_found,
            'Block was not found in this message.',
          );
        }
      }
      final items = <Map<String, dynamic>>[];
      var budget = maxChars;
      String? next;
      var first = true;
      var after = anchor;
      var resumeValidated = cursor == null;
      while (true) {
        final rows = first && requested != null
            ? [requested]
            : first && anchor != null
            ? [anchor]
            : await dao.scanForTools(
                sessionId: sessionId,
                after: after,
                descending: order == 'desc',
              );
        first = false;
        if (rows.isEmpty) {
          break;
        }
        final owners = {
          for (final s in await sessions.getValidForTools(
            work,
            rows.map((r) => r.sessionId),
          ))
            s.id: s,
        };
        for (final row in rows) {
          after = row;
          final owner = owners[row.sessionId];
          if (owner == null) {
            continue;
          }
          final parts = filterTranscript(
            normalizeTranscript(row),
            kinds: kinds,
            toolName: toolName,
            toolStatus: status,
            query: action == 'search' ? query : null,
            blockId: blockId,
          );
          final out = <Map<String, dynamic>>[];
          for (final part in parts) {
            var offset = 0;
            if (!resumeValidated) {
              if (part.index < cursor!['part']) {
                continue;
              }
              if (part.index != cursor['part'] || part.id != cursor['block']) {
                _invalidCursor();
              }
              offset = cursor['offset'] as int;
              if (offset < 0 || offset >= part.text.runes.length) {
                _invalidCursor();
              }
              resumeValidated = true;
            }
            if (budget == 0 || (out.isEmpty && items.length >= limit)) {
              next = _encodeCursor(fingerprint, {
                'message': row.id,
                'part': part.index,
                'block': part.id,
                'offset': offset,
              });
              break;
            }
            final slice = part.slice(offset, budget);
            final consumed = (slice['text'] as String).runes.length;
            out.add(slice);
            budget -= consumed;
            if (slice['truncated'] == true) {
              next = _encodeCursor(fingerprint, {
                'message': row.id,
                'part': part.index,
                'block': part.id,
                'offset': offset + consumed,
              });
              break;
            }
          }
          if (!resumeValidated) {
            _invalidCursor();
          }
          if (out.isNotEmpty) {
            items.add({
              'id': row.id,
              'role': row.role,
              'type': row.type,
              'sequence': row.sequence,
              'created_at': row.createdAt.toUtc().toIso8601String(),
              if (scope == 'work') ...{
                'session_id': owner.id,
                'session_title': _title(owner.title),
                'session_title_truncated': owner.title.runes.length > 200,
                'session_mode': owner.mode,
              },
              'parts': out,
            });
          }
          if (next != null) {
            break;
          }
        }
        if (next != null || action == 'get') {
          break;
        }
      }
      return _success(
        {
          'work_id': work,
          'session_id': sessionId,
          if (scope == 'work') 'scope': 'work',
          'items': items,
          'has_more': next != null,
          'next_cursor': next,
        },
        'message',
        items.length,
      );
    } finally {
      lease.release();
    }
  }
}

String _title(String text) => String.fromCharCodes(text.runes.take(200));
Map<String, dynamic> _sessionJson(AiChatSession row) => {
  'id': row.id,
  'work_id': row.novelId,
  'title': _title(row.title),
  'title_truncated': row.title.runes.length > 200,
  'mode': row.mode,
  'parent_id': row.parentId,
  'created_at': row.createdAt.toUtc().toIso8601String(),
  'updated_at': row.updatedAt.toUtc().toIso8601String(),
};
Map<String, dynamic> _success(
  Map<String, dynamic> data,
  String noun,
  int count,
) => {
  'ok': true,
  'output': 'Returned $count $noun${count == 1 ? '' : 's'}.',
  'data': data,
};
String? _string(Map<String, dynamic> o, String key) {
  if (!o.containsKey(key)) {
    return null;
  }
  final value = o[key];
  if (value is! String || value.trim().isEmpty) {
    throw _SessionsError(
      ToolErrorCode.invalid_argument,
      '$key must be a nonempty string.',
    );
  }
  return value;
}

int _integer(
  Map<String, dynamic> o,
  String key,
  int fallback,
  int min,
  int max,
) {
  if (!o.containsKey(key)) {
    return fallback;
  }
  final value = o[key];
  if (value is! int || value < min || value > max) {
    throw _SessionsError(
      ToolErrorCode.invalid_argument,
      '$key must be an integer from $min to $max.',
    );
  }
  return value;
}

Never _invalidCursor() => throw const _SessionsError(
  ToolErrorCode.invalid_argument,
  'Cursor is invalid; restart the query.',
);
Map<String, dynamic>? _decodeCursor(String? cursor, String fingerprint) {
  if (cursor == null) {
    return null;
  }
  try {
    final value = jsonDecode(utf8.decode(base64Url.decode(cursor)));
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['query'] != fingerprint ||
        value['message'] is! String ||
        (value['updated'] == null &&
            (value['part'] is! int || value['offset'] is! int))) {
      _invalidCursor();
    }
    return value;
  } on FormatException {
    _invalidCursor();
  }
}

String _encodeCursor(String fingerprint, Map<String, dynamic> position) =>
    base64Url.encode(
      utf8.encode(
        jsonEncode({'version': 1, 'query': fingerprint, ...position}),
      ),
    );
