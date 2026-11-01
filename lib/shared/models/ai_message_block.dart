// 职责: AI 消息块模型 — 序列化文本、思考、工具、图片、AskUser 与下一步建议块
// 关联文件:
//   lib/shared/providers/ai_providers.dart
//   lib/shared/models/ask_user_models.dart
//   lib/shared/heuristic/chat_next_action.dart
//   lib/shared/services/ai/ai_chat_service.dart
import 'package:json_annotation/json_annotation.dart';

import 'ask_user_models.dart';
import 'ai_nested_tool_call.dart';

export 'ai_nested_tool_call.dart';

part 'ai_message_block.g.dart';

sealed class AiMessageBlock {
  const AiMessageBlock({required this.id});

  final String id;

  Map<String, dynamic> toJson();

  static AiMessageBlock fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? 'text';
    switch (kind) {
      case 'text':
        return AiTextBlock.fromJson(json);
      case 'thinking':
        return AiThinkingBlock.fromJson(json);
      case 'tool_call':
        return AiToolCallBlock.fromJson(json);
      case 'image':
        return AiImageBlock.fromJson(json);
      case 'attachment':
        return AiAttachmentBlock.fromJson(json);
      case 'ask_user':
        return AiAskUserBlock.fromJson(json);
      case 'suggest_next_action':
        return AiSuggestNextActionBlock.fromJson(json);
    }
    return AiTextBlock(
      id: json['id'] as String? ?? 'unknown',
      text: json['text'] as String? ?? '',
    );
  }
}

/// A user-supplied file in the ordered message body. Bytes stay in session files.
class AiAttachmentBlock extends AiMessageBlock {
  const AiAttachmentBlock({
    required super.id,
    required this.name,
    required this.path,
    required this.mimeType,
    this.imageNumber,
  });

  final String name;
  final String path;
  final String mimeType;

  /// Stable within one user message; absent on older attachments.
  final int? imageNumber;
  bool get isImage => mimeType.startsWith('image/');

  factory AiAttachmentBlock.fromJson(Map<String, dynamic> json) =>
      AiAttachmentBlock(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        mimeType: json['mime_type'] as String,
        imageNumber: json['image_number'] as int?,
      );

  AiAttachmentBlock withPath(String value) => AiAttachmentBlock(
    id: id,
    name: name,
    path: value,
    mimeType: mimeType,
    imageNumber: imageNumber,
  );

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'attachment',
    'id': id,
    'name': name,
    'path': path,
    'mime_type': mimeType,
    if (imageNumber != null) 'image_number': imageNumber,
  };
}

@JsonSerializable()
class AiTextBlock extends AiMessageBlock {
  const AiTextBlock({required super.id, required this.text});

  final String text;

  AiTextBlock copyWith({String? text}) {
    return AiTextBlock(id: id, text: text ?? this.text);
  }

  factory AiTextBlock.fromJson(Map<String, dynamic> json) =>
      _$AiTextBlockFromJson(json);

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'text',
    ..._$AiTextBlockToJson(this),
  };
}

@JsonSerializable()
class AiThinkingBlock extends AiMessageBlock {
  const AiThinkingBlock({
    required super.id,
    required this.text,
    this.signature,
    this.encryptedContents = const [],
  });

  final String text;
  final String? signature;
  @JsonKey(defaultValue: <String>[])
  final List<String> encryptedContents;

  AiThinkingBlock copyWith({
    String? text,
    String? signature,
    List<String>? encryptedContents,
  }) {
    return AiThinkingBlock(
      id: id,
      text: text ?? this.text,
      signature: signature ?? this.signature,
      encryptedContents: encryptedContents ?? this.encryptedContents,
    );
  }

  factory AiThinkingBlock.fromJson(Map<String, dynamic> json) =>
      _$AiThinkingBlockFromJson(json);

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'thinking',
    ..._$AiThinkingBlockToJson(this),
  };
}

enum AiToolCallStatus { pending, rejected, cancelled, running, success, error }

