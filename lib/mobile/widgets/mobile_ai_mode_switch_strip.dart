// 职责: 移动端作品内 AI 页横向模式切换 pill 条 — 五模式图标+标签，选中态高亮。
// 关联文件:
//   lib/mobile/widgets/mobile_ai_mode.dart
//   lib/mobile/widgets/mobile_ai_session_app_bar.dart
//   lib/mobile/providers/ai_mode_session_memory_provider.dart
//   lib/shared/models/ai_session_mode.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/models/ai_session_mode.dart';
import '../../shared/theme/theme.dart';
import 'mobile_ai_mode.dart';

/// 横向可滚动的 AI 模式 pill 条（对齐 designs/mobile/m_ai.jsx ChatScreen 模式切换条）。
class MobileAiModeSwitchStrip extends StatelessWidget {
  const MobileAiModeSwitchStrip({
    super.key,
    required this.currentMode,
    required this.novelContext,
    this.currentSessionId,
    this.onModeSelected,
  });

  final AiSessionMode currentMode;
  final MobileAiNovelContext novelContext;

  /// 当前页真实会话 id；切走时写入进程内记忆（临时 draft 会被忽略）。
  final String? currentSessionId;
  final ValueChanged<AiSessionMode>? onModeSelected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.md,
        RevericSpacing.xxs,
        RevericSpacing.md,
        RevericSpacing.sm,
      ),
      child: Row(
        children: [
          for (final entry in mobileAiModes) ...[
            _ModePill(
              icon: entry.icon,
              label: context.t(entry.labelKey),
              selected: entry.mode == currentMode,
              colors: colors,
              typo: typo,
              onTap: () {
                if (entry.mode == currentMode) {
                  return;
                }
                if (onModeSelected != null) {
                  onModeSelected!(entry.mode);
                  return;
                }
                unawaited(
                  pushReplacementMobileAiModePage(
                    context,
                    mode: entry.mode,
                    currentMode: currentMode,
                    currentSessionId: currentSessionId,
                    novel: novelContext,
                  ),
                );
              },
            ),
            if (entry != mobileAiModes.last)
              const SizedBox(width: RevericSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool selected;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                icon,
                size: 14,
                color: selected ? colors.accentWarm : colors.textMuted,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                label,
                style: typo.uiSmall.copyWith(
                  color: selected ? colors.accentWarm : colors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
