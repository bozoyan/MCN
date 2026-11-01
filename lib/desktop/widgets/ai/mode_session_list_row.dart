// 职责: AI 互动 mode 侧边栏会话行 — 展示选中态、处理状态并提供右键删除。
// 关联文件:
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/shared/providers/ai_mode_processing.dart
//   lib/shared/components/reveric_context_menu.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/components/reveric_spinner.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_session_mode.dart';
import '../../../shared/providers/ai_mode_processing.dart';
import '../../../shared/theme/theme.dart';

class ModeSessionListRow extends ConsumerWidget {
  const ModeSessionListRow({
    super.key,
    required this.session,
    required this.mode,
    required this.isActive,
    this.onSelectSession,
    this.onDeleteSession,
  });

  final AiChatSession session;
  final AiSessionMode mode;
  final bool isActive;
  final ValueChanged<String>? onSelectSession;
  final ValueChanged<String>? onDeleteSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isProcessing = ref.watch(
      aiSessionProcessingProvider(mode: mode, sessionId: session.id),
    );
    final processingLabel = isActive
        ? context.t(LocaleKeys.aiSessionProcessingCurrent)
        : context.t(LocaleKeys.aiSessionProcessingBackground);
    final title = session.title.trim().isEmpty
        ? context.t(LocaleKeys.aiSessionTitleDefault)
        : session.title;

    return GestureDetector(
      onSecondaryTapDown: onDeleteSession == null
          ? null
          : (details) => unawaited(
              showRevericContextMenu(
                context: context,
                position: details.globalPosition,
                entries: [
                  RevericMenuItem(
                    icon: RevericIcons.delete,
                    iconColor: colors.warningText,
                    labelColor: colors.warningText,
                    label: context.t(LocaleKeys.commonDelete),
                    onTap: () => onDeleteSession?.call(session.id),
                  ),
                ],
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
                  _buildLeadingIndicator(
                    colors: colors,
                    isProcessing: isProcessing,
                    accent: true,
                  ),
                ] else if (isProcessing) ...[
                  _buildLeadingIndicator(
                    colors: colors,
                    isProcessing: true,
                    accent: false,
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: (isActive ? typo.uiSemibold : typo.ui).copyWith(
                          color: isActive
                              ? colors.textPrimary
                              : colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isProcessing)
                        Text(
                          processingLabel,
                          style: typo.uiTiny.copyWith(
                            color: isActive ? colors.accent : colors.textMuted,
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

  Widget _buildLeadingIndicator({
    required RevericColors colors,
    required bool isProcessing,
    required bool accent,
  }) {
    if (isProcessing) {
      return Padding(
        padding: const EdgeInsets.only(right: RevericSpacing.sm),
        child: SizedBox(
          width: 8,
          height: 8,
          child: RevericSpinner(
            strokeWidth: 1.5,
            color: accent ? colors.accent : colors.textMuted,
          ),
        ),
      );
    }

    if (!accent) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: RevericSpacing.sm),
      decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
    );
  }
}
