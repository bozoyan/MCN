// 职责: AI 会话历史垂直列表 — 桌面端 council/theater/in-character 等模式共用的历史记录展示组件。
// 关联文件:
//   lib/desktop/widgets/agent_council/agent_council_panel.dart
//   lib/desktop/features/theater/panel.dart
//   lib/desktop/features/monologue/panel.dart
//   lib/shared/database/app_database.dart
import 'package:flutter/material.dart';

import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/theme/theme.dart';

class AiSessionHistoryStrip extends StatelessWidget {
  final List<AiChatSession> sessions;
  final String icon;
  final String title;
  final String emptyHint;
  final String defaultSessionTitle;
  final ValueSetter<AiChatSession>? onSelectSession;
  final ValueSetter<String>? onDeleteSession;
  final double maxHeight;

  const AiSessionHistoryStrip({
    super.key,
    required this.sessions,
    required this.icon,
    required this.title,
    required this.emptyHint,
    required this.defaultSessionTitle,
    this.onSelectSession,
    this.onDeleteSession,
    this.maxHeight = 260,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x2l,
              RevericSpacing.md,
              RevericSpacing.sm,
              RevericSpacing.xs,
            ),
            child: Row(
              children: [
                RevericIcon(
                  RevericIcons.history_outlined,
                  size: 14,
                  color: colors.textSubtle,
                ),
                const SizedBox(width: RevericSpacing.xs),
                Text(
                  title,
                  style: typo.uiTinySemibold.copyWith(
                    color: colors.textSubtle,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: RevericSpacing.xs),
                if (sessions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.xs,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceDim,
                      borderRadius: BorderRadius.circular(RevericRadius.small),
                    ),
                    child: Text(
                      '${sessions.length}',
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(child: _buildBody(context, colors, typo)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(RevericSpacing.x2l),
        child: Center(
          child: Text(
            emptyHint,
            style: typo.uiTiny.copyWith(color: colors.textSubtle),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xs),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final title = session.title.trim().isEmpty
            ? defaultSessionTitle
            : session.title;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelectSession?.call(session),
            hoverColor: colors.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.x2l,
                vertical: RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  RevericIcon(icon, size: 14, color: colors.textSubtle),
                  const SizedBox(width: RevericSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: typo.uiSmall.copyWith(
                            color: colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatSubtitle(session.updatedAt, context),
                          style: typo.uiTiny.copyWith(color: colors.textSubtle),
                        ),
                      ],
                    ),
                  ),
                  if (onDeleteSession != null)
                    InkWell(
                      onTap: () => onDeleteSession?.call(session.id),
                      borderRadius: BorderRadius.circular(RevericRadius.small),
                      child: Padding(
                        padding: const EdgeInsets.all(RevericSpacing.xxs),
                        child: RevericIcon(
                          RevericIcons.close,
                          size: 12,
                          color: colors.textSubtle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatSubtitle(DateTime when, BuildContext context) {
    final now = DateTime.now();
    final date = DateTime(when.year, when.month, when.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) {
      final hh = when.hour.toString().padLeft(2, '0');
      final mm = when.minute.toString().padLeft(2, '0');
      return context.t(LocaleKeys.homeToday, namedArgs: {'time': '$hh:$mm'});
    }
    if (diff == 1) return context.t(LocaleKeys.homeYesterday);
    if (diff < 7) {
      return context.t(LocaleKeys.homeDaysAgo, namedArgs: {'count': '$diff'});
    }
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}
