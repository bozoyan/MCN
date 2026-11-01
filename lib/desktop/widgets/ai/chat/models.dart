// 职责: AI 聊天面板 — 声明草稿消息和用户引用展示模型。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
part of 'panel.dart';

class AiChatDraftMessage {
  const AiChatDraftMessage({
    required this.id,
    required this.text,
    this.autoSend = false,
  });

  final String id;
  final String text;
  final bool autoSend;
}

class AiChatHandoffDraft {
  const AiChatHandoffDraft({
    required this.id,
    required this.label,
    required this.content,
    required this.title,
    this.providerId,
    this.model,
    this.autoSend = false,
    this.references = const [],
    this.initialText,
    this.sourceSessionId,
    this.sourceMode,
    this.reasoningEffort,
    this.needsSourceValidation = false,
    this.files = const [],
  });

  final String id;
  final String label;
  final String content;
  final String title;
  final String? providerId;
  final String? model;
  final bool autoSend;
  final List<AiContextReference> references;
  final String? initialText;
  final String? sourceSessionId;
  final AiSessionMode? sourceMode;
  final String? reasoningEffort;
  final bool needsSourceValidation;

  /// 作为附件放在 [initialText] 之前的文件，与用户手动添加的附件一样随消息归档。
  final List<XFile> files;

  factory AiChatHandoffDraft.continuationRequest(String sourceSessionId) =>
      AiChatHandoffDraft(
        id: 'continue_${DateTime.now().microsecondsSinceEpoch}',
        label: '',
        content: '',
        title: '',
        sourceSessionId: sourceSessionId,
        needsSourceValidation: true,
      );

  factory AiChatHandoffDraft.fromContinuation(
    PendingChatHandoff draft,
  ) => AiChatHandoffDraft(
    id: '__handoff_draft__continue_${DateTime.now().microsecondsSinceEpoch}',
    label: draft.label,
    content: draft.content,
    title: '',
    initialText: draft.initialText,
    references: draft.references,
    sourceSessionId: draft.sourceSessionId,
    sourceMode: draft.sourceMode,
    providerId: draft.providerId,
    model: draft.model,
    reasoningEffort: draft.reasoningEffort,
  );
}

class AiChatShortcutDraft {
  const AiChatShortcutDraft({
    required this.id,
    required this.text,
    this.autoSend = false,
    this.references = const [],
  });

  final String id;
  final String text;
  final bool autoSend;
  final List<AiContextReference> references;
}
