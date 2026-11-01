// 职责: TodoWrite 工具调用结果卡片 — 在消息中显示工具执行摘要，支持展开查看待办详情
// 关联文件:
//   lib/shared/models/ai_message_block.dart
//   lib/shared/models/todo_models.dart
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/tools/tool_card_common.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/todo.json
//   assets/translations/zh-CN/todo.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/theme/theme.dart';

/// TodoWrite 工具调用结果卡片
///
/// 当 AI 调用 TodoWrite 工具时，在消息中显示一个简洁的摘要卡片，
/// 可展开查看完整的待办项列表。
class TodoToolCard extends StatefulWidget {
  const TodoToolCard({super.key, required this.block});

  final AiToolCallBlock block;

  @override
  State<TodoToolCard> createState() => _TodoToolCardState();
}

class _TodoToolCardState extends State<TodoToolCard> {
  bool _expanded = false;

  AiToolCallBlock get block => widget.block;

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final result = block.result;
    final todos = _extractTodos(result);
    final todoCount = todos.length;
    final pendingCount = todos
        .where(
          (todo) =>
              todo['status'] != 'completed' && todo['status'] != 'cancelled',
        )
        .length;
    final summary = result?['todos'] is List
        ? plural(
            LocaleKeys.todoRemaining,
            pendingCount,
            namedArgs: {'count': '$pendingCount'},
            context: context,
          )
        : '';

    final status = block.status;
    final isSuccess = status == AiToolCallStatus.success;
    final isError =
        status == AiToolCallStatus.error || block.errorMessage != null;
    final canExpand = todoCount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: RevericSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            onTap: canExpand ? _toggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.md,
                vertical: RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  _buildStatusRevericIcon(colors, isSuccess, isError),
                  const SizedBox(width: RevericSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.t(LocaleKeys.todoToolCardTitle),
                          style: typo.uiSemibold.copyWith(
                            color: colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        if (summary.isNotEmpty)
                          Text(
                            summary,
                            style: typo.uiSmall.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (todoCount > 0) _buildCountBadge(colors, typo, todoCount),
                  if (canExpand)
                    Padding(
                      padding: const EdgeInsets.only(left: RevericSpacing.sm),
                      child: RevericIcon(
                        _expanded
                            ? RevericIcons.expand_less_rounded
                            : RevericIcons.expand_more_rounded,
                        size: 18,
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && todos.isNotEmpty) ...[
            Divider(height: 1, color: colors.borderSubtle),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.md,
                RevericSpacing.sm,
                RevericSpacing.md,
                RevericSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final todo in todos)
                    _buildTodoRow(context, colors, typo, todo),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTodoRow(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
    Map<String, dynamic> todo,
  ) {
    final content = todo['content'] as String? ?? '';
    final statusStr = todo['status'] as String? ?? 'pending';
    final priorityStr = todo['priority'] as String? ?? 'medium';
    final isDone = statusStr == 'completed' || statusStr == 'cancelled';
    final icon = switch (statusStr) {
      'in_progress' => RevericIcons.pending_rounded,
      'completed' => RevericIcons.check_circle_rounded,
      'cancelled' => RevericIcons.cancel_rounded,
      _ => RevericIcons.circle_outlined,
    };
    final iconColor = switch (statusStr) {
      'in_progress' => colors.accent,
      'completed' => colors.additionBorder,
      'cancelled' => colors.textMuted,
      _ => colors.textMuted,
    };
    final priorityColor = switch (priorityStr) {
      'high' => colors.deletionBorder,
      'medium' => colors.accentAmber,
      _ => colors.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RevericIcon(icon, size: 14, color: iconColor),
          const SizedBox(width: RevericSpacing.sm),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: priorityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              content,
              style: typo.uiSmall.copyWith(
                color: isDone ? colors.textMuted : colors.textSecondary,
                decoration: isDone ? TextDecoration.lineThrough : null,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRevericIcon(
    RevericColors colors,
    bool isSuccess,
    bool isError,
  ) {
    final (icon, color) = switch ((isSuccess, isError)) {
      (_, true) => (RevericIcons.error_outline_rounded, colors.deletionBorder),
      (true, _) => (RevericIcons.checklist_rounded, colors.accent),
      _ => (RevericIcons.pending_actions_rounded, colors.textMuted),
    };

    return RevericIcon(icon, size: 20, color: color);
  }

  Widget _buildCountBadge(
    RevericColors colors,
    RevericTypography typo,
    int count,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
      ),
      child: Text(
        '$count',
        style: typo.uiSemibold.copyWith(fontSize: 11, color: colors.accent),
      ),
    );
  }

  List<Map<String, dynamic>> _extractTodos(Map<String, dynamic>? result) {
    if (result == null) return const [];
    final todos = result['todos'] as List<dynamic>?;
    if (todos == null) return const [];
    return todos.cast<Map<String, dynamic>>();
  }
}
