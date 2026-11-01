// 职责: 移动端 AI 模式页通用「历史会话」底部弹窗 — 列出某模式某作品的历史会话供选择重开，含 debounce 标题搜索与处理中状态。
// 关联文件:
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/features/council/page.dart
//   lib/mobile/features/monologue/page.dart
//   lib/mobile/features/theater/page.dart
//   lib/mobile/features/roleplay/page.dart
//   lib/mobile/widgets/delete_confirm.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/providers/ai_mode_processing.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/home.json
//   assets/translations/zh-CN/home.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/search-debounce.md
//   .agents/rules/error-handling.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/components/reveric_search_field.dart';
import '../../shared/components/reveric_spinner.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/providers/ai_providers.dart' show aiChatRuntimeProvider;
import '../../shared/providers/novel_providers.dart';
import '../../shared/database/app_database.dart' show AiChatSession;
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/ai_session_mode.dart';
import '../../shared/providers/ai_mode_processing.dart';
import '../../shared/theme/theme.dart';
import 'delete_confirm.dart';
import 'sheet.dart';

final _log = AppLogger.forModule('AiSessionHistorySheet');

/// 左滑删除按钮占整行宽度的比例（与 [MobileSectionCard] 一致）。
const double _endActionExtentRatio = 0.26;

/// 弹出某模式的历史会话列表，返回用户选择的会话（取消则为 null）。
/// [sessions] 应已按需过滤到当前作品并按最近更新排序。
/// [currentSessionId] 标记当前正在查看的会话，用于高亮。
/// [mode] 用于查询该会话是否正在处理。
/// [modeLabel] 用于 header 副标题「模式名 · N 条」。
/// [onDelete] 启用左滑删除；传入后每行可左滑出删除按钮，由调用方负责实际持久化删除
/// （确认弹窗与本地列表刷新由本 sheet 内部处理）。
Future<AiChatSession?> showAiSessionHistorySheet(
  BuildContext context, {
  required List<AiChatSession> sessions,
  String? currentSessionId,
  required AiSessionMode mode,
  required String modeLabel,
  Future<void> Function(AiChatSession session)? onDelete,
  Future<void> Function(AiChatSession session)? onContinue,
  String? databasePath,
}) {
  return showModalBottomSheet<AiChatSession>(
    context: context,
    backgroundColor: RevericTheme.colorsOf(context).surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RevericRadius.x2l),
      ),
    ),
    builder: (sheetContext) {
      return _AiSessionHistorySheet(
        sessions: sessions,
        currentSessionId: currentSessionId,
        mode: mode,
        modeLabel: modeLabel,
        onDelete: onDelete,
        onContinue: onContinue,
        databasePath: databasePath,
      );
    },
  );
}

class _AiSessionHistorySheet extends HookWidget {
  const _AiSessionHistorySheet({
    required this.sessions,
    required this.currentSessionId,
    required this.mode,
    required this.modeLabel,
    this.onDelete,
    this.onContinue,
    this.databasePath,
  });

  final List<AiChatSession> sessions;
  final String? currentSessionId;
  final AiSessionMode mode;
  final String modeLabel;
  final Future<void> Function(AiChatSession session)? onDelete;
  final Future<void> Function(AiChatSession session)? onContinue;
  final String? databasePath;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final search = useDebouncedSearch();
    final effectiveQuery = search.query;
    final defaultTitle = context.t(LocaleKeys.aiSessionTitleDefault);

    // 本地持有会话快照，删除后即时刷新列表；关闭重开时由调用方传入最新快照。
    final sessionsState = useState<List<AiChatSession>>(sessions);
    final liveSessions = sessionsState.value;

    final filteredSessions = useMemoized(() {
      if (effectiveQuery.isEmpty) {
        return liveSessions;
      }
      return liveSessions
          .where((session) {
            final title = session.title.trim().isEmpty
                ? defaultTitle
                : session.title;
            return title.toLowerCase().contains(effectiveQuery);
          })
          .toList(growable: false);
    }, [liveSessions, effectiveQuery, defaultTitle]);

    final subtitle = context.t(
      LocaleKeys.aiSessionHistorySubtitle,
      namedArgs: {'mode': modeLabel, 'count': '${liveSessions.length}'},
    );

