// 职责: Diff 详情对话框 — 在弹窗中展示完整的行级差异化详情，支持更大的可视区域与更短的折叠阈值
// 关联文件:
//   lib/shared/widgets/ai/diff/diff_view.dart
//   lib/shared/widgets/ai/tool_activity_group.dart
import 'package:flutter/material.dart';

import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'diff_view.dart';

class DiffDetailDialog extends StatefulWidget {
  const DiffDetailDialog({
    super.key,
    required this.oldText,
    required this.newText,
    this.title,
    this.label,
  });

  final String oldText;
  final String newText;
  final String? title;
  final String? label;

  static Future<void> show(
    BuildContext context, {
    required String oldText,
    required String newText,
    String? title,
    String? label,
  }) {
    return showDialog(
      context: context,
      builder: (_) => DiffDetailDialog(
        oldText: oldText,
        newText: newText,
        title: title,
        label: label,
      ),
    );
  }

  @override
  State<DiffDetailDialog> createState() => _DiffDetailDialogState();
}

class _DiffDetailDialogState extends State<DiffDetailDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return AlertDialog(
      backgroundColor: colors.surfaceContainerHigh,
      title: Row(
        children: [
          RevericIcon(
            RevericIcons.description_outlined,
            size: 18,
            color: colors.textMuted,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.title != null && widget.title!.isNotEmpty)
                  Text(
                    widget.title!,
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (widget.label != null && widget.label!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.label!,
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 960,
        height: 600,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: AiDiffView(
              oldText: widget.oldText,
              newText: widget.newText,
              contextLines: 5,
              collapseThreshold: 12,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            context.t(LocaleKeys.commonClose),
            style: typo.ui.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}