const Object _copySentinel = Object();

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class AiToolCallBlock extends AiMessageBlock {
  const AiToolCallBlock({
    required super.id,
    required this.callId,
    required this.toolName,
    required this.arguments,
    this.requestId,
    this.status = AiToolCallStatus.pending,
    this.result,
    this.metadata,
    this.errorMessage,
    this.targetPath,
    this.diffOldText,
    this.diffNewText,
    this.thoughtSignature,
    this.nestedCalls = const [],
  });

  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final int? requestId;
  final AiToolCallStatus status;
  final Map<String, dynamic>? result;

  /// UI 辅助数据，由工具结果中的 `_metadata` 提取而来。不会发送给模型，
  /// 仅用于 tool card 展示与「apply 到对应对象」等交互。
  final Map<String, dynamic>? metadata;

  final String? errorMessage;

  final String? targetPath;
  final String? diffOldText;
  final String? diffNewText;
  final String? thoughtSignature;
  final List<AiNestedToolCall> nestedCalls;

  String get source => metadata?['tool_source'] as String? ?? 'builtin';
  String? get mcpServer => metadata?['mcp_server'] as String?;
  String? get executionState => result?['executionState'] as String?;

  bool get isEdit => toolName == 'Edit';
  bool get isWrite => toolName == 'Write';
  bool get isRead => toolName == 'Read';
  bool get hasDiff =>
      (diffOldText != null || diffNewText != null) && (isEdit || isWrite);

  AiToolCallBlock copyWith({
    String? callId,
    String? toolName,
    Map<String, dynamic>? arguments,
    Object? requestId = _copySentinel,
    AiToolCallStatus? status,
    Map<String, dynamic>? result,
    Map<String, dynamic>? metadata,
    String? errorMessage,
    String? targetPath,
    String? diffOldText,
    String? diffNewText,
    Object? thoughtSignature = _copySentinel,
    List<AiNestedToolCall>? nestedCalls,
  }) {
    return AiToolCallBlock(
      id: id,
      callId: callId ?? this.callId,
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      requestId: requestId == _copySentinel
          ? this.requestId
          : requestId as int?,
      status: status ?? this.status,
      nestedCalls: nestedCalls ?? this.nestedCalls,
      result: result ?? this.result,
      metadata: metadata ?? this.metadata,
      errorMessage: errorMessage ?? this.errorMessage,
      targetPath: targetPath ?? this.targetPath,
      diffOldText: diffOldText ?? this.diffOldText,
      diffNewText: diffNewText ?? this.diffNewText,
      thoughtSignature: thoughtSignature == _copySentinel
          ? this.thoughtSignature
          : thoughtSignature as String?,
    );
  }

  factory AiToolCallBlock.fromJson(Map<String, dynamic> json) {
    final block = _$AiToolCallBlockFromJson(json);
    final calls = block.nestedCalls;
    return block.copyWith(
      nestedCalls:
          block.status == AiToolCallStatus.running ||
              block.status == AiToolCallStatus.pending
          ? calls
          : settleNestedCalls(
              calls,
              cancelled: block.status == AiToolCallStatus.cancelled,
            ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'tool_call',
    ..._$AiToolCallBlockToJson(copyWith(nestedCalls: nestedCalls)),
  };
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AiImageBlock extends AiMessageBlock {
  const AiImageBlock({
    required super.id,
    required this.prompt,
    this.toolName,
    this.imageUrl,
    this.imageBase64,
    this.localFilePath,
    this.assetId,
    this.revisedPrompt,
    this.characterId,
    this.itemId,
    this.status = AiImageStatus.generating,
    this.errorMessage,
  });

  final String prompt;
  final String? toolName;
  final String? imageUrl;
  final String? imageBase64;
  final String? localFilePath;
  final String? assetId;
  final String? revisedPrompt;
  final String? characterId;
  final String? itemId;
  final AiImageStatus status;
  final String? errorMessage;

  bool get hasImage =>
      imageUrl != null || imageBase64 != null || localFilePath != null;

  String? get effectiveSource {
    if (localFilePath != null) return localFilePath;
    if (imageBase64 != null) return 'data:image/png;base64,$imageBase64';
    if (imageUrl != null) return imageUrl;
    return null;
  }

  AiImageBlock copyWith({
    String? prompt,
    String? toolName,
    String? imageUrl,
    String? imageBase64,
    String? localFilePath,
    String? assetId,
    String? revisedPrompt,
    String? characterId,
    String? itemId,
    AiImageStatus? status,
    String? errorMessage,
  }) {
    return AiImageBlock(
      id: id,
      prompt: prompt ?? this.prompt,
      toolName: toolName ?? this.toolName,
      imageUrl: imageUrl ?? this.imageUrl,
      imageBase64: imageBase64 ?? this.imageBase64,
      localFilePath: localFilePath ?? this.localFilePath,
      assetId: assetId ?? this.assetId,
      revisedPrompt: revisedPrompt ?? this.revisedPrompt,
      characterId: characterId ?? this.characterId,
      itemId: itemId ?? this.itemId,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory AiImageBlock.fromJson(Map<String, dynamic> json) =>
      _$AiImageBlockFromJson(json);

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'image',
    ..._$AiImageBlockToJson(this),
  };
}

enum AiImageStatus { generating, success, error }

enum AiAskUserStatus {
  pending,
  answered,
  cancelled,
  error,
  timed_out,
  interrupted;

  static AiAskUserStatus fromResult(AskUserResult result) =>
      switch (result.resolution) {
        AskUserResolution.timeout => timed_out,
        AskUserResolution.interrupted => interrupted,
        null when result.cancelled => cancelled,
        null when result.ok => answered,
        null => error,
      };
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AiAskUserBlock extends AiMessageBlock {
  const AiAskUserBlock({
    required super.id,
    required this.callId,
    required this.questions,
    this.status = AiAskUserStatus.pending,
    this.answers,
    this.errorMessage,
    this.resolution,
    this.unansweredQuestionIds,
  });

  final String callId;
  final List<Map<String, dynamic>> questions;
  final AiAskUserStatus status;
  final List<Map<String, dynamic>>? answers;
  final String? errorMessage;
  final AskUserResolution? resolution;
  final List<String>? unansweredQuestionIds;

  bool get isPending => status == AiAskUserStatus.pending;
  bool get isAnswered => status == AiAskUserStatus.answered;

  AiAskUserBlock copyWith({
    String? callId,
    List<Map<String, dynamic>>? questions,
    AiAskUserStatus? status,
    List<Map<String, dynamic>>? answers,
    String? errorMessage,
    AskUserResolution? resolution,
    List<String>? unansweredQuestionIds,
  }) {
    return AiAskUserBlock(
      id: id,
      callId: callId ?? this.callId,
      questions: questions ?? this.questions,
      status: status ?? this.status,
      answers: answers ?? this.answers,
      errorMessage: errorMessage ?? this.errorMessage,
      resolution: resolution ?? this.resolution,
      unansweredQuestionIds:
          unansweredQuestionIds ?? this.unansweredQuestionIds,
    );
  }

  factory AiAskUserBlock.fromJson(Map<String, dynamic> json) =>
      _$AiAskUserBlockFromJson(json);

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'ask_user',
    ..._$AiAskUserBlockToJson(this),
  };
}

/// 下一步建议块 —— 由模型的 `SuggestNextAction` 工具调用挂上来。
///
/// 与 [AiAskUserBlock] 平行，但生命周期相反：本块不阻塞回合，用户没点也是正常终态。
/// [suggestions] 存的是**已裁决**结果（白名单形状校验过完），仅用于会话恢复时重放。
@JsonSerializable(fieldRename: FieldRename.snake)
class AiSuggestNextActionBlock extends AiMessageBlock {
  const AiSuggestNextActionBlock({
    required super.id,
    required this.callId,
    required this.suggestions,
  });

  final String callId;
  final List<Map<String, dynamic>> suggestions;

  factory AiSuggestNextActionBlock.fromJson(Map<String, dynamic> json) =>
      _$AiSuggestNextActionBlockFromJson(json);

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'suggest_next_action',
    ..._$AiSuggestNextActionBlockToJson(this),
  };
}