    Future<void> deleteSession(AiChatSession session) async {
      final title = session.title.trim().isEmpty ? defaultTitle : session.title;
      final confirmed = await showMobileDeleteConfirm(context, title: title);
      if (!confirmed) return;
      await onDelete?.call(session);
      sessionsState.value = liveSessions
          .where((s) => s.id != session.id)
          .toList(growable: false);
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.lg,
                RevericSpacing.lg,
                RevericSpacing.lg,
                RevericSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.surfaceDim,
                      borderRadius: BorderRadius.circular(RevericRadius.large),
                    ),
                    alignment: Alignment.center,
                    child: RevericIcon(
                      RevericIcons.history_rounded,
                      size: 18,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t(LocaleKeys.aiSessionHistoryTitle),
                          style: typo.uiSemibold.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: RevericSpacing.xxs),
                        Text(
                          subtitle,
                          style: typo.uiSmall.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (liveSessions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.lg,
                  0,
                  RevericSpacing.lg,
                  RevericSpacing.sm,
                ),
                child: RevericSearchField(
                  controller: search.controller,
                  hint: context.t(LocaleKeys.aiSessionHistorySearchPlaceholder),
                  fillColor: colors.surfaceDim,
                ),
              ),
            if (liveSessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.lg,
                  0,
                  RevericSpacing.lg,
                  RevericSpacing.x2l,
                ),
                child: Text(
                  context.t(LocaleKeys.aiSessionHistoryEmpty),
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              )
            else if (filteredSessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.lg,
                  0,
                  RevericSpacing.lg,
                  RevericSpacing.x2l,
                ),
                child: Text(
                  context.t(LocaleKeys.aiSessionHistoryNoMatches),
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    RevericSpacing.sm,
                    RevericSpacing.xxs,
                    RevericSpacing.sm,
                    RevericSpacing.sm,
                  ),
                  itemCount: filteredSessions.length,
                  itemBuilder: (context, index) {
                    final session = filteredSessions[index];
                    return _SessionHistoryRow(
                      session: session,
                      mode: mode,
                      isCurrent: session.id == currentSessionId,
                      defaultTitle: defaultTitle,
                      onTap: () => Navigator.of(context).pop(session),
                      databasePath: databasePath,
                      onContinue: onContinue == null
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              onContinue!(session);
                            },
                      onDelete: onDelete == null
                          ? null
                          : () => deleteSession(session),
                      deleteLabel: context.t(LocaleKeys.commonDelete),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionHistoryRow extends ConsumerStatefulWidget {
  const _SessionHistoryRow({
    required this.session,
    required this.mode,
    required this.isCurrent,
    required this.defaultTitle,
    required this.onTap,
    this.onDelete,
    this.onContinue,
    this.databasePath,
    this.deleteLabel,
  });

  final AiChatSession session;
  final AiSessionMode mode;
  final bool isCurrent;
  final String defaultTitle;
  final VoidCallback onTap;

  /// 启用左滑删除（与 [MobileSectionCard] 一致）。
  final VoidCallback? onDelete;
  final VoidCallback? onContinue;
  final String? databasePath;
  final String? deleteLabel;

  @override
  ConsumerState<_SessionHistoryRow> createState() => _SessionHistoryRowState();
}

class _SessionHistoryRowState extends ConsumerState<_SessionHistoryRow>
    with TickerProviderStateMixin {
  SlidableController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.onDelete != null) {
      _controller = SlidableController(this);
    }
  }

