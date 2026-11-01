// 职责: 封装 AiChatPanel 的局部 UI 状态（hooks 创建的 controllers、notifiers、refs）
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/services/ai/chat_session_controller.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import '../../../../shared/widgets/ai/chat/composer_controller.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/database/novel_content_database.dart'
    show WorkingChange;
import '../../../../shared/models/novel_workspace.dart';
import '../../../../shared/models/slash_entry.dart';
import '../../../../shared/providers/settings_providers.dart';
import '../../../../shared/services/ai/chat_session_controller.dart';
import '../../../../shared/services/working_overlay.dart';

// PendingChatHandoff / QueuedChatMessage 已移到 shared 控制器（单一发送编排），
// 这里 export 回吐，保持 composer/panel 引用零改动。
export '../../../../shared/services/ai/chat_session_controller.dart'
    show PendingChatHandoff, QueuedChatMessage;

class ComposerNotice {
  const ComposerNotice.warning({required this.message});

  final String message;
}

/// 桌面聊天面板内按会话隔离的待发送消息。
///
/// 面板可在多个会话之间切换，而旧会话的 Agent 仍可能在后台运行；队列必须按
/// session 保存，不能因查看其它会话而覆盖或丢弃。
class SessionQueuedMessageStore {
  SessionQueuedMessageStore(this._messages);

  final ValueNotifier<Map<String?, QueuedChatMessage>> _messages;

  ValueNotifier<Map<String?, QueuedChatMessage>> get notifier => _messages;

  QueuedChatMessage? forSession(String? sessionId) =>
      _messages.value[sessionId];

  Iterable<QueuedChatMessage> get all => _messages.value.values;

  void setForSession(String? sessionId, QueuedChatMessage? message) {
    final next = Map<String?, QueuedChatMessage>.from(_messages.value);
    if (message == null) {
      next.remove(sessionId);
    } else {
      next[sessionId] = message;
    }
    _messages.value = next;
  }
}

class AiChatPanelState {
  AiChatPanelState({
    required this.composerController,
    required this.composerFocusNode,
    required this.sendGuardUntil,
    required this.attachedReferences,
    required this.referenceImagePaths,
    required this.pendingHandoff,
    required this.queuedMessages,
    required this.composerNotice,
    required this.slashMatches,
    required this.slashIndex,
    required this.userScrolledUp,
    required this.consumedDraftId,
    required this.pendingAutoSendSessionId,
    required this.pendingLoadTarget,
    required this.slashMenuController,
    required this.composerInputLink,
    required this.modelSelectorLink,
    required this.modelSelectorOpenTrigger,
    required this.modelMenuVisible,
    required this.pendingModelSelection,
  });

  final ChatComposerController composerController;
  final FocusNode composerFocusNode;
  final ObjectRef<DateTime?> sendGuardUntil;
  final ValueNotifier<List<AiContextReference>> attachedReferences;

  /// 快捷出图的参考图本地路径(最多 4 张);发送 /出图 指令后清空。
  final ValueNotifier<List<String>> referenceImagePaths;
  final ValueNotifier<PendingChatHandoff?> pendingHandoff;
  final SessionQueuedMessageStore queuedMessages;
  final ValueNotifier<ComposerNotice?> composerNotice;
  final ValueNotifier<List<SlashEntry>> slashMatches;
  final ValueNotifier<int> slashIndex;
  final ObjectRef<bool> userScrolledUp;
  final ObjectRef<String?> consumedDraftId;
  final ValueNotifier<String?> pendingAutoSendSessionId;
  final ObjectRef<String?> pendingLoadTarget;
  final OverlayPortalController slashMenuController;

  /// 用于将 onboarding 气泡定位到 composer 输入框上方。
  final LayerLink composerInputLink;

  /// 用于将 onboarding 气泡定位到 model selector 按钮上方。
  final LayerLink modelSelectorLink;

  /// 增量触发 model selector 自动打开菜单。
  final ValueNotifier<int> modelSelectorOpenTrigger;

  /// model selector 菜单当前是否可见。
  final ValueNotifier<bool> modelMenuVisible;

