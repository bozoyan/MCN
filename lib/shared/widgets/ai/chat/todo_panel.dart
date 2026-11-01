// 职责: AI 会话 Todo 列表面板 — 显示当前会话的任务列表，支持折叠展开（桌面/移动共用）
// 关联文件:
//   lib/shared/providers/todo_providers.dart
//   lib/shared/models/todo.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/todo.json
//   assets/translations/zh-CN/todo.json

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/models/todo.dart';
import 'package:reveric/shared/providers/todo_providers.dart';
import 'package:reveric/shared/components/reveric_surfaces.dart';
import 'package:reveric/shared/theme/theme.dart';

/// 会话 Todo 列表面板 — 固定在聊天区域顶部，可折叠展开
class TodoPanel extends HookConsumerWidget {
  const TodoPanel({
    super.key,
    this.initialExpanded = false,
    this.sessionId,
    this.maxListHeight,
  });

  /// 嵌在聊天列顶部时的列表高度上限：父级给的是不受限高度，不封顶时任务一多
  /// 就把消息区和 composer 挤出面板。
  static const double inlineMaxListHeight = 240;

  final bool initialExpanded;
  final String? sessionId;

  /// 展开列表的最大高度，超出部分在列表内滚动；null 表示不额外限制。
  final double? maxListHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final todosAsync = ref.watch(sessionTodosProvider(sessionId));

    return todosAsync.when(
      data: (todos) {
        if (todos.isEmpty) return const SizedBox.shrink();
        return _TodoPanelContent(
          todos: todos,
          initialExpanded: initialExpanded,
          maxListHeight: maxListHeight,
          colors: colors,
          typo: typo,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
    );
  }
}

class _TodoPanelContent extends StatefulWidget {
  const _TodoPanelContent({
    required this.todos,
    required this.initialExpanded,
    required this.maxListHeight,
    required this.colors,
    required this.typo,
  }) : super(key: const ValueKey('todo_panel_content'));

  final List<Todo> todos;
  final bool initialExpanded;
  final double? maxListHeight;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  State<_TodoPanelContent> createState() => _TodoPanelContentState();
}

class _TodoPanelContentState extends State<_TodoPanelContent> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  @override
  void didUpdateWidget(covariant _TodoPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当有新任务添加时，自动展开
    if (widget.todos.length > oldWidget.todos.length && !_expanded) {
      setState(() => _expanded = true);
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = widget.todos
        .where((t) => !t.isCompleted && !t.isCancelled)
        .length;
    final completedCount = widget.todos.where((t) => t.isCompleted).length;
    final inProgressCount = widget.todos.where((t) => t.isInProgress).length;

    return RevericElevatedCard(
      fallback: widget.colors.surface,
      margin: const EdgeInsets.only(
        left: RevericSpacing.md,
        right: RevericSpacing.md,
        top: RevericSpacing.sm,
        bottom: RevericSpacing.xs,
      ),
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部 — 始终显示
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(RevericRadius.large),
              bottom: Radius.circular(_expanded ? 0 : RevericRadius.large),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.md,
                vertical: RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  // 图标
                  _buildHeaderRevericIcon(
                    widget.colors,
                    inProgressCount,
                    pendingCount,
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  // 标题和统计
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          context.t(LocaleKeys.todoPanelTitle),
                          style: widget.typo.uiSemibold.copyWith(
                            color: widget.colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.xs),
                        _buildStatusBadge(
                          '$completedCount/${widget.todos.length}',
                          widget.colors,
                          pendingCount == 0
                              ? widget.colors.additionBorder
                              : widget.colors.accent,
                        ),
                      ],
                    ),
                  ),
                  // 展开/收起图标
                  RevericIcon(
                    _expanded
                        ? RevericIcons.expand_less_rounded
                        : RevericIcons.expand_more_rounded,
                    size: 18,
                    color: widget.colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // 展开时的任务列表
          if (_expanded) ...[
            Divider(
              height: 1,
              color: widget.colors.borderSubtle,
              indent: RevericSpacing.md,
              endIndent: RevericSpacing.md,
            ),
            // 高度受限时（如展开模式右侧面板）列表自身滚动，避免撑破卡片；
            // 高度不受限时 SingleChildScrollView 按内容收缩，保持原有排版。
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: widget.maxListHeight ?? double.infinity,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(RevericSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...widget.todos.map(
                        (todo) => _TodoRow(
                          todo: todo,
                          colors: widget.colors,
                          typo: widget.typo,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderRevericIcon(
    RevericColors colors,
    int inProgressCount,
    int pendingCount,
  ) {
    final icon = inProgressCount > 0
        ? RevericIcons.pending_actions_rounded
        : pendingCount == 0
        ? RevericIcons.check_circle_rounded
        : RevericIcons.checklist_rounded;
    final iconColor = inProgressCount > 0
        ? colors.accent
        : pendingCount == 0
        ? colors.additionBorder
        : colors.textMuted;

    return RevericIcon(icon, size: 18, color: iconColor);
  }

  Widget _buildStatusBadge(String text, RevericColors colors, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.todo,
    required this.colors,
    required this.typo,
  });

  final Todo todo;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor, textColor, decoration) = _getStatusStyle();

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 状态图标
          RevericIcon(icon, size: 16, color: iconColor),
          const SizedBox(width: RevericSpacing.sm),
          // 优先级指示器
          _PriorityIndicator(priority: todo.priority, colors: colors),
          const SizedBox(width: RevericSpacing.sm),
          // 任务内容
          Expanded(
            child: Text(
              todo.content,
              style: typo.uiSmall.copyWith(
                color: textColor,
                decoration: decoration,
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

  (String, Color, Color, TextDecoration?) _getStatusStyle() {
    switch (todo.status) {
      case 'pending':
        return (
          RevericIcons.circle_outlined,
          colors.textMuted,
          colors.textSecondary,
          null,
        );
      case 'in_progress':
        return (
          RevericIcons.pending_rounded,
          colors.accent,
          colors.textPrimary,
          null,
        );
      case 'completed':
        return (
          RevericIcons.check_circle_rounded,
          colors.additionBorder,
          colors.textMuted,
          TextDecoration.lineThrough,
        );
      case 'cancelled':
        return (
          RevericIcons.cancel_rounded,
          colors.deletionBorder,
          colors.textMuted,
          TextDecoration.lineThrough,
        );
      default:
        return (
          RevericIcons.circle_outlined,
          colors.textMuted,
          colors.textSecondary,
          null,
        );
    }
  }
}

class _PriorityIndicator extends StatelessWidget {
  const _PriorityIndicator({required this.priority, required this.colors});

  final String priority;
  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'high' => colors.deletionBorder,
      'medium' => colors.accentAmber,
      'low' => colors.textMuted,
      _ => colors.textMuted,
    };

    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
