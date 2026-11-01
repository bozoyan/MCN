// 职责: 全书章节排版进度弹窗 — 在弹窗内执行批量排版任务并展示已完成/总章数
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/services/chapter_format_all.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/error-handling.md
//   .agents/rules/i18n.md
import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../logger/app_logger.dart';
import '../theme/theme.dart';
import '../components/reveric_dialog.dart';

final _log = AppLogger.forModule('FormatAll');

/// 弹出不可关闭的排版进度弹窗，并在弹窗内执行 [run]。
///
/// [run] 通过 `onProgress(done, total)` 汇报进度；完成后弹窗自动关闭。
/// 返回 `(实际改写章数, 任务异常)`：成功时异常为 null，失败时 [run] 抛出的
/// 错误原样回传给调用方（弹窗自身不透出未处理异步异常）。
Future<(int, Object?)> showFormatAllProgressDialog(
  BuildContext context, {
  required Future<int> Function(void Function(int done, int total) onProgress)
  run,
}) {
  return showRevericDialog<(int, Object?)>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FormatAllProgressDialog(run: run),
  ).then((result) => result ?? (0, null));
}

class _FormatAllProgressDialog extends StatefulWidget {
  const _FormatAllProgressDialog({required this.run});

  final Future<int> Function(void Function(int done, int total) onProgress) run;

  @override
  State<_FormatAllProgressDialog> createState() =>
      _FormatAllProgressDialogState();
}

class _FormatAllProgressDialogState extends State<_FormatAllProgressDialog> {
  int? _done;
  int? _total;

  @override
  void initState() {
    super.initState();
    unawaited(_execute());
  }

  /// 无论成败都以 `(count, error)` 关闭弹窗：调用方据此区分部分成功与失败，
  /// 异常在这里被消费，不再以未处理异步错误逃逸。
  Future<void> _execute() async {
    var count = 0;
    Object? error;
    try {
      count = await widget.run((done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      });
    } catch (e, st) {
      // 部分章节可能已写库（count 为已完成数）；细节由底层日志承载，
      // 这里记录一条带完成数的摘要即可。
      _log.error(
        '[DB] format all chapters failed done=$count error=$e',
        error: e,
        stackTrace: st,
      );
      error = e;
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop((count, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final total = _total;

    return PopScope(
      canPop: false,
      child: RevericDialog(
        title: context.t(LocaleKeys.workspaceChapterFormatConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t(LocaleKeys.workspaceChapterFormatProgressLabel),
              style: typo.ui.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.md),
            LinearProgressIndicator(
              value: _done != null && total != null && total > 0
                  ? _done! / total
                  : null,
              minHeight: 4,
              borderRadius: BorderRadius.circular(RevericRadius.small),
              color: colors.accent,
              backgroundColor: colors.surfaceDim,
            ),
            if (_done != null && total != null) ...[
              const SizedBox(height: RevericSpacing.sm),
              Text(
                '$_done / $total',
                textAlign: TextAlign.end,
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
