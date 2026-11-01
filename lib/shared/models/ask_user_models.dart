// 职责: 解析 AskUser 问题与选项，并提供 UI 和 Service 共用的请求、回答类型。
// 关联文件:
//   lib/shared/agent/tools.dart
//   lib/shared/services/ai/tools_ask_user.dart
//   lib/shared/models/ai_message_block.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/desktop/widgets/ai/tools/ask_user_card.dart

import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'ask_user_models.g.dart';

/// AskUser 自动处理来源；JSON 值独立于卡片状态命名。
@JsonEnum(alwaysCreate: true)
enum AskUserResolution {
  @JsonValue('timeout')
  timeout,
  @JsonValue('interrupted')
  interrupted;

  String get jsonValue => _$AskUserResolutionEnumMap[this]!;
}

/// AskUser 工具选项
class AskUserOption {
  const AskUserOption({
    required this.label,
    this.description,
    this.recommended = false,
  });

  final String label;
  final String? description;
  final bool recommended;

  factory AskUserOption.fromJson(Map<String, dynamic> json) {
    final description = json['description']?.toString().trim();
    return AskUserOption(
      label: json['label']?.toString() ?? '',
      description: description == null || description.isEmpty
          ? null
          : description,
      recommended: _parseAskUserBool(json['recommended']),
    );
  }

  static AskUserOption? tryParse(Object? raw) {
    if (raw is Map) {
      return AskUserOption.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw is String) {
      final label = raw.trim();
      if (label.isEmpty) {
        return null;
      }
      return AskUserOption(label: label);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    if (description != null) 'description': description,
    'recommended': recommended,
  };
}

/// AskUser 工具中的单个问题
class AskUserQuestion {
  const AskUserQuestion({
    required this.id,
    required this.question,
    this.options,
    this.allowFreeText = true,
    this.multiSelect = false,
  });

  final String id;
  final String question;
  final List<AskUserOption>? options;
  final bool allowFreeText;
  final bool multiSelect;

  factory AskUserQuestion.fromJson(Map<String, dynamic> json, {int index = 0}) {
    final id = json['id']?.toString();
    final options = _parseAskUserArray(
      json['options'],
      field: 'questions[$index].options',
    )?.map(AskUserOption.tryParse).nonNulls.toList();
    return AskUserQuestion(
      id: id == null || id.trim().isEmpty ? 'q${index + 1}' : id,
      question: json['question']?.toString() ?? '',
      options: options == null || options.isEmpty ? null : options,
      allowFreeText: _parseAskUserBool(
        json['allow_free_text'],
        defaultValue: true,
      ),
      multiSelect: _parseAskUserBool(json['multi_select']),
    );
  }

  static AskUserQuestion? tryParse(Object? raw, {int index = 0}) {
    if (raw is Map) {
      return AskUserQuestion.fromJson(
        Map<String, dynamic>.from(raw),
        index: index,
      );
    }
    if (raw is String) {
      final question = raw.trim();
      if (question.isEmpty) {
        return null;
      }
      return AskUserQuestion(id: 'q${index + 1}', question: question);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    if (options != null) 'options': options!.map((o) => o.toJson()).toList(),
    'allow_free_text': allowFreeText,
    'multi_select': multiSelect,
  };
}

/// AskUser 工具中单个问题的回答
class AskUserAnswer {
  const AskUserAnswer({
    required this.questionId,
    this.answer,
    this.selectedOptions,
  });

  final String questionId;
  final String? answer;
  final List<String>? selectedOptions;

  factory AskUserAnswer.fromJson(Map<String, dynamic> json) {
    return AskUserAnswer(
      questionId: json['question_id']?.toString() ?? '',
      answer: json['answer']?.toString(),
      selectedOptions: (json['selected_options'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'question_id': questionId,
    if (answer != null) 'answer': answer,
    if (selectedOptions != null) 'selected_options': selectedOptions,
  };
}

/// AskUser 工具结果
class AskUserResult {
  const AskUserResult({
    required this.ok,
    this.answers,
    this.cancelled = false,
    this.error,
    this.resolution,
    this.unansweredQuestionIds,
  });

  final bool ok;
  final List<AskUserAnswer>? answers;
  final bool cancelled;
  final String? error;
  final AskUserResolution? resolution;
  final List<String>? unansweredQuestionIds;

  factory AskUserResult.timeout(List<AskUserQuestion> questions) {
    final answers = <AskUserAnswer>[];
    final unanswered = <String>[];
    for (final question in questions) {
      final recommended =
          question.options
              ?.where((option) => option.recommended)
              .map((option) => option.label)
              .toList() ??
          const <String>[];
      if (recommended.isEmpty) {
        unanswered.add(question.id);
      } else {
        answers.add(
          AskUserAnswer(
            questionId: question.id,
            selectedOptions: question.multiSelect
                ? recommended
                : [recommended.first],
          ),
        );
      }
    }
    return AskUserResult(
      ok: true,
      answers: answers,
      resolution: AskUserResolution.timeout,
      unansweredQuestionIds: unanswered,
    );
  }

  Map<String, dynamic> toJson() => {
    'ok': ok,
    if (answers != null) 'answers': answers!.map((a) => a.toJson()).toList(),
    'cancelled': cancelled,
    if (error != null) 'error': error,
    if (resolution != null) 'resolution': resolution!.jsonValue,
    if (unansweredQuestionIds != null)
      'unanswered_question_ids': unansweredQuestionIds,
    if (resolution == AskUserResolution.timeout && (answers?.isEmpty ?? true))
      'message': '用户未回答，请根据现有上下文继续',
  };
}

/// AskUser 工具请求
class AskUserRequest {
  const AskUserRequest({required this.callId, required this.questions});

  final String callId;
  final List<AskUserQuestion> questions;
}

/// AskUser 工具输入参数
class AskUserInput {
  const AskUserInput({required this.questions});

  final List<AskUserQuestion> questions;

  factory AskUserInput.fromJson(Map<String, dynamic> json) {
    final questions = _parseAskUserArray(json['questions'], field: 'questions')
        ?.asMap()
        .entries
        .map((entry) => AskUserQuestion.tryParse(entry.value, index: entry.key))
        .nonNulls
        .where((question) => question.question.trim().isNotEmpty)
        .toList();
    return AskUserInput(questions: questions ?? const []);
  }
}

/// AskUser 工具回调类型定义
typedef AiAskUserCallback =
    Future<AskUserResult> Function(AskUserRequest request);

/// 只解码完整的 JSON 数组；不猜测普通文本的分隔方式或修补被截断的选项。
List<dynamic>? _parseAskUserArray(Object? raw, {required String field}) {
  if (raw == null) {
    return null;
  }
  if (raw is List) {
    return raw;
  }
  if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded;
      }
    } on FormatException {
      // JSON 异常可能带入问题正文，统一转换为仅含字段和类型的错误。
    }
  }
  final shape = switch (raw) {
    String() => 'string',
    Map() => 'object',
    bool() => 'boolean',
    num() => 'number',
    _ => 'other',
  };
  throw FormatException(
    'AskUser.$field must be a JSON array; received $shape.',
  );
}

bool _parseAskUserBool(Object? raw, {bool defaultValue = false}) {
  if (raw is bool) {
    return raw;
  }
  if (raw is num) {
    return raw != 0;
  }
  if (raw is String) {
    final value = raw.trim().toLowerCase();
    if (value == 'true' || value == 'yes' || value == '1') {
      return true;
    }
    if (value == 'false' || value == 'no' || value == '0') {
      return false;
    }
  }
  return defaultValue;
}
