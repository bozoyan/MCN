// 职责: 将已保存聊天消息投影为可检索、可分页的正文与工具片段。
// 关联文件:
//   lib/shared/models/ai_message_block.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/ai/sessions/run_command_handler.dart
import 'dart:convert';

import '../../../database/novel_content_database.dart';
import '../../../models/ai_message_block.dart';
import '../tool_result_payloads.dart';
import '../tool_error_normalize.dart' show toolResultIsSuccess;

class TranscriptPart {
  const TranscriptPart({
    required this.index,
    required this.kind,
    required this.text,
    this.id,
    this.toolName,
    this.callId,
    this.toolStatus,
  });
  final int index;
  final String kind;
  final String text;
  final String? id;
  final String? toolName;
  final String? callId;
  final String? toolStatus;

  Map<String, dynamic> slice(int offset, int length) {
    final points = text.runes.toList();
    final end = (offset + length).clamp(0, points.length);
    return {
      if (id != null) 'id': id,
      'part_index': index,
      'kind': kind,
      if (kind == 'tool') ...{
        'tool_name': toolName,
        'call_id': callId,
        'tool_status': toolStatus,
      },
      'text': String.fromCharCodes(points.sublist(offset, end)),
      'text_offset': offset,
      'truncated': end < points.length,
    };
  }
}

List<TranscriptPart> normalizeTranscript(AiChatMessage row) {
  final parts = <TranscriptPart>[];
  void add(
    String kind,
    String text, {
    String? id,
    String? toolName,
    String? callId,
    String? status,
  }) {
    if (text.isEmpty) {
      return;
    }
    parts.add(
      TranscriptPart(
        index: parts.length,
        kind: kind,
        text: text,
        id: id,
        toolName: toolName,
        callId: callId,
        toolStatus: status,
      ),
    );
  }

  if (row.type == 'compact_summary' ||
      row.type == 'system_remind' ||
      row.role == 'system') {
    add(row.type == 'compact_summary' ? 'summary' : 'system', row.content);
    return parts;
  }
  if (row.type == 'tool_result') {
    final payload = jsonDecode(row.content) as Map<String, dynamic>;
    final metadata = row.metadata ?? const <String, dynamic>{};
    final hasStatus =
        metadata['is_error'] is bool ||
        (payload['ok'] is bool || !toolResultIsSuccess(payload));
    add(
      'tool',
      jsonEncode(Map.of(payload)..remove('_metadata')),
      toolName: metadata['tool_name'] as String?,
      callId: metadata['tool_call_id'] as String?,
      status: !hasStatus
          ? null
          : aiToolResultStatus(
              payload,
              errorMessage: metadata['is_error'] == true ? row.content : null,
            ).name,
    );
    return parts;
  }
  final kind = row.role == 'user' ? 'user' : 'assistant';
  final blocks = row.blocks ?? const <AiMessageBlock>[];
  if (!blocks.whereType<AiTextBlock>().any((b) => b.text.isNotEmpty)) {
    add(kind, row.content);
  }
  for (final block in blocks) {
    switch (block) {
      case AiTextBlock():
        add(kind, block.text, id: block.id);
      case AiThinkingBlock():
        break;
      case AiToolCallBlock():
        add(
          'tool',
          jsonEncode({
            'arguments': block.arguments,
            'result': block.result == null
                ? null
                : (Map.of(block.result!)..remove('_metadata')),
            'error': block.errorMessage,
          }),
          id: block.id,
          toolName: block.toolName,
          callId: block.callId,
          status: block.status.name,
        );
      case AiAttachmentBlock():
        add(kind, jsonEncode(block.toJson()), id: block.id);
      case AiImageBlock():
        add(
          kind,
          jsonEncode({
            'prompt': block.prompt,
            'revised_prompt': block.revisedPrompt,
            'url': block.imageUrl,
            'path': block.localFilePath,
          }),
          id: block.id,
        );
      case AiAskUserBlock():
        add(
          'assistant',
          jsonEncode({'questions': block.questions, 'answers': block.answers}),
          id: block.id,
        );
      case AiSuggestNextActionBlock():
        add('assistant', jsonEncode(block.suggestions), id: block.id);
    }
  }
  return parts;
}

List<TranscriptPart> filterTranscript(
  List<TranscriptPart> parts, {
  required Set<String> kinds,
  String? toolName,
  String? toolStatus,
  String? query,
  String? blockId,
}) => parts
    .where(
      (p) =>
          kinds.contains(p.kind) &&
          (blockId == null || p.id == blockId) &&
          (p.kind != 'tool' ||
              ((toolName == null || p.toolName == toolName) &&
                  (toolStatus == null || p.toolStatus == toolStatus))) &&
          (query == null || p.text.contains(query)),
    )
    .toList();