  /// 用户已选择、等待随下一次发送应用的模型。
  final ValueNotifier<PendingChatModelSelection?> pendingModelSelection;
}

AiChatPanelState useAiChatPanelState({
  WidgetRef? ref,
  String? databasePath,
  List<WorkingChange> pendingAiChanges = const [],
  bool isAgentTurnActive = false,
  FocusNode? composerFocusNode,
}) {
  final composerController = useChatComposerController();
  // hooks 规则要求无条件调用;外部节点优先,自建节点在外部提供时仅创建/释放不用。
  final ownComposerFocusNode = useFocusNode();
  final effectiveComposerFocusNode = composerFocusNode ?? ownComposerFocusNode;
  final sendGuardUntil = useRef<DateTime?>(null);
  final attachedReferences = useState(<AiContextReference>[]);
  final referenceImagePaths = useState(<String>[]);
  final pendingHandoff = useState<PendingChatHandoff?>(null);
  final queuedMessages = useState(<String?, QueuedChatMessage>{});
  final queuedMessageStore = useMemoized(
    () => SessionQueuedMessageStore(queuedMessages),
    [queuedMessages],
  );
  final composerNotice = useState<ComposerNotice?>(null);
  final slashMatches = useState<List<SlashEntry>>(const []);
  final slashIndex = useState(0);
  final userScrolledUp = useRef(false);
  final consumedDraftId = useRef<String?>(null);
  final pendingAutoSendSessionId = useState<String?>(null);
  final pendingLoadTarget = useRef<String?>(null);
  final slashMenuController = useMemoized(() => OverlayPortalController(), []);
  final composerInputLink = useMemoized(() => LayerLink(), []);
  final modelSelectorLink = useMemoized(() => LayerLink(), []);
  final modelSelectorOpenTrigger = useState(0);
  final modelMenuVisible = useState(false);
  final pendingModelSelection = useState<PendingChatModelSelection?>(null);

  final pendingAiChangeIds = pendingAiChanges
      .where(
        (change) =>
            change.status == workingChangeStatusActive &&
            change.source == workingChangeSourceAi,
      )
      .map((change) => change.id)
      .toList();
  final pendingAiChangeIdSet = pendingAiChangeIds.toSet();

  useEffect(() {
    if (ref == null || databasePath == null || databasePath.isEmpty) {
      return null;
    }
    ref
        .read(aiAutoAcceptFailedChangeIdsProvider(databasePath).notifier)
        .retainOnly(pendingAiChangeIdSet);
    return null;
  }, [ref, databasePath, pendingAiChangeIds.join(',')]);

  return useMemoized(
    () => AiChatPanelState(
      composerController: composerController,
      composerFocusNode: effectiveComposerFocusNode,
      sendGuardUntil: sendGuardUntil,
      attachedReferences: attachedReferences,
      referenceImagePaths: referenceImagePaths,
      pendingHandoff: pendingHandoff,
      queuedMessages: queuedMessageStore,
      composerNotice: composerNotice,
      slashMatches: slashMatches,
      slashIndex: slashIndex,
      userScrolledUp: userScrolledUp,
      consumedDraftId: consumedDraftId,
      pendingAutoSendSessionId: pendingAutoSendSessionId,
      pendingLoadTarget: pendingLoadTarget,
      slashMenuController: slashMenuController,
      composerInputLink: composerInputLink,
      modelSelectorLink: modelSelectorLink,
      modelSelectorOpenTrigger: modelSelectorOpenTrigger,
      modelMenuVisible: modelMenuVisible,
      pendingModelSelection: pendingModelSelection,
    ),
    [
      composerController,
      effectiveComposerFocusNode,
      sendGuardUntil,
      attachedReferences,
      referenceImagePaths,
      pendingHandoff,
      queuedMessageStore,
      composerNotice,
      slashMatches,
      slashIndex,
      userScrolledUp,
      consumedDraftId,
      pendingAutoSendSessionId,
      pendingLoadTarget,
      slashMenuController,
      composerInputLink,
      modelSelectorLink,
      modelSelectorOpenTrigger,
      modelMenuVisible,
      pendingModelSelection,
    ],
  );
}
