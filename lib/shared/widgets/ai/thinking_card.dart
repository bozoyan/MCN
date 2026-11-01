// 职责: 可折叠思考内容卡片 — 默认折叠，展示 AI 推理过程
// 关联文件:
//   lib/shared/agent/agent_run_state.dart
//   lib/shared/localization/locale_keys.dart
import 'package:flutter/material.dart';

import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/stable_selection_area.dart';

class ThinkingCard extends StatefulWidget {
  final String content;
  final bool initiallyExpanded;

  /// false 时内容不可选中（内容仍在流式增长的阶段）。
  final bool selectable;

  const ThinkingCard({
    super.key,
    required this.content,
    this.initiallyExpanded = false,
    this.selectable = true,
  });

  @override
  State<ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<ThinkingCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.content.trim().isEmpty) return const SizedBox.shrink();

    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      margin: EdgeInsets.only(
        top: RevericSpacing.sm,
        bottom: _expanded ? RevericSpacing.xs : 0,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(RevericRadius.medium),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.md,
                vertical: RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  RevericIcon(
                    RevericIcons.psychology_alt_outlined,
                    size: 14,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                  Expanded(
                    child: Text(
                      context.t(LocaleKeys.aiReasoningSection),
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ),
                  RevericIcon(
                    _expanded
                        ? RevericIcons.expand_less_rounded
                        : RevericIcons.expand_more_rounded,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.md,
                0,
                RevericSpacing.md,
                RevericSpacing.sm,
              ),
              child: StableSelectionArea(
                selectable: widget.selectable,
                child: Text(
                  widget.content.trim(),
                  style: typo.uiTiny.copyWith(
                    color: colors.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