  @override
  void didUpdateWidget(covariant _SessionHistoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onDelete != null && _controller == null) {
      _controller = SlidableController(this);
    } else if (widget.onDelete == null && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// 长按弹出该行的次要操作。当前只有「延续对话」，且仅在会话已有落库消息时
  /// 可用；查询放在长按时而不是每行 build 时。
  Future<void> _showRowActions(
    BuildContext context, {
    required String title,
  }) async {
    final databasePath = widget.databasePath;
    final onContinue = widget.onContinue;
    if (databasePath == null || onContinue == null) {
      return;
    }
    bool hasSavedMessages;
    try {
      hasSavedMessages = await ref
          .read(novelContentDatabaseProvider(databasePath))
          .aiChatMessageDao
          .hasSavedMessages(widget.session.id);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=ai_chat_messages operation=SELECT '
        'session=${widget.session.id} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (!hasSavedMessages || !context.mounted) {
      return;
    }

    final runtime = ref.read(aiChatRuntimeProvider(widget.session.id));
    final busy = runtime.isRequestInFlight || runtime.isSessionMutationInFlight;
    final confirmed = await showMobileSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = RevericTheme.colorsOf(sheetContext);
        final typo = RevericTheme.typographyOf(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: !busy,
              leading: RevericIcon(
                RevericIcons.git_fork,
                size: 20,
                color: busy ? colors.textSubtle : colors.accent,
              ),
              title: Text(
                sheetContext.t(LocaleKeys.aiChatContinue),
                style: typo.ui.copyWith(
                  color: busy ? colors.textSubtle : colors.textPrimary,
                ),
              ),
              subtitle: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
              onTap: busy ? null : () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      onContinue();
    }
  }

  Widget _rowBody(BuildContext context, {required BorderRadius borderRadius}) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isProcessing = ref.watch(
      aiSessionProcessingProvider(
        mode: widget.mode,
        sessionId: widget.session.id,
      ),
    );
    final title = widget.session.title.trim().isEmpty
        ? widget.defaultTitle
        : widget.session.title;
    final processingLabel = widget.isCurrent
        ? context.t(LocaleKeys.aiSessionProcessingCurrent)
        : context.t(LocaleKeys.aiSessionProcessingBackground);
    final subtitle = isProcessing
        ? processingLabel
        : _formatSessionTime(context, widget.session.updatedAt);
    // 启用左滑删除时需要不透明背景遮住红色删除面板；否则保持原透明背景。
    final bgColor = widget.onDelete == null
        ? (widget.isCurrent ? colors.selected : Colors.transparent)
        : (widget.isCurrent ? colors.selected : colors.surface);

    return Material(
      color: bgColor,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: widget.onTap,
        // 次要操作走长按 sheet（删除仍在左滑里），对齐桌面端的行右键菜单。
        onLongPress: widget.onContinue == null || widget.databasePath == null
            ? null
            : () => unawaited(_showRowActions(context, title: title)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          child: Row(
            children: [
              if (isProcessing) ...[
                SizedBox(
                  width: 8,
                  height: 8,
                  child: RevericSpinner(
                    strokeWidth: 1.5,
                    color: widget.isCurrent ? colors.accent : colors.textMuted,
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
              ],
              RevericIcon(
                RevericIcons.history_rounded,
                size: 18,
                color: widget.isCurrent ? colors.accent : colors.textMuted,
              ),
              const SizedBox(width: RevericSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: widget.isCurrent
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      subtitle,
                      style: typo.uiSmall.copyWith(
                        color: isProcessing
                            ? (widget.isCurrent
                                  ? colors.accent
                                  : colors.textMuted)
                            : colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isCurrent) ...[
                const SizedBox(width: RevericSpacing.sm),
                RevericIcon(
                  RevericIcons.check,
                  size: 18,
                  color: colors.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final controller = _controller;

    if (widget.onDelete == null || controller == null) {
      return _rowBody(
        context,
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(RevericRadius.x2l),
      child: Slidable(
        controller: controller,
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: _endActionExtentRatio,
          children: [
            CustomSlidableAction(
              onPressed: (_) => widget.onDelete!(),
              backgroundColor: colors.error.withValues(alpha: 0.88),
              borderRadius: BorderRadius.zero,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RevericIcon(
                    RevericIcons.delete_outline,
                    size: 20,
                    color: colors.onAccent,
                  ),
                  if (widget.deleteLabel != null) ...[
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      widget.deleteLabel!,
                      style: typo.uiTiny.copyWith(color: colors.onAccent),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: controller.animation,
          builder: (context, _) {
            final open = (-controller.ratio / _endActionExtentRatio).clamp(
              0.0,
              1.0,
            );
            final rightRadius = RevericRadius.x2l * (1.0 - open);
            return _rowBody(
              context,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(RevericRadius.x2l),
                bottomLeft: Radius.circular(RevericRadius.x2l),
                topRight: Radius.circular(rightRadius),
                bottomRight: Radius.circular(rightRadius),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _formatSessionTime(BuildContext context, DateTime when) {
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
  final mm = when.month.toString().padLeft(2, '0');
  final dd = when.day.toString().padLeft(2, '0');
  return '${when.year}-$mm-$dd';
}
