// 职责: 桌面端角色扮演消息流 — 逐条渲染作者发言与角色回应，生成中在末尾挂同款卡片，出错时追加中断提示，并跟随滚动。
// 关联文件:
//   lib/desktop/features/roleplay/panel.dart
//   lib/shared/widgets/ai/roleplay_message_card.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:flutter/material.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/roleplay_models.dart';
import '../../../shared/services/ai/roleplay_session_codec.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/ai_mode_error_notice.dart';
import '../../../shared/widgets/ai/roleplay_message_card.dart';
import '../../../shared/widgets/ai/user_respecting_auto_scroll_controller.dart';

const _density = AgentMessageDensity.panel;

class RoleplayMessageList extends StatefulWidget {
  const RoleplayMessageList({
    super.key,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.userName,
    required this.userAvatarPath,
    required this.onOpenActiveRunDetail,
    this.databasePath,
    this.novelId,
  });

  final RoleplaySession session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final String userName;
  final String userAvatarPath;
  final Future<void> Function(String title) onOpenActiveRunDetail;
  final String? databasePath;
  final String? novelId;

  @override
  State<RoleplayMessageList> createState() => _RoleplayMessageListState();
}

class _RoleplayMessageListState extends State<RoleplayMessageList> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void initState() {
    super.initState();
    // 历史恢复后直接挂载完整列表，首次布局也需要贴底。
    _autoScroll.scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant RoleplayMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = oldWidget.session.id != widget.session.id;
    // 切换会话 → 恢复自动跟随，否则上个会话的回看状态会带到新会话。
    if (sessionChanged) {
      _autoScroll.resumeFollow();
    }
    final messages = widget.session.messages;
    final countChanged = oldWidget.session.messages.length != messages.length;
    // 用户自己发出的消息必须可见：即使正在回看历史也恢复跟随。
    // 依赖 countChanged 才判断，避免流式期间每个 token 都把暂停状态冲掉。
    if (countChanged &&
        messages.isNotEmpty &&
        messages.last.speakerId == roleplayUserSpeakerId) {
      _autoScroll.resumeFollow();
    }
    final streamingChanged =
        oldWidget.activeRun?.accumulatedText !=
            widget.activeRun?.accumulatedText ||
        oldWidget.activeRun?.blocks.length != widget.activeRun?.blocks.length ||
        (oldWidget.activeRun == null) != (widget.activeRun == null);
    final errorChanged = oldWidget.session.failure != widget.session.failure;
    if (sessionChanged || countChanged || streamingChanged || errorChanged) {
      _autoScroll.scheduleScrollToBottom(streaming: widget.activeRun != null);
    }
  }

  @override
  void dispose() {
    _autoScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final messages = session.messages;
    // 生成中但还没收到首个 delta 时也显示同一张卡片（跳动三点），不另起占位组件。
    final showPending =
        widget.activeRun != null || session.phase == RoleplayPhase.generating;
    final failure = session.failure;
    final hasError = session.phase == RoleplayPhase.error && failure != null;

    return NotificationListener<ScrollNotification>(
      onNotification: _autoScroll.handleScrollNotification,
      child: ListView.builder(
        controller: _autoScroll.scrollController,
        padding: const EdgeInsets.all(RevericSpacing.lg),
        itemCount: messages.length + (showPending ? 1 : 0) + (hasError ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < messages.length) {
            final message = messages[index];
            return RoleplayMessageCard(
              message: message,
              character: session.character,
              density: _density,
              userName: widget.userName,
              userAvatarPath: widget.userAvatarPath,
              completedRun: widget.runHistory[message.id],
              databasePath: widget.databasePath,
              novelId: widget.novelId,
            );
          }
          if (showPending && index == messages.length) {
            return RoleplayStreamingCard(
              run: widget.activeRun,
              character: session.character,
              density: _density,
              onOpenDetail: () =>
                  widget.onOpenActiveRunDetail(session.character.name),
            );
          }
          return AiModeErrorNotice(
            title: context.t(LocaleKeys.aiRunInterrupted),
            failure: failure!,
          );
        },
      ),
    );
  }
}
