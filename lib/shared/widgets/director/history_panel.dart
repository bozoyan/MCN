// 职责: 布景历史浮层 — 列出每次保存的快照，当前版标注「当前」，其余可恢复。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/models/director/persistence.dart
//   lib/shared/widgets/director/stage.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_button.dart';
import '../../components/reveric_icon_button.dart';
import '../../services/director/session.dart';
import '../../models/director/persistence.dart';
import '../../theme/theme.dart';
import '../../logger/app_logger.dart';
import 'strings.dart';

final _log = AppLogger.forModule('DirectorHistory');

String _stamp(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class DirectorHistoryPanel extends HookWidget {
  const DirectorHistoryPanel({
    super.key,
    required this.session,
    required this.onClose,
  });
  final DirectorSession session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final saved = useListenableSelector(session, () => session.savedRevisionId);
    final retry = useState(0);
    final entries = useMemoized(session.historyEntries, [
      session,
      saved,
      retry.value,
    ]);
    final snapshot = useFuture(entries);
    useEffect(() {
      if (snapshot.hasError) {
        _log.error(
          'director history failed',
          error: snapshot.error,
          stackTrace: snapshot.stackTrace,
        );
      }
      return null;
    }, [snapshot.error]);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final items = snapshot.data ?? const [];
    return Container(
      key: const ValueKey('director-history'),
      width: RevericSizes.directorHistoryWidth,
      constraints: const BoxConstraints(
        maxHeight: RevericSizes.directorHistoryMaxHeight,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.lg,
              RevericSpacing.xs,
              RevericSpacing.xxs,
              RevericSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'history'),
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                RevericIconButton(
                  icon: RevericIcons.close,
                  tooltip: tr(context, 'close'),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),
          if (!snapshot.hasError &&
              snapshot.connectionState == ConnectionState.done &&
              items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: Text(
                tr(context, 'history_empty'),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ),
          if (snapshot.hasError)
            Padding(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: Column(
                children: [
                  Text(tr(context, 'operation_failed')),
                  RevericButton.secondary(
                    label: tr(context, 'retry'),
                    onPressed: () => retry.value++,
                  ),
                ],
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xxs),
              child: Column(
                children: [
                  for (final e in items)
                    _Row(
                      entry: e,
                      current: e.id == saved && !session.history.dirty,
                      onRestore: () => session.attempt(() async {
                        await session.restoreHistory(e);
                        onClose();
                      }),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.current,
    required this.onRestore,
  });
  final DirectorRevision entry;
  final bool current;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.xs,
      ),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.person,
            size: RevericSizes.buttonIconSize,
            color: colors.textMuted,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'history_manual'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmall.copyWith(color: colors.textPrimary),
                ),
                Text(
                  _stamp(entry.savedAt),
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (current)
            Text(
              tr(context, 'history_current'),
              style: typo.uiTiny.copyWith(color: colors.accent),
            )
          else
            RevericButton.secondary(
              label: tr(context, 'restore'),
              size: RevericButtonSize.compact,
              onPressed: onRestore,
            ),
        ],
      ),
    );
  }
}
