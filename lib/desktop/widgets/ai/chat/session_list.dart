// 职责: AI Chat 会话列表 — 侧边栏「聊天」标签页内容，展示 chat mode 的会话列表、分页加载、新建/删除操作。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/models/ai_session_mode.dart';
import '../../../../shared/providers/ai_mode_processing.dart';
import '../../../../shared/theme/theme.dart';
import 'session_context_menu.dart';

class ChatSessionList extends StatelessWidget {
  const ChatSessionList({
    super.key,
    required this.sessions,
    this.activeSessionId,
    this.onSelectSession,
    this.onCreateSession,
    this.onDeleteSession,
    this.onContinueSession,
    this.databasePath,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
  });

  final List<AiChatSession> sessions;
  final String? activeSessionId;
  final ValueSetter<String>? onSelectSession;
  final VoidCallback? onCreateSession;
  final ValueSetter<String>? onDeleteSession;
  final ValueSetter<String>? onContinueSession;
  final String? databasePath;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;

  /// 过滤出 chat mode 的会话
  List<AiChatSession> get _chatSessions => sessions.where((s) {
    final mode = AiSessionMode.fromString(s.mode);
    return mode.isChat;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final chatSessions = _chatSessions;

    if (chatSessions.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (!hasMore || isLoadingMore || onLoadMore == null) {
                return false;
              }
              if (notification.metrics.extentAfter > 160) {
                return false;
              }
              onLoadMore!.call();
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xs),
              itemCount: chatSessions.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= chatSessions.length) {
                  return _buildLoadMoreRow(context);
                }
                final session = chatSessions[index];
                final isActive = session.id == activeSessionId;
                return _ChatSessionListRow(
                  session: session,
                  isActive: isActive,
                  onSelectSession: onSelectSession,
                  onDeleteSession: onDeleteSession,
                  onContinueSession: onContinueSession,
                  databasePath: databasePath,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(RevericSpacing.x3l),
              child: Text(
                context.t(LocaleKeys.aiSessionListEmpty),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x2l,
        RevericSpacing.md,
        RevericSpacing.sm,
        RevericSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            context.t(LocaleKeys.aiChatHistory),
            style: typo.uiTinySemibold.copyWith(
              color: colors.textSubtle,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (onCreateSession != null)
            IconButton(
              tooltip: context.t(LocaleKeys.aiNewSession),
              onPressed: onCreateSession,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: RevericIcon(
                RevericIcons.add,
                size: 16,
                color: colors.textSubtle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreRow(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xs),
      child: Center(
        child: isLoadingMore
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                ),
              )
            : IconButton(
                onPressed: onLoadMore,
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: RevericIcon(
                  RevericIcons.expand_more,
                  size: 16,
                  color: colors.textSubtle,
                ),
              ),
      ),
    );
  }
}

class _ChatSessionListRow extends ConsumerWidget {
  const _ChatSessionListRow({
    required this.session,
    required this.isActive,
    this.onSelectSession,
    this.onDeleteSession,
    this.onContinueSession,
    this.databasePath,
  });

  final AiChatSession session;
  final bool isActive;
  final ValueSetter<String>? onSelectSession;
  final ValueSetter<String>? onDeleteSession;
  final ValueSetter<String>? onContinueSession;
  final String? databasePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isProcessing = ref.watch(
      aiSessionProcessingProvider(
        mode: AiSessionMode.chat,
        sessionId: session.id,
      ),
    );
    final title = session.title.trim().isEmpty
        ? context.t(LocaleKeys.aiSessionTitleDefault)
        : session.title;
    final processingLabel = isActive
        ? context.t(LocaleKeys.aiSessionProcessingCurrent)
        : context.t(LocaleKeys.aiSessionProcessingBackground);
    final subtitle = isProcessing
        ? processingLabel
        : _formatSubtitle(context, session.updatedAt);

    return GestureDetector(
      onSecondaryTapDown: (details) => unawaited(
        showChatSessionContextMenu(
          context: context,
          ref: ref,
          position: details.globalPosition,
          sessionId: session.id,
          databasePath: databasePath,
          onContinue: onContinueSession == null
              ? null
              : () => onContinueSession!(session.id),
          onDelete: onDeleteSession == null
              ? null
              : () => onDeleteSession!(session.id),
        ),
      ),
      child: Material(
        color: isActive ? colors.selected : Colors.transparent,
        child: InkWell(
          onTap: () => onSelectSession?.call(session.id),
          hoverColor: colors.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.x2l,
              vertical: RevericSpacing.sm,
            ),
            child: Row(
              children: [
                if (isActive) ...[
                  _buildActiveLeadingIndicator(
                    context,
                    isProcessing: isProcessing,
                  ),
                ] else if (isProcessing) ...[
                  _buildBackgroundProcessingIndicator(context),
                  const SizedBox(width: RevericSpacing.sm),
                ],
                RevericIcon(
                  RevericIcons.chat_bubble_outline,
                  size: 14,
                  color: isActive ? colors.accent : colors.textSubtle,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: (isActive ? typo.uiSmallSemibold : typo.uiSmall)
                            .copyWith(
                              color: isActive
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: typo.uiTiny.copyWith(
                          color: isProcessing
                              ? (isActive ? colors.accent : colors.textMuted)
                              : colors.textSubtle,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveLeadingIndicator(
    BuildContext context, {
    required bool isProcessing,
  }) {
    final colors = RevericTheme.colorsOf(context);

    if (isProcessing) {
      return Padding(
        padding: const EdgeInsets.only(right: RevericSpacing.sm),
        child: SizedBox(
          width: 8,
          height: 8,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
          ),
        ),
      );
    }

    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: RevericSpacing.sm),
      decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
    );
  }

  Widget _buildBackgroundProcessingIndicator(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return SizedBox(
      width: 8,
      height: 8,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        valueColor: AlwaysStoppedAnimation<Color>(colors.textMuted),
      ),
    );
  }

  String _formatSubtitle(BuildContext context, DateTime when) {
    final now = DateTime.now();
    final date = DateTime(when.year, when.month, when.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) {
      final hh = when.hour.toString().padLeft(2, '0');
      final mm = when.minute.toString().padLeft(2, '0');
      return context.t(LocaleKeys.homeToday, namedArgs: {'time': '$hh:$mm'});
    }
    if (diff == 1) {
      return context.t(LocaleKeys.homeYesterday);
    }
    if (diff < 7) {
      return context.t(LocaleKeys.homeDaysAgo, namedArgs: {'count': '$diff'});
    }
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}
